import SwiftUI

struct RecipientField: View {
    let title: String
    @Binding var text: String
    let suggestions: [RecipientSuggestion]
    let excluded: Set<String>
    @FocusState private var focused: Bool
    @State private var editing = false
    private var matches: [RecipientSuggestion] {
        guard focused else { return [] }
        let last = text.trimmingCharacters(in: .whitespaces)
        guard !last.hasSuffix(","), !last.hasSuffix(";"), let term = RecipientInput.tokens(text).last,
              RecipientInput.address(term) == nil, term.count >= 2 else { return [] }
        return Array(suggestions.filter { !excluded.contains($0.id) &&
            ($0.address.email.localizedCaseInsensitiveContains(term) || $0.address.displayName.localizedCaseInsensitiveContains(term))
        }.prefix(5))
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(title).font(.subheadline).foregroundStyle(MailStyle.secondaryInk).frame(minWidth: 52, alignment: .leading)
                if !editing && !text.isEmpty {
                    Button { editing = true } label: {
                        Text(RecipientInput.tokens(text).map { RecipientInput.address($0)?.displayName ?? $0 }.joined(separator: ", "))
                            .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Edit \(title) recipients")
                        .contextMenu {
                            ForEach(Array(RecipientInput.tokens(text).enumerated()), id: \.offset) { _, token in
                                Button("Remove \(token)", systemImage: "minus.circle", role: .destructive) {
                                    var pieces = RecipientInput.tokens(text)
                                    if let index = pieces.firstIndex(of: token) { pieces.remove(at: index); text = pieces.joined(separator: ", ") }
                                }
                            }
                        }
                } else {
                    TextField("Email addresses", text: $text)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(title).accessibilityIdentifier("compose\(title)")
                        .focused($focused)
                        .task { if editing { focused = true } }
                }
            }.frame(minHeight: 44)
            if !RecipientInput.invalid(text).isEmpty {
                Text("Check address: " + RecipientInput.invalid(text).joined(separator: ", "))
                    .font(.caption).foregroundStyle(.red).accessibilityIdentifier("invalidRecipients-\(title)")
            }
            ForEach(matches) { suggestion in
                Button {
                    text = RecipientInput.replacingLastToken(text, with: suggestion.address)
                } label: {
                    VStack(alignment: .leading) {
                        Text(suggestion.address.displayName)
                        Text(suggestion.address.email).font(.caption).foregroundStyle(MailStyle.secondaryInk)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("Add \(suggestion.address.email) to \(title)")
            }
        }
        .onChange(of: focused) { _, value in editing = value }
    }
}
