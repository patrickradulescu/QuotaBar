import Foundation
import QuotaBarCore

enum UpdateCheckOutcome {
    case updateAvailable(current: ReleaseVersion, latest: GitHubRelease)
    case upToDate(current: ReleaseVersion, latest: GitHubRelease)
}

final class UpdateChecker {
    enum CheckError: Error {
        case invalidCurrentVersion
        case invalidResponse
        case responseTooLarge
    }

    private static let latestReleaseURL = URL(
        string: "https://api.github.com/repos/patrickradulescu/QuotaBar/releases/latest"
    )!
    private static let maximumResponseBytes = 256 * 1_024

    private let session: URLSession
    private var task: URLSessionDataTask?

    init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        session = URLSession(configuration: configuration)
    }

    deinit {
        task?.cancel()
        session.invalidateAndCancel()
    }

    func check(
        currentVersion: String,
        completion: @escaping (Result<UpdateCheckOutcome, Error>) -> Void
    ) {
        task?.cancel()

        guard let current = ReleaseVersion(currentVersion) else {
            completion(.failure(CheckError.invalidCurrentVersion))
            return
        }

        var request = URLRequest(url: Self.latestReleaseURL)
        request.httpMethod = "GET"
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue("QuotaBar/\(current.description)", forHTTPHeaderField: "User-Agent")

        task = session.dataTask(with: request) { data, response, error in
            let result: Result<UpdateCheckOutcome, Error>

            if let error {
                result = .failure(error)
            } else if let response = response as? HTTPURLResponse,
                      response.statusCode == 200,
                      let data {
                if data.count > Self.maximumResponseBytes {
                    result = .failure(CheckError.responseTooLarge)
                } else {
                    do {
                        let latest = try GitHubReleaseParser.parse(data: data)
                        result = latest.version > current
                            ? .success(.updateAvailable(current: current, latest: latest))
                            : .success(.upToDate(current: current, latest: latest))
                    } catch {
                        result = .failure(error)
                    }
                }
            } else {
                result = .failure(CheckError.invalidResponse)
            }

            DispatchQueue.main.async {
                completion(result)
            }
        }
        task?.resume()
    }
}
