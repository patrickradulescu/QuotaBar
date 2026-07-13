import Foundation
import XCTest
@testable import QuotaBarCore

final class AgyStatusPayloadTests: XCTestCase {
    private let observedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func testSanitizesCurrentQuotaPayloadAndConvertsRemainingToUsed() throws {
        let snapshot = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt
        ))

        XCTAssertEqual(snapshot.schemaVersion, 1)
        XCTAssertEqual(snapshot.sourceVersion, "1.1.1")
        XCTAssertEqual(snapshot.fiveHour?.remainingFraction, 0.9924045)
        XCTAssertEqual(snapshot.weekly?.remainingFraction, 0.99873406)

        let usage = try XCTUnwrap(snapshot.normalizedUsage(
            now: observedAt,
            maximumAge: 60
        ))
        XCTAssertEqual(usage.primary?.windowMinutes, 300)
        XCTAssertEqual(usage.primary?.usedPercent ?? -1, 0.75955, accuracy: 0.000_001)
        XCTAssertEqual(usage.secondary?.windowMinutes, 10_080)
        XCTAssertEqual(usage.secondary?.usedPercent ?? -1, 0.126594, accuracy: 0.000_001)
        XCTAssertEqual(
            snapshot.compactStatusLine,
            "QuotaBar · Gemini · 5H 99.24% LEFT · WK 99.87% LEFT"
        )
    }

    func testIgnoresNullQuotaStartupEvents() throws {
        let data = Data(#"{"version":"1.1.1","email":"private@example.com","quota":null}"#.utf8)
        XCTAssertNil(try AgyStatusPayloadParser.parse(data: data, observedAt: observedAt))
    }

    func testSupportsWeeklyOnlyPlans() throws {
        let data = Data(
            #"{"version":"1.1.1","quota":{"gemini-weekly":{"remaining_fraction":0.75,"reset_in_seconds":7200}}}"#.utf8
        )
        let snapshot = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: data,
            observedAt: observedAt
        ))
        let usage = try XCTUnwrap(snapshot.normalizedUsage(now: observedAt))

        XCTAssertEqual(usage.primary?.windowMinutes, 10_080)
        XCTAssertEqual(usage.primary?.usedPercent, 25)
        XCTAssertNil(usage.secondary)
    }

    func testDropsInvalidBucketButKeepsValidBucket() throws {
        let data = Data(
            #"{"quota":{"gemini-5h":{"remaining_fraction":2},"gemini-weekly":{"remaining_fraction":0.4}}}"#.utf8
        )
        let snapshot = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: data,
            observedAt: observedAt
        ))

        XCTAssertNil(snapshot.fiveHour)
        XCTAssertEqual(snapshot.weekly?.remainingFraction, 0.4)
    }

    func testFallsBackToResetDurationWhenTimestampIsStale() throws {
        let data = Data(
            #"{"quota":{"gemini-5h":{"remaining_fraction":0.5,"reset_time":"2020-01-01T00:00:00Z","reset_in_seconds":3600}}}"#.utf8
        )
        let snapshot = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: data,
            observedAt: observedAt
        ))

        XCTAssertEqual(
            snapshot.fiveHour?.resetsAt,
            observedAt.addingTimeInterval(3600)
        )
    }

    func testRejectsPayloadWithoutValidGeminiQuota() {
        let data = Data(#"{"quota":{"3p-5h":{"remaining_fraction":1}}}"#.utf8)
        XCTAssertThrowsError(try AgyStatusPayloadParser.parse(data: data)) { error in
            XCTAssertEqual(error as? AgyStatusPayloadParser.ParseError, .invalidQuota)
        }
    }

    func testRejectsMalformedPayload() {
        XCTAssertThrowsError(try AgyStatusPayloadParser.parse(data: Data("not json".utf8))) { error in
            XCTAssertEqual(error as? AgyStatusPayloadParser.ParseError, .malformedPayload)
        }
    }

    func testRejectsStaleFutureAndExpiredCache() throws {
        let snapshot = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt
        ))

        XCTAssertNil(snapshot.normalizedUsage(
            now: observedAt.addingTimeInterval(31 * 60),
            maximumAge: 30 * 60
        ))
        XCTAssertNil(snapshot.normalizedUsage(
            now: observedAt.addingTimeInterval(-6 * 60),
            maximumAge: 30 * 60
        ))
    }

    func testCacheRoundTripContainsOnlyNormalizedFields() throws {
        let snapshot = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt
        ))
        let encoded = try AgyQuotaCacheCodec.encode(snapshot)
        let text = try XCTUnwrap(String(data: encoded, encoding: .utf8))

        XCTAssertFalse(text.contains("private@example.com"))
        XCTAssertFalse(text.contains("/Users/private/project"))
        XCTAssertFalse(text.contains("conversation_id"))
        XCTAssertEqual(try AgyQuotaCacheCodec.decode(encoded), snapshot)
    }

    func testCachePolicyThrottlesOnlyBrieflyWhenQuotaIsUnchanged() throws {
        let existing = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt
        ))
        let immediate = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt.addingTimeInterval(14)
        ))
        let later = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt.addingTimeInterval(16)
        ))

        XCTAssertFalse(AgyQuotaCachePolicy.shouldPersist(
            incoming: immediate,
            replacing: existing
        ))
        XCTAssertTrue(AgyQuotaCachePolicy.shouldPersist(
            incoming: later,
            replacing: existing
        ))
    }

    func testCachePolicyPersistsChangedQuotaImmediately() throws {
        let existing = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt
        ))
        let changedData = Data(
            String(decoding: Self.currentPayload, as: UTF8.self)
                .replacingOccurrences(of: "0.9924045", with: "0.9")
                .utf8
        )
        let changed = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: changedData,
            observedAt: observedAt.addingTimeInterval(1)
        ))

        XCTAssertTrue(AgyQuotaCachePolicy.shouldPersist(
            incoming: changed,
            replacing: existing
        ))
    }

    func testCachePolicyRecoversFromFutureDatedExistingCache() throws {
        let incoming = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt
        ))
        let futureExisting = try XCTUnwrap(AgyStatusPayloadParser.parse(
            data: Self.currentPayload,
            observedAt: observedAt.addingTimeInterval(60)
        ))

        XCTAssertTrue(AgyQuotaCachePolicy.shouldPersist(
            incoming: incoming,
            replacing: futureExisting
        ))
    }

    private static let currentPayload = Data(
        """
        {
          "version": "1.1.1",
          "email": "private@example.com",
          "cwd": "/Users/private/project",
          "conversation_id": "secret-conversation",
          "quota": {
            "3p-5h": {
              "remaining_fraction": 1,
              "reset_time": "2023-11-15T03:13:20Z",
              "reset_in_seconds": 17984
            },
            "gemini-5h": {
              "remaining_fraction": 0.9924045,
              "reset_time": "2023-11-15T03:13:20Z",
              "reset_in_seconds": 17424
            },
            "gemini-weekly": {
              "remaining_fraction": 0.99873406,
              "reset_time": "2023-11-20T22:13:20Z",
              "reset_in_seconds": 604224
            }
          }
        }
        """.utf8
    )
}
