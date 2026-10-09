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
        #if !targetEnvironment(simulator)
        // Directory attributes request inheritance; encryption guarantees apply to files.
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard isComplete(attributes[.protectionKey]) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        #endif
    }
    private static func isComplete(_ value: Any?) -> Bool {
        (value as? FileProtectionType) == .complete || (value as? String) == FileProtectionType.complete.rawValue
    }
    static func protectTree(_ directory: URL) throws {
        try protectDirectory(directory)
        for file in try entries(directory) { try protect(file) }
    }
    private static func entries(_ directory: URL) throws -> [URL] {
        let root = directory.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        var pending = [directory], result: [URL] = []
        while let current = pending.popLast() {
            for file in try FileManager.default.contentsOfDirectory(at: current, includingPropertiesForKeys: [.isSymbolicLinkKey, .isDirectoryKey]) {
                let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isDirectoryKey])
                guard values.isSymbolicLink != true, file.standardizedFileURL.resolvingSymlinksInPath().path.hasPrefix(root) else { throw CocoaError(.fileReadNoPermission) }
                result.append(file)
                if values.isDirectory == true { pending.append(file) }
            }
        }
        return result
    }
    static func finding(for directory: URL, title: String = "Local file protection") -> SecurityFinding {
        #if targetEnvironment(simulator)
        return SecurityFinding(id: directory.path, title: title, verdict: .unknown,
            explanation: "The simulator does not expose device Data Protection guarantees. File workflows can be tested here, but encryption and lock behaviour require the signed LiveContainer device.")
        #else
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard isComplete(attributes[.protectionKey]) else { throw CocoaError(.fileReadNoPermission) }
            let files = try entries(directory)
            for file in files {
                guard isComplete(try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey]) else { throw CocoaError(.fileReadNoPermission) }
            }
            return SecurityFinding(id: directory.path, title: title, verdict: .checked,
                explanation: "Complete iOS Data Protection attributes confirmed on this directory and \(files.count) existing entries at inspection time. This checks file attributes, not LiveContainer isolation or hardware encryption. The host controls the sandbox; future files and device lock behaviour require runtime testing.")
        } catch {
            return SecurityFinding(id: directory.path, title: title, verdict: .unknown,
                explanation: "Complete protection could not be confirmed for every existing entry. LiveContainer host signing, shared sandbox, file creation and device lock behaviour require device testing.")
        }
        #endif
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
