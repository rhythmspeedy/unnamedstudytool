import SwiftUI
import AVFoundation

enum AmbientSound: String, CaseIterable, Identifiable {
    case silence
    case whiteNoise, pinkNoise, brownNoise
    case rain, forestRain, deepOcean, distantThunder, fireplace
    case roomTone, deskFan, quietCafe, libraryRoom, nightTrain, airplaneCabin

    enum Category: String, CaseIterable, Identifiable {
        case quiet = "Quiet"
        case noiseColors = "Noise colors"
        case nature = "Weather & nature"
        case places = "Places & motion"
        var id: String { rawValue }
    }

    var id: String { rawValue }
    var category: Category {
        switch self {
        case .silence: .quiet
        case .whiteNoise, .pinkNoise, .brownNoise: .noiseColors
        case .rain, .forestRain, .deepOcean, .distantThunder, .fireplace: .nature
        case .roomTone, .deskFan, .quietCafe, .libraryRoom, .nightTrain, .airplaneCabin: .places
        }
    }
    var title: String {
        switch self {
        case .silence: "Silence"
        case .whiteNoise: "White noise"
        case .pinkNoise: "Pink noise"
        case .brownNoise: "Brown noise"
        case .rain: "Rain"
        case .forestRain: "Forest rain"
        case .deepOcean: "Deep ocean"
        case .distantThunder: "Distant thunder"
        case .fireplace: "Fireplace"
        case .roomTone: "Room tone"
        case .deskFan: "Desk fan"
        case .quietCafe: "Quiet café"
        case .libraryRoom: "Library room"
        case .nightTrain: "Night train"
        case .airplaneCabin: "Airplane cabin"
        }
    }
    var icon: String {
        switch self {
        case .silence: "speaker.slash"
        case .whiteNoise: "waveform"
        case .pinkNoise: "waveform.path"
        case .brownNoise: "waveform.path.ecg"
        case .rain: "cloud.rain"
        case .forestRain: "tree"
        case .deepOcean: "water.waves"
        case .distantThunder: "cloud.bolt.rain"
        case .fireplace: "flame"
        case .roomTone: "wind"
        case .deskFan: "fan"
        case .quietCafe: "cup.and.saucer"
        case .libraryRoom: "books.vertical"
        case .nightTrain: "tram.fill"
        case .airplaneCabin: "airplane"
        }
    }
    var detail: String {
        switch self {
        case .silence: "No background audio."
        case .whiteNoise: "A crisp, even mask across the frequency range."
        case .pinkNoise: "Balanced noise with a softer high end."
        case .brownNoise: "A deep, low-weighted wash."
        case .rain: "Steady rain without sharp drops."
        case .forestRain: "Softer rain moving through a leafy canopy."
        case .deepOcean: "Slow, low swells with a distant wash."
        case .distantThunder: "Gentle rain with an occasional low rumble."
        case .fireplace: "Warm room tone with restrained crackling."
        case .roomTone: "A nearly still indoor air texture."
        case .deskFan: "Consistent airflow and a quiet rotating hum."
        case .quietCafe: "Layered, indistinct conversation with a soft room hush."
        case .libraryRoom: "Subtle room air, pencil texture, and page turns."
        case .nightTrain: "Low rail rhythm and a muted carriage hum."
        case .airplaneCabin: "Smooth engine and cabin airflow."
        }
    }
    var colors: [Color] {
        switch self {
        case .silence: [.gray.opacity(0.2), .gray.opacity(0.45)]
        case .whiteNoise: [Color(red: 0.46, green: 0.49, blue: 0.53), Color(red: 0.82, green: 0.84, blue: 0.85)]
        case .pinkNoise: [Color(red: 0.55, green: 0.31, blue: 0.36), Color(red: 0.86, green: 0.58, blue: 0.61)]
        case .brownNoise: [Color(red: 0.29, green: 0.22, blue: 0.19), Color(red: 0.69, green: 0.51, blue: 0.36)]
        case .rain: [Color(red: 0.2, green: 0.38, blue: 0.48), Color(red: 0.48, green: 0.69, blue: 0.72)]
        case .forestRain: [Color(red: 0.12, green: 0.29, blue: 0.22), Color(red: 0.42, green: 0.63, blue: 0.43)]
        case .deepOcean: [Color(red: 0.08, green: 0.22, blue: 0.33), Color(red: 0.23, green: 0.53, blue: 0.65)]
        case .distantThunder: [Color(red: 0.16, green: 0.19, blue: 0.27), Color(red: 0.4, green: 0.46, blue: 0.57)]
        case .fireplace: [Color(red: 0.41, green: 0.16, blue: 0.08), Color(red: 0.86, green: 0.49, blue: 0.18)]
        case .roomTone: [Color(red: 0.28, green: 0.36, blue: 0.3), Color(red: 0.65, green: 0.7, blue: 0.55)]
        case .deskFan: [Color(red: 0.25, green: 0.36, blue: 0.39), Color(red: 0.58, green: 0.72, blue: 0.71)]
        case .quietCafe: [Color(red: 0.34, green: 0.2, blue: 0.13), Color(red: 0.72, green: 0.48, blue: 0.29)]
        case .libraryRoom: [Color(red: 0.3, green: 0.22, blue: 0.16), Color(red: 0.65, green: 0.55, blue: 0.4)]
        case .nightTrain: [Color(red: 0.11, green: 0.18, blue: 0.24), Color(red: 0.35, green: 0.49, blue: 0.58)]
        case .airplaneCabin: [Color(red: 0.22, green: 0.3, blue: 0.4), Color(red: 0.53, green: 0.65, blue: 0.75)]
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
    private var cache: [AmbientSound: Data] = [:]
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
            guard let self else { return }
            // Every texture is generated locally, so there are no bundled recordings or licenses.
            let data: Data
            if let cached = self.cache[sound] { data = cached }
            else {
                data = await Task.detached(priority: .userInitiated) { Self.wave(sound) }.value
                self.cache[sound] = data
            }
            guard !Task.isCancelled, self.generation == token else { return }
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
        let rate = 22050, count = rate * 24, fade = rate / 3
        var seed = sound.rawValue.utf8.reduce(UInt64(741923)) { ($0 &* 1099511628211) ^ UInt64($1) }
        var low = 0.0
        var softer = 0.0
        var pink0 = 0.0, pink1 = 0.0, pink2 = 0.0, pink3 = 0.0, pink4 = 0.0, pink5 = 0.0, pink6 = 0.0
        var crackle = 0.0
        var samples = [Double](); samples.reserveCapacity(count + fade)
        func noise() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 32) / Double(UInt32.max) * 2 - 1
        }
        func distantVoice(_ time: Double, pitch: Double, phraseRate: Double, syllableRate: Double, phase: Double) -> Double {
            // Several softly gated harmonic voices suggest conversation without forming words.
            let phraseWave = sin(time * 2 * .pi * phraseRate + phase + sin(time * 0.19 + phase) * 0.5)
            let phrase = pow(max(0, phraseWave + 0.28) / 1.28, 1.35)
            let syllableWave = sin(time * 2 * .pi * syllableRate + phase + sin(time * 0.73 + phase) * 0.65)
            let syllable = 0.32 + 0.68 * pow(max(0, syllableWave + 0.18) / 1.18, 0.7)
            let intonation = 1 + 0.035 * sin(time * 2 * .pi * (phraseRate * 0.47) + phase)
            let fundamental = pitch * intonation
            let voiced = sin(time * 2 * .pi * fundamental + phase)
                + 0.48 * sin(time * 2 * .pi * fundamental * 2.02 + phase * 0.7)
                + 0.22 * sin(time * 2 * .pi * fundamental * 3.01 + phase * 1.3)
            let vowelColor = 0.32 * sin(time * 2 * .pi * (520 + pitch * 0.22) + phase)
                + 0.18 * sin(time * 2 * .pi * (930 + pitch * 0.31) + phase * 0.4)
                + 0.08 * sin(time * 2 * .pi * (1_650 + pitch * 0.17) + phase * 1.7)
            return phrase * syllable * (voiced * 0.15 + vowelColor * 0.12)
        }
        for index in 0..<(count + fade) {
            let white = noise(), impulse = noise()
            low = 0.992 * low + 0.008 * white
            softer = 0.92 * softer + 0.08 * white
            pink0 = 0.99886 * pink0 + white * 0.0555179
            pink1 = 0.99332 * pink1 + white * 0.0750759
            pink2 = 0.969 * pink2 + white * 0.153852
            pink3 = 0.8665 * pink3 + white * 0.3104856
            pink4 = 0.55 * pink4 + white * 0.5329522
            pink5 = -0.7616 * pink5 - white * 0.016898
            let pink = pink0 + pink1 + pink2 + pink3 + pink4 + pink5 + pink6 + white * 0.5362
            pink6 = white * 0.115926
            let t = Double(index) / Double(rate)
            let sample: Double
            switch sound {
            case .whiteNoise: sample = white * 0.35
            case .pinkNoise: sample = pink * 0.11
            case .brownNoise: sample = low * 2.6
            case .rain: sample = softer * 0.85 + white * 0.13 * (0.82 + 0.18 * sin(t * 0.7))
            case .forestRain:
                let canopy = 0.72 + 0.18 * sin(t * 0.41) + 0.1 * sin(t * 0.17)
                sample = softer * 0.62 + low * 0.8 + (white - softer) * 0.08 * canopy
            case .deepOcean:
                let swell = 0.62 + 0.25 * sin(t * 2 * .pi / 8.7) + 0.1 * sin(t * 2 * .pi / 3.9)
                sample = low * 2.4 * swell + softer * 0.08
            case .distantThunder:
                let delta = t - 10.5
                let rumble = delta >= 0 && delta < 7 ? exp(-delta / 2.4) * (low * 4.5 + sin(t * 2 * .pi * 34) * 0.1) : 0
                sample = softer * 0.42 + low * 0.65 + rumble
            case .fireplace:
                if impulse > 0.99955 { crackle = 0.7 + (impulse - 0.99955) * 650 }
                crackle *= 0.91
                sample = low * 0.75 + softer * 0.08 + crackle * (white * 0.75 + 0.25)
            case .roomTone: sample = low * 0.65 + softer * 0.18 + sin(t * 2 * .pi * 60) * 0.015
            case .deskFan:
                let rotation = 0.88 + 0.12 * sin(t * 2 * .pi * 1.15)
                sample = softer * 0.28 * rotation + sin(t * 2 * .pi * 55) * 0.075 + sin(t * 2 * .pi * 110) * 0.025
            case .quietCafe:
                let conversation = distantVoice(t, pitch: 104, phraseRate: 0.19, syllableRate: 2.35, phase: 0.4)
                    + distantVoice(t, pitch: 137, phraseRate: 0.23, syllableRate: 2.82, phase: 2.2)
                    + distantVoice(t, pitch: 176, phraseRate: 0.17, syllableRate: 3.18, phase: 4.6)
                    + distantVoice(t, pitch: 121, phraseRate: 0.27, syllableRate: 2.58, phase: 5.5)
                let consonantHush = (white - softer) * 0.035 * (0.55 + 0.45 * abs(sin(t * 2 * .pi * 2.7)))
                sample = low * 0.34 + pink * 0.012 + conversation + consonantHush
            case .libraryRoom:
                let pageDelta = t.truncatingRemainder(dividingBy: 12) - 6.4
                let page = pageDelta >= 0 && pageDelta < 1.2 ? sin(pageDelta * .pi / 1.2) * (white - softer) * 0.4 : 0
                let pencil = (0.5 + 0.5 * sin(t * 2.3)) * (white - softer) * 0.045
                sample = low * 0.52 + softer * 0.08 + page + pencil
            case .nightTrain:
                let rail = pow(max(0, sin(t * 2 * .pi * 1.72)), 12) + pow(max(0, sin(t * 2 * .pi * 1.72 + 0.7)), 14)
                sample = low * 1.8 + softer * 0.12 + rail * (0.08 + softer * 0.28) + sin(t * 2 * .pi * 48) * 0.025
            case .airplaneCabin:
                let drift = 0.9 + 0.1 * sin(t * 0.23)
                sample = low * 1.7 + softer * 0.17 * drift + sin(t * 2 * .pi * 73) * 0.07 + sin(t * 2 * .pi * 146) * 0.025
            case .silence: sample = 0
            }
            samples.append(sample)
        }
        var loop = [Double](); loop.reserveCapacity(count)
        for index in 0..<count {
            let value: Double
            if index < fade {
                let mix = Double(index) / Double(fade)
                value = samples[count + index] * (1 - mix) + samples[index] * mix
            } else { value = samples[index] }
            loop.append(value)
        }
        let peak = loop.reduce(0) { max($0, abs($1)) }
        let rms = sqrt(loop.reduce(0) { $0 + $1 * $1 } / Double(max(1, loop.count)))
        let gain = min(peak > 0 ? 0.9 / peak : 1, rms > 0 ? 0.135 / rms : 1)
        var pcm = Data(capacity: count * 2)
        for value in loop {
            var sample = Int16(max(-1, min(1, value * gain)) * 32767).littleEndian
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
    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 12)]
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(AmbientSound.Category.allCases) { category in
                VStack(alignment: .leading, spacing: 9) {
                    Text(category.rawValue.uppercased()).font(.caption2.weight(.semibold)).tracking(1.4).foregroundStyle(.secondary)
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(AmbientSound.allCases.filter { $0.category == category }) { sound in
                            Button { selected = sound } label: {
                                VStack(spacing: 8) {
                                    Image(systemName: sound.icon).font(.title3).foregroundStyle(.white)
                                        .frame(maxWidth: .infinity).frame(height: 46)
                                        .background(LinearGradient(colors: sound.colors, startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 9))
                                        .overlay(RoundedRectangle(cornerRadius: 9).stroke(selected == sound ? theme.accent : .clear, lineWidth: 2))
                                    Text(sound.title).font(.caption).lineLimit(1).minimumScaleFactor(0.75)
                                }
                            }.buttonStyle(.plain).help(sound.detail).accessibilityLabel("\(sound.title) sound").accessibilityHint(sound.detail).accessibilityAddTraits(selected == sound ? .isSelected : [])
                        }
                    }
                }.accessibilityElement(children: .contain).accessibilityLabel(category.rawValue)
            }
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: selected.icon).frame(width: 18)
                VStack(alignment: .leading, spacing: 2) {
                    Text(selected.title).font(.callout.weight(.semibold))
                    Text(selected.detail).font(.caption).foregroundStyle(.secondary)
                }
            }.padding(10).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface.opacity(0.65), in: RoundedRectangle(cornerRadius: 9))
            HStack {
                Image(systemName: "speaker.wave.1")
                Slider(value: $volume, in: 0...1).accessibilityLabel("Ambient volume")
                Button(audio.playing || audio.preparing ? "Stop sound" : "Preview") {
                    if audio.playing || audio.preparing { audio.stop() } else { audio.play() }
                }.disabled(selected == .silence)
            }
            Toggle("Stop sound when focus ends", isOn: $stopAtEnd).font(.caption)
            Text("15 original local sound textures · no downloads or recordings · silence by default").font(.caption).foregroundStyle(.secondary)
        }
        .onChange(of: selected) { _, _ in audio.selectionChanged() }
        .onChange(of: volume) { _, _ in audio.updateVolume() }
        .alert("Sound needs attention", isPresented: Binding(get: { audio.error != nil }, set: { if !$0 { audio.error = nil } })) { Button("OK") { audio.error = nil } } message: { Text(audio.error ?? "") }
    }
}
