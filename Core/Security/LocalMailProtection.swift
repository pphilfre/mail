import Foundation
import Security

/// iOS Data Protection encrypts these files using device keys. No guest entitlements,
/// access-group names, Secure Enclave availability or normal installation are assumed.
enum LocalMailProtection {
    static func protectDirectory(_ directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.complete])
        try protect(directory)
        var directory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
    static func protect(_ file: URL) throws {
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: file.path)
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard isComplete(attributes[.protectionKey]) else {
            throw CocoaError(.fileWriteNoPermission)
        }
    }
    private static func isComplete(_ value: Any?) -> Bool {
        (value as? FileProtectionType) == .complete || (value as? String) == FileProtectionType.complete.rawValue
    }
    static func protectTree(_ directory: URL) throws {
        try protectDirectory(directory)
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        if let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isSymbolicLinkKey]) {
            for case let file as URL in enumerator {
                guard try file.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true,
                      file.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root) else { throw CocoaError(.fileWriteNoPermission) }
                try protect(file)
            }
        }
    }
    static func finding(for directory: URL) -> SecurityFinding {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard isComplete(attributes[.protectionKey]) else { throw CocoaError(.fileReadNoPermission) }
            return SecurityFinding(id: "storage", title: "Local file protection", verdict: .checked,
                explanation: "Complete iOS Data Protection is set on the mail directory. Email database, sidecars and cached attachments are protected and excluded from backup. This checks file attributes, not LiveContainer isolation or hardware encryption; the host controls the sandbox.")
        } catch {
            return SecurityFinding(id: "storage", title: "Local file protection", verdict: .unknown,
                explanation: "File protection could not be confirmed in this runtime. LiveContainer host signing, shared sandbox and device lock behaviour require device testing.")
        }
    }
    static func keychainProbe() -> SecurityFinding {
        let service = "dev.freddiephilpot.dispatch.security-probe.\(UUID())"
        let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service, kSecAttrAccount as String: "probe", kSecAttrSynchronizable as String: false]
        var item = query
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let bytes = Data(UUID().uuidString.utf8)
        item[kSecValueData as String] = bytes
        let add = SecItemAdd(item as CFDictionary, nil)
        guard add == errSecSuccess else {
            return SecurityFinding(id: "keychain", title: "Keychain compatibility", verdict: .unknown,
                explanation: "Keychain write failed (\(add)). Check LiveContainer signing and Keychain separation settings. No plaintext credential fallback is used.")
        }
        var read = query; read[kSecReturnData as String] = true
        var output: CFTypeRef?
        let load = SecItemCopyMatching(read as CFDictionary, &output)
        let remove = SecItemDelete(query as CFDictionary)
        let passed = load == errSecSuccess && (output as? Data) == bytes && remove == errSecSuccess
        return SecurityFinding(id: "keychain", title: "Keychain compatibility", verdict: passed ? .checked : .unknown,
            explanation: passed ? "Device-local Keychain write/read/delete succeeded in this process. Cross-container isolation, relaunch persistence and host updates still need LiveContainer device testing." : "Keychain round trip failed (read \(load), delete \(remove)). Check host signing. Credentials are never saved to preferences or the mail database.")
    }
}
