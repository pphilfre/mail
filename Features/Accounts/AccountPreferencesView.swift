import SwiftUI
import SwiftData

struct AccountPreferencesView: View {
    let account: MailAccount
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(MailFeedback.self) private var feedback
    @State private var nickname: String
    @State private var colour: String
    @State private var saveError: String?
    @State private var signature: String
    private let colours = [("Blue", "007AFF"), ("Purple", "AF52DE"), ("Green", "248A3D"), ("Orange", "C93400"), ("Pink", "D70069")]
    init(account: MailAccount) {
        self.account = account
        _nickname = State(initialValue: account.displayName)
        _colour = State(initialValue: account.colourHex)
        _signature = State(initialValue: UserDefaults.standard.string(forKey: MailSignature.key(account.id)) ?? "")
    }
    var body: some View {
        Form {
            Section("Account") {
                LabeledContent("Email", value: account.email)
                TextField("Nickname", text: $nickname)
                Picker("Colour", selection: $colour) {
                    ForEach(colours, id: \.1) { name, value in
                        Label { Text(name) } icon: { Circle().fill(Color(mailHex: value)).frame(width: 12, height: 12) }.tag(value)
                    }
                }
            }
            Section {
                TextEditor(text: $signature).frame(minHeight: 120).accessibilityLabel("Signature")
            } header: { Text("Signature") } footer: { Text("Added to new messages and replies from this account. Saved drafts keep their existing text.") }
            if let saveError { Text(saveError).foregroundStyle(.red) }
        }
        .scrollContentBackground(.hidden).background(MailStyle.canvas)
        .navigationTitle("Personalise account").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let previousName = account.displayName; let previousColour = account.colourHex
                    account.displayName = nickname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? account.email : nickname.trimmingCharacters(in: .whitespacesAndNewlines)
                    account.colourHex = colour
                    do {
                        try context.save()
                        UserDefaults.standard.set(signature, forKey: MailSignature.key(account.id))
                        feedback.show("Account updated", detail: "Just the way you like it")
                        dismiss()
                    }
                    catch { account.displayName = previousName; account.colourHex = previousColour; saveError = error.localizedDescription }
                }
            }
        }
    }
}
