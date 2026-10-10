import SwiftUI

struct SecurityInspectorView: View {
    let message: MailMessage
    let attachments: [MailAttachment]
    var imagesAllowed = false
    @Environment(\.dismiss) private var dismiss
    @Environment(AppRuntime.self) private var runtime
    @AppStorage("remoteImages") private var remoteImages = false
    @State private var headers: [GmailHeader] = []
    @State private var history: [LocalSenderRecord] = []
    @State private var inspections: [UUID: AttachmentInspection] = [:]
    @State private var inspectionErrors: [UUID: String] = [:]
    @State private var embeddedQR: [String] = []
    @State private var qrFinding = SecurityFinding(id: "embedded-qr", title: "Embedded QR codes", verdict: .unknown, explanation: "Not inspected yet. Remote images are never fetched for analysis.")
    @State private var keychain: SecurityFinding?
    @State private var storageChecks: [SecurityFinding] = []
    @State private var reputations: [String: SecurityFinding] = [:]
    @State private var apiKey = ""
    @State private var pendingLookup: ReputationTarget?
    @State private var busy = false
    @State private var verifiedAuthentication: [SecurityFinding]?
    @State private var confirmAuthentication = false
    @State private var authenticationBusy = false
    @State private var authenticationTask: Task<Void, Never>?
    private var authenticationFindings: [SecurityFinding] { verifiedAuthentication ?? MailAuthentication.findings(headers: headers) }
    private var html: String { message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) } ?? "" }
    private var observations: MailSecurityObservations { MailSecurityObservations(html: html, text: message.plainTextBody ?? message.snippet) }
    private var links: [MailSecurityObservations.Link] {
        let qr = MailSecurityObservations(html: "", text: (embeddedQR + inspections.values.flatMap(\.qrLinks)).joined(separator: "\n"))
        var seen = Set<String>()
        return (observations.links + qr.links).filter { seen.insert($0.destination).inserted }
    }
    private var identityFindings: [SecurityFinding] { SenderSecurity.findings(sender: message.sender, replyTo: message.replyTo, history: history) }
    private var linkFinding: SecurityFinding {
        let known = Set(history.filter { !$0.spam }.map { SenderSecurity.domain($0.email) })
        let concerns = links.flatMap { $0.concerns + SenderSecurity.domainConcerns($0.host.lowercased(), known: known) }
        return SecurityFinding(id: "links", title: "Links and redirects", verdict: concerns.isEmpty ? .unknown : .concern,
            explanation: concerns.isEmpty ? "\(links.count) web links found in cached content. Destinations and redirects have not been visited or verified." : Array(Set(concerns)).sorted().joined(separator: " "), points: concerns.isEmpty ? 0 : 20)
    }
    private var report: SecurityReport {
        var findings = authenticationFindings + identityFindings + [linkFinding, qrFinding]
        for file in attachments {
            if let inspection = inspections[file.id] { findings += [inspection.type, inspection.qr] }
            else { findings.append(SecurityFinding(id: file.id.uuidString, title: file.filename, verdict: .unknown, explanation: "Attachment contents unavailable.")) }
        }
        findings += Array(reputations.values)
        findings.append(SecurityFinding(id: "unscanned", title: "Malware coverage", verdict: .unknown, explanation: "No local antivirus engine is installed."))
        return SecurityReport(findings: findings)
    }
    var body: some View {
        List {
            Section {
                Label(report.verdict == .concern ? "Concerns found" : "Incomplete analysis", systemImage: report.verdict.symbol).font(.title3.weight(.semibold))
                LabeledContent("Observed risk", value: "\(report.score)/100")
                Text("\(report.unknownCount) checks remain unknown. Zero means no scored evidence was found, never that this email is safe. Points: sender 25, spam history 15, links 20, failed DKIM 20, type 30/file, QR concerns 15/image, VirusTotal flags 50/item; capped at 100.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Authentication & identity") {
                LabeledContent("Sender", value: message.senderEmail).textSelection(.enabled)
                ForEach(authenticationFindings) { finding($0) }
                Button(authenticationBusy ? "Verifying original message…" : "Verify original Gmail signature…") { confirmAuthentication = true }
                    .disabled(authenticationBusy || runtime.gmail == nil)
                Text("Optional: downloads the original message from Gmail (up to 20 MB) and verifies full-body RSA/Ed25519 DKIM locally. Google Public DNS receives signing selectors/domains, the From domain and your IP. Sender-controlled DNS may observe queries or tracking identifiers in selectors. No email body or attachment bytes go to DNS. SPF and unsupported alignment remain unknown.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Phishing & impersonation") { ForEach(identityFindings) { finding($0) } }
            Section("Links & redirects") {
                finding(linkFinding)
                ForEach(links) { link in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(link.host).font(.subheadline.weight(.medium))
                        Text(link.destination).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                        reputationRow(.url(link.destination))
                    }
                }
            }
            Section("Attachments & SHA-256") {
                if attachments.isEmpty { Text("No attachments listed.").foregroundStyle(.secondary) }
                ForEach(attachments) { file in
                    VStack(alignment: .leading, spacing: 6) {
                        Label(file.filename, systemImage: "doc")
                        if let inspection = inspections[file.id] {
                            finding(inspection.type); finding(inspection.qr)
                            Text(inspection.hash).font(.caption.monospaced()).textSelection(.enabled)
                            reputationRow(.fileHash(inspection.hash))
                            ForEach(Array(inspection.qrLinks.enumerated()), id: \.offset) { item in Text("QR payload: " + item.element).font(.caption).textSelection(.enabled) }
                        } else {
                            Label("Unknown", systemImage: SecurityVerdict.unknown.symbol)
                            Text(inspectionErrors[file.id] ?? "Download this file to calculate its hash and inspect its type and QR codes.").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text("Hashes identify contents; they are not safety verdicts. No local antivirus engine is installed. Preview accepts recognised PDF, raster image and UTF-8 text types; active content, mismatches and unidentified types are blocked.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("QR codes in cached content") {
                finding(qrFinding)
                ForEach(Array(embeddedQR.enumerated()), id: \.offset) { item in Text(item.element).font(.caption).textSelection(.enabled) }
                Text("Vision inspects up to 12 embedded raster data images and downloaded raster attachments, first frame only, up to 20 megapixels. Remote images, CID images not stored as attachments, PDF pages and archives remain uninspected.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Tracking & privacy") {
                LabeledContent("External images", value: observations.hasRemoteImages ? "Detected" : "None detected in cached HTML")
                Label(imagesAllowed || remoteImages ? "Remote images allowed by your preference" : "Remote content blocked", systemImage: imagesAllowed || remoteImages ? SecurityVerdict.unknown.symbol : SecurityVerdict.checked.symbol)
                LabeledContent("Possible tracking pixels", value: "\(observations.possibleTrackingPixels)")
                Text("Scripts, frames, forms, objects, network connections and remote fonts are blocked. Remote images are blocked by default. Images with explicit one-pixel dimensions are removed even when images are enabled; other trackers may escape detection. Enabling images exposes requests, your IP and possibly message-specific tokens to their hosts.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Optional VirusTotal lookups") {
                SecureField("VirusTotal API key (this sheet only)", text: $apiKey).textInputAutocapitalization(.never).autocorrectionDisabled()
                Text("Each lookup requires your confirmation. URL lookups share the complete URL, including private query tokens. File lookups share only SHA-256 hashes, which may identify private files. VirusTotal receives your IP and API key. No attachment bytes or email bodies are uploaded. Only existing reports are retrieved; no scan is submitted. The key stays in memory while this sheet is open; report summaries stay in memory for this app session.").font(.footnote).foregroundStyle(.secondary)
            }
            Section("Storage & LiveContainer") {
                ForEach(storageChecks) { finding($0) }
                if let keychain { finding(keychain) }
                Button("Check Keychain compatibility") { keychain = LocalMailProtection.keychainProbe() }
                Text("LiveContainer supplies the host sandbox and entitlements. No custom Keychain group or Secure Enclave entitlement is requested. Successful checks cannot prove isolation from the host or other guest code. Device lock, relaunch, file-picker access and Quick Look require testing on your signed host.").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Security Inspector").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { MailCloseButton { dismiss() } } }
        .presentationDetents([.large]).presentationDragIndicator(.visible)
        .confirmationDialog("Share with VirusTotal?", isPresented: Binding(get: { pendingLookup != nil }, set: { if !$0 { pendingLookup = nil } }), titleVisibility: .visible) {
            if let target = pendingLookup { Button("Send lookup") { pendingLookup = nil; Task { await lookup(target) } } }
            Button("Cancel", role: .cancel) { pendingLookup = nil }
        } message: { Text("VirusTotal receives this exact URL or hash, your IP and API key. URLs may contain private tokens. No file contents are sent.\n\n" + (pendingLookup?.sharedValue ?? "")) }
        .confirmationDialog("Verify original message?", isPresented: $confirmAuthentication, titleVisibility: .visible) {
            Button("Download and verify with DNS") { authenticationTask = Task { await verifyAuthentication() } }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("Downloads the original message from your Gmail account and queries Google Public DNS for signing selectors/domains and the From domain. Google sees your IP; sender-controlled DNS may observe selector queries containing tracking identifiers. No body or attachment bytes go to DNS or VirusTotal. Checks use current DNS keys/policies, not historical delivery-time data.")
        }
        .task(id: MailSecurityContent.fingerprint(message, attachments: attachments)) { await inspect() }
        .onDisappear { apiKey = ""; authenticationTask?.cancel(); authenticationTask = nil }
        .onChange(of: report, initial: true) { _, value in
            runtime.securityReports[message.id] = (MailSecurityContent.fingerprint(message, attachments: attachments), value)
        }
    }
    private func finding(_ value: SecurityFinding) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(value.title, systemImage: value.verdict.symbol)
            Text(value.explanation).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
    private func reputationRow(_ target: ReputationTarget) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if let value = reputations[target.sharedValue] { finding(value) }
            else { Label("Reputation unknown", systemImage: SecurityVerdict.unknown.symbol).font(.caption) }
            Button("Look up with VirusTotal…") { pendingLookup = target }.font(.caption)
                .disabled(apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || busy)
        }
    }
    private func lookup(_ target: ReputationTarget) async {
        busy = true; defer { busy = false }
        do { reputations[target.sharedValue] = try await runtime.reputation.lookup(target, apiKey: apiKey) }
        catch { reputations[target.sharedValue] = SecurityFinding(id: target.sharedValue, title: "VirusTotal reputation", verdict: .unknown, explanation: error.localizedDescription) }
    }
    private func inspect() async {
        authenticationTask?.cancel(); verifiedAuthentication = nil
        storageChecks = await Task.detached(priority: .utility) {
            [LocalMailProtection.finding(for: URL.applicationSupportDirectory.appending(path: "Dispatch"), title: "Email and draft file protection"),
             LocalMailProtection.finding(for: URL.applicationSupportDirectory.appending(path: "Mail/Attachments"), title: "Received attachment file protection")]
        }.value
        headers = (try? runtime.repository?.securityHeaders(message.id)) ?? []
        history = (try? runtime.repository?.senderSecurityHistory(for: message)) ?? []
        inspections = [:]; inspectionErrors = [:]
        let cache = runtime.gmail?.attachmentCache ?? AttachmentCache()
        for file in attachments {
            guard !Task.isCancelled else { return }
            do { inspections[file.id] = try await cache.inspect(file.cachedRelativePath, filename: file.filename, mimeType: file.mimeType) }
            catch { inspectionErrors[file.id] = error.localizedDescription }
        }
        let content = html
        let result = await Task.detached(priority: .utility) {
            let images = QRCodeSecurity.embeddedImages(content)
            var values: [String] = []; var failures = 0
            for data in images { do { values += try QRCodeSecurity.payloads(data) } catch { failures += 1 } }
            return (values, images.count, failures)
        }.value
        guard !Task.isCancelled else { return }
        embeddedQR = result.0
        qrFinding = QRCodeSecurity.embeddedFinding(result.0, imageCount: result.1, failures: result.2)
    }
    private func verifyAuthentication() async {
        authenticationBusy = true; defer { authenticationBusy = false }
        let accountID = message.accountID, remoteID = message.remoteID, sender = message.senderEmail
        let fingerprint = MailSecurityContent.fingerprint(message, attachments: attachments)
        do {
            guard let gmail = runtime.gmail, let repository = runtime.repository,
                  let account = try repository.account(id: accountID), account.providerRaw == MailProviderKind.gmail.rawValue else {
                throw AuthenticationError.unavailable("Original-message verification requires a connected Gmail account.")
            }
            let raw = try await gmail.client(accountID).originalMessage(remoteID)
            let findings = await MailAuthenticator().analyse(raw: raw, expectedSender: sender)
            guard !Task.isCancelled, fingerprint == MailSecurityContent.fingerprint(message, attachments: attachments) else { return }
            verifiedAuthentication = findings
        } catch {
            guard !Task.isCancelled else { return }
            verifiedAuthentication = ["spf", "dkim", "dmarc"].map { SecurityFinding(id: $0, title: $0.uppercased(), verdict: .unknown, explanation: error.localizedDescription) }
        }
    }
    private func verifyAuthentication() async {
        authenticationBusy = true; defer { authenticationBusy = false }
        let accountID = message.accountID, remoteID = message.remoteID, sender = message.senderEmail
        let fingerprint = MailSecurityContent.fingerprint(message, attachments: attachments)
        do {
            guard let gmail = runtime.gmail, let repository = runtime.repository,
                  let account = try repository.account(id: accountID), account.providerRaw == MailProviderKind.gmail.rawValue else {
                throw AuthenticationError.unavailable("Original-message verification requires a connected Gmail account.")
            }
            let raw = try await gmail.client(accountID).originalMessage(remoteID)
            let findings = await MailAuthenticator().analyse(raw: raw, expectedSender: sender)
            guard !Task.isCancelled, fingerprint == MailSecurityContent.fingerprint(message, attachments: attachments) else { return }
            verifiedAuthentication = findings
        } catch {
            guard !Task.isCancelled else { return }
            verifiedAuthentication = ["spf", "dkim", "dmarc"].map { SecurityFinding(id: $0, title: $0.uppercased(), verdict: .unknown, explanation: error.localizedDescription) }
        }
    }
}
