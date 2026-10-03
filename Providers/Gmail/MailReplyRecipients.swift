import Foundation

enum MailReplyRecipients {
    static func make(sender: MailAddress, replyTo: [MailAddress], to: [MailAddress], cc: [MailAddress],
                     ownEmail: String, replyAll: Bool) -> (to: [String], cc: [String]) {
        let own = ownEmail.lowercased()
        // Replying to one's sent message addresses its original recipients.
        let targets = sender.email.lowercased() == own ? to : (replyTo.isEmpty ? [sender] : replyTo)
        var seen: Set<String> = [own]
        func unique(_ addresses: [MailAddress]) -> [String] {
            addresses.compactMap { address in
                guard seen.insert(address.email.lowercased()).inserted else { return nil }
                return address.email
            }
        }
        let recipients = unique(targets + (replyAll ? to : []))
        let copies = replyAll ? unique(cc) : []
        return (recipients, copies)
    }
}
