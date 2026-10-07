import AppKit
import AudioCore
import CoreAudio
import AVFoundation
import Combine

final class AudioModel: ObservableObject {
    @Published var settings: EffectSettings {
        didSet {
            session.apply(settings)
            if let data = try? JSONEncoder().encode(settings) { UserDefaults.standard.set(data, forKey: "effects") }
        }
    }
    @Published private(set) var isRunning = false
    @Published private(set) var isStarting = false
    @Published private(set) var status = "Ready when you are"
    @Published private(set) var outputName = "Default output"
    @Published private(set) var level: Float = 0
    @Published private(set) var hasSignal = false
    @Published private(set) var error: String?
    @Published private(set) var sampleRate = ""
    private let session = SystemAudioSession()
    private var timer: AnyCancellable?
    private var observers: [NSObjectProtocol] = []
    private var workspaceObservers: [NSObjectProtocol] = []
    private var outputListener: AudioObjectPropertyListenerBlock?
    private var startedAt = Date()
    private var lastReceived: UInt64 = 0
    private var lastCallback = Date()
    private var routeAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    init() {
        if let data = UserDefaults.standard.data(forKey: "effects"),
           let value = try? JSONDecoder().decode(EffectSettings.self, from: data),
           value.muffle.isFinite, value.space.isFinite, value.pitch.isFinite, value.output.isFinite {
            settings = EffectSettings(muffle: min(1, max(0, value.muffle)), space: min(1, max(0, value.space)),
                                      pitch: min(0, max(-7, value.pitch)), output: min(1, max(0, value.output)))
        } else { settings = .init() }
        refreshOutput()
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.routeChanged()
        }
        outputListener = listener
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &routeAddress, .main, listener)
        observers.append(NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange,
            object: nil, queue: .main) { [weak self] _ in
                guard self?.isRunning == true else { return }
                self?.stop(message: "Audio route changed · press Enable to reconnect")
            })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in self?.session.stop() })
        workspaceObservers.append(NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main) { [weak self] _ in self?.stop(message: "Paused for sleep · press Enable to reconnect") })
        timer = Timer.publish(every: 0.08, on: .main, in: .common).autoconnect().sink { [weak self] _ in self?.updateMeter() }
    }

    deinit {
        session.stop()
        if let outputListener { AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &routeAddress, .main, outputListener) }
        observers.forEach(NotificationCenter.default.removeObserver)
        workspaceObservers.forEach(NSWorkspace.shared.notificationCenter.removeObserver)
    }

    var selectedPreset: String {
        EffectSettings.presets.first(where: {
            $0.settings.muffle == settings.muffle && $0.settings.space == settings.space && $0.settings.pitch == settings.pitch
        })?.name ?? "Custom"
    }

    func selectPreset(_ name: String) {
        if let preset = EffectSettings.presets.first(where: { $0.name == name }) {
            var value = preset.settings
            value.output = settings.output
            settings = value
        }
    }

    func toggle() { isRunning ? stop() : start() }

    func start() {
        guard !isRunning, !isStarting else { return }
        isStarting = true; error = nil
        status = "Connecting system audio…"
        // Let the UI display the connecting state before the system permission prompt.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            defer { self.isStarting = false }
            do {
                try self.session.start(settings: self.settings)
                self.isRunning = true
                self.startedAt = Date(); self.lastCallback = Date(); self.lastReceived = 0
                self.sampleRate = String(format: "%.1f kHz", self.session.sampleRate / 1_000)
                self.status = "Listening for audio"
                self.refreshOutput()
            } catch {
                self.isRunning = false
                self.error = error.localizedDescription
                self.status = "Couldn’t connect"
            }
        }
    }

    func stop(message: String = "Bypassed · original audio") {
        isRunning = false
        session.stop()
        level = 0; hasSignal = false; status = message
    }

    func openPermissions() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refreshOutput() {
        outputName = (try? AudioHardware.name(of: AudioHardware.defaultOutput())) ?? "No output device"
    }

    private func routeChanged() {
        if isRunning { stop(message: "Output changed · press Enable to reconnect") }
        refreshOutput()
    }

    private func updateMeter() {
        guard isRunning else { return }
        let received = session.receivedFrames
        if received != lastReceived { lastCallback = Date(); lastReceived = received }
        level = max(session.peak, level * 0.8)
        hasSignal = level > 0.0001
        if Date().timeIntervalSince(lastCallback) > 8 {
            stop(message: "Capture stopped · original audio restored")
            error = "No audio buffers arrived. Allow Sound EQ in Screen & System Audio Recording, then enable it again. Some protected sources may not allow capture."
            return
        }
        status = hasSignal ? "Processing system audio" : "Listening for audio"
        if Date().timeIntervalSince(startedAt) > 10 && !hasSignal {
            status = "No signal · play something or check audio permission"
        }
    }
}
