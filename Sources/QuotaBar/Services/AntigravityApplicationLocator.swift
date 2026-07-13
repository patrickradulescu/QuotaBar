import AppKit
import Foundation

struct AntigravityApplication: Sendable {
    let url: URL
    let bundleIdentifier: String
}

enum AntigravityApplicationLocator {
    private static let googleTeamIdentifier = "EQHXZ8M8AV"
    private static let applications: [(bundleIdentifier: String, paths: [String])] = [
        (
            "com.google.antigravity",
            [
                "/Applications/Antigravity.app",
                "\(NSHomeDirectory())/Applications/Antigravity.app"
            ]
        ),
        (
            "com.google.antigravity-ide",
            [
                "/Applications/Antigravity IDE.app",
                "\(NSHomeDirectory())/Applications/Antigravity IDE.app"
            ]
        )
    ]

    static func locate(preferredBundleIdentifier: String? = nil) -> AntigravityApplication? {
        var orderedApplications = applications
        if let preferredBundleIdentifier,
           let preferredIndex = orderedApplications.firstIndex(where: {
               $0.bundleIdentifier == preferredBundleIdentifier
           }) {
            let preferred = orderedApplications.remove(at: preferredIndex)
            orderedApplications.insert(preferred, at: 0)
        }

        for application in orderedApplications {
            var candidates = application.paths.map(URL.init(fileURLWithPath:))
            if let registered = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: application.bundleIdentifier
            ) {
                candidates.append(registered)
            }

            var inspectedPaths = Set<String>()
            for candidate in candidates {
                let resolved = candidate.resolvingSymlinksInPath()
                guard inspectedPaths.insert(resolved.path).inserted,
                      FileManager.default.fileExists(atPath: resolved.path),
                      CodeSignatureVerifier.hasValidSignature(
                          resolved,
                          teamIdentifier: googleTeamIdentifier,
                          signingIdentifier: application.bundleIdentifier
                      ) else {
                    continue
                }

                return AntigravityApplication(
                    url: resolved,
                    bundleIdentifier: application.bundleIdentifier
                )
            }
        }

        return nil
    }
}
