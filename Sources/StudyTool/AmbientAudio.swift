import SwiftUI
import AVFoundation

enum AmbientSound: String, CaseIterable, Identifiable {
    case silence, rain, brownNoise, roomTone
    var id: String { rawValue }
    var title: String { switch self { case .silence: "Silence"; case .rain: "Rain"; case .brownNoise: "Brown noise"; case .roomTone: "Room tone" } }
    var icon: String { switch self { case .silence: "speaker.slash"; case .rain: "cloud.rain"; case .brownNoise: "waveform"; case .roomTone: "wind" } }
    var colors: [Color] {
        switch self {
        case .silence: [.gray.opacity(0.2), .gray.opacity(0.45)]
        case .rain: [Color(red: 0.2, green: 0.38, blue: 0.48), Color(red: 0.48, green: 0.69, blue: 0.72)]
        case .brownNoise: [Color(red: 0.29, green: 0.22, blue: 0.19), Color(red: 0.69, green: 0.51, blue: 0.36)]
        case .roomTone: [Color(red: 0.28, green: 0.36, blue: 0.3), Color(red: 0.65, green: 0.7, blue: 0.55)]
        }
    }
}

@MainActor final class AmbientAudioController: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published private(set) var playing = false
    @Published private(set) var preparing = false
    @Published var error: String?
    private let defaults: UserDefaults
    private var player: AVAudioPlayer?
    private var preparation: Task<Void, Never>?
    private var generation = UUID()
    private var timerWasRunning = false
    init(defaults: UserDefaults = .standard) { self.defaults = defaults }
    var selected: AmbientSound { AmbientSound(rawValue: defaults.string(forKey: "ambientSound") ?? "silence") ?? .silence }
    var volume: Double { defaults.object(forKey: "ambientVolume") == nil ? 0.25 : min(1, max(0, defaults.double(forKey: "ambientVolume"))) }
    func updateVolume() { player?.volume = Float(volume) }
    func selectionChanged() { if playing || preparing { play() } }
    func timerChanged(running: Bool, focus: Bool, completed: Bool) {
        let stopAtEnd = defaults.object(forKey: "ambientStopAtEnd") as? Bool != false
        if running && !timerWasRunning && focus && !playing && !preparing { play() }
        if (!running && !completed) || (stopAtEnd && (completed || !focus)) { stop() }
        timerWasRunning = running
    }
    func play() {
        stop()
        let sound = selected
        guard sound != .silence else { return }
        let token = UUID(); generation = token; preparing = true
        preparation = Task { [weak self] in
            // Original synthesized textures need no downloads, bundled recordings, or licenses.
            let data = await Task.detached(priority: .userInitiated) { Self.wave(sound) }.value
            guard let self, !Task.isCancelled, self.generation == token else { return }
            do {
                let player = try AVAudioPlayer(data: data, fileTypeHint: AVFileType.wav.rawValue)
                player.delegate = self; player.numberOfLoops = -1; player.volume = Float(self.volume)
                guard player.prepareToPlay(), player.play() else { throw WorkspaceFailure.invalid("The audio device could not begin playback.") }
                self.player = player; self.playing = true; self.preparing = false
            } catch { self.preparing = false; self.error = "Sound could not play. \(error.localizedDescription)" }
        }
    }
    func stop() { generation = UUID(); preparation?.cancel(); preparation = nil; player?.stop(); player = nil; playing = false; preparing = false }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) {
        let message = error?.localizedDescription ?? "The sound could not be decoded."
        Task { @MainActor [weak self] in self?.stop(); self?.error = message }
    }
    nonisolated static func wave(_ sound: AmbientSound) -> Data {
        let rate = 22050, count = rate * 16, fade = rate / 4
        var seed: UInt64 = 741923
        var low = 0.0
        var softer = 0.0
        var samples = [Double](); samples.reserveCapacity(count + fade)
        for index in 0..<(count + fade) {
            seed = seed &* 6364136223846793005 &+ 1
            let white = Double(seed >> 32) / Double(UInt32.max) * 2 - 1
            low = 0.985 * low + 0.015 * white
            softer = 0.92 * softer + 0.08 * white
            let t = Double(index) / Double(rate)
            let sample: Double
            switch sound {
            case .rain: sample = softer * 0.9 + white * 0.16 * (0.8 + 0.2 * sin(t * 0.7))
            case .brownNoise: sample = low * 2.2
            case .roomTone: sample = low * 0.65 + softer * 0.18 + sin(t * 2 * .pi * 60) * 0.015
            case .silence: sample = 0
            }
            samples.append(sample)
        }
        var pcm = Data(capacity: count * 2)
        for index in 0..<count {
            let value: Double
            if index < fade {
                let mix = Double(index) / Double(fade)
                value = samples[count + index] * (1 - mix) + samples[index] * mix
            } else { value = samples[index] }
            var sample = Int16(max(-1, min(1, value)) * 28000).littleEndian
            withUnsafeBytes(of: &sample) { pcm.append(contentsOf: $0) }
        }
        var data = Data()
        func text(_ value: String) { data.append(contentsOf: value.utf8) }
        func u32(_ value: UInt32) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        func u16(_ value: UInt16) { var n = value.littleEndian; withUnsafeBytes(of: &n) { data.append(contentsOf: $0) } }
        text("RIFF"); u32(UInt32(pcm.count + 36)); text("WAVEfmt "); u32(16); u16(1); u16(1)
        u32(UInt32(rate)); u32(UInt32(rate * 2)); u16(2); u16(16); text("data"); u32(UInt32(pcm.count)); data.append(pcm)
        return data
    }
}

struct AmbientPicker: View {
    @EnvironmentObject private var audio: AmbientAudioController
    @AppStorage("ambientSound") private var selected: AmbientSound = .silence
    @AppStorage("ambientVolume") private var volume = 0.25
    @AppStorage("ambientStopAtEnd") private var stopAtEnd = true
    @AppStorage("theme") private var theme: StudyTheme = .graphite
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ForEach(AmbientSound.allCases) { sound in
                    Button { selected = sound } label: {
                        VStack(spacing: 8) {
                            Image(systemName: sound.icon).font(.title3).foregroundStyle(.white)
                                .frame(maxWidth: .infinity).frame(height: 48)
                                .background(LinearGradient(colors: sound.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
                                .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected == sound ? theme.accent : .clear, lineWidth: 2))
                            Text(sound.title).font(.caption).lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }.buttonStyle(.plain).accessibilityLabel("\(sound.title) sound").accessibilityAddTraits(selected == sound ? .isSelected : [])
                }
            }
            HStack {
                Image(systemName: "speaker.wave.1")
                Slider(value: $volume, in: 0...1).accessibilityLabel("Ambient volume")
                Button(audio.playing || audio.preparing ? "Stop sound" : "Preview") {
                    if audio.playing || audio.preparing { audio.stop() } else { audio.play() }
                }.disabled(selected == .silence)
            }
            Toggle("Stop sound when focus ends", isOn: $stopAtEnd).font(.caption)
            Text("Local sound textures · plays with your focus timer · silence by default").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: selected) { _, _ in audio.selectionChanged() }
        .onChange(of: volume) { _, _ in audio.updateVolume() }
        .alert("Sound needs attention", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) { Button("OK") { audio.error = nil } } message: { Text(audio.error ?? "") }
    }
}
