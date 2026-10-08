import SwiftUI
import UIKit
import Contacts
import ContactsUI
import EventKit
import EventKitUI

struct MessageExport: Identifiable {
    let id = UUID()
    let url: URL
}

@MainActor enum MessageUtilities {
    static func readableCopy(_ message: MailMessage) -> String {
        let text = message.plainTextBody ?? message.cachedHTML.flatMap { String(data: $0, encoding: .utf8) }.map(MailMIME.readableHTML) ?? message.snippet
        return "\(message.subject)\n\nFrom: \(message.sender.displayName) <\(message.senderEmail)>\nTo: \(message.to.map(\.email).joined(separator: ", "))\nDate: \(message.receivedAt.formatted())\n\n\(text)"
    }
    static func formatter(_ message: MailMessage) -> UISimpleTextPrintFormatter {
        let formatter = UISimpleTextPrintFormatter(text: readableCopy(message))
        formatter.font = .systemFont(ofSize: 14)
        formatter.color = .black
        return formatter
    }
    static func printMessage(_ message: MailMessage) -> Bool {
        let controller = UIPrintInteractionController.shared
        let info = UIPrintInfo(dictionary: nil)
        info.jobName = message.subject; info.outputType = .general
        controller.printInfo = info; controller.printFormatter = formatter(message)
        return controller.present(animated: true, completionHandler: nil)
    }
    static func pdf(_ message: MailMessage) throws -> MessageExport {
        let renderer = UIPrintPageRenderer()
        let paper = CGRect(x: 0, y: 0, width: 595, height: 842)
        renderer.setValue(NSValue(cgRect: paper), forKey: "paperRect")
        renderer.setValue(NSValue(cgRect: paper.insetBy(dx: 36, dy: 40)), forKey: "printableRect")
        renderer.addPrintFormatter(formatter(message), startingAtPageAt: 0)
        let data = UIGraphicsPDFRenderer(bounds: paper).pdfData { context in
            for page in 0..<renderer.numberOfPages {
                context.beginPage(); renderer.drawPage(at: page, in: paper)
            }
        }
        let directory = FileManager.default.temporaryDirectory.appending(path: "MailExports", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for file in (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? [] {
            let modified = try? file.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
            if (modified ?? .distantPast) < Date().addingTimeInterval(-86400) { try? FileManager.default.removeItem(at: file) }
        }
        let url = directory.appending(path: "Message-\(UUID().uuidString.prefix(8)).pdf")
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        return MessageExport(url: url)
    }
}

struct MessageShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

struct SenderContactEditor: UIViewControllerRepresentable {
    let name: String
    let email: String
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> UINavigationController {
        let contact = CNMutableContact()
        contact.givenName = name == email ? "" : name
        contact.emailAddresses = [CNLabeledValue(label: CNLabelWork, value: email as NSString)]
        let editor = CNContactViewController(forNewContact: contact)
        editor.contactStore = CNContactStore(); editor.delegate = context.coordinator
        return UINavigationController(rootViewController: editor)
    }
    func updateUIViewController(_ controller: UINavigationController, context: Context) {}
    @MainActor final class Coordinator: NSObject, CNContactViewControllerDelegate {
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func contactViewController(_ viewController: CNContactViewController, didCompleteWith contact: CNContact?) { done() }
    }
}

struct MessageCalendarEditor: UIViewControllerRepresentable {
    let subject: String
    let notes: String
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator { dismiss() } }
    func makeUIViewController(context: Context) -> EKEventEditViewController {
        // EventKitUI lets the person save an event without giving Dispatch calendar read access.
        let editor = EKEventEditViewController()
        editor.eventStore = context.coordinator.store
        let event = EKEvent(eventStore: context.coordinator.store)
        event.title = subject; event.notes = notes
        event.startDate = Date().addingTimeInterval(3600); event.endDate = event.startDate.addingTimeInterval(3600)
        editor.event = event; editor.editViewDelegate = context.coordinator
        return editor
    }
    func updateUIViewController(_ controller: EKEventEditViewController, context: Context) {}
    @MainActor final class Coordinator: NSObject, EKEventEditViewDelegate {
        let store = EKEventStore()
        let done: () -> Void
        init(done: @escaping () -> Void) { self.done = done }
        func eventEditViewController(_ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction) { done() }
    }
}
