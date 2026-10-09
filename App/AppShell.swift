import SwiftUI
import SwiftData

struct AppShell: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [MailAccount]
    @Query(filter: #Predicate<StoreMetadata> { $0.key == "mail-triage-undo" }) private var undoMetadata: [StoreMetadata]
    @AppStorage("showSampleInbox") private var showSamples = false
    @AppStorage("appearance") private var appearance = "system"
    @State private var feedback = MailFeedback()
    private var undoRecord: MailUndoRecord? {
        undoMetadata.first.flatMap { try? JSONDecoder().decode(MailUndoRecord.self, from: Data($0.value.utf8)) }
    }

    var body: some View {
        Group {
            if accounts.isEmpty && !showSamples {
                NavigationStack { WelcomeView() }
            } else {
                NavigationStack {
                    InboxView()
                }
            }
        }
        .tint(MailStyle.accent)
        .modifier(MailFeedbackOverlay())
        .environment(feedback)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .task {
            await Task.yield()
            MailWebViewPool.prepare()
            if let record = undoRecord, record.expiresAt > Date() { showTriageConfirmation(record) }
            await runtime.gmail?.syncAll()
        }
        .task(id: scenePhase) {
            guard scenePhase == .active else { return }
            while !Task.isCancelled {
                await runtime.deliverScheduledMail()
                do { try await Task.sleep(for: .seconds(1)) } catch { return }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && runtime.gmail?.connecting != true { Task { await runtime.gmail?.syncAll() } }
        }
        .onChange(of: runtime.connectivity.reconnectionCount) { _, _ in
            if scenePhase == .active && runtime.gmail?.connecting != true {
                Task { await runtime.gmail?.syncAll() }
            }
        }
        .onChange(of: runtime.gmail?.error) { _, error in
            if let error { feedback.show("Mail needs attention", detail: error, symbol: "exclamationmark", tone: .error) }
        }
        .onChange(of: accounts.map(\.id)) { old, new in
            if new.count > old.count { feedback.show("Account connected", detail: "Your mail is on its way", symbol: "envelope.badge") }
            else if new.count < old.count { feedback.show("Account removed", tone: .information) }
        }
        .onChange(of: undoRecord?.id) { _, _ in
            guard let record = undoRecord, record.expiresAt > Date(), feedback.triageKind == record.title else { return }
            feedback.triageKind = nil
            showTriageConfirmation(record)
        }
    }
    private func showTriageConfirmation(_ record: MailUndoRecord) {
        feedback.confirmTriage(record, online: runtime.connectivity.isConnected != false) {
            guard record.expiresAt > Date() else { return }
            feedback.select()
            if let gmail = runtime.gmail { gmail.undo(record.id) }
            else {
                do { _ = try runtime.repository?.undoTriage(record.id) }
                catch { feedback.show("Couldn’t undo", detail: error.localizedDescription, symbol: "exclamationmark", tone: .error) }
            }
        }
    }
}

struct WelcomeView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(MailFeedback.self) private var feedback
    @AppStorage("showSampleInbox") private var showSamples = false
    @State private var arrived = false
    @State private var showingTasks = false

    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                welcomeContent
                    .padding(28)
                    .frame(maxWidth: 520, minHeight: geometry.size.height)
                    .frame(maxWidth: .infinity)
            }
        }
        .background {
            LinearGradient(colors: [MailStyle.accent.opacity(0.1), MailStyle.canvas, MailStyle.paper], startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
        }
        .task { withAnimation(reduceMotion ? nil : .spring(duration: 0.45, bounce: 0.12)) { arrived = true } }
        .navigationDestination(isPresented: $showingTasks) {
            MailTasksView(accountID: nil)
        }
    }
    private var welcomeContent: some View {
        VStack(alignment: .leading, spacing: 24) {
            Label("Dispatch", systemImage: "envelope.open")
                .font(.title3.weight(.semibold)).padding(.top, 8)
            Spacer()
            WelcomeMailPreview()
                .scaleEffect(arrived || reduceMotion ? 1 : 0.95)
                .opacity(arrived || reduceMotion ? 1 : 0)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 12) {
                Text("Welcome to Dispatch").font(.largeTitle.bold()).tracking(-1)
                Text("A little more calm.\nA lot less inbox.").font(.title3).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(spacing: 14) {
                if let error = runtime.gmail?.error { Text(error).font(.callout).foregroundStyle(.red) }
                Button {
                    Task { await runtime.gmail?.connect() }
                } label: {
                    HStack {
                        if runtime.gmail?.connecting == true { ProgressView() }
                        Text(runtime.gmail?.connecting == true ? "Signing in…" : "Sign in with Google").fontWeight(.semibold)
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                }
                .buttonStyle(.glassProminent)
                .disabled(runtime.gmail == nil || runtime.gmail?.connecting == true)
                Button("Explore sample mail") { feedback.select(); showSamples = true }
                    .font(.subheadline.weight(.medium)).frame(minHeight: 44)
                Button("Tasks", systemImage: "checklist") { showingTasks = true }
                    .buttonStyle(.glass).accessibilityIdentifier("welcomeTasksButton")
                Text("Gmail, for now. Zoho is on its way.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}

private struct WelcomeMailPreview: View {
    var body: some View {
        ZStack {
            preview(sender: "Alex Morgan", initials: "AM", subject: "A quieter inbox", color: .blue)
                .rotationEffect(.degrees(-6)).offset(x: -12, y: -65)
            preview(sender: "Studio team", initials: "ST", subject: "Something worth opening", color: .purple)
                .rotationEffect(.degrees(4)).offset(x: 12)
            preview(sender: "Jamie Chen", initials: "JC", subject: "See you on Saturday", color: .teal)
                .rotationEffect(.degrees(-2)).offset(x: -5, y: 65)
        }.padding(.horizontal, 16).frame(height: 236)
    }
    private func preview(sender: String, initials: String, subject: String, color: Color) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(initials).font(.system(.caption, design: .rounded, weight: .semibold)).foregroundStyle(color)
                .frame(width: 36, height: 36).background(color.opacity(0.08), in: .rect(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 5) {
                Text(sender).font(.subheadline.weight(.semibold))
                Text(subject).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Circle().fill(MailStyle.accent).frame(width: 6, height: 6).padding(.top, 5)
        }
        .padding(18).frame(maxWidth: .infinity, alignment: .leading)
        .background(MailStyle.paper, in: .rect(cornerRadius: 20))
        .shadow(color: .black.opacity(0.05), radius: 14, y: 8)
    }
}
