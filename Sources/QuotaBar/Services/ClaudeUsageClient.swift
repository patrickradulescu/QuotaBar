import Foundation
import QuotaBarCore

/// Reads Claude Code's documented `/usage` screen without opening Claude's
/// credential store or calling private endpoints. The official CLI runs in a
/// pseudo-terminal and its terminal output exists only in memory. One helper is
/// reused while an eligible app remains active so quota refreshes do not create
/// a new Claude session on every timer tick.
final class ClaudeUsageClient: UsageProviderClient {
    let provider: ProviderKind = .claude
    var onUpdate: ((ProviderUsage) -> Void)?

    private enum Phase {
        case idle
        case waitingForPrompt
        case waitingForUsage
        case ready
        case exiting
    }

    private static let minimumRefreshInterval: TimeInterval = 120
    private static let probeTimeout: TimeInterval = 20

    private let ioQueue = DispatchQueue(
        label: "com.patrickradulescu.quotabar.claude-usage",
        qos: .utility
    )

    private var process: Process?
    private var inputPipe: Pipe?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var screen: ANSIScreen?
    private var phase: Phase = .idle
    private var lastProbeStartedAt: Date?
    private var probeGeneration = 0
    private var parseGeneration = 0
    private var timeoutGeneration = 0
    private var pendingUsage: ProviderUsage?
    private var terminalResultPublished = false
    private var stoppedByClient = false

    func start() {
        ioQueue.async { [weak self] in
            self?.startProbeIfAllowedOnQueue()
        }
    }

    func refresh() {
        ioQueue.async { [weak self] in
            self?.startProbeIfAllowedOnQueue()
        }
    }

    func stop() {
        ioQueue.sync {
            stoppedByClient = true
            probeGeneration += 1
            parseGeneration += 1
            timeoutGeneration += 1

            if process?.isRunning == true {
                // Ask the interactive client to leave its modal, then exit. If
                // the app itself is quitting, terminate immediately afterward
                // so no helper is orphaned.
                writeOnQueue(Data([0x1B]))
                writeOnQueue(Data("/exit\r".utf8))
                process?.terminate()
            }
            resetProcessStateOnQueue()
        }
    }

    private func startProbeIfAllowedOnQueue() {
        let now = Date()
        if process?.isRunning == true {
            guard phase == .ready else { return }
            if let lastProbeStartedAt,
               now.timeIntervalSince(lastProbeStartedAt) < Self.minimumRefreshInterval {
                return
            }
            lastProbeStartedAt = now
            requestUsageOnQueue(generation: probeGeneration)
            return
        }

        lastProbeStartedAt = now

        guard let claudeURL = CommandLocator.claude() else {
            publish(.unavailable(.claude, detail: "Claude CLI not found"))
            return
        }

        guard let workingDirectory = prepareWorkingDirectory() else {
            publish(.failed(.claude, detail: "Could not prepare Claude probe"))
            return
        }

        let scriptURL = URL(fileURLWithPath: "/usr/bin/script")
        guard FileManager.default.isExecutableFile(atPath: scriptURL.path) else {
            publish(.unavailable(.claude, detail: "macOS PTY helper not found"))
            return
        }

        stoppedByClient = false
        terminalResultPublished = false
        pendingUsage = nil
        parseGeneration = 0
        probeGeneration += 1
        let generation = probeGeneration
        phase = .waitingForPrompt
        screen = ANSIScreen(columns: 100, rows: 36)

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()

        process.executableURL = scriptURL
        process.arguments = [
            "-q",
            "/dev/null",
            claudeURL.path,
            "--safe-mode",
            "--ax-screen-reader",
            "--strict-mcp-config",
            "--tools",
            "",
            "--no-chrome"
        ]
        process.currentDirectoryURL = workingDirectory
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.environment = ProviderProcessEnvironment.minimal(columns: 100, rows: 36)

        outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            self?.ioQueue.async {
                self?.consumeOutputOnQueue(data, generation: generation)
            }
        }

