import SwiftUI

struct MailRowDate: View {
    let date: Date
    var body: some View {
        Group {
            if Calendar.current.isDateInToday(date) { Text(date, format: .dateTime.hour().minute()) }
            else { Text(date, format: .dateTime.day().month(.abbreviated)) }
        }.font(.caption).foregroundStyle(.secondary)
    }
}
