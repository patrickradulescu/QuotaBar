import Foundation
import Security

enum CodeSignatureVerifier {
    static func hasValidSignature(
        _ url: URL,
        teamIdentifier: String,
        signingIdentifier: String
    ) -> Bool {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &code) == errSecSuccess,
              let code else {
            return false
        }

        guard let requirement = requirement(
            teamIdentifier: teamIdentifier,
            signingIdentifier: signingIdentifier
        ) else { return false }

        let flags = SecCSFlags(rawValue: kSecCSStrictValidate | kSecCSCheckAllArchitectures)
        return SecStaticCodeCheckValidity(code, flags, requirement) == errSecSuccess
    }

    static func hasValidRunningSignature(
        pid: pid_t,
        teamIdentifier: String,
        signingIdentifier: String
    ) -> Bool {
        guard pid > 1,
              let requirement = requirement(
                  teamIdentifier: teamIdentifier,
                  signingIdentifier: signingIdentifier
              ) else { return false }

        let attributes = [
            kSecGuestAttributePid as String: NSNumber(value: pid)
        ] as CFDictionary
        var code: SecCode?
        guard SecCodeCopyGuestWithAttributes(
            nil,
            attributes,
            SecCSFlags(),
            &code
        ) == errSecSuccess,
        let code else {
            return false
        }

        return SecCodeCheckValidity(
            code,
            SecCSFlags(rawValue: kSecCSStrictValidate),
            requirement
        ) == errSecSuccess
    }

    private static func requirement(
        teamIdentifier: String,
        signingIdentifier: String
    ) -> SecRequirement? {
        let source = "anchor apple generic and certificate leaf[subject.OU] = \"\(teamIdentifier)\" and identifier \"\(signingIdentifier)\""
        var requirement: SecRequirement?
        guard SecRequirementCreateWithString(
            source as CFString,
            SecCSFlags(),
            &requirement
        ) == errSecSuccess else {
            return nil
        }
        return requirement
    }
}
