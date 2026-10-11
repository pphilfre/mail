import SwiftUI
import UIKit
import Observation

@MainActor @Observable final class RichMailEditorController {
    weak var view: UITextView?
    var changed: (() -> Void)?
    var bold = false
    var italic = false
    var underline = false

    func checkpointUndo(_ title: String) {
        guard let view else { return }
        let previous = RichMailEditor.snapshot(view.attributedText), selection = view.selectedRange
        view.undoManager?.registerUndo(withTarget: self) { controller in
            MainActor.assumeIsolated { controller.restore(previous, selection: selection, title: title) }
        }
        view.undoManager?.setActionName(title)
    }
    private func restore(_ document: RichMailBody, selection: NSRange, title: String) {
        guard let view else { return }
        checkpointUndo(title)
        view.attributedText = RichMailEditor.attributed(document.text, document: document)
        let start = min(selection.location, view.textStorage.length)
        view.selectedRange = NSRange(location: start, length: min(selection.length, view.textStorage.length - start))
        changed?(); refresh()
    }

    func refresh() {
        guard let view else { return }
        let attributes = view.selectedRange.length > 0 && view.selectedRange.location < view.textStorage.length
            ? view.textStorage.attributes(at: view.selectedRange.location, effectiveRange: nil) : view.typingAttributes
        let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
        bold = traits.contains(.traitBold); italic = traits.contains(.traitItalic)
        underline = (attributes[.underlineStyle] as? Int ?? 0) != 0
    }
    func toggle(_ key: NSAttributedString.Key) {
        guard let view else { return }
        let selection = view.selectedRange
        var typing = view.typingAttributes
        if key == .font { return }
        let selected = selection.length > 0 && selection.location < view.textStorage.length
            ? view.textStorage.attribute(key, at: selection.location, effectiveRange: nil) : typing[key]
        let enabled = (selected as? Int ?? 0) != 0
        let value = enabled ? 0 : NSUnderlineStyle.single.rawValue
        if selection.length > 0 { checkpointUndo("Formatting"); view.textStorage.addAttribute(key, value: value, range: selection) }
        typing[key] = value; view.typingAttributes = typing
        changed?(); refresh(); view.becomeFirstResponder()
    }
    func toggleTrait(_ trait: UIFontDescriptor.SymbolicTraits) {
        guard let view else { return }
        let selection = view.selectedRange
        let current = view.selectedRange.length > 0 && selection.location < view.textStorage.length
            ? view.textStorage.attribute(.font, at: selection.location, effectiveRange: nil) as? UIFont : view.typingAttributes[.font] as? UIFont
        let remove = current?.fontDescriptor.symbolicTraits.contains(trait) == true
        func font(_ value: UIFont) -> UIFont {
            var traits = value.fontDescriptor.symbolicTraits
            if remove { traits.remove(trait) } else { traits.insert(trait) }
            return UIFont(descriptor: value.fontDescriptor.withSymbolicTraits(traits) ?? value.fontDescriptor, size: value.pointSize)
        }
        if selection.length > 0 {
            checkpointUndo("Formatting")
            let snapshot = NSAttributedString(attributedString: view.textStorage)
            view.textStorage.beginEditing()
            snapshot.enumerateAttribute(.font, in: selection) { value, range, _ in
                view.textStorage.addAttribute(.font, value: font(value as? UIFont ?? .preferredFont(forTextStyle: .body)), range: range)
            }
            view.textStorage.endEditing()
        }
        view.typingAttributes[.font] = font(current ?? .preferredFont(forTextStyle: .body))
        changed?(); refresh(); view.becomeFirstResponder()
    }
    func list(numbered: Bool) {
        guard let view else { return }
        let source = view.text as NSString
        let range = source.paragraphRange(for: view.selectedRange)
        let paragraphText = source.substring(with: range)
        var lines = paragraphText.components(separatedBy: "\n")
        if lines.count > 1 && lines.last == "" { lines.removeLast() }
        let remove = lines.allSatisfy { numbered ? $0.range(of: #"^\d+\. "#, options: .regularExpression) != nil : $0.hasPrefix("• ") }
        var offset = range.location
        let edits = lines.enumerated().map { index, line -> (NSRange, String) in
            let prefix = line.range(of: #"^(?:• |\d+\. )"#, options: .regularExpression).map { String(line[$0]).utf16.count } ?? 0
            let edit = (NSRange(location: offset, length: prefix), remove ? "" : numbered ? "\(index + 1). " : "• ")
            offset += line.utf16.count + 1
            return edit
        }
        checkpointUndo("List")
        var start = view.selectedRange.location, end = start + view.selectedRange.length
        view.textStorage.beginEditing()
        for (edit, prefix) in edits.reversed() {
            let delta = prefix.utf16.count - edit.length
            view.textStorage.replaceCharacters(in: edit, with: NSAttributedString(string: prefix, attributes: view.typingAttributes))
            if edit.location <= start { start += delta; end += delta }
            else if edit.location < end { end += delta }
        }
        view.textStorage.endEditing()
        start = max(0, min(start, view.textStorage.length)); end = max(start, min(end, view.textStorage.length))
        view.selectedRange = NSRange(location: start, length: end - start)
        changed?(); view.becomeFirstResponder()
    }
    func link(_ value: String) {
        guard let view, RichMailBody.safeLink(value) else { return }
        checkpointUndo("Link")
        if view.selectedRange.length == 0 { view.insertText(value); view.selectedRange = NSRange(location: view.selectedRange.location - (value as NSString).length, length: (value as NSString).length) }
        view.textStorage.addAttribute(.link, value: value, range: view.selectedRange)
        view.typingAttributes.removeValue(forKey: .link)
        changed?(); view.becomeFirstResponder()
    }
}

struct RichMailEditor: UIViewRepresentable {
    @Binding var text: String
    @Binding var document: RichMailBody?
    let controller: RichMailEditorController

    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.backgroundColor = .clear
        view.isScrollEnabled = false
        view.adjustsFontForContentSizeCategory = true
        view.font = .preferredFont(forTextStyle: .body)
        view.allowsEditingTextAttributes = true
        view.textContainerInset = UIEdgeInsets(top: 14, left: 0, bottom: 18, right: 0)
        view.textContainer.lineFragmentPadding = 0
        view.accessibilityLabel = "Message body"; view.accessibilityIdentifier = "composeBody"
        view.attributedText = Self.attributed(text, document: document)
        view.delegate = context.coordinator
        controller.view = view
        controller.changed = { [weak coordinator = context.coordinator, weak view] in
            if let view { coordinator?.textViewDidChange(view) }
        }
        return view
    }
    func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self
        guard view.text != text else { return }
        context.coordinator.updating = true
        defer { context.coordinator.updating = false }
        // Signature changes and inserted snippets retain formatting outside the edited range.
        let old = Self.snapshot(view.attributedText)
        let updated = document?.text == text ? document : old.replacingText(with: text)
        let selection = view.selectedRange
        view.attributedText = Self.attributed(text, document: updated)
        view.selectedRange = NSRange(location: min(selection.location, text.utf16.count), length: 0)
        // Publish on the next run loop; mutating SwiftUI state during updateUIView is invalid.
        Task { @MainActor [weak coordinator = context.coordinator, weak view] in
            guard let view, view.text == coordinator?.parent.text else { return }
            coordinator?.textViewDidChange(view)
        }
    }
    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width, width > 0 else { return nil }
        let size = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(260, size.height))
    }
    static func attributed(_ text: String, document: RichMailBody?) -> NSAttributedString {
        let result = NSMutableAttributedString(string: text, attributes: [.font: UIFont.preferredFont(forTextStyle: .body), .foregroundColor: UIColor.label])
        guard let document, document.text == text else { return result }
        for run in document.runs where run.location >= 0 && run.length > 0 && run.location <= result.length && run.length <= result.length - run.location {
            let range = NSRange(location: run.location, length: run.length)
            let base = UIFont.preferredFont(forTextStyle: .body)
            var traits: UIFontDescriptor.SymbolicTraits = []
            if run.bold { traits.insert(.traitBold) }; if run.italic { traits.insert(.traitItalic) }
            result.addAttribute(.font, value: UIFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits) ?? base.fontDescriptor, size: base.pointSize), range: range)
            if run.underline { result.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if run.strike { result.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: range) }
            if let link = run.link, RichMailBody.safeLink(link) { result.addAttribute(.link, value: link, range: range) }
        }
        return result
    }
    static func snapshot(_ attributed: NSAttributedString) -> RichMailBody {
        var runs: [RichMailBody.Run] = []
        attributed.enumerateAttributes(in: NSRange(location: 0, length: attributed.length)) { attributes, range, _ in
            let traits = (attributes[.font] as? UIFont)?.fontDescriptor.symbolicTraits ?? []
            let run = RichMailBody.Run(location: range.location, length: range.length,
                bold: traits.contains(.traitBold), italic: traits.contains(.traitItalic),
                underline: (attributes[.underlineStyle] as? Int ?? 0) != 0,
                strike: (attributes[.strikethroughStyle] as? Int ?? 0) != 0,
                link: (attributes[.link] as? URL)?.absoluteString ?? attributes[.link] as? String)
            if run.bold || run.italic || run.underline || run.strike || run.link != nil { runs.append(run) }
        }
        return RichMailBody(text: attributed.string, runs: runs)
    }
    @MainActor final class Coordinator: NSObject, UITextViewDelegate {
        var parent: RichMailEditor
        var updating = false
        init(_ parent: RichMailEditor) { self.parent = parent }
        func textViewDidChangeSelection(_ textView: UITextView) { if !updating { parent.controller.refresh() } }
        func textViewDidChange(_ view: UITextView) {
            guard !updating else { return }
            parent.text = view.text
            parent.document = RichMailEditor.snapshot(view.attributedText)
            parent.controller.refresh()
            view.invalidateIntrinsicContentSize()
        }
        func textView(_ view: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0 else { return true }
            let source = view.text as NSString
            let lineRange = source.paragraphRange(for: NSRange(location: range.location, length: 0))
            let before = source.substring(with: NSRange(location: lineRange.location, length: range.location - lineRange.location))
            var prefix: String?
            if before.hasPrefix("• ") { prefix = "• " }
            else if let match = before.range(of: #"^\d+\. "#, options: .regularExpression), let number = Int(before[match].dropLast(2)) { prefix = "\(number + 1). " }
            guard let prefix else { return true }
            parent.controller.checkpointUndo("Continue list")
            let attributes = view.typingAttributes
            if before == "• " || before.range(of: #"^\d+\. $"#, options: .regularExpression) != nil {
                view.textStorage.replaceCharacters(in: NSRange(location: lineRange.location, length: before.utf16.count), with: NSAttributedString(string: "\n", attributes: attributes))
                view.selectedRange = NSRange(location: lineRange.location + 1, length: 0)
            } else {
                let inserted = "\n" + prefix
                view.textStorage.replaceCharacters(in: range, with: NSAttributedString(string: inserted, attributes: attributes))
                view.selectedRange = NSRange(location: range.location + inserted.utf16.count, length: 0)
            }
            textViewDidChange(view)
            return false
        }
    }
}
