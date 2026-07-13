import Foundation
import XCTest
@testable import QuotaBarCore

final class UpdateCheckerTests: XCTestCase {
    override func tearDown() {
        UpdateURLProtocol.setStubs([])
        super.tearDown()
    }

    func testReportsUpToDateOnEqualRelease() throws {
        let result = runCheck(currentVersion: "0.4.0", stub: .response(
            status: 200,
            data: releaseData(tag: "v0.4.0")
        ))

        guard case let .success(.upToDate(current, latest)) = result else {
            return XCTFail("Expected up-to-date result")
        }
        XCTAssertEqual(current, ReleaseVersion("0.4.0"))
        XCTAssertEqual(latest.version, ReleaseVersion("0.4.0"))
    }

    func testReportsNewerStableRelease() {
        let result = runCheck(currentVersion: "0.3.0", stub: .response(
            status: 200,
            data: releaseData(tag: "v0.4.0")
        ))

        guard case let .success(.updateAvailable(current, latest)) = result else {
            return XCTFail("Expected update-available result")
        }
        XCTAssertEqual(current, ReleaseVersion("0.3.0"))
        XCTAssertEqual(latest.version, ReleaseVersion("0.4.0"))
    }

    func testRejectsMalformedSuccessfulResponse() {
        assertError(
            .invalidReleaseFeed,
            result: runCheck(currentVersion: "0.4.0", stub: .response(
                status: 200,
                data: Data("not-json".utf8)
            ))
        )
    }

    func testClassifiesRateLimitAndServerErrors() {
        for (status, expected) in [
            (403, UpdateChecker.CheckError.rateLimited),
            (429, .rateLimited),
            (503, .serverUnavailable)
        ] {
            assertError(
                expected,
                result: runCheck(currentVersion: "0.4.0", stub: .response(
                    status: status,
                    data: Data()
                ))
            )
        }
    }

    func testRejectsOversizedResponseBeforeBodyDownload() {
        assertError(
            .responseTooLarge,
            result: runCheck(currentVersion: "0.4.0", stub: .response(
                status: 200,
                data: Data(repeating: 0x41, count: 256 * 1_024 + 1),
                headers: ["Content-Length": String(256 * 1_024 + 1)]
            ))
        )
    }

    func testRejectsOversizedUnknownLengthStreamingResponse() {
        assertError(
            .responseTooLarge,
            result: runCheck(currentVersion: "0.4.0", stub: .response(
                status: 200,
                data: Data(repeating: 0x41, count: 256 * 1_024 + 1)
            ))
        )
    }

    func testClassifiesTimeoutAndOfflineErrors() {
        assertError(
            .timedOut,
            result: runCheck(
                currentVersion: "0.4.0",
                stub: .failure(URLError(.timedOut))
            )
        )
        assertError(
            .networkUnavailable,
            result: runCheck(
                currentVersion: "0.4.0",
                stub: .failure(URLError(.notConnectedToInternet))
            )
        )
    }

    func testRejectsInvalidInstalledVersionOnMainThread() {
        let completion = expectation(description: "completion")
        let checker = makeChecker()

        checker.check(currentVersion: "broken") { result in
            XCTAssertTrue(Thread.isMainThread)
            self.assertError(.invalidCurrentVersion, result: result)
            completion.fulfill()
        }

        wait(for: [completion], timeout: 2)
    }

    func testNewestCheckSuppressesQueuedOlderCompletion() {
        let firstRequestStarted = expectation(description: "first request started")
        UpdateURLProtocol.setStubs([
            .delayedResponse(
                status: 200,
                data: releaseData(tag: "v0.4.0"),
                delay: 0.2
            ),
            .response(status: 200, data: releaseData(tag: "v0.4.2"))
        ], onFirstStart: {
            firstRequestStarted.fulfill()
        })
        let staleCompletion = expectation(description: "stale completion")
        staleCompletion.isInverted = true
        let latestCompletion = expectation(description: "latest completion")
        let checker = makeChecker()

        checker.check(currentVersion: "0.3.0") { _ in
            staleCompletion.fulfill()
        }
        wait(for: [firstRequestStarted], timeout: 1)
        checker.check(currentVersion: "0.4.0") { result in
            guard case let .success(.updateAvailable(_, latest)) = result else {
                return XCTFail("Expected latest update result")
            }
            XCTAssertEqual(latest.version, ReleaseVersion("0.4.2"))
            latestCompletion.fulfill()
        }

        wait(for: [latestCompletion, staleCompletion], timeout: 2)
    }

