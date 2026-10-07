import SwiftUI
import AudioCore

private let frost = Color(red: 0.89, green: 0.96, blue: 1)
private let aqua = Color(red: 0.34, green: 0.89, blue: 0.96)
private let seafoam = Color(red: 0.42, green: 0.96, blue: 0.75)
private let secondary = Color(red: 0.58, green: 0.72, blue: 0.79)

struct MainView: View {
    @ObservedObject var model: AudioModel

    var body: some View {
        VStack(spacing: 20) {
            header
            presets
            toneDisplay
            HStack(spacing: 12) {
                EffectControl(title: "Muffle", subtitle: "Kick + low-pass", icon: "water.waves", accent: aqua,
                              value: $model.settings.muffle, range: 0...1,
                              display: "\(Int(model.settings.muffle * 100))", unit: "%", low: "Open", high: "Dark")
                EffectControl(title: "Space", subtitle: "Reverb", icon: "sparkles", accent: seafoam,
                              value: $model.settings.space, range: 0...1,
                              display: "\(Int(model.settings.space * 100))", unit: "%", low: "Dry", high: "Distant")
                EffectControl(title: "Pitch", subtitle: "Semitones", icon: "waveform", accent: Color(red: 0.61, green: 0.74, blue: 1),
                              value: $model.settings.pitch, range: -7...0,
                              display: String(format: "%.1f", model.settings.pitch), unit: "st", low: "−7 st", high: "Original")
            }
            output
            footer
        }
        .padding(.horizontal, 26).padding(.top, 8).padding(.bottom, 22)
        .frame(width: 720)
        .background {
            ZStack {
                LinearGradient(colors: [Color(red: 0.065, green: 0.16, blue: 0.23), Color(red: 0.025, green: 0.065, blue: 0.11)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [aqua.opacity(0.12), .clear], center: .topLeading, startRadius: 0, endRadius: 490)
                RadialGradient(colors: [seafoam.opacity(0.07), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 350)
                AeroRibbons().stroke(.white.opacity(0.045), lineWidth: 1)
            }.ignoresSafeArea()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable().interpolation(.high).scaledToFit().frame(width: 48, height: 48)
                .accessibilityHidden(true)
            (Text("Sound ").foregroundColor(frost) + Text("EQ").foregroundColor(aqua))
                .font(.system(size: 26, weight: .light)).tracking(-0.8)
                .shadow(color: aqua.opacity(0.25), radius: 12, y: 1)
            Spacer()
            Button { model.toggle() } label: {
                HStack(spacing: 8) {
                    Image(systemName: "power").font(.system(size: 13, weight: .semibold))
                    Text(model.isStarting ? "Connecting…" : model.isRunning ? "Bypass" : "Enable")
                        .font(.system(size: 12, weight: .semibold))
                }.frame(minWidth: 86).padding(.horizontal, 12).frame(height: 37)
            }
            .buttonStyle(AeroButtonStyle(selected: model.isRunning))
            .disabled(model.isStarting)
            .help("Enable processing or return to original audio (⌘B)")
        }
    }

    private var presets: some View {
        HStack(spacing: 3) {
            ForEach(EffectSettings.presets, id: \.name) { preset in
                Button { model.selectPreset(preset.name) } label: {
                    Text(preset.name).font(.system(size: 11, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: 31)
                }
                .buttonStyle(AeroButtonStyle(selected: model.selectedPreset == preset.name, compact: true))
                .accessibilityAddTraits(model.selectedPreset == preset.name ? .isSelected : [])
            }
        }
        .padding(4)
        .background(.black.opacity(0.24), in: Capsule())
        .overlay(Capsule().strokeBorder(.white.opacity(0.10), lineWidth: 0.75))
    }

    private var toneDisplay: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 17).fill(LinearGradient(
                colors: [Color(red: 0.02, green: 0.09, blue: 0.14), Color(red: 0.035, green: 0.15, blue: 0.20)], startPoint: .top, endPoint: .bottom))
            ResponseView(muffle: model.settings.muffle, space: model.settings.space, active: model.isRunning)
                .padding(.horizontal, 1)
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Label("Tone", systemImage: "waveform.path").font(.system(size: 11, weight: .medium)).foregroundStyle(secondary)
                    Spacer()
                    HStack(spacing: 5) {
                        Circle().fill(model.isRunning ? seafoam : secondary.opacity(0.6)).frame(width: 5, height: 5)
                        Text(model.isRunning ? "ACTIVE" : "BYPASSED").font(.system(size: 8, weight: .medium)).tracking(1.2)
                    }.foregroundStyle(model.isRunning ? seafoam : secondary)
                }
                Text(model.settings.muffle < 0.001 ? "Full range" : String(format: "%.2f kHz", model.settings.cutoff / 1_000))
                    .font(.system(size: 19, weight: .light, design: .rounded)).monospacedDigit().foregroundStyle(frost)
                Spacer()
                HStack {
                    Text("20 Hz"); Spacer(); Text("200"); Spacer(); Text("2k"); Spacer(); Text("20k")
                }.font(.system(size: 9, design: .monospaced)).foregroundStyle(secondary.opacity(0.8))
            }.padding(18)
            // Curved reflection across the top of the inset glass.
            GlassReflection().fill(LinearGradient(colors: [.white.opacity(0.075), .white.opacity(0.005)], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .frame(height: 174).clipShape(RoundedRectangle(cornerRadius: 17))
        .overlay(RoundedRectangle(cornerRadius: 17).strokeBorder(
            LinearGradient(colors: [.black.opacity(0.7), aqua.opacity(0.18), .white.opacity(0.12)], startPoint: .top, endPoint: .bottom), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 1, y: 1)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Tone shape illustration")
        .accessibilityValue(model.settings.muffle < 0.001 ? "Full range" : "Low-pass cutoff \(Int(model.settings.cutoff)) hertz")
    }

    private var output: some View {
        HStack(spacing: 11) {
            Image(systemName: "speaker.wave.2.fill").foregroundStyle(aqua.opacity(0.8)).font(.system(size: 12))
            Text("Output").font(.system(size: 11, weight: .medium)).foregroundStyle(frost)
            Slider(value: $model.settings.output, in: 0...1).tint(aqua).frame(width: 152)
                .accessibilityLabel("Output volume")
            Text("\(Int(model.settings.output * 100))%")
                .font(.system(size: 10, design: .monospaced)).foregroundStyle(secondary).frame(width: 34, alignment: .leading)
            Spacer()
            Text("Tempo unchanged").font(.system(size: 10)).foregroundStyle(secondary)
        }
        .padding(.horizontal, 15).padding(.vertical, 9)
        .background(.black.opacity(0.16), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(.white.opacity(0.06), lineWidth: 0.75))
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Circle().fill(model.isRunning ? seafoam : secondary.opacity(0.5)).frame(width: 5, height: 5)
                    .shadow(color: model.isRunning ? seafoam.opacity(0.7) : .clear, radius: 4)
                Text(model.status).font(.system(size: 11)).foregroundStyle(frost.opacity(0.85))
                Spacer(minLength: 4)
                LevelMeter(level: model.level, active: model.isRunning)
            }
            HStack {
                Text("All apps  →  \(model.outputName)").lineLimit(1)
                Spacer()
                if model.isRunning { Text(model.sampleRate) }
            }.font(.system(size: 10)).foregroundStyle(secondary)
            if let error = model.error {
                Text(error).font(.system(size: 11)).foregroundStyle(Color(red: 1, green: 0.74, blue: 0.56)).fixedSize(horizontal: false, vertical: true)
                Button("Open audio permissions") { model.openPermissions() }.font(.system(size: 11)).tint(aqua)
            }
        }.padding(.horizontal, 3)
    }
}

