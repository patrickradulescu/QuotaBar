import Foundation

/// A deliberately small environment for provider helpers.
///
/// QuotaBar never forwards its complete inherited environment because developer
/// shells and launch agents often contain unrelated API keys, proxy credentials,
/// loader hooks, or tool-specific overrides.
enum ProviderProcessEnvironment {
    static func minimal(columns: Int? = nil, rows: Int? = nil) -> [String: String] {
        let parent = ProcessInfo.processInfo.environment
        var environment: [String: String] = [:]

        for key in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "LC_ALL", "LC_CTYPE", "TZ"] {
            if let value = parent[key], !value.isEmpty {
                environment[key] = value
            }
        }

        environment["HOME"] = environment["HOME"] ?? NSHomeDirectory()
        // Provider executables are resolved and verified before launch. Their
        // quota-only modes do not need user-writable package-manager helpers.
        environment["PATH"] = "/usr/bin:/bin:/usr/sbin:/sbin"
        environment["TERM"] = "xterm-256color"

        if let columns {
            environment["COLUMNS"] = String(columns)
        }
        if let rows {
            environment["LINES"] = String(rows)
        }

        return environment
    }
}
