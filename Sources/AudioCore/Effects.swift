import AVFoundation

public struct EffectSettings: Codable, Equatable {
    public var muffle: Float
    public var space: Float
    public var pitch: Float
    public var output: Float

    public init(muffle: Float = 0.48, space: Float = 0.24, pitch: Float = -2, output: Float = 0.75) {
        self.muffle = muffle; self.space = space; self.pitch = pitch; self.output = output
    }

    public var cutoff: Float { 18_000 * pow(650 / 18_000, min(1, max(0, muffle))) }
    public static let presets: [(name: String, settings: EffectSettings)] = [
        ("After hours", .init()),
        ("Next room", .init(muffle: 0.80, space: 0.12, pitch: 0)),
        ("Daydream", .init(muffle: 0.30, space: 0.45, pitch: -3)),
        ("Clean", .init(muffle: 0, space: 0, pitch: 0))
    ]
}

/// All graph changes happen off the audio callbacks. Apple audio units handle parameter updates.
public final class EffectsChain {
    public let engine = AVAudioEngine()
    private let pitch = AVAudioUnitTimePitch()
    private let reverb = AVAudioUnitReverb()
    private let tone = AVAudioUnitEQ(numberOfBands: 2)
    private let ambienceTone = AVAudioUnitEQ(numberOfBands: 1)
    private let preDelay = AVAudioUnitDelay()
    private let ambience = AVAudioMixerNode()
    private let blend = AVAudioMixerNode()
    private let limiter = AVAudioUnitEffect(audioComponentDescription: AudioComponentDescription(
        componentType: kAudioUnitType_Effect,
        componentSubType: kAudioUnitSubType_PeakLimiter,
        componentManufacturer: kAudioUnitManufacturer_Apple,
        componentFlags: 0, componentFlagsMask: 0
    ))

    public init(source: AVAudioNode, format: AVAudioFormat) {
        for node in [source, pitch, reverb, tone, ambienceTone, preDelay, ambience, blend, limiter] { engine.attach(node) }
        engine.connect(source, to: pitch, format: format)
        engine.connect(pitch, to: tone, format: format)
        // Keep direct bass/transients intact; only the ambience takes the long route.
        engine.connect(tone, to: [AVAudioConnectionPoint(node: blend, bus: 0),
                                  AVAudioConnectionPoint(node: ambienceTone, bus: 0)], fromBus: 0, format: format)
        engine.connect(ambienceTone, to: preDelay, format: format)
        engine.connect(preDelay, to: reverb, format: format)
        engine.connect(reverb, to: ambience, format: format)
        engine.connect(ambience, to: blend, fromBus: 0, toBus: 1, format: format)
        engine.connect(blend, to: limiter, format: format)
        engine.connect(limiter, to: engine.mainMixerNode, format: format)
        pitch.rate = 1
        pitch.overlap = 8
        reverb.loadFactoryPreset(.largeHall2)
        reverb.wetDryMix = 100
        preDelay.wetDryMix = 100
        preDelay.feedback = 0
        ambienceTone.bands[0].filterType = .highPass
        ambienceTone.bands[0].frequency = 180
        ambienceTone.bands[0].bypass = false
        tone.bands[0].filterType = .lowPass
        tone.bands[0].bandwidth = 0.5
        tone.bands[1].filterType = .parametric
        tone.bands[1].frequency = 80
        tone.bands[1].bandwidth = 1.2
        apply(.init())
    }

    public func apply(_ settings: EffectSettings) {
        pitch.pitch = min(0, max(-7, settings.pitch)) * 100
        pitch.bypass = abs(settings.pitch) < 0.01
        let muffle = min(1, max(0, settings.muffle))
        let space = min(1, max(0, settings.space))
        // Space adds distant reflections, rather than replacing the direct attack.
        // A silent return at zero also prevents old tails leaking into Clean.
        ambience.outputVolume = space < 0.001 ? 0 : space * 0.8
        preDelay.delayTime = 0.035 + Double(space) * 0.060
        preDelay.lowPassCutoff = 5_000
        // A small kick-centered lift without a shelf raising the whole low end.
        tone.bands[1].gain = 2 * muffle
        tone.bands[1].bypass = muffle < 0.001
        tone.bands[0].frequency = min(settings.cutoff, Float(tone.inputFormat(forBus: 0).sampleRate * 0.45))
        tone.bands[0].bypass = settings.muffle < 0.001
        engine.mainMixerNode.outputVolume = min(1, max(0, settings.output))
    }
}
