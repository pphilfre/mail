import SwiftUI

extension Color {
    init(mailHex: String) {
        let value = UInt64(mailHex, radix: 16) ?? 0x007AFF
        self.init(.sRGB, red: Double((value >> 16) & 255) / 255,
            green: Double((value >> 8) & 255) / 255, blue: Double(value & 255) / 255, opacity: 1)
    }
}