private struct AeroButtonStyle: ButtonStyle {
    var selected = false
    var compact = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(selected ? frost : secondary)
            .background {
                Capsule().fill(LinearGradient(stops: [
                    .init(color: selected ? Color(red: 0.22, green: 0.55, blue: 0.68) : .white.opacity(compact ? 0.025 : 0.15), location: 0),
                    .init(color: selected ? Color(red: 0.10, green: 0.35, blue: 0.48) : .white.opacity(compact ? 0.015 : 0.065), location: 0.49),
                    .init(color: selected ? Color(red: 0.045, green: 0.24, blue: 0.36) : .black.opacity(0.08), location: 0.51),
                    .init(color: selected ? Color(red: 0.09, green: 0.39, blue: 0.46) : .white.opacity(0.025), location: 1)
                ], startPoint: .top, endPoint: .bottom))
            }
            .overlay(Capsule().strokeBorder(LinearGradient(colors: [.white.opacity(selected ? 0.45 : compact ? 0.06 : 0.25), aqua.opacity(selected ? 0.22 : 0.03)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
            .shadow(color: selected ? aqua.opacity(0.1) : .clear, radius: 7, y: 2)
            .brightness(configuration.isPressed ? -0.07 : 0)
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

private struct GlassOrb: View {
    let icon: String
    let color: Color
    let size: CGFloat
    var body: some View {
        ZStack {
            Circle().fill(RadialGradient(colors: [color.opacity(0.85), color.opacity(0.22), Color(red: 0.02, green: 0.12, blue: 0.21)], center: .init(x: 0.5, y: 0.95), startRadius: 0, endRadius: size * 0.95))
            Circle().fill(LinearGradient(colors: [.white.opacity(0.13), .clear], startPoint: .topLeading, endPoint: .bottomTrailing))
            Image(systemName: icon).font(.system(size: size * 0.40, weight: .medium)).foregroundStyle(.white.opacity(0.94))
                .shadow(color: color, radius: 5)
            Ellipse().fill(LinearGradient(colors: [.white.opacity(0.65), .white.opacity(0.06)], startPoint: .top, endPoint: .bottom))
                .frame(width: size * 0.72, height: size * 0.34).offset(y: -size * 0.23)
        }
        .frame(width: size, height: size)
        .overlay(Circle().strokeBorder(LinearGradient(colors: [.white.opacity(0.6), color.opacity(0.15), color.opacity(0.6)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.35), radius: 3, y: 3)
        .shadow(color: color.opacity(0.15), radius: 10)
        .accessibilityHidden(true)
    }
}

private struct EffectControl: View {
    let title: String
    let subtitle: String
    let icon: String
    let accent: Color
    @Binding var value: Float
    let range: ClosedRange<Float>
    let display: String
    let unit: String
    let low: String
    let high: String

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 9) {
                GlassOrb(icon: icon, color: accent, size: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(frost)
                    Text(subtitle).font(.system(size: 10)).foregroundStyle(secondary)
                }
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(display).font(.system(size: 31, weight: .ultraLight, design: .rounded)).monospacedDigit().foregroundStyle(frost)
                Text(unit).font(.system(size: 11, weight: .light)).foregroundStyle(accent.opacity(0.8))
            }.padding(.top, 1)
            VStack(spacing: 4) {
                Slider(value: $value, in: range).tint(accent)
                    .accessibilityLabel(title).accessibilityValue("\(display) \(unit)")
                HStack { Text(low); Spacer(); Text(high) }
                    .font(.system(size: 9)).foregroundStyle(secondary)
            }
        }
        .padding(15).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 15).fill(LinearGradient(colors: [.white.opacity(0.085), .white.opacity(0.025), .black.opacity(0.07)], startPoint: .topLeading, endPoint: .bottomTrailing))
        }
        .overlay(RoundedRectangle(cornerRadius: 15).strokeBorder(LinearGradient(colors: [.white.opacity(0.25), .white.opacity(0.04)], startPoint: .top, endPoint: .bottom), lineWidth: 0.75))
        .shadow(color: .black.opacity(0.16), radius: 5, y: 4)
    }
}

private struct LevelMeter: View {
    let level: Float
    let active: Bool
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<22) { index in
                let lit = active && Float(index) / 22 < max(0, (20 * log10(max(0.00001, level)) + 54) / 54)
                RoundedRectangle(cornerRadius: 1)
                    .fill(LinearGradient(colors: lit ? [seafoam, aqua.opacity(0.8)] : [aqua.opacity(0.15), aqua.opacity(0.07)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 3, height: 9)
            }
        }.accessibilityLabel("Input audio level")
            .accessibilityValue(active ? String(format: "%.0f decibels", 20 * log10(max(0.00001, level))) : "Bypassed")
    }
}

private struct GlassReflection: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            p.move(to: .zero); p.addLine(to: CGPoint(x: rect.maxX, y: 0))
            p.addLine(to: CGPoint(x: rect.maxX, y: rect.height * 0.28))
            p.addQuadCurve(to: CGPoint(x: 0, y: rect.height * 0.50), control: CGPoint(x: rect.width * 0.48, y: rect.height * 0.18))
            p.closeSubpath()
        }
    }
}

