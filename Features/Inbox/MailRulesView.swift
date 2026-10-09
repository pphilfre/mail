import SwiftUI
import SwiftData

struct MailRulesView: View {
    @Environment(AppRuntime.self) private var runtime
    @Query private var metadata: [StoreMetadata]
    @State private var editing: MailOrganisationRule?
    @State private var errorMessage: String?
    private var rules: [MailOrganisationRule] { metadata.compactMap(MailOrganisationRule.decode).sorted { $0.name < $1.name } }
    var body: some View {
        List {
            Text("Rules run once per matching message when mail is downloaded. Changes sync to Gmail through the existing action queue.").font(.footnote).foregroundStyle(.secondary)
            ForEach(rules) { rule in
                Button { editing = rule } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(rule.name).foregroundStyle(.primary)
                        Text((rule.enabled ? "" : "Paused · ") + rule.action.capitalized + " · " + [rule.sender, rule.subject].filter { !$0.isEmpty }.joined(separator: " · ")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }.onDelete { offsets in
                do { for index in offsets { try runtime.repository?.setMetadata(rules[index].key, value: nil) }; try runtime.repository?.context.save() }
                catch { errorMessage = error.localizedDescription }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }.navigationTitle("Organisation rules")
            .toolbar { ToolbarItem(placement: .primaryAction) { Button("Add rule", systemImage: "plus") { editing = MailOrganisationRule() } } }
            .sheet(item: $editing) { rule in NavigationStack { MailRuleEditor(rule: rule) } }
    }
}

private struct MailRuleEditor: View {
    @Environment(AppRuntime.self) private var runtime
    @Environment(\.dismiss) private var dismiss
    @Query private var accounts: [MailAccount]
    @Query private var folders: [MailFolder]
    @State var rule: MailOrganisationRule
    @State private var errorMessage: String?
    var body: some View {
        Form {
            TextField("Rule name", text: $rule.name)
            Toggle("Enabled", isOn: $rule.enabled)
            Picker("Account", selection: $rule.accountID) {
                Text("All accounts").tag(UUID?.none)
                ForEach(accounts) { Text($0.email).tag(Optional($0.id)) }
            }
            .onChange(of: rule.accountID) { _, _ in if rule.action.hasPrefix("labelAdd:") { rule.action = "read" } }
            Section("Match all conditions") {
                TextField("Sender contains", text: $rule.sender).textInputAutocapitalization(.never).autocorrectionDisabled()
                TextField("Subject contains", text: $rule.subject)
            }
            Picker("Action", selection: $rule.action) {
                Text("Mark read").tag("read"); Text("Star").tag("star"); Text("Archive").tag("archive")
                ForEach(folders.filter { $0.accountID == rule.accountID && $0.kindRaw == "user" }) { folder in
                    Text("Label: " + folder.name).tag("labelAdd:" + folder.remoteID)
                }
            }
            if let errorMessage { Text(errorMessage).foregroundStyle(.red) }
        }.navigationTitle("Edit rule")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button("Save") {
                    rule.sender = rule.sender.trimmingCharacters(in: .whitespacesAndNewlines)
                    rule.subject = rule.subject.trimmingCharacters(in: .whitespacesAndNewlines)
                    rule.revision = UUID()
                    do { try runtime.repository?.saveRule(rule); dismiss() } catch { errorMessage = error.localizedDescription }
                }.disabled(rule.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || (rule.sender.isEmpty && rule.subject.isEmpty)) }
            }
    }
}
