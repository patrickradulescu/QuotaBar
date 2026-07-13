import Foundation
import QuotaBarCore

final class CodexAppServerClient: UsageProviderClient {
    let provider: ProviderKind = .codex
    var onUpdate: ((ProviderUsage) -> Void)?

    private static let maximumLineBytes = 512 * 1_024
    private static let maximumPendingBufferBytes = 1_024 * 1_024
    private static let initializationTimeout: TimeInterval = 10
    private static let rateLimitRequestTimeout: TimeInterval = 10

    private let ioQueue = DispatchQueue(label: "com.patrickradulescu.quotabar.codex-app-server")
    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var outputBuffer = Data()
    private var nextRequestID = 10
    private var initializeRequestID: Int?
    private var pendingRateLimitRequestIDs: Set<Int> = []
    private var initialized = false
    private var processGeneration = 0

    func start() {
        ioQueue.async { [weak self] in
            self?.startOnQueue()
        }
    }

    func refresh() {
        ioQueue.async { [weak self] in
            guard let self else { return }
            if self.process?.isRunning != true {
                self.startOnQueue()
                return
            }
            guard self.initialized else { return }
            self.requestRateLimitsOnQueue(generation: self.processGeneration)
        }
    }

    func stop() {
        ioQueue.sync {
            tearDownCurrentProcessOnQueue(terminate: true)
        }
    }

    private func startOnQueue() {
        if let process {
            guard !process.isRunning else { return }
            // A refresh can beat the termination callback onto the serial queue.
            // Retire that dead generation before creating the replacement.
            tearDownCurrentProcessOnQueue(terminate: false)
        }

        guard let executable = CommandLocator.codex() else {
            publish(.unavailable(.codex, detail: "Codex CLI not found"))
            return
        }

        processGeneration &+= 1
        let generation = processGeneration
        initialized = false
        initializeRequestID = nil
        pendingRateLimitRequestIDs.removeAll(keepingCapacity: true)
        outputBuffer.removeAll(keepingCapacity: true)

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProviderProcessEnvironment.minimal()

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ioQueue.async {
                self?.consumeOutputOnQueue(data, generation: generation)
            }
        }

