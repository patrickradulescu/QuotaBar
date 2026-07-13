import Foundation
import Security

enum CommandLocator {
    static func codex() -> URL? {
        firstSignedExecutable(
            [
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
                "/Applications/ChatGPT.app/Contents/Resources/codex",
                "\(NSHomeDirectory())/Applications/ChatGPT.app/Contents/Resources/codex"
            ],
            teamIdentifier: "2DC432GLL2",
            signingIdentifier: "codex"
        )
    }

    static func claude() -> URL? {
        firstSignedExecutable(
            [
                "/opt/homebrew/bin/claude",
                "/usr/local/bin/claude",
                "\(NSHomeDirectory())/.local/bin/claude"
            ],
            teamIdentifier: "Q6L2SF6YDW",
            signingIdentifier: "com.anthropic.claude-code"
        )
    }

    private static func firstSignedExecutable(
        _ candidates: [String],
        teamIdentifier: String,
        signingIdentifier: String
    ) -> URL? {
        for path in candidates {
            let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard FileManager.default.isExecutableFile(atPath: resolved.path),
                  hasValidSignature(
                    resolved,
                    teamIdentifier: teamIdentifier,
                    signingIdentifier: signingIdentifier
                  ) else {
                continue
            }
            return resolved
        }
        return nil
    }

    private static func hasValidSignature(
        _ url: URL,
        teamIdentifier: String,
        signingIdentifier: String
    ) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return false
        }

        let source = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(signingIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            source as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess else {
            return false
        }

        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }
}