        // Always drain stderr to prevent backpressure, but never retain, parse,
        // log, or persist it because it may include local account context.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        process.terminationHandler = { [weak self] _ in
            self?.ioQueue.async {
                self?.handleTerminationOnQueue(generation: generation)
            }
        }

        self.process = process
        self.inputPipe = inputPipe
        self.outputPipe = outputPipe
        self.errorPipe = errorPipe

        do {
            try process.run()
        } catch {
            resetProcessStateOnQueue()
            publish(.failed(.claude, detail: "Could not start Claude CLI"))
            return
        }

        scheduleTimeoutOnQueue(generation: generation)
        scheduleCommandFallbackOnQueue(generation: generation)
    }

    private func consumeOutputOnQueue(_ data: Data, generation: Int) {
        guard generation == probeGeneration, phase != .idle else { return }
        screen?.feed(data)
        guard let rendered = screen?.renderedText else { return }

        if phase == .waitingForPrompt {
            if requiresInteractiveSetup(rendered) {
                finishOnQueue(
                    with: .unavailable(
                        .claude,
                        detail: "Run Claude Code once to complete setup"
                    ),
                    generation: generation
                )
                return
            }

            if promptIsReady(rendered) {
                requestUsageOnQueue(generation: generation)
            }
        }

        guard phase == .waitingForUsage,
              !rendered.localizedCaseInsensitiveContains("Refreshing") else {
            return
        }

        guard let usage = try? ClaudeUsageParser.parse(screen: rendered) else {
            return
        }

        // Claude redraws the screen in pieces. Keep replacing the normalized
        // snapshot, then accept it only after a short quiet period so the
        // weekly window has time to arrive too.
        pendingUsage = usage
        parseGeneration += 1
        let currentParseGeneration = parseGeneration
        ioQueue.asyncAfter(deadline: .now() + 0.9) { [weak self] in
            guard let self,
                  generation == self.probeGeneration,
                  currentParseGeneration == self.parseGeneration,
                  self.phase == .waitingForUsage,
                  let pendingUsage = self.pendingUsage else {
                return
            }
            self.finishOnQueue(with: pendingUsage, generation: generation)
        }
    }

    private func scheduleCommandFallbackOnQueue(generation: Int) {
        ioQueue.asyncAfter(deadline: .now() + 4) { [weak self] in
            guard let self,
                  generation == self.probeGeneration,
                  self.phase == .waitingForPrompt else {
                return
            }

            let rendered = self.screen?.renderedText ?? ""
            if self.requiresInteractiveSetup(rendered) {
                self.finishOnQueue(
                    with: .unavailable(
                        .claude,
                        detail: "Run Claude Code once to complete setup"
                    ),
                    generation: generation
                )
            } else if self.promptIsReady(rendered) {
                self.requestUsageOnQueue(generation: generation)
            } else {
                // Never type into an unknown Claude screen. A new CLI version,
                // consent dialog, or account warning must be handled by the
                // user in Claude Code itself first.
                self.finishOnQueue(
                    with: .unavailable(
                        .claude,
                        detail: "Claude prompt not ready"
                    ),
                    generation: generation
                )
            }
        }
    }

    private func scheduleTimeoutOnQueue(generation: Int) {
        timeoutGeneration += 1
        let timeout = timeoutGeneration
        ioQueue.asyncAfter(deadline: .now() + Self.probeTimeout) { [weak self] in
            guard let self,
                  generation == self.probeGeneration,
                  timeout == self.timeoutGeneration,
                  self.phase == .waitingForPrompt || self.phase == .waitingForUsage else {
                return
            }
            self.finishOnQueue(
                with: .failed(.claude, detail: "Claude usage timed out"),
                generation: generation
            )
        }
    }

    private func requestUsageOnQueue(generation: Int) {
        guard generation == probeGeneration,
              phase == .waitingForPrompt || phase == .ready else {
            return
        }
        screen = ANSIScreen(columns: 100, rows: 36)
        pendingUsage = nil
        terminalResultPublished = false
        phase = .waitingForUsage
        writeOnQueue(Data("/usage\r".utf8))
        scheduleTimeoutOnQueue(generation: generation)
    }

    private func finishOnQueue(with usage: ProviderUsage, generation: Int) {
        guard generation == probeGeneration,
              phase != .idle,
              phase != .exiting else {
            return
        }

        terminalResultPublished = true
        timeoutGeneration += 1
        publish(usage)

        if usage.state == .live {
            returnToReadyOnQueue(generation: generation)
        } else {
            beginCleanExitOnQueue(generation: generation)
        }
    }

    private func returnToReadyOnQueue(generation: Int) {
        guard generation == probeGeneration, process?.isRunning == true else { return }
        phase = .ready
        pendingUsage = nil
        parseGeneration += 1
        writeOnQueue(Data([0x1B]))

        // Discard the finished modal after Claude has redrawn its home screen.
        ioQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self,
                  generation == self.probeGeneration,
                  self.phase == .ready else {
                return
            }
            self.screen = ANSIScreen(columns: 100, rows: 36)
            self.terminalResultPublished = false
        }
    }

    private func beginCleanExitOnQueue(generation: Int) {
        phase = .exiting
        writeOnQueue(Data([0x1B]))

        ioQueue.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            guard let self,
                  generation == self.probeGeneration,
                  self.phase == .exiting,
                  self.process?.isRunning == true else {
                return
            }
            self.writeOnQueue(Data("/exit\r".utf8))
        }

        ioQueue.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self,
                  generation == self.probeGeneration,
                  self.phase == .exiting,
                  self.process?.isRunning == true else {
                return
            }
            self.process?.terminate()
        }
    }

    private func handleTerminationOnQueue(generation: Int) {
        guard generation == probeGeneration else { return }

        let shouldReport = !stoppedByClient && !terminalResultPublished
        let rendered = screen?.renderedText ?? ""
        resetProcessStateOnQueue()

        guard shouldReport else { return }
        if requiresInteractiveSetup(rendered) {
            publish(.unavailable(.claude, detail: "Run Claude Code once to complete setup"))
        } else {
            publish(.failed(.claude, detail: "Claude usage unavailable"))
        }
    }

    private func writeOnQueue(_ data: Data) {
        guard let handle = inputPipe?.fileHandleForWriting else { return }
        do {
            try handle.write(contentsOf: data)
        } catch {
            // A closing PTY is expected during normal shutdown. Never include
            // terminal output or account details in an error path.
        }
    }

    private func resetProcessStateOnQueue() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        inputPipe?.fileHandleForWriting.closeFile()
        process = nil
        inputPipe = nil
        outputPipe = nil
        errorPipe = nil
        screen = nil
        pendingUsage = nil
        timeoutGeneration += 1
        phase = .idle
    }

    private func prepareWorkingDirectory() -> URL? {
        guard let cachesURL = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }

        let directory = cachesURL
            .appendingPathComponent("com.patrickradulescu.QuotaBar", isDirectory: true)
            .appendingPathComponent("ClaudeProbe", isDirectory: true)

        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o700],
                ofItemAtPath: directory.path
            )
            return directory
        } catch {
            return nil
        }
    }

    private func promptIsReady(_ rendered: String) -> Bool {
        let lowercased = rendered.lowercased()
        let safeModeHome = lowercased.contains("claude code v") &&
            lowercased.contains("safe mode: all customizations are disabled") &&
            (lowercased.contains("welcome back") || lowercased.contains("/effort"))

        return safeModeHome ||
            lowercased.contains("for shortcuts") ||
            lowercased.contains("claude code") && lowercased.contains("help")
    }

    private func requiresInteractiveSetup(_ rendered: String) -> Bool {
        let lowercased = rendered.lowercased()
        return [
            "choose the text style",
            "select login method",
            "login with",
            "authentication required",
            "not logged in",
            "do you trust the files",
            "trust this folder",
            "press enter to continue"
        ].contains { lowercased.contains($0) }
    }

    private func publish(_ usage: ProviderUsage) {
        DispatchQueue.main.async { [weak self] in
            self?.onUpdate?(usage)
        }
    }
}
