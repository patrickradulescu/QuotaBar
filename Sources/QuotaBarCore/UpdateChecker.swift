import Foundation

public enum UpdateCheckOutcome {
    case updateAvailable(current: ReleaseVersion, latest: GitHubRelease)
    case upToDate(current: ReleaseVersion, latest: GitHubRelease)
}

public final class UpdateChecker {
    public enum CheckError: Error, Equatable {
        case invalidCurrentVersion
        case invalidResponse
        case responseTooLarge
        case rateLimited
        case serverUnavailable
        case invalidReleaseFeed
        case timedOut
        case networkUnavailable
    }

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/patrickradulescu/QuotaBar/releases/latest"
    )!
    private static let maximumResponseBytes = 256 * 1_024

    private let configuration: URLSessionConfiguration
    private let releaseURL: URL
    private let stateLock = NSLock()
    private var activeRequest: UpdateRequest?
    private var requestGeneration = 0

    public init() {
        configuration = Self.ephemeralConfiguration()
        releaseURL = Self.latestReleaseURL
    }

    public init(configuration: URLSessionConfiguration, releaseURL: URL) {
        self.configuration = configuration
        self.releaseURL = releaseURL
    }

    deinit {
        stateLock.lock()
        requestGeneration &+= 1
        let request = activeRequest
        activeRequest = nil
        stateLock.unlock()
        request?.cancel()
    }

    public func check(
        currentVersion: String,
        completion: @escaping (Result<UpdateCheckOutcome, Error>) -> Void
    ) {
        stateLock.lock()
        requestGeneration &+= 1
        let generation = requestGeneration
        let previousRequest = activeRequest
        activeRequest = nil
        stateLock.unlock()
        previousRequest?.cancel()

        guard let current = ReleaseVersion(currentVersion) else {
            DispatchQueue.main.async { [weak self] in
                guard self?.isCurrent(generation: generation) == true else { return }
                completion(.failure(CheckError.invalidCurrentVersion))
            }
            return
        }

        let request = UpdateRequest(
            configuration: configuration,
            releaseURL: releaseURL,
            maximumResponseBytes: Self.maximumResponseBytes,
            current: current
        ) { [weak self] result in
            guard self?.finishIfCurrent(generation: generation) == true else { return }
            completion(result)
        }

        stateLock.lock()
        guard generation == requestGeneration else {
            stateLock.unlock()
            request.cancel()
            return
        }
        activeRequest = request
        stateLock.unlock()
        request.start()
    }

    private func isCurrent(generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return generation == requestGeneration
    }

    private func finishIfCurrent(generation: Int) -> Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard generation == requestGeneration else { return false }
        activeRequest = nil
        return true
    }

    private static func ephemeralConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        return configuration
    }
}

private final class UpdateRequest: NSObject, URLSessionDataDelegate, @unchecked Sendable {
    private let configuration: URLSessionConfiguration
    private let releaseURL: URL
    private let maximumResponseBytes: Int
    private let current: ReleaseVersion
    private let completion: (Result<UpdateCheckOutcome, Error>) -> Void
    private let stateLock = NSLock()

    private var session: URLSession?
    private var task: URLSessionDataTask?
    private var responseData = Data()
    private var pendingError: UpdateChecker.CheckError?
    private var hasCompleted = false

    init(
        configuration: URLSessionConfiguration,
        releaseURL: URL,
        maximumResponseBytes: Int,
        current: ReleaseVersion,
        completion: @escaping (Result<UpdateCheckOutcome, Error>) -> Void
    ) {
        self.configuration = configuration
        self.releaseURL = releaseURL
        self.maximumResponseBytes = maximumResponseBytes
        self.current = current
        self.completion = completion
    }

    func start() {
        var request = URLRequest(url: releaseURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("QuotaBar/\(current.description)", forHTTPHeaderField: "User-Agent")

        let session = URLSession(
            configuration: configuration,
            delegate: self,
            delegateQueue: nil
        )
        let task = session.dataTask(with: request)
        stateLock.lock()
        guard !hasCompleted else {
            stateLock.unlock()
            session.invalidateAndCancel()
            return
        }
        self.session = session
        self.task = task
        stateLock.unlock()
        task.resume()
    }

    func cancel() {
        stateLock.lock()
        guard !hasCompleted else {
            stateLock.unlock()
            return
        }
        hasCompleted = true
        let task = task
        let session = session
        self.task = nil
        self.session = nil
        stateLock.unlock()
        task?.cancel()
        session?.invalidateAndCancel()
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
    ) {
        guard let response = response as? HTTPURLResponse else {
            setPendingError(.invalidResponse)
            completionHandler(.cancel)
            return
        }

        switch response.statusCode {
        case 200:
            if response.expectedContentLength > Int64(maximumResponseBytes) {
                setPendingError(.responseTooLarge)
                completionHandler(.cancel)
            } else {
                completionHandler(.allow)
            }
        case 403, 429:
            setPendingError(.rateLimited)
            completionHandler(.cancel)
        case 500...599:
            setPendingError(.serverUnavailable)
            completionHandler(.cancel)
        default:
            setPendingError(.invalidResponse)
            completionHandler(.cancel)
        }
    }

    func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        stateLock.lock()
        guard !hasCompleted, pendingError == nil else {
            stateLock.unlock()
            return
        }
        guard data.count <= maximumResponseBytes - responseData.count else {
            pendingError = .responseTooLarge
            stateLock.unlock()
            dataTask.cancel()
            return
        }
        responseData.append(data)
        stateLock.unlock()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        stateLock.lock()
        guard !hasCompleted else {
            stateLock.unlock()
            return
        }
        hasCompleted = true
        let pendingError = pendingError
        let responseData = responseData
        self.task = nil
        self.session = nil
        stateLock.unlock()

        let result: Result<UpdateCheckOutcome, Error>
        if let pendingError {
            result = .failure(pendingError)
        } else if let urlError = error as? URLError {
            result = .failure(Self.classify(urlError))
        } else if error != nil {
            result = .failure(UpdateChecker.CheckError.networkUnavailable)
        } else {
            do {
                let latest = try GitHubReleaseParser.parse(data: responseData)
                result = latest.version > current
                    ? .success(.updateAvailable(current: current, latest: latest))
                    : .success(.upToDate(current: current, latest: latest))
            } catch {
                result = .failure(UpdateChecker.CheckError.invalidReleaseFeed)
            }
        }

        session.finishTasksAndInvalidate()
        DispatchQueue.main.async { [completion] in
            completion(result)
        }
    }

    private func setPendingError(_ error: UpdateChecker.CheckError) {
        stateLock.lock()
        if !hasCompleted, pendingError == nil {
            pendingError = error
        }
        stateLock.unlock()
    }

    private static func classify(_ error: URLError) -> UpdateChecker.CheckError {
        if error.code == .timedOut {
            return .timedOut
        }
        return .networkUnavailable
    }
}
