import SwiftUI

struct AppearanceSettingsView: View {
    private struct Choice: Identifiable {
        let id: String
        let name: String
        let hex: UInt32
    }
    @AppStorage("appearance") private var appearance = "system"
    @AppStorage("surfaceColour") private var surface = "stone"
    @AppStorage("accentColour") private var accent = "plum"
    @AppStorage("customAccentColour") private var customAccent = "705267"
    @AppStorage("mailFont") private var font = "serif"

    private let surfaces: [Choice] = [
        .init(id: "stone", name: "Stone", hex: 0xF1EFEB), .init(id: "sky", name: "Sky", hex: 0xEAF0F4),
        .init(id: "sage", name: "Sage", hex: 0xEDF3ED), .init(id: "blush", name: "Blush", hex: 0xF5EEEB)
    ]
    private let accents: [Choice] = [
        .init(id: "plum", name: "Plum", hex: 0x705267), .init(id: "ocean", name: "Ocean", hex: 0x17688F),
        .init(id: "forest", name: "Forest", hex: 0x28774E), .init(id: "coral", name: "Coral", hex: 0xA84E3D),
        .init(id: "gold", name: "Gold", hex: 0x916416)
    ]
    private var customColour: Binding<Color> {
        Binding(get: { Color(hex: customAccent) }, set: { value in
            let ui = UIColor(value)
            var red: CGFloat = 0; var green: CGFloat = 0; var blue: CGFloat = 0; var alpha: CGFloat = 0
            if ui.getRed(&red, green: &green, blue: &blue, alpha: &alpha) {
                customAccent = String(format: "%02X%02X%02X", Int(red * 255), Int(green * 255), Int(blue * 255))
                accent = "custom"
            }
        })
    }

    var body: some View {
        List {
            Section("Mode") {
                Picker("Appearance", selection: $appearance) {
                    Text("System").tag("system")
                    Text("Light").tag("light")
                    Text("Dark").tag("dark")
                }.pickerStyle(.segmented)
            }
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("A calmer place for your mail")
                        .font(MailStyle.heading).foregroundStyle(MailStyle.ink)
                    HStack(spacing: 10) {
                        Image(systemName: "envelope").foregroundStyle(MailStyle.accent)
                        Text("A little colour, your way.").foregroundStyle(MailStyle.secondaryInk)
                    }.font(.subheadline)
                }
                .frame(maxWidth: .infinity, alignment: .leading).padding(20)
                .background(MailStyle.paper, in: .rect(cornerRadius: 18))
                .listRowBackground(Color.clear)
            }
            Section("Background") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                    ForEach(surfaces) { item in
                        choice(name: item.name, colour: Color(hex: String(format: "%06X", item.hex)), selected: surface == item.id, checkColour: .black) { surface = item.id }
                    }
                }.padding(.vertical, 8)
            }
            Section("Accent") {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 12) {
                    ForEach(accents) { item in
                        choice(name: item.name, colour: Color(hex: String(format: "%06X", item.hex)), selected: accent == item.id, checkColour: .white) { accent = item.id }
                    }
                }.padding(.vertical, 8)
                ColorPicker("Custom accent", selection: customColour, supportsOpacity: false)
                Button {
                    accent = "custom"
                } label: {
                    Label("Use custom accent", systemImage: accent == "custom" ? "checkmark.circle.fill" : "circle")
                }.accessibilityAddTraits(accent == "custom" ? .isSelected : [])
            }
            Section("Font") {
                Picker("Font", selection: $font) {
                    Text("Classic serif").tag("serif")
                    Text("System").tag("system")
                    Text("Rounded").tag("rounded")
                    Text("Monospaced").tag("monospaced")
                }.pickerStyle(.inline)
            }
        }
        .modifier(MailWorkspaceList())
        .mailSheetTitle("Colours & type")
        .preferredColorScheme(appearance == "system" ? nil : appearance == "dark" ? .dark : .light)
    }

    private func choice(name: String, colour: Color, selected: Bool, checkColour: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Circle().fill(colour).frame(width: 44, height: 44)
                    .overlay { if selected { Image(systemName: "checkmark").font(.headline.bold()).foregroundStyle(checkColour) } }
                    .overlay { Circle().strokeBorder(selected ? MailStyle.ink : MailStyle.divider, lineWidth: selected ? 2 : 1).padding(-4) }
                Text(name).font(.caption).foregroundStyle(MailStyle.ink)
            }.frame(maxWidth: .infinity)
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

private extension Color {
    init(hex: String) {
        let value = UInt32(hex, radix: 16) ?? 0x705267
        self.init(red: Double((value >> 16) & 255) / 255,
                  green: Double((value >> 8) & 255) / 255,
                  blue: Double(value & 255) / 255)
    }
}

struct CreditsView: View {
    var body: some View {
        List {
            Section("About") {
                Text("Dispatch is made by Freddie Philpot to make everyday mail feel a little calmer.")
            }
            Section("Find me") {
                Link("LinkedIn", destination: URL(string: "https://www.linkedin.com/in/freddiephilpot")!)
                Link("GitHub", destination: URL(string: "https://github.com/pphilfre")!)
                Link("Portfolio", destination: URL(string: "https://freddiephilpot.dev")!)
                Link("contact@freddiephilpot.dev", destination: URL(string: "mailto:contact@freddiephilpot.dev")!)
            }
        }
        .modifier(MailWorkspaceList())
        .mailSheetTitle("Credits")
    }
}
