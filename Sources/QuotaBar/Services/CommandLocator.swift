import Foundation

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

    static func agy() -> URL? {
        firstSignedExecutable(
            [
                "\(NSHomeDirectory())/.local/bin/agy",
                "/opt/homebrew/bin/agy",
                "/usr/local/bin/agy"
            ],
            teamIdentifier: "EQHXZ8M8AV",
            signingIdentifier: "cli"
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
                  CodeSignatureVerifier.hasValidSignature(
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
}
