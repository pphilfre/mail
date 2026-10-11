import SwiftUI

struct MailIntegrationSettings: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.scenePhase) private var phase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("mailAppLock") private var locked = false
    @AppStorage("backgroundMailRefresh") private var backgroundRefresh = false
    @AppStorage("notifyNewMail") private var notifications = false
    @AppStorage("remoteImages") private var remoteImages = false
    var body: some View {
        Form {
            Section {
                Toggle(isOn: Binding(get: { locked }, set: { enabled in Task { await runtime.appLock.setEnabled(enabled) } })) {
                    feature("App lock", "faceid", .green)
                }.disabled(runtime.appLock.authenticating).accessibilityIdentifier("mailAppLockToggle")
                Toggle(isOn: $remoteImages) { feature("Remote images", "photo", .blue) }
                if let error = runtime.appLock.error { Text(error).font(.caption).foregroundStyle(.secondary) }
            }
            Section {
                HStack {
                    feature("Apple Intelligence", "sparkles", .purple)
                    Spacer()
                    if LocalMailModel.systemAvailable {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Available")
                    } else { Text("Unavailable").font(.caption).foregroundStyle(.secondary) }
                }
                HStack {
                    feature("Writing model", "pencil.and.outline", .pink)
                    Spacer()
                    if runtime.localModel.installed {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("Installed")
                    } else if runtime.localModel.downloadProgress == nil {
                        Button("Install") { Task { await runtime.localModel.download() } }
                            .disabled(runtime.localModel.busy || !LocalModelWorker.supported)
                    }
                }
                if let fraction = runtime.localModel.downloadProgress {
                    VStack(alignment: .leading, spacing: 6) {
                        ProgressView(value: fraction).tint(.purple)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: fraction)
                        HStack {
                            Text(fraction, format: .percent.precision(.fractionLength(0)))
                            Spacer()
                            Button("Cancel") { runtime.localModel.cancel() }
                        }.font(.caption)
                    }
                }
                if let status = runtime.localModel.status { Text(status).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("Model details") {
                    Text("Apple Intelligence runs on supported devices when enabled in iOS Settings. When unavailable, summaries show original passages from downloaded message bodies.")
                    Text("The optional Qwen3 0.6B writing model downloads about 347 MB over Wi-Fi and needs a physical device with at least 6 GB RAM. It helps rewrite short drafts; it is not used for factual summaries. Review suggestions before applying.")
                    if runtime.localModel.installed {
                        Button("Delete writing model", role: .destructive) { Task { await runtime.localModel.delete() } }
                            .disabled(runtime.localModel.busy)
                    }
                }.font(.caption).foregroundStyle(.secondary)
            } footer: { Text("Writing and summarisation run on your device.") }
            Section {
                Toggle(isOn: Binding(get: { backgroundRefresh }, set: { enabled in
                    Task {
                        do { try await runtime.configureBackgroundRefresh(enabled) }
                        catch { runtime.nativeServices.error = error.localizedDescription }
                    }
                })) { feature("Background refresh", "arrow.trianglehead.2.clockwise.rotate.90", .teal) }
                    .disabled(runtime.nativeServices.configuringStorage || (!backgroundRefresh && !runtime.nativeServices.refreshAvailable))
                if runtime.nativeServices.configuringStorage { ProgressView("Updating storage protection…").font(.caption) }
                Toggle(isOn: Binding(get: { notifications && runtime.nativeServices.notificationsEnabled }, set: { enabled in
                    notifications = enabled
                    if enabled { Task { await runtime.nativeServices.enableNotifications() } }
                })) { feature("New mail alerts", "bell.badge", .orange) }
                if runtime.nativeServices.notificationStatus == .denied || !runtime.nativeServices.refreshAvailable {
                    Button("Open iOS Settings", systemImage: "arrow.up.forward.app") {
                        if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                    }
                }
                if let error = runtime.nativeServices.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                DisclosureGroup("Delivery details") {
                    Text("iOS chooses when background refresh runs. New mail alerts appear after a successful refresh and hide sender and subject. App lock pauses background access. This is periodic fetch, not real-time push.")
                    Text("Enabling refresh keeps encrypted mail storage accessible to Dispatch after the first device unlock, including while the phone is locked. Draft attachment files retain protection while locked.")
                    Text("Scheduled mail can send during a granted refresh while unlocked, or when Dispatch is open. iOS does not guarantee the scheduled time.")
                }.font(.caption).foregroundStyle(.secondary)
            }
        }.navigationTitle("Privacy & Intelligence").navigationBarTitleDisplayMode(.inline)
            .task { await runtime.nativeServices.updateAuthorization() }
            .onChange(of: phase) { _, value in if value == .active { Task { await runtime.nativeServices.updateAuthorization() } } }
    }
    private func feature(_ title: String, _ symbol: String, _ color: Color) -> some View {
        Label { Text(title) } icon: {
            Image(systemName: symbol).foregroundStyle(color).frame(width: 28, height: 28)
        }
    }
}
