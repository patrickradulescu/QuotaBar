import Foundation

public struct ReleaseVersion: Comparable, CustomStringConvertible, Equatable, Sendable {
    public let major: Int
    public let minor: Int
    public let patch: Int
    public let prereleaseIdentifiers: [String]

    public init?(_ value: String) {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.first == "v" || normalized.first == "V" {
            normalized.removeFirst()
        }

        guard !normalized.isEmpty else { return nil }

        let buildParts = normalized.split(
            separator: "+",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard let coreAndPrerelease = buildParts.first,
              !coreAndPrerelease.isEmpty,
              buildParts.count == 1 || !buildParts[1].isEmpty else {
            return nil
        }
        normalized = String(coreAndPrerelease)
        let versionAndPrerelease = normalized.split(
            separator: "-",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        let core = versionAndPrerelease[0].split(
            separator: ".",
            omittingEmptySubsequences: false
        )

        guard (1...3).contains(core.count),
              core.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else {
            return nil
        }

        var numbers = core.compactMap { Int($0) }
        guard numbers.count == core.count else { return nil }
        while numbers.count < 3 {
            numbers.append(0)
        }

        let prerelease: [String]
        if versionAndPrerelease.count == 2 {
            prerelease = versionAndPrerelease[1].split(
                separator: ".",
                omittingEmptySubsequences: false
            ).map(String.init)
            guard !prerelease.isEmpty,
                  prerelease.allSatisfy({ identifier in
                    !identifier.isEmpty && identifier.utf8.allSatisfy { byte in
                        (48...57).contains(byte)
                            || (65...90).contains(byte)
                            || (97...122).contains(byte)
                            || byte == 45
                    }
                  }) else {
                return nil
            }
        } else {
            prerelease = []
        }

        major = numbers[0]
        minor = numbers[1]
        patch = numbers[2]
        prereleaseIdentifiers = prerelease
    }

    public var description: String {
        let core = "\(major).\(minor).\(patch)"
        guard !prereleaseIdentifiers.isEmpty else { return core }
        return core + "-" + prereleaseIdentifiers.joined(separator: ".")
    }

    public static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        let lhsCore = [lhs.major, lhs.minor, lhs.patch]
        let rhsCore = [rhs.major, rhs.minor, rhs.patch]
        if lhsCore != rhsCore {
            return lhsCore.lexicographicallyPrecedes(rhsCore)
        }

        if lhs.prereleaseIdentifiers.isEmpty {
            return false
        }
        if rhs.prereleaseIdentifiers.isEmpty {
            return true
        }

        for (left, right) in zip(lhs.prereleaseIdentifiers, rhs.prereleaseIdentifiers) {
            if left == right { continue }
            let leftNumber = Int(left)
            let rightNumber = Int(right)
            switch (leftNumber, rightNumber) {
            case let (.some(left), .some(right)):
                return left < right
            case (.some, .none):
                return true
            case (.none, .some):
                return false
            case (.none, .none):
                return left < right
            }
        }

        return lhs.prereleaseIdentifiers.count < rhs.prereleaseIdentifiers.count
    }
}

public struct GitHubRelease: Equatable, Sendable {
    public let version: ReleaseVersion
    public let tagName: String
    public let pageURL: URL

    public init(version: ReleaseVersion, tagName: String, pageURL: URL) {
        self.version = version
        self.tagName = tagName
        self.pageURL = pageURL
    }
}

public enum GitHubReleaseParser {
    public enum ParseError: Error, Equatable {
        case malformedResponse
        case unpublishedRelease
        case invalidVersion
        case untrustedReleaseURL
    }

    private struct Response: Decodable {
        let tagName: String
        let htmlURL: String
        let draft: Bool
        let prerelease: Bool

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case draft
            case prerelease
        }
    }

    public static func parse(data: Data) throws -> GitHubRelease {
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw ParseError.malformedResponse
        }
        guard !response.draft, !response.prerelease else {
            throw ParseError.unpublishedRelease
        }
        guard let version = ReleaseVersion(response.tagName) else {
            throw ParseError.invalidVersion
        }
        guard let pageURL = URL(string: response.htmlURL),
              pageURL.scheme?.lowercased() == "https",
              pageURL.host?.lowercased() == "github.com",
              pageURL.user == nil,
              pageURL.password == nil,
              pageURL.port == nil,
              pageURL.query == nil,
              pageURL.fragment == nil,
              pageURL.path == "/patrickradulescu/QuotaBar/releases/tag/\(response.tagName)" else {
            throw ParseError.untrustedReleaseURL
        }

        return GitHubRelease(
            version: version,
            tagName: response.tagName,
            pageURL: pageURL
        )
    }
}
