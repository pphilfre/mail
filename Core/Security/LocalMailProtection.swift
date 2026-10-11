import Foundation
import Security

/// Device Data Protection. Background mail explicitly opts into access after the first unlock.
enum LocalMailProtection {
    static func protectDirectory(_ directory: URL, protection: FileProtectionType = .complete) throws {
        #if targetEnvironment(simulator)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        #else
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true,
            attributes: [.protectionKey: protection])
        #endif
        try protect(directory, protection: protection)
        var directory = directory
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
    }
    static func protect(_ file: URL, protection: FileProtectionType = .complete) throws {
        #if !targetEnvironment(simulator)
        try FileManager.default.setAttributes([.protectionKey: protection], ofItemAtPath: file.path)
        // Directory attributes request inheritance; encryption guarantees apply to files.
        guard try file.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true else { return }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard matches(attributes[.protectionKey], protection) else {
            throw CocoaError(.fileWriteNoPermission)
        }
        #endif
    }
    private static func isComplete(_ value: Any?) -> Bool {
        matches(value, .complete)
    }
    private static func matches(_ value: Any?, _ protection: FileProtectionType) -> Bool {
        (value as? FileProtectionType) == protection || (value as? String) == protection.rawValue
    }
    static func storageProtection(backgroundRefresh: Bool) -> FileProtectionType {
        backgroundRefresh ? .completeUntilFirstUserAuthentication : .complete
    }
    static func protectionForEntry(_ file: URL, storage: FileProtectionType, preservingDraftAttachments: Bool) -> FileProtectionType {
        let components = file.standardizedFileURL.pathComponents
        return preservingDraftAttachments && components.contains("DraftAttachments") ? .complete : storage
    }
    static func protectTree(_ directory: URL, protection: FileProtectionType = .complete, preservingDraftAttachments: Bool = false) throws {
        try protectDirectory(directory, protection: protection)
        for file in try entries(directory) {
            try protect(file, protection: protectionForEntry(file, storage: protection, preservingDraftAttachments: preservingDraftAttachments))
        }
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
    static func finding(for directory: URL, title: String = "Local file protection", protection: FileProtectionType = .complete) -> SecurityFinding {
        #if targetEnvironment(simulator)
        return SecurityFinding(id: directory.path, title: title, verdict: .unknown,
            explanation: "The simulator does not expose device Data Protection guarantees. Encryption and lock behaviour require a signed physical device.")
        #else
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: directory.path)
            guard matches(attributes[.protectionKey], protection) else { throw CocoaError(.fileReadNoPermission) }
            let files = try entries(directory)
            for file in files {
                let value = try FileManager.default.attributesOfItem(atPath: file.path)[.protectionKey]
                guard matches(value, protection) || isComplete(value) else { throw CocoaError(.fileReadNoPermission) }
            }
            return SecurityFinding(id: directory.path, title: title, verdict: .checked,
                explanation: "iOS Data Protection attributes confirmed on this directory and \(files.count) existing entries. " + (protection == .complete ? "Files require an unlocked device." : "Background mail storage remains available after the first unlock; draft attachment files retain Complete protection.") + " Future files and actual device lock behaviour require device testing.")
        } catch {
            return SecurityFinding(id: directory.path, title: title, verdict: .unknown,
                explanation: "The configured protection could not be confirmed for every existing entry. File creation and device lock behaviour require testing on the installed signed app.")
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
                explanation: "Keychain write failed (\(add)). Check the installed app’s signing identity and Keychain access group. No plaintext credential fallback is used.")
        }
        var read = query; read[kSecReturnData as String] = true
        var output: CFTypeRef?
        let load = SecItemCopyMatching(read as CFDictionary, &output)
        let remove = SecItemDelete(query as CFDictionary)
        let passed = load == errSecSuccess && (output as? Data) == bytes && remove == errSecSuccess
        return SecurityFinding(id: "keychain", title: "Keychain compatibility", verdict: passed ? .checked : .unknown,
            explanation: passed ? "Device-local Keychain write/read/delete succeeded in this process. Relaunch persistence and signing continuity require testing on the installed app." : "Keychain round trip failed (read \(load), delete \(remove)). Check app signing. Credentials are never saved to preferences or the mail database.")
    }
}
