import SwiftUI
import SwiftData

struct AppShell: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.scenePhase) private var scenePhase
    @Query private var accounts: [MailAccount]
    @AppStorage("showSampleInbox") private var showSamples = false
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("selectedMailAccount") private var selectedMailAccount = ""
    @State private var showingCompose = false

    var body: some View {
        Group {
            if accounts.isEmpty && !showSamples {
                WelcomeView()
            } else {
                NavigationStack {
                    InboxView()
                        .toolbar {
                            ToolbarItem(placement: .primaryAction) {
                                Button("Compose", systemImage: "square.and.pencil") { showingCompose = true }
                                    .accessibilityIdentifier("composeButton")
                            }
                        }
                }
            }
        }
        .tint(MailStyle.accent)
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
        .task { await runtime.gmail?.syncAll() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && runtime.gmail?.connecting != true { Task { await runtime.gmail?.syncAll() } }
        }
        .onChange(of: runtime.connectivity.reconnectionCount) { _, _ in
            if scenePhase == .active && runtime.gmail?.connecting != true {
                Task { await runtime.gmail?.syncAll() }
            }
        }
        .sheet(isPresented: $showingCompose) {
            NavigationStack { ComposeView(draft: LocalDraft(accountID: UUID(uuidString: selectedMailAccount))) }
        }
    }
}

struct WelcomeView: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("showSampleInbox") private var showSamples = false
    @State private var arrived = false

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "envelope.open.fill")
                .font(.system(size: 76, weight: .light))
                .foregroundStyle(MailStyle.accent.gradient)
                .frame(width: 164, height: 164)
                .glassEffect(.regular, in: .rect(cornerRadius: 44))
                .rotationEffect(.degrees(arrived || reduceMotion ? 0 : -12))
                .offset(y: arrived || reduceMotion ? 0 : 24)
                .accessibilityHidden(true)
            VStack(spacing: 12) {
                Text("Welcome to Dispatch").font(.largeTitle.bold()).multilineTextAlignment(.center)
                Text("A little more calm.\nA lot less inbox.").font(.title3).foregroundStyle(.secondary).multilineTextAlignment(.center)
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
                Button {} label: {
                    HStack {
                        Text("Sign in with Zoho")
                        Text("Coming soon").font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 10)
                }.buttonStyle(.glass).disabled(true)
                Button("Explore sample mail") { showSamples = true }.font(.footnote)
                Text("Your mail, together. Your credentials, safely in Keychain.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
        }
        .padding(28)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
        .task { withAnimation(reduceMotion ? nil : .spring(duration: 0.9, bounce: 0.2)) { arrived = true } }
    }
}
