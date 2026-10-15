import SwiftUI

enum MailStyle {
    // Paper and ink stay opaque. Native bars and transient controls supply the glass layer.
    static var accent: Color {
        Color(uiColor: UIColor { traits in
            let choice = UserDefaults.standard.string(forKey: "accentColour") ?? "plum"
            let hex: UInt32
            switch choice {
            case "ocean": hex = traits.userInterfaceStyle == .dark ? 0x8BC8ED : 0x17688F
            case "forest": hex = traits.userInterfaceStyle == .dark ? 0x9AD9B3 : 0x28774E
            case "coral": hex = traits.userInterfaceStyle == .dark ? 0xF1B7A8 : 0xA84E3D
            case "gold": hex = traits.userInterfaceStyle == .dark ? 0xE7C787 : 0x916416
            case "custom": hex = UInt32(UserDefaults.standard.string(forKey: "customAccentColour") ?? "705267", radix: 16) ?? 0x705267
            default: hex = traits.userInterfaceStyle == .dark ? 0xD2B5C9 : 0x705267
            }
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }
    static let success = Color(red: 0.16, green: 0.62, blue: 0.43)
    static let intelligence = adaptive(light: 0x614CC4, dark: 0xBDB0FF)
    static var canvas: Color { surface(light: [0xF1EFEB, 0xEAF0F4, 0xEDF3ED, 0xF5EEEB], dark: [0x19181B, 0x151D24, 0x172019, 0x241A19]) }
    static var paper: Color { surface(light: [0xFAF9F6, 0xF8FBFD, 0xF9FCF8, 0xFFF9F6], dark: [0x211F23, 0x1E2831, 0x202A22, 0x2C2220]) }
    static let ink = adaptive(light: 0x252428, dark: 0xF2EFF1)
    static let secondaryInk = adaptive(light: 0x666269, dark: 0xB8B2BC)
    static let divider = adaptive(light: 0xDEDAD7, dark: 0x423E45, highContrastLight: 0x8C858C, highContrastDark: 0x8D858F)
    static var tile: Color { surface(light: [0xECE9E6, 0xE6EFF5, 0xE9F1E8, 0xF3E7E1], dark: [0x302D33, 0x2A3640, 0x2C382E, 0x3A2D2A]) }
    static let rowSpacing: CGFloat = 6
    static let contentPadding: CGFloat = 20
    static let readingWidth: CGFloat = 680
    static let controlRadius: CGFloat = 10
    static let icon = Font.system(size: 19, weight: .medium)
    static var heading: Font { .system(.largeTitle, design: selectedFontDesign, weight: .medium) }
    static var readerTitle: Font { .system(.title, design: selectedFontDesign, weight: .medium) }
    static let sectionHeading = Font.system(.subheadline, weight: .semibold)

    static var selectedFontDesign: Font.Design {
        switch UserDefaults.standard.string(forKey: "mailFont") ?? "serif" {
        case "rounded": .rounded
        case "system": .default
        case "monospaced": .monospaced
        default: .serif
        }
    }

    private static func surface(light: [UInt32], dark: [UInt32]) -> Color {
        Color(uiColor: UIColor { traits in
            let index: Int
            switch UserDefaults.standard.string(forKey: "surfaceColour") ?? "stone" {
            case "sky": index = 1
            case "sage": index = 2
            case "blush": index = 3
            default: index = 0
            }
            let hex = traits.userInterfaceStyle == .dark ? dark[index] : light[index]
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }

    private static func adaptive(light: UInt32, dark: UInt32, highContrastLight: UInt32? = nil, highContrastDark: UInt32? = nil) -> Color {
        Color(uiColor: UIColor { traits in
            let highContrast = traits.accessibilityContrast == .high
            let hex = traits.userInterfaceStyle == .dark
                ? (highContrast ? highContrastDark ?? dark : dark)
                : (highContrast ? highContrastLight ?? light : light)
            return UIColor(red: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255,
                           blue: CGFloat(hex & 255) / 255, alpha: 1)
        })
    }

    static func motion(reduced: Bool) -> Animation? {
        reduced ? nil : .easeInOut(duration: 0.2)
    }

    static func mailboxSymbol(_ name: String) -> String {
        switch name {
        case "Inbox": "tray"
        case "All Mail": "tray.2"
        case "Unread": "envelope.badge"
        case "Starred": "star"
        case "Sent": "paperplane"
        case "Drafts": "square.and.pencil"
        case "Archive": "archivebox"
        case "Snoozed": "clock"
        case "Spam": "exclamationmark.shield"
        default: "trash"
        }
    }

    static func accountTitle(_ account: MailAccount, unread: Int) -> String {
        account.displayName + (unread > 0 ? " (\(unread) unread)" : "")
    }
}

/// A continuous workspace, grouped by spacing rather than a stack of rounded cards.
struct MailWorkspaceList: ViewModifier {
    func body(content: Content) -> some View {
        content
            .listStyle(.plain)
            .listSectionSpacing(.custom(24))
            .listSectionSeparator(.hidden)
            .listRowSeparatorTint(MailStyle.divider)
            .listRowBackground(MailStyle.paper)
            .scrollContentBackground(.hidden)
            .background(MailStyle.paper)
            .font(.body)
            .foregroundStyle(MailStyle.ink)
            .tint(MailStyle.accent)
            .environment(\.defaultMinListRowHeight, 52)
    }
}

/// Shared text tabs for inbox and search, with a non-colour selected-state cue.
struct MailFilterLabel: View {
    let title: String
    let selected: Bool
    var body: some View {
        Text(title)
            .font(.subheadline.weight(selected ? .semibold : .regular))
            .foregroundStyle(selected ? MailStyle.accent : MailStyle.secondaryInk)
            .padding(.vertical, 10)
            .frame(minHeight: 44)
            .fixedSize(horizontal: true, vertical: false)
            .overlay(alignment: .bottom) {
                if selected { Rectangle().fill(MailStyle.accent).frame(height: 2) }
            }
    }
}

struct MailRule: View {
    @Environment(\.colorSchemeContrast) private var contrast
    var body: some View {
        Rectangle().fill(MailStyle.divider).frame(height: contrast == .increased ? 1 : 0.5).accessibilityHidden(true)
    }
}

struct MailNavigationTitle: View {
    let title: String
    var body: some View {
        Text(title).font(.system(.title2, design: MailStyle.selectedFontDesign, weight: .medium))
            .foregroundStyle(MailStyle.ink).lineLimit(1).accessibilityAddTraits(.isHeader)
    }
}

/// Opaque fallback for custom glass controls when transparency is reduced.
struct MailControlSurface: ViewModifier {
    var cornerRadius: CGFloat = 1000
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(MailStyle.tile, in: .rect(cornerRadius: cornerRadius))
        } else {
            content.glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        }
    }
}

/// A shared minimum touch target for compact, icon-only navigation controls.
struct MailCloseButton: View {
    @Environment(MailFeedback.self) private var feedback
    var title = "Close"
    let action: () -> Void

    var body: some View {
        Button { feedback.select(); action() } label: {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 44, height: 44).contentShape(.circle)
        }
        .labelStyle(.iconOnly)
        .accessibilityLabel(title)
    }
}

extension View {
    func mailSheetTitle(_ title: String) -> some View {
        navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .principal) { MailNavigationTitle(title: title) } }
    }
}

struct MailInfoLabel: View {
    let title: String
    let information: String
    @State private var showing = false
    var body: some View {
        HStack(spacing: 4) {
            Text(title)
            Button { showing = true } label: {
                Image(systemName: "info.circle").font(.footnote).foregroundStyle(MailStyle.secondaryInk)
                    .frame(width: 44, height: 44)
            }.buttonStyle(.borderless).accessibilityLabel("About " + title)
                .popover(isPresented: $showing) {
                    Text(information).font(.callout).padding(20).frame(idealWidth: 280)
                        .presentationCompactAdaptation(.popover)
                }
        }
    }
}
