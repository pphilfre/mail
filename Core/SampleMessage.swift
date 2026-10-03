import Foundation

struct SampleMessage: Identifiable, Hashable, Sendable {
    let id: UUID
    let sender: String
    let address: String
    let subject: String
    let body: String
    let date: Date
    var isRead: Bool

    var snippet: String { body.replacingOccurrences(of: "\n", with: " ") }

    static let examples: [SampleMessage] = [
        SampleMessage(
            id: UUID(), sender: "Alex Morgan", address: "alex@example.com",
            subject: "A quieter inbox",
            body: "Hi Freddie,\n\nHere’s a sample message to explore the reader. Your real mail will appear here once account connections are ready.\n\nThis message stays on your device and is never sent.\n\nAlex",
            date: Date().addingTimeInterval(-900), isRead: false
        ),
        SampleMessage(
            id: UUID(), sender: "Studio team", address: "studio@example.com",
            subject: "Notes for next week",
            body: "A quick note for Monday: bring your ideas, and we’ll work through the details together.\n\nThis is sample mail for checking the app’s layout.",
            date: Date().addingTimeInterval(-7200), isRead: false
        ),
        SampleMessage(
            id: UUID(), sender: "Jamie Chen", address: "jamie@example.com",
            subject: "Re: Saturday plans",
            body: "That sounds good. See you at eleven!\n\nThis is sample mail.",
            date: Date().addingTimeInterval(-86400), isRead: true
        )
    ]
}
