import SwiftUI

enum StudyTheme: String, CaseIterable, Identifiable {
    case graphite, parchment, forest, ocean, clay
    case midnight, evergreen, oxblood, espresso, inkstone
    case sage, stillwater, driftwood, haze, moonstone
    case aurora, nocturne, afterHours = "after hours", blackCherry = "black cherry", deepSea = "deep sea"

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var scheme: ColorScheme { [.parchment, .clay, .afterHours, .deepSea].contains(self) ? .light : .dark }

    var background: Color {
        switch self {
        case .graphite: Color(hex: 0x121214)
        case .parchment: Color(hex: 0xF3EFE5)
        case .forest: Color(hex: 0x14221D)
        case .ocean: Color(hex: 0x142433)
        case .clay: Color(hex: 0xF1E5DD)
        case .midnight: Color(hex: 0x0B1220)
        case .evergreen: Color(hex: 0x091611)
        case .oxblood: Color(hex: 0x1A0D10)
        case .espresso: Color(hex: 0x17110D)
        case .inkstone: Color(hex: 0x111315)
        case .sage: Color(hex: 0x181E1A)
        case .stillwater: Color(hex: 0x171F24)
        case .driftwood: Color(hex: 0x211D19)
        case .haze: Color(hex: 0x292534)
        case .moonstone: Color(hex: 0x1B1E24)
        case .aurora: Color(hex: 0x0D161A)
        case .nocturne: Color(hex: 0x19112B)
        case .afterHours: Color(hex: 0xF3EDE1)
        case .blackCherry: Color(hex: 0x170D13)
        case .deepSea: Color(hex: 0xE8F1F1)
        }
    }

    var surface: Color {
        switch self {
        case .graphite: Color(hex: 0x242427)
        case .parchment: Color(hex: 0xFFFCF5)
        case .forest: Color(hex: 0x22382F)
        case .ocean: Color(hex: 0x21394D)
        case .clay: Color(hex: 0xFFF8F2)
        case .midnight: Color(hex: 0x172033)
        case .evergreen: Color(hex: 0x14271F)
        case .oxblood: Color(hex: 0x2C171B)
        case .espresso: Color(hex: 0x2B211A)
        case .inkstone: Color(hex: 0x24282C)
        case .sage: Color(hex: 0x29332C)
        case .stillwater: Color(hex: 0x29353C)
        case .driftwood: Color(hex: 0x36302A)
        case .haze: Color(hex: 0x3D364C)
        case .moonstone: Color(hex: 0x2D323C)
        case .aurora: Color(hex: 0x17272B)
        case .nocturne: Color(hex: 0x302047)
        case .afterHours: Color(hex: 0xFFFAF0)
        case .blackCherry: Color(hex: 0x2C1723)
        case .deepSea: Color(hex: 0xF7FCFB)
        }
    }

    var accent: Color {
        switch self {
        case .graphite: Color(hex: 0xECECEF)
        case .parchment: Color(hex: 0x59634D)
        case .forest: Color(hex: 0xBBD3A6)
        case .ocean: Color(hex: 0xA8CDE0)
        case .clay: Color(hex: 0x9A5039)
        case .midnight: Color(hex: 0x8FB7FF)
        case .evergreen: Color(hex: 0x83D1AA)
        case .oxblood: Color(hex: 0xE5A0A8)
        case .espresso: Color(hex: 0xD9AD7C)
        case .inkstone: Color(hex: 0xAAB8C2)
        case .sage: Color(hex: 0xB2C2AA)
        case .stillwater: Color(hex: 0xA7BDC4)
        case .driftwood: Color(hex: 0xC9BAA5)
        case .haze: Color(hex: 0xCFC0E0)
        case .moonstone: Color(hex: 0xB6BDCD)
        case .aurora: Color(hex: 0x6EE7C8)
        case .nocturne: Color(hex: 0xC4A2EC)
        case .afterHours: Color(hex: 0x82633C)
        case .blackCherry: Color(hex: 0xFF92B4)
        case .deepSea: Color(hex: 0x356B74)
        }
    }

    var ink: Color { scheme == .dark ? Color(hex: 0xF0F1EB) : Color(hex: 0x292A26) }
    var buttonInk: Color { scheme == .dark ? Color(hex: 0x17201D) : .white }
}

enum FocusSize: String, CaseIterable, Identifiable {
    case compact, comfortable, expansive

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
    var width: CGFloat { switch self { case .compact: 720; case .comfortable: 900; case .expansive: 1080 } }
    var height: CGFloat { switch self { case .compact: 600; case .comfortable: 720; case .expansive: 820 } }
    var fontSize: CGFloat { switch self { case .compact: 28; case .comfortable: 34; case .expansive: 40 } }
}

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB, red: Double((hex >> 16) & 255) / 255, green: Double((hex >> 8) & 255) / 255, blue: Double(hex & 255) / 255, opacity: 1)
    }
}

struct AppAppearance: ViewModifier {
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    func body(content: Content) -> some View {
        content.preferredColorScheme(theme.scheme).tint(theme.accent).foregroundStyle(theme.ink)
    }
}

