import SwiftUI

extension View {
    @MainActor func studyEnvironment(_ hub: StudyHub) -> some View {
        environmentObject(hub).environmentObject(hub.library).environmentObject(hub.todos)
            .environmentObject(hub.notes).environmentObject(hub.editors).environmentObject(hub.workspace)
            .environmentObject(hub.router).environmentObject(hub.pomodoro).environmentObject(hub.audio)
    }
}
struct MenuTimerLabel: View {
    @ObservedObject var timer: PomodoroStore
    var body: some View { Label(timer.clock.running || timer.clock.awaitingNext ? timer.time : "Study", systemImage: "timer").monospacedDigit() }
}
struct MenuTimerView: View {
    @EnvironmentObject private var timer: PomodoroStore
    @EnvironmentObject private var workspace: WorkspaceStore
    @EnvironmentObject private var hub: StudyHub
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text("\(timer.clock.phase.rawValue) · \(timer.time)")
        if let intention = workspace.state.intention { Text(intention.labelSnapshot) }
        Button(timer.clock.awaitingNext ? "Start next interval" : timer.clock.running ? "Pause" : "Start / resume") { hub.run(.toggleTimer) }
        Divider()
        Button("Open unnamedstudytool") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        Button("Quit unnamedstudytool") { NSApp.terminate(nil) }
    }
}
