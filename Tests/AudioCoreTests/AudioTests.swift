import XCTest
import AVFoundation
import AudioRing
@testable import AudioCore

final class AudioTests: XCTestCase {
    func testStereoInterleavedCaptureToPlanarOutput() throws {
        let ring = try XCTUnwrap(eq_ring_create(64, 4))
        defer { eq_ring_destroy(ring) }
        let inputFormat = try XCTUnwrap(AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 48_000, channels: 2, interleaved: true))
        let input = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: 8))
        input.frameLength = 8
        let samples = try XCTUnwrap(input.floatChannelData)[0]
        for i in 0..<8 { samples[i * 2] = Float(i) / 10; samples[i * 2 + 1] = -Float(i) / 10 }
        eq_ring_write(ring, input.audioBufferList)
        let output = makeBuffer(frames: 8)
        eq_ring_read(ring, output.mutableAudioBufferList, 8)
        for i in 0..<8 {
            XCTAssertEqual(output.floatChannelData![0][i], Float(i) / 10)
            XCTAssertEqual(output.floatChannelData![1][i], -Float(i) / 10)
        }
        XCTAssertEqual(eq_ring_received(ring), 8)
        XCTAssertEqual(eq_ring_dropped(ring), 0)
    }

    func testPrefillUnderrunAndRecovery() throws {
        let ring = try XCTUnwrap(eq_ring_create(64, 8))
        defer { eq_ring_destroy(ring) }
        let input = makeBuffer(frames: 4, value: 0.3)
        let output = makeBuffer(frames: 8, value: 0.9)
        eq_ring_write(ring, input.audioBufferList)
        eq_ring_read(ring, output.mutableAudioBufferList, 8)
        XCTAssertEqual(output.floatChannelData![0][0], 0, "Do not start before prefill")
        eq_ring_write(ring, input.audioBufferList)
        eq_ring_read(ring, output.mutableAudioBufferList, 8)
        XCTAssertEqual(output.floatChannelData![0][7], 0.3)
        eq_ring_read(ring, output.mutableAudioBufferList, 8)
        XCTAssertEqual(output.floatChannelData![0][0], 0, "Underrun must output silence, not stale memory")
        XCTAssertEqual(eq_ring_underruns(ring), 1)
        eq_ring_write(ring, makeBuffer(frames: 8, value: 0.7).audioBufferList)
        eq_ring_read(ring, output.mutableAudioBufferList, 8)
        XCTAssertEqual(output.floatChannelData![1][7], 0.7)
    }

    func testOverflowIsBoundedAndNonFiniteInputIsSilenced() throws {
        let ring = try XCTUnwrap(eq_ring_create(16, 4))
        defer { eq_ring_destroy(ring) }
        let input = makeBuffer(frames: 32, value: 0.2)
        eq_ring_write(ring, input.audioBufferList)
        XCTAssertEqual(eq_ring_dropped(ring), 16)
        let output = makeBuffer(frames: 16)
        eq_ring_read(ring, output.mutableAudioBufferList, 16)
        XCTAssertEqual(output.floatChannelData![0][15], 0.2)
        let invalid = makeBuffer(frames: 16, value: .nan)
        invalid.floatChannelData![1][0] = .infinity
        eq_ring_write(ring, invalid.audioBufferList)
        eq_ring_read(ring, output.mutableAudioBufferList, 16)
        for channel in 0..<2 { for i in 0..<16 { XCTAssertEqual(output.floatChannelData![channel][i], 0) } }
    }

    func testMuffleAttenuatesTreble() throws {
        let clean = try render(settings: .init(muffle: 0, space: 0, pitch: 0, output: 1), frequency: 6_000)
        let dark = try render(settings: .init(muffle: 0.9, space: 0, pitch: 0, output: 1), frequency: 6_000)
        XCTAssertGreaterThan(rms(clean[48_000..<96_000]), 0.1)
        XCTAssertLessThan(rms(dark[48_000..<96_000]), rms(clean[48_000..<96_000]) * 0.1)
    }

    func testPitchLowersFrequencyWithoutChangingRenderDuration() throws {
        let output = try render(settings: .init(muffle: 0, space: 0, pitch: -7, output: 1), frequency: 440)
        let tail = Array(output[48_000..<96_000])
        let crossings = zip(tail, tail.dropFirst()).filter { $0 < 0 && $1 >= 0 }.count
        let expected = 440 * pow(2, -7.0 / 12)
        XCTAssertEqual(Double(crossings), expected, accuracy: 3)
        XCTAssertEqual(output.count, 144_000)
        XCTAssertTrue(output.allSatisfy(\.isFinite))
    }

    func testReverbHasTailAfterSourceStops() throws {
        let dry = try render(settings: .init(muffle: 0, space: 0, pitch: 0, output: 1), frequency: 440, signalFrames: 12_000)
        let wet = try render(settings: .init(muffle: 0, space: 0.8, pitch: 0, output: 1), frequency: 440, signalFrames: 12_000)
        XCTAssertLessThan(rms(dry[24_000..<48_000]), 0.00001)
        XCTAssertGreaterThan(rms(wet[24_000..<48_000]), 0.0001)
    }

    func testMuffleKeepsKickWeightWithoutDeepBassShelf() throws {
        let clean = EffectSettings(muffle: 0, space: 0, pitch: 0, output: 1)
        let muffled = EffectSettings(muffle: 0.85, space: 0, pitch: 0, output: 1)
        let dryKick = try render(settings: clean, frequency: 80)
        let weightedKick = try render(settings: muffled, frequency: 80)
        let drySub = try render(settings: clean, frequency: 30)
        let neutralSub = try render(settings: muffled, frequency: 30)
        let kickRatio = rms(weightedKick[48_000..<96_000]) / rms(dryKick[48_000..<96_000])
        XCTAssertGreaterThan(kickRatio, 1.12)
        XCTAssertLessThan(kickRatio, 1.3, "Keep the kick lift modest")
        XCTAssertEqual(rms(neutralSub[48_000..<96_000]) / rms(drySub[48_000..<96_000]), 1, accuracy: 0.05)
    }

    func testSpacePreservesDirectAttackAndAddsDistantStereoTail() throws {
        let dry = try render(settings: .init(muffle: 0.8, space: 0, pitch: 0, output: 1), frequency: 800, signalFrames: 480)
        let wet = try renderStereo(settings: .init(muffle: 0.8, space: 1, pitch: 0, output: 1), frequency: 800, signalFrames: 480)
        let attackError = zip(dry.prefix(1_440), wet[0].prefix(1_440)).map { abs($0 - $1) }.max()!
        XCTAssertLessThan(attackError, 0.0001, "Space must not soften or delay the direct attack")
        XCTAssertGreaterThan(rms(wet[0][24_000..<72_000]), 0.00001, "Reflections should remain well after the source stops")
        let stereoDifference = zip(wet[0][12_000..<72_000], wet[1][12_000..<72_000]).map { $0 - $1 }
        XCTAssertGreaterThan(rms(stereoDifference[...]), 0.00001, "Ambience should spread beyond the mono source")
    }

    func testBoostedBassAndSpaceRemainFiniteAndPeakLimited() throws {
        let output = try renderStereo(settings: .init(muffle: 1, space: 1, pitch: 0, output: 1), frequency: 65, amplitude: 0.95)
        for channel in output {
            XCTAssertTrue(channel.allSatisfy(\.isFinite))
            XCTAssertLessThanOrEqual(channel.map { abs($0) }.max()!, 1.01)
        }
    }

    private func makeBuffer(frames: UInt32, value: Float = 0) -> AVAudioPCMBuffer {
        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
        buffer.frameLength = frames
        for channel in 0..<2 { for i in 0..<Int(frames) { buffer.floatChannelData![channel][i] = value } }
        return buffer
    }

    private func rms(_ samples: ArraySlice<Float>) -> Float {
        sqrt(samples.reduce(0) { $0 + $1 * $1 } / Float(samples.count))
    }

    private func render(settings: EffectSettings, frequency: Double, signalFrames: Int = 144_000) throws -> [Float] {
        try renderStereo(settings: settings, frequency: frequency, signalFrames: signalFrames)[0]
    }

    private func renderStereo(settings: EffectSettings, frequency: Double, signalFrames: Int = 144_000, amplitude: Float = 0.2) throws -> [[Float]] {
        let input = makeBuffer(frames: 144_000)
        for i in 0..<min(signalFrames, 144_000) {
            let sample = Float(sin(2 * Double.pi * frequency * Double(i) / 48_000)) * amplitude
            input.floatChannelData![0][i] = sample; input.floatChannelData![1][i] = sample
        }
        let player = AVAudioPlayerNode()
        let chain = EffectsChain(source: player, format: input.format)
        chain.apply(settings)
        try chain.engine.enableManualRenderingMode(.offline, format: input.format, maximumFrameCount: 4_096)
        let buffer = AVAudioPCMBuffer(pcmFormat: input.format, frameCapacity: 4_096)!
        player.scheduleBuffer(input)
        try chain.engine.start()
        player.play()
        defer { chain.engine.stop() }
        var result: [[Float]] = [[], []]
        var attempts = 0
        while result[0].count < 144_000 && attempts < 200 {
            attempts += 1
            let count = AVAudioFrameCount(min(4_096, 144_000 - result[0].count))
            let status = try chain.engine.renderOffline(count, to: buffer)
            if status == .success {
                for channel in 0..<2 {
                    result[channel].append(contentsOf: UnsafeBufferPointer(start: buffer.floatChannelData![channel], count: Int(buffer.frameLength)))
                }
            } else if status != .cannotDoInCurrentContext {
                throw AudioFailure("Offline rendering failed: \(status.rawValue)")
            }
        }
        guard result[0].count == 144_000 else { throw AudioFailure("Offline render did not complete") }
        return result
    }
}