struct StudySettingsView: View {
    @EnvironmentObject private var workspace: WorkspaceStore
    @AppStorage("menuBarTimer") private var menuBarTimer = false
    @State private var section = "General"
    @AppStorage("pomodoroFocus") private var pomodoroFocus = 25
    @AppStorage("pomodoroShort") private var pomodoroShort = 5
    @AppStorage("pomodoroLong") private var pomodoroLong = 15
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @AppStorage("focusSize") private var focusSize: FocusSize = .comfortable
    @AppStorage("timerEnabled") private var timerEnabled = false
    @AppStorage("timerSeconds") private var timerSeconds = 30

    var body: some View {
        VStack(spacing: 0) {
            Picker("Settings section", selection: $section) {
                Text("General").tag("General")
                Text("Flashcards").tag("Flashcards")
                Text("Pomodoro").tag("Pomodoro")
                Text("Data").tag("Data")
            }.pickerStyle(.segmented).padding(22)
        Form {
            if section == "General" {
            Section("Appearance") {
                Text("Essentials").font(.caption).foregroundStyle(.secondary)
                themeRow([.graphite, .midnight, .evergreen, .inkstone, .parchment])
                Text("Earth & sea").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                themeRow([.oxblood, .espresso, .ocean, .clay, .forest])
                Text("Soft horizons").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                themeRow([.sage, .stillwater, .deepSea, .haze, .nocturne])
                Text("Warmth & glow").font(.caption).foregroundStyle(.secondary).padding(.top, 4)
                themeRow([.moonstone, .afterHours, .driftwood, .aurora, .blackCherry])
            }

            Section("Your workspace") {
                TargetSettingsView()
                Toggle("Show Pomodoro in the menu bar", isOn: $menuBarTimer)
                Text("Your lists and flashcards save on this Mac. The Pomodoro timer keeps running while you move between tools; quitting the app ends the timer run.").font(.callout).foregroundStyle(.secondary)
            }
            Section("About and updates") {
                Text("unnamedstudytool \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                Link("Download updates…", destination: URL(string: "https://github.com/rhythmspeedy/unnamedstudytool/releases/latest")!)
                Text("Opens the official GitHub releases page. Quit the app, then replace the app in Applications with the new download. Your study data is stored separately. The app never installs updates automatically.").font(.caption).foregroundStyle(.secondary)
            }
            }
            if section == "Flashcards" {
            Section("Focus session") {
                Picker("Window size", selection: $focusSize) {
                    ForEach(FocusSize.allCases) { size in Text(size.title).tag(size) }
                }.pickerStyle(.segmented)
                Text("Study cards fit the available workspace. Navigation stays accessible during a session.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Card timer") {
                Toggle("Use a timer", isOn: $timerEnabled)
                Stepper("\(timerSeconds) seconds per card", value: $timerSeconds, in: 5...300, step: 5)
                    .disabled(!timerEnabled)
                Text("At zero, the answer appears. You still decide when to move on. The timer pauses when the app is inactive.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("Keyboard") {
                Text("Space  Flip     ← / Z  Previous     → / X  Next     Esc  End session")
                    .font(.system(.caption, design: .monospaced))
            }
            }
            if section == "Pomodoro" {
                Section("Intervals") {
                    Stepper("Focus: \(pomodoroFocus) minutes", value: $pomodoroFocus, in: 1...120)
                    Stepper("Short break: \(pomodoroShort) minutes", value: $pomodoroShort, in: 1...60)
                    Stepper("Long break: \(pomodoroLong) minutes", value: $pomodoroLong, in: 1...60)
                    Text("A long break follows every four completed focus intervals. Changes apply to the next interval or when you reset the current one.").font(.caption).foregroundStyle(.secondary)
                }
                Section("Focus sounds") { AmbientPicker() }
            }
            if section == "Data" { DataSettingsView(); DailyBackupSettingsView(); DeletedFlashcardsSettingsView() }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .background(theme.background)
        }.frame(width: 560, height: 560).background(theme.background)
        .modifier(AppAppearance())
        .alert("Workspace needs attention", isPresented: Binding(get: { workspace.error != nil }, set: { if !$0 { workspace.error = nil } })) {
            if workspace.dirty { Button("Retry saving") { workspace.flush() } }
            Button("OK") { workspace.error = nil }
        } message: { Text(workspace.error ?? "") }
    }

    private func themeRow(_ themes: [StudyTheme]) -> some View {
        HStack(spacing: 12) {
            ForEach(themes) { option in
                Button { theme = option } label: {
                    VStack(spacing: 7) {
                        HStack(spacing: 0) {
                            option.background
                            option.surface
                            option.accent
                        }
                        .frame(height: 30)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme == option ? theme.accent : .clear, lineWidth: 2))
                        Text(option.title).font(.caption2).lineLimit(1).minimumScaleFactor(0.8)
                    }
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .accessibilityLabel("\(option.title) theme")
                .accessibilityAddTraits(theme == option ? .isSelected : [])
            }
        }.padding(.vertical, 2)
    }
}
