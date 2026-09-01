import Foundation
import LocalAuthentication
import Security
import CryptoKit

/// Touch ID unlock for passphrase mode.
///
/// The point of passphrase mode is that the key is not on the disk — so a Touch ID that
/// merely returned `true` and then read a local key would be theatre. Instead the master
/// key is handed to the Secure Enclave, stored under a `.biometryCurrentSet` access
/// control, and only released when a fingerprint matches. Your passphrase always remains
/// the fallback, so losing the Keychain item costs convenience, never data.
enum Biometry {
    /// Overridable so the self-test can use a throwaway service and clean up after itself.
    static var service = "app.klipvault.biometric"
    static let account = "master-key"

    enum Capability {
        case ready
        case noHardware
        /// Hardware is present, but biometric Keychain items live in the data-protection
        /// keychain, which requires an `application-identifier` entitlement backed by a real
        /// provisioning profile. An ad-hoc signed build gets errSecMissingEntitlement, and a
        /// build that *self-declares* the entitlement is killed outright by the system.
        case needsSignedBuild
    }

    static var isAvailable: Bool {
        var e: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
    }

    /// Probed once, by actually trying the write — cheaper to ask the system than to guess
    /// from the code signature, and it lights up automatically the day this app is signed.
    static let capability: Capability = {
        guard isAvailable else { return .noHardware }
        let probe = "app.klipvault.capability-probe"
        let base: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                   kSecAttrService as String: probe,
                                   kSecAttrAccount as String: "probe"]
        SecItemDelete(base as CFDictionary)
        guard let access = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, nil) else {
            return .needsSignedBuild
        }
        var add = base
        add[kSecValueData as String] = Data(repeating: 0, count: 32)
        add[kSecAttrAccessControl as String] = access
        let status = SecItemAdd(add as CFDictionary, nil)
        SecItemDelete(base as CFDictionary)
        return status == errSecSuccess ? .ready : .needsSignedBuild
    }()

    static var isReady: Bool { capability == .ready }

    /// "Touch ID" or "Face ID", whichever this Mac actually has.
    static var name: String {
        let ctx = LAContext()
        _ = ctx.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        return ctx.biometryType == .faceID ? "Face ID" : "Touch ID"
    }

    private static func query(_ extra: [String: Any] = [:]) -> [String: Any] {
        var q: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                kSecAttrService as String: service,
                                kSecAttrAccount as String: account]
        q.merge(extra) { _, new in new }
        return q
    }

    /// Asking for attributes rather than data never triggers a prompt, so this is safe
    /// to call while drawing a settings pane.
    static var isEnrolled: Bool {
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query([kSecReturnAttributes as String: true,
                                                kSecMatchLimit as String: kSecMatchLimitOne]) as CFDictionary,
                                         &out)
        return status == errSecSuccess
    }

    @discardableResult
    static func store(_ key: SymmetricKey) -> Bool {
        remove()
        var acError: Unmanaged<CFError>?
        guard let access = SecAccessControlCreateWithFlags(nil,
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .biometryCurrentSet, &acError) else {
            return false
        }
        let raw = key.withUnsafeBytes { Data($0) }
        return SecItemAdd(query([kSecValueData as String: raw,
                                 kSecAttrAccessControl as String: access]) as CFDictionary, nil) == errSecSuccess
    }

    static func remove() { SecItemDelete(query() as CFDictionary) }

    /// Prompts for a fingerprint. Runs off the main thread — a Keychain call that shows UI
    /// will deadlock the run loop otherwise — and calls back on it.
    static func retrieve(reason: String, completion: @escaping (SymmetricKey?) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let ctx = LAContext()
            ctx.localizedReason = reason
            ctx.localizedCancelTitle = "Use passphrase"
            var out: CFTypeRef?
            let status = SecItemCopyMatching(query([kSecReturnData as String: true,
                                                    kSecMatchLimit as String: kSecMatchLimitOne,
                                                    kSecUseAuthenticationContext as String: ctx]) as CFDictionary,
                                             &out)
            let key = (status == errSecSuccess ? out as? Data : nil)
                .flatMap { $0.count == 32 ? SymmetricKey(data: $0) : nil }
            DispatchQueue.main.async { completion(key) }
        }
    }
}