private struct AeroRibbons: Shape {
    func path(in rect: CGRect) -> Path {
        Path { p in
            for offset in [0.0, 12.0, 70.0] {
                p.move(to: CGPoint(x: rect.width * 0.42 + offset, y: -30))
                p.addCurve(to: CGPoint(x: rect.maxX + 40, y: rect.height * 0.73 + offset),
                           control1: CGPoint(x: rect.width * 0.68, y: rect.height * 0.20 + offset),
                           control2: CGPoint(x: rect.width * 0.7, y: rect.height * 0.62 + offset))
            }
        }
    }
}

private struct ResponseView: View {
    let muffle: Float
    let space: Float
    let active: Bool

    var body: some View {
        Canvas { context, size in
            var grid = Path()
            for i in 1..<13 {
                let x = size.width * Double(i) / 13
                grid.move(to: CGPoint(x: x, y: 0)); grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for i in 1..<5 {
                let y = size.height * Double(i) / 5
                grid.move(to: CGPoint(x: 0, y: y)); grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            context.stroke(grid, with: .color(aqua.opacity(0.045)), lineWidth: 0.5)
            let cutoff = Double(EffectSettings(muffle: muffle).cutoff)
            func point(_ x: Double) -> CGPoint {
                let frequency = 20 * pow(1_000, x / size.width)
                let attenuation = muffle < 0.001 ? 0 : 10 * log10(1 + pow(frequency / cutoff, 4))
                return CGPoint(x: x, y: 82 + min(60, attenuation * 1.8))
            }
            var curve = Path()
            curve.move(to: point(0))
            for x in stride(from: 1.0, through: size.width, by: 1) { curve.addLine(to: point(x)) }
            var fill = curve
            fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [aqua.opacity(0.16), seafoam.opacity(0.015)]), startPoint: CGPoint(x: 0, y: 80), endPoint: CGPoint(x: 0, y: size.height)))
            for i in 1...3 {
                let echo = curve.applying(CGAffineTransform(translationX: Double(i) * Double(space) * 15, y: Double(i) * Double(space) * 14))
                context.stroke(echo, with: .color(aqua.opacity(Double(space) * 0.20)), lineWidth: 1)
            }
            context.drawLayer { glow in
                glow.addFilter(.blur(radius: 5))
                glow.stroke(curve, with: .color(aqua.opacity(active ? 0.6 : 0.25)), lineWidth: 3)
            }
            context.stroke(curve, with: .linearGradient(Gradient(colors: [seafoam.opacity(active ? 0.9 : 0.6), aqua.opacity(active ? 1 : 0.65)]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: 0)), lineWidth: 1.5)
        }.accessibilityHidden(true)
    }
}