        // Drain stderr so the child can never block. We intentionally do not persist it:
        // provider logs may contain local paths or account metadata.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] terminated in
            self?.ioQueue.async {
                guard let self, generation == self.processGeneration else { return }
                let detail = "Codex app-server exited (\(terminated.terminationStatus))"
                self.tearDownCurrentProcessOnQueue(terminate: false)
                self.publish(.failed(.codex, detail: detail))
            }
        }

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        do {
            try process.run()
            sendInitializeOnQueue(generation: generation)
        } catch {
            failOnQueue(
                detail: "Could not start Codex: \(error.localizedDescription)",
                generation: generation
            )
        }
    }

    private func sendInitializeOnQueue(generation: Int) {
        guard generation == processGeneration else { return }
        let id = nextID()
        initializeRequestID = id
        guard sendOnQueue([
            "method": "initialize",
            "id": id,
            "params": [
                "clientInfo": [
                    "name": "quota_bar",
                    "title": "QuotaBar",
                    "version": AppVersion.current
                ]
            ]
        ], generation: generation) else {
            failOnQueue(detail: "Codex connection closed", generation: generation)
            return
        }

        ioQueue.asyncAfter(deadline: .now() + Self.initializationTimeout) { [weak self] in
            guard let self,
                  generation == self.processGeneration,
                  self.initializeRequestID == id,
                  !self.initialized else {
                return
            }
            self.failOnQueue(detail: "Codex initialization timed out", generation: generation)
        }
    }

    private func requestRateLimitsOnQueue(generation: Int) {
        guard generation == processGeneration,
              initialized,
              pendingRateLimitRequestIDs.isEmpty else {
            return
        }

        let id = nextID()
        pendingRateLimitRequestIDs.insert(id)
        guard sendOnQueue([
            "method": "account/rateLimits/read",
            "id": id,
            "params": [:] as [String: String]
        ], generation: generation) else {
            failOnQueue(detail: "Codex connection closed", generation: generation)
            return
        }

        ioQueue.asyncAfter(deadline: .now() + Self.rateLimitRequestTimeout) { [weak self] in
            guard let self,
                  generation == self.processGeneration,
                  self.pendingRateLimitRequestIDs.contains(id) else {
                return
            }
            self.failOnQueue(detail: "Codex usage request timed out", generation: generation)
        }
    }

    private func sendOnQueue(_ object: [String: Any], generation: Int) -> Bool {
        guard generation == processGeneration,
              let handle = inputPipe?.fileHandleForWriting,
              JSONSerialization.isValidJSONObject(object),
              var data = try? JSONSerialization.data(withJSONObject: object) else {
            return false
        }

        data.append(0x0A)
        do {
            try handle.write(contentsOf: data)
            return true
        } catch {
            return false
        }
    }

    private func consumeOutputOnQueue(_ data: Data, generation: Int) {
        guard generation == processGeneration else { return }
        guard data.count <= Self.maximumPendingBufferBytes,
              outputBuffer.count <= Self.maximumPendingBufferBytes - data.count else {
            failOnQueue(detail: "Codex response exceeded the safe size limit", generation: generation)
            return
        }

        outputBuffer.append(data)

        while let newline = outputBuffer.firstIndex(of: 0x0A) {
            let line = Data(outputBuffer[..<newline])
            outputBuffer.removeSubrange(...newline)
            guard !line.isEmpty else { continue }
            guard line.count <= Self.maximumLineBytes else {
                failOnQueue(detail: "Codex response line exceeded the safe size limit", generation: generation)
                return
            }
            handleLineOnQueue(line, generation: generation)
            guard generation == processGeneration else { return }
        }
    }

    private func handleLineOnQueue(_ line: Data, generation: Int) {
        guard generation == processGeneration else { return }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
            return
        }

        if let id = object["id"] as? Int, id == initializeRequestID {
            initializeRequestID = nil
            if object["result"] != nil {
                initialized = true
                guard sendOnQueue(
                    ["method": "initialized", "params": [:] as [String: String]],
                    generation: generation
                ) else {
                    failOnQueue(detail: "Codex connection closed", generation: generation)
                    return
                }
                requestRateLimitsOnQueue(generation: generation)
            } else {
                failOnQueue(detail: "Codex initialization failed", generation: generation)
            }
            return
        }

        guard let id = object["id"] as? Int,
              pendingRateLimitRequestIDs.remove(id) != nil else {
            return
        }

        do {
            let snapshot = try CodexRateLimitParser.parse(jsonLine: line)
            publish(snapshot)
        } catch {
            failOnQueue(detail: "Codex usage unavailable", generation: generation)
        }
    }

    private func nextID() -> Int {
        defer { nextRequestID &+= 1 }
        return nextRequestID
    }

    private func failOnQueue(detail: String, generation: Int) {
        guard generation == processGeneration else { return }
        // Invalidating the generation before publishing makes every already-
        // queued timeout, output, and termination callback a no-op. Exactly one
        // terminal error is therefore emitted for this helper generation.
        tearDownCurrentProcessOnQueue(terminate: true)
        publish(.failed(.codex, detail: detail))
    }

    private func publish(_ usage: ProviderUsage) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(usage)
        }
    }

    private func tearDownCurrentProcessOnQueue(terminate: Bool) {
        processGeneration &+= 1

        let processToTerminate = process
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        processToTerminate?.terminationHandler = nil
        inputPipe?.fileHandleForWriting.closeFile()

        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        initialized = false
        initializeRequestID = nil
        pendingRateLimitRequestIDs.removeAll(keepingCapacity: true)
        outputBuffer.removeAll(keepingCapacity: true)

        if terminate, processToTerminate?.isRunning == true {
            processToTerminate?.terminate()
        }
    }
}

private enum AppVersion {
    static var current: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.4.1"
    }
}