    func testInvalidVersionCompletionCannotBeatNewerValidCheck() {
        UpdateURLProtocol.setStubs([
            .response(status: 200, data: releaseData(tag: "v0.4.1"))
        ])
        let staleCompletion = expectation(description: "invalid stale completion")
        staleCompletion.isInverted = true
        let latestCompletion = expectation(description: "valid latest completion")
        let checker = makeChecker()

        checker.check(currentVersion: "broken") { _ in
            staleCompletion.fulfill()
        }
        checker.check(currentVersion: "0.4.0") { result in
            guard case let .success(.updateAvailable(_, latest)) = result else {
                return XCTFail("Expected valid latest result")
            }
            XCTAssertEqual(latest.version, ReleaseVersion("0.4.1"))
            latestCompletion.fulfill()
        }

        wait(for: [latestCompletion, staleCompletion], timeout: 2)
    }

    private func runCheck(
        currentVersion: String,
        stub: UpdateURLProtocol.Stub
    ) -> Result<UpdateCheckOutcome, Error> {
        UpdateURLProtocol.setStubs([stub])
        let completion = expectation(description: "update check")
        let checker = makeChecker()
        var captured: Result<UpdateCheckOutcome, Error>?

        checker.check(currentVersion: currentVersion) { result in
            XCTAssertTrue(Thread.isMainThread)
            captured = result
            completion.fulfill()
        }

        wait(for: [completion], timeout: 3)
        return captured ?? .failure(UpdateChecker.CheckError.invalidResponse)
    }

    private func makeChecker() -> UpdateChecker {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [UpdateURLProtocol.self]
        return UpdateChecker(
            configuration: configuration,
            releaseURL: URL(string: "https://updates.example.test/latest")!
        )
    }

    private func releaseData(tag: String) -> Data {
        Data(
            """
            {
              "tag_name": "\(tag)",
              "html_url": "https://github.com/patrickradulescu/QuotaBar/releases/tag/\(tag)",
              "draft": false,
              "prerelease": false
            }
            """.utf8
        )
    }

    private func assertError(
        _ expected: UpdateChecker.CheckError,
        result: Result<UpdateCheckOutcome, Error>,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard case let .failure(error) = result else {
            return XCTFail("Expected failure", file: file, line: line)
        }
        XCTAssertEqual(error as? UpdateChecker.CheckError, expected, file: file, line: line)
    }
}

private final class UpdateURLProtocol: URLProtocol {
    enum Stub {
        case response(status: Int, data: Data, headers: [String: String] = [:])
        case delayedResponse(status: Int, data: Data, delay: TimeInterval)
        case failure(Error)
    }

    private static let stateLock = NSLock()
    private static var stubs: [Stub] = []
    private static var onFirstStart: (() -> Void)?
    private let instanceLock = NSLock()
    private var stopped = false

    static func setStubs(
        _ newStubs: [Stub],
        onFirstStart: (() -> Void)? = nil
    ) {
        stateLock.lock()
        stubs = newStubs
        self.onFirstStart = onFirstStart
        stateLock.unlock()
    }

    private static func takeStub() -> (Stub, (() -> Void)?)? {
        stateLock.lock()
        defer { stateLock.unlock() }
        guard !stubs.isEmpty else { return nil }
        let callback = onFirstStart
        onFirstStart = nil
        return (stubs.removeFirst(), callback)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let (stub, onStart) = Self.takeStub() else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        onStart?()

        switch stub {
        case let .response(status, data, headers):
            deliver(status: status, data: data, headers: headers)
        case let .delayedResponse(status, data, delay):
            DispatchQueue.global().asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.deliver(status: status, data: data, headers: [:])
            }
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    private func deliver(status: Int, data: Data, headers: [String: String]) {
        instanceLock.lock()
        let shouldStop = stopped
        instanceLock.unlock()
        guard !shouldStop else { return }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        if !data.isEmpty {
            client?.urlProtocol(self, didLoad: data)
        }
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {
        instanceLock.lock()
        stopped = true
        instanceLock.unlock()
    }
}
