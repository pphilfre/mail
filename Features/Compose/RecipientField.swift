import SwiftUI

struct RecipientField: View {
    let title: String
    @Binding var text: String
    let suggestions: [RecipientSuggestion]
    let excluded: Set<String>
    @FocusState private var focused: Bool
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
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(.secondary).frame(width: 36, alignment: .leading)
                if !focused && !text.isEmpty {
                    Button("Edit recipients") { focused = true }.font(.subheadline)
                        .accessibilityLabel("Edit \(title) recipients")
                } else {
                    TextField("Email addresses", text: $text)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityLabel(title).accessibilityIdentifier("compose\(title)")
                        .focused($focused)
                }
            }
            if !focused && !text.isEmpty {
                ScrollView(.horizontal) {
                    HStack {
                        ForEach(Array(RecipientInput.tokens(text).enumerated()), id: \.offset) { index, token in
                            HStack(spacing: 6) {
                                Button(RecipientInput.address(token)?.displayName ?? token) { focused = true }
                                    .foregroundStyle(RecipientInput.address(token) == nil ? Color.red : Color.primary)
                                Button("Remove \(token)", systemImage: "xmark.circle.fill") {
                                    var pieces = RecipientInput.tokens(text); pieces.remove(at: index); text = pieces.joined(separator: ", ")
                                }.labelStyle(.iconOnly).foregroundStyle(.secondary)
                            }.font(.caption).padding(8).background(.quaternary, in: Capsule())
                        }
                    }
                }
            }
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
                        Text(suggestion.address.email).font(.caption).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.plain).accessibilityLabel("Add \(suggestion.address.email) to \(title)")
            }
        }
    }
}
