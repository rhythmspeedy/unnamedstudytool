import SwiftUI

struct AnimatedWordmark: View {
    var size: CGFloat = 52
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @State private var appeared = false

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array("unnamed".enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .scaleEffect(appeared || reduceMotion ? 1 : 0.25, anchor: .bottom)
                    .rotationEffect(.degrees(appeared || reduceMotion ? 0 : (index.isMultiple(of: 2) ? -18 : 18)))
                    .offset(y: appeared || reduceMotion ? 0 : 8)
                    .opacity(appeared || reduceMotion ? 1 : 0)
                    .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.62).delay(Double(index) * 0.035), value: appeared)
            }
        }
        .font(.system(size: size, weight: .semibold, design: .rounded))
        .overlay(alignment: .bottom) {
            Capsule().fill(theme.accent).frame(width: 32, height: 3)
                .scaleEffect(x: appeared ? 1 : 0.1, y: 1)
                .animation(reduceMotion ? nil : .spring(response: 0.26, dampingFraction: 0.55), value: appeared)
                .opacity(appeared || reduceMotion ? 0 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2).delay(0.4), value: appeared)
                .offset(y: 7)
        }
        .accessibilityElement(children: .ignore).accessibilityLabel("unnamed")
        .onAppear { appeared = true }
    }
}

/// Covers the existing window, rather than opening or resizing a splash window.
struct LaunchIntro: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    let finish: () -> Void

    var body: some View {
        ZStack {
            theme.background
            AnimatedWordmark().foregroundStyle(theme.ink)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityLabel("Welcome to unnamed")
        .task {
            if !reduceMotion {
                // Cancellation is expected if the window closes during the intro.
                try? await Task.sleep(for: .milliseconds(800))
                guard !Task.isCancelled else { return }
            }
            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { finish() }
        }
    }
}

struct BubbleNavigation: View {
    let page: StudyPage
    let select: (StudyPage) -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    @State private var position: CGFloat = 0
    @State private var compression: CGFloat = 1
    private var selectedIndex: CGFloat { CGFloat(StudyPage.allCases.firstIndex(of: page) ?? 0) }

    var body: some View {
        GeometryReader { geometry in
            let width = (geometry.size.width - 8) / CGFloat(StudyPage.allCases.count)
            ZStack(alignment: .leading) {
                Capsule().fill(theme.ink.opacity(0.055))
                Capsule().fill(theme.accent)
                    .frame(width: width, height: 30)
                    .scaleEffect(x: compression, y: 1 - (1 - compression) * 0.25)
                    .offset(x: 4 + width * (reduceMotion ? selectedIndex : position))
                    .allowsHitTesting(false)
                HStack(spacing: 0) {
                    ForEach(StudyPage.allCases, id: \.self) { target in
                        Button { select(target) } label: {
                            Text(target.rawValue).font(.system(size: 12, weight: .medium))
                                .foregroundStyle(target == page ? theme.buttonInk : theme.ink)
                                .frame(maxWidth: .infinity, minHeight: 36)
                                .contentShape(Capsule())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(target == page ? .isSelected : [])
                    }
                }.padding(.horizontal, 4)
            }
        }.frame(height: 38)
        .accessibilityElement(children: .contain).accessibilityLabel("Study tool")
        .task(id: page) {
            guard !reduceMotion else { position = selectedIndex; compression = 1; return }
            guard position != selectedIndex else {
                withAnimation(.spring(response: 0.18, dampingFraction: 0.65)) { compression = 1 }
                return
            }
            withAnimation(.easeIn(duration: 0.045)) { compression = 0.58 }
            // Cancellation means another tab was chosen; only the newest request moves the pill.
            try? await Task.sleep(for: .milliseconds(45))
            guard !Task.isCancelled else { return }
            guard !reduceMotion else { position = selectedIndex; compression = 1; return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.72)) { position = selectedIndex }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.58).delay(0.045)) { compression = 1 }
        }
        .onChange(of: reduceMotion) { _, _ in
            position = selectedIndex
            compression = 1
        }
    }
}

/// An entrance only: outgoing editors are detached immediately, so fast tool
/// changes never leave two instances of the same cached native editor alive.
struct StudyReveal: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var visible = false
    var duration: Double = 0.22
    var distance: CGFloat = 6

    func body(content: Content) -> some View {
        content
            .opacity(visible || reduceMotion ? 1 : 0)
            .offset(y: visible || reduceMotion ? 0 : distance)
            .onAppear {
                withAnimation(reduceMotion ? nil : .easeOut(duration: duration)) {
                    visible = true
                }
            }
    }
}

struct HomeToolButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage("theme") private var theme: StudyTheme = .graphite

    func makeBody(configuration: Configuration) -> some View {
        HomeToolButton(configuration: configuration, theme: theme, reduceMotion: reduceMotion)
    }

    private struct HomeToolButton: View {
        let configuration: ButtonStyle.Configuration
        let theme: StudyTheme
        let reduceMotion: Bool
        @State private var hovering = false

        var body: some View {
            configuration.label
                .overlay(RoundedRectangle(cornerRadius: 14).fill(theme.accent.opacity(hovering ? 0.06 : 0)).allowsHitTesting(false))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(theme.accent.opacity(hovering ? 0.25 : 0), lineWidth: 1).allowsHitTesting(false))
                .scaleEffect(configuration.isPressed && !reduceMotion ? 0.992 : 1)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.14), value: hovering)
                .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}
