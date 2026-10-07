# Sound EQ

A native macOS app for muffled, spacious, lower-pitched system audio. Works with audio from other apps, without installing a virtual audio driver. Audio stays in memory on your Mac; nothing is recorded or uploaded.

[Download Sound EQ](https://apps.rafi.network/sound-eq/) · macOS 14.4+ · Apple Silicon and Intel · MIT licensed

## Controls

- **Muffle** softens the highs and adds a gentle 80 Hz kick lift, without a deep-bass shelf.
- **Space** adds delayed stereo ambience while preserving the direct attack.
- **Pitch** lowers pitch by up to seven semitones at unchanged playback speed.
- **Output** controls the processed level. **Bypass** restores original audio.

Settings persist, but processing starts disabled on launch. Allow Sound EQ in System Settings → Privacy & Security → Screen & System Audio Recording when prompted.

## Build and test

Requires macOS 14.4+ and Xcode 16 or newer (Swift 6 tools). No third-party dependencies.

```sh
swift test
# Quit any running Sound EQ before replacing its executable.
bash scripts/build-app.sh
open 'dist/Sound EQ.app'
```

Local builds are ad-hoc signed and may need audio capture permission again after rebuilding. The downloadable release is separately Developer ID signed and notarized.

For Xcode, open `SoundEQ.xcodeproj`, select your own signing team and a unique bundle identifier. The archive/export scripts accept `DEVELOPMENT_TEAM` from your environment and use your Xcode account; no credentials are included.

## Audio path

Core Audio process tap → preallocated stereo ring → pitch → low-pass/kick EQ → direct signal plus filtered, pre-delayed reverb → peak limiter → output.

The tap excludes this process and mutes original audio only while it is read. Bypass, quit and failed startup release capture. Changing audio devices or sleeping stops processing; enable again to reconnect. This is a listening effect, not a low-latency monitoring tool. No per-app selection, multichannel processing or automatic updates yet.

Offline tests cover tone response, attack preservation, stereo reverb tails, pitch, limiting, and ring-buffer edge cases. Bluetooth/USB routing and long sessions still benefit from hands-on testing.

## Contributing

Issues and pull requests are welcome. Include your macOS version, output device and steps to reproduce audio issues. Run `swift test` and a release build before submitting changes. Do not commit signing credentials, provisioning profiles or recordings containing private audio.

## License

[MIT](LICENSE). The included app artwork was generated with an image-generation tool; its prompt is in `Resources/Brand/generation-prompt.txt`.
