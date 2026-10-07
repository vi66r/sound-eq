import SwiftUI
import AudioCore

@main
struct SoundEQApp: App {
    @StateObject private var model = AudioModel()

    var body: some Scene {
        Window("Sound EQ", id: "main") {
            MainView(model: model)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 720, height: 590)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(model.isRunning ? "Bypass effects" : "Enable effects") { model.toggle() }
                    .keyboardShortcut("b", modifiers: [.command])
                    .disabled(model.isStarting)
            }
        }
        MenuBarExtra {
            MenuContent(model: model)
        } label: {
            Image(systemName: model.isRunning ? "waveform.circle.fill" : "waveform.circle")
                .accessibilityLabel("Sound EQ")
        }
    }
}

private struct MenuContent: View {
    @ObservedObject var model: AudioModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Text(model.status)
        Button(model.isRunning ? "Bypass effects" : "Enable effects") { model.toggle() }
            .disabled(model.isStarting)
        Divider()
        ForEach(EffectSettings.presets, id: \.name) { preset in
            Button(preset.name + (model.selectedPreset == preset.name ? " ✓" : "")) { model.selectPreset(preset.name) }
        }
        Divider()
        Button("Open Sound EQ") {
            openWindow(id: "main")
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
        Button("Quit Sound EQ") {
            model.stop()
            NSApplication.shared.terminate(nil)
        }.keyboardShortcut("q")
    }
}
