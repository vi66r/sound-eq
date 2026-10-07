import AVFoundation
import CoreAudio
import AudioRing

public struct AudioFailure: LocalizedError {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

private func checked(_ result: OSStatus, _ action: String) throws {
    guard result == noErr else {
        throw AudioFailure("\(action) failed (\(result)). Check System Settings → Privacy & Security → Screen & System Audio Recording, then try again.")
    }
}

public enum AudioHardware {
    public static func defaultOutput() throws -> AudioObjectID {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device = AudioObjectID(0)
        var size = UInt32(MemoryLayout.size(ofValue: device))
        try checked(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device), "Find output")
        guard device != kAudioObjectUnknown else { throw AudioFailure("Connect an audio output device first.") }
        return device
    }

    public static func name(of device: AudioObjectID) -> String {
        var address = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: CFString = "Default output" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &value) {
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, $0)
        }
        guard status == noErr else { return "Default output" }
        return value as String
    }
}

/// Owned by the main thread. The two audio callbacks only access the C SPSC ring.
@available(macOS 14.2, *)
public final class SystemAudioSession {
    private var tap = AudioObjectID(kAudioObjectUnknown)
    private var device = AudioObjectID(kAudioObjectUnknown)
    private var ioProc: AudioDeviceIOProcID?
    private var ring: OpaquePointer?
    private var chain: EffectsChain?
    public private(set) var sampleRate = 0.0

    public init() {}
    deinit { stop() }

    public var peak: Float { ring.map(eq_ring_peak) ?? 0 }
    public var receivedFrames: UInt64 { ring.map(eq_ring_received) ?? 0 }
    public var droppedFrames: UInt64 { ring.map(eq_ring_dropped) ?? 0 }
    public var underruns: UInt64 { ring.map(eq_ring_underruns) ?? 0 }

    public func start(settings: EffectSettings) throws {
        stop()
        do {
            // Instantiate the output unit before resolving our process object.
            // Never create a global tap without excluding our own playback.
            let registrationEngine = AVAudioEngine()
            _ = registrationEngine.outputNode
            var pid = getpid()
            var process = AudioObjectID(kAudioObjectUnknown)
            var processSize = UInt32(MemoryLayout<AudioObjectID>.size)
            var processAddress = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            try checked(AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &processAddress,
                UInt32(MemoryLayout<pid_t>.size), &pid, &processSize, &process), "Identify audio process")
            guard process != kAudioObjectUnknown else { throw AudioFailure("Could not identify Sound EQ’s output. Capture was left off to prevent feedback.") }

            let description = CATapDescription(stereoGlobalTapButExcludeProcesses: [process])
            description.name = "Sound EQ · system audio"
            description.uuid = UUID()
            description.isPrivate = true
            description.muteBehavior = .mutedWhenTapped
            try checked(AudioHardwareCreateProcessTap(description, &tap), "Create system audio tap")

            var stream = AudioStreamBasicDescription()
            var streamSize = UInt32(MemoryLayout<AudioStreamBasicDescription>.size)
            var formatAddress = AudioObjectPropertyAddress(mSelector: kAudioTapPropertyFormat,
                mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            try checked(AudioObjectGetPropertyData(tap, &formatAddress, 0, nil, &streamSize, &stream), "Read capture format")
            guard stream.mFormatID == kAudioFormatLinearPCM,
                  stream.mFormatFlags & kAudioFormatFlagIsFloat != 0,
                  stream.mBitsPerChannel == 32, stream.mChannelsPerFrame == 2,
                  stream.mSampleRate >= 8_000,
                  let format = AVAudioFormat(standardFormatWithSampleRate: stream.mSampleRate, channels: 2)
            else { throw AudioFailure("This output’s capture format is unsupported. Try the built-in output or another stereo device.") }
            sampleRate = stream.mSampleRate
            guard let ring = eq_ring_create(UInt32(sampleRate * 0.25), UInt32(sampleRate * 0.025)) else {
                throw AudioFailure("Could not allocate the audio buffer.")
            }
            self.ring = ring
            let source = AVAudioSourceNode(format: format) { _, _, frameCount, buffers in
                eq_ring_read(ring, buffers, frameCount)
                return noErr
            }
            let chain = EffectsChain(source: source, format: format)
            self.chain = chain
            chain.apply(settings)

            let aggregate: [String: Any] = [
                kAudioAggregateDeviceNameKey: "Sound EQ Capture",
                kAudioAggregateDeviceUIDKey: "network.rafi.sound-eq.capture.\(UUID().uuidString)",
                kAudioAggregateDeviceIsPrivateKey: true,
                kAudioAggregateDeviceTapAutoStartKey: false,
                kAudioAggregateDeviceTapListKey: [[
                    kAudioSubTapUIDKey: description.uuid.uuidString,
                    kAudioSubTapDriftCompensationKey: true
                ]]
            ]
            try checked(AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device), "Create audio route")
            try checked(AudioDeviceCreateIOProcIDWithBlock(&ioProc, device, nil) { _, input, _, _, _ in
                eq_ring_write(ring, input)
            }, "Prepare audio capture")
            // Only mute the original after our output has successfully started.
            chain.engine.prepare()
            try chain.engine.start()
            try checked(AudioDeviceStart(device, ioProc), "Start system audio capture")
            withExtendedLifetime(registrationEngine) {}
        } catch {
            stop()
            throw error
        }
    }

    public func apply(_ settings: EffectSettings) { chain?.apply(settings) }

    public func stop() {
        // Restore original audio first; then stop both callbacks before freeing their ring.
        if device != kAudioObjectUnknown {
            if let ioProc {
                AudioDeviceStop(device, ioProc)
                AudioDeviceDestroyIOProcID(device, ioProc)
            }
            AudioHardwareDestroyAggregateDevice(device)
        }
        ioProc = nil; device = AudioObjectID(kAudioObjectUnknown)
        if tap != kAudioObjectUnknown { AudioHardwareDestroyProcessTap(tap) }
        tap = AudioObjectID(kAudioObjectUnknown)
        chain?.engine.stop()
        chain = nil
        if let ring { eq_ring_destroy(ring) }
        ring = nil
    }
}
