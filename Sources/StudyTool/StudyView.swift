import SwiftUI

struct StudyView: View {
    @EnvironmentObject private var hub: StudyHub
    @EnvironmentObject private var router: StudyRouter
    @State private var session: StudySession
    @State private var revealed = false
    @State private var remaining = 30.0
    @State private var lastTick = ProcessInfo.processInfo.systemUptime
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @AppStorage("focusSize") private var focusSize: FocusSize = .comfortable
    @AppStorage("timerEnabled") private var timerEnabled = false
    @AppStorage("timerSeconds") private var timerSeconds = 30
    private let ticks = Timer.publish(every: 0.2, on: .main, in: .common).autoconnect()
    let close: () -> Void

    init(initial: StudySession, close: @escaping () -> Void) {
        _session = State(initialValue: initial)
        self.close = close
    }

    private var displayedText: String {
        guard let card = session.current else { return "" }
        return revealed ? card.back : card.front
    }

    private var textSize: CGFloat {
        switch displayedText.count {
        case 0...220: return focusSize.fontSize
        case 221...500: return min(focusSize.fontSize, 27)
        default: return min(focusSize.fontSize, 22)
        }
    }

    var body: some View {
        GeometryReader { geometry in
            sessionContent
                .frame(width: min(focusSize.width, max(0, geometry.size.width - 24)),
                       height: min(focusSize.height, max(0, geometry.size.height - 24)))
                .background(theme.background)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .modifier(AppAppearance())
        .onAppear { resetTimer() }
        .onReceive(ticks) { _ in updateTimer() }
        .onChange(of: timerSeconds) { _, _ in resetTimer() }
        .onChange(of: timerEnabled) { _, _ in resetTimer() }
    }

    private var sessionContent: some View {
        VStack(spacing: 20) {
            HStack {
                Text("FOCUS SESSION")
                    .font(.system(size: 11, weight: .medium, design: .monospaced))
                    .tracking(2).foregroundStyle(.secondary)
                Spacer()
                Button("End session", action: close)
            }

            ProgressView(value: Double(session.mastered), total: Double(max(session.total, 1)))
                .tint(theme.accent)

            if session.current != nil {
                HStack {
                    Text("\(session.mastered) of \(session.total) completed")
                    if let card = session.current, let source = session.sources[card.id], let name = session.sourceNames[source] {
                        Text(name).lineLimit(1)
                    }
                    Spacer()
                    if timerEnabled {
                        Text(remaining <= 0 ? "Time’s up" : revealed ? "Timer stopped" : "\(Int(ceil(remaining)))s")
                            .monospacedDigit()
                    } else {
                        Text("\(session.queue.count) remaining")
                    }
                }.font(.caption).foregroundStyle(.secondary)

                VStack(spacing: 14) {
                    Text(revealed ? "ANSWER" : "PROMPT")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(3).foregroundStyle(.secondary)
                    ScrollView {
                        Text(displayedText)
                            .font(.system(size: textSize, weight: .medium, design: .serif))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 20)
                    }.id("\(session.current?.id.uuidString ?? "")-\(revealed)")
                }
                .padding(34)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.surface, in: RoundedRectangle(cornerRadius: 20))
                .overlay(RoundedRectangle(cornerRadius: 20).stroke(theme.ink.opacity(0.12)))

                HStack(spacing: 16) {
                    Button { previous() } label: { Label("Previous", systemImage: "arrow.left") }
                        .controlSize(.large)
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .disabled(!session.canGoBack)
                    Button(revealed ? "Show prompt" : "Reveal answer") { revealed.toggle() }
                        .controlSize(.large)
                        .keyboardShortcut(.space, modifiers: [])
                    Button { next() } label: { Label("Next", systemImage: "arrow.right") }
                        .buttonStyle(PrimaryButtonStyle())
                        .keyboardShortcut(.rightArrow, modifiers: [])
                }
                .background {
                    HStack {
                        Button("Previous") { previous() }
                            .keyboardShortcut("z", modifiers: [])
                            .disabled(!session.canGoBack)
                        Button("Next") { next() }
                            .keyboardShortcut("x", modifiers: [])
                    }
                    .hidden()
                    .accessibilityHidden(true)
                }

                Text("Space to flip · ← previous · → next · browse freely")
                    .font(.caption).foregroundStyle(.secondary)
                if revealed {
                    HStack(spacing: 14) {
                        Button("Again · 1") { rate(.again) }.keyboardShortcut("1", modifiers: [])
                        Button("Unsure · 2") { rate(.unsure) }.keyboardShortcut("2", modifiers: [])
                        Button("Know · 3") { rate(.know) }.keyboardShortcut("3", modifiers: [])
                    }.font(.caption)
                }
            } else {
                Spacer()
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 56, weight: .ultraLight)).foregroundStyle(theme.accent)
                Text("That’s a little more learned.").font(.system(size: 32, design: .serif))
                Text("You worked through all \(session.total) cards.").foregroundStyle(.secondary)
                HStack {
                    Button { previous() } label: { Label("Previous card", systemImage: "arrow.left") }
                        .keyboardShortcut(.leftArrow, modifiers: [])
                        .background {
                            Button("Previous card") { previous() }
                                .keyboardShortcut("z", modifiers: [])
                                .hidden().accessibilityHidden(true)
                        }
                    Button("Back to deck", action: close).buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
                }
                Spacer()
            }
        }
        .padding(36)
        .background {
            if !router.focused { Button("End session", action: close).keyboardShortcut(.cancelAction).hidden().accessibilityHidden(true) }
        }
        .onExitCommand { if router.focused { router.focused = false } else { close() } }
    }

    private func next() {
        session.answer(known: true)
        hub.studied(session)
        revealed = false
        resetTimer()
    }

    private func previous() {
        session.goBack()
        hub.studied(session)
        revealed = false
        resetTimer()
    }

    private func rate(_ confidence: StudySession.Confidence) {
        if let card = session.current { hub.rate(card, confidence: confidence) }
        session.rate(confidence); hub.studied(session); revealed = false; resetTimer()
    }

    private func resetTimer() {
        remaining = Double(min(max(timerSeconds, 5), 300))
        lastTick = ProcessInfo.processInfo.systemUptime
    }

    private func updateTimer() {
        let now = ProcessInfo.processInfo.systemUptime
        let elapsed = now - lastTick
        lastTick = now
        guard timerEnabled, !revealed, session.current != nil, NSApp.isActive, elapsed < 1 else { return }
        remaining = max(0, remaining - elapsed)
        if remaining == 0 { revealed = true }
    }
}
