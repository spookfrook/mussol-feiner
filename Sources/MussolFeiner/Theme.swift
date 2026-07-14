import AppKit
import SwiftUI

enum MussolTheme {
    static let paper = Color(red: 0.945, green: 0.918, blue: 0.835)
    static let paperLight = Color(red: 0.976, green: 0.961, blue: 0.914)
    static let ink = Color(red: 0.075, green: 0.071, blue: 0.063)
    static let mutedInk = Color(red: 0.35, green: 0.33, blue: 0.29)
    static let rule = Color.black.opacity(0.16)
    static let signalYellow = Color(red: 0.96, green: 0.67, blue: 0.05)
    static let signalRed = Color(red: 0.84, green: 0.16, blue: 0.12)
    static let signalCyan = Color(red: 0.02, green: 0.56, blue: 0.66)
    static let signalViolet = Color(red: 0.36, green: 0.22, blue: 0.52)

    static func color(hex: String) -> Color {
        Color(nsColor: NSColor(hex: hex) ?? .systemGray)
    }

    static func hex(color: Color) -> String? {
        guard let nsColor = NSColor(color).usingColorSpace(.deviceRGB) else { return nil }
        return String(
            format: "#%02X%02X%02X",
            Int(round(nsColor.redComponent * 255)),
            Int(round(nsColor.greenComponent * 255)),
            Int(round(nsColor.blueComponent * 255))
        )
    }
}

extension NSColor {
    convenience init?(hex: String) {
        let clean = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        guard clean.count == 6, let value = Int(clean, radix: 16) else { return nil }
        self.init(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

struct PaperBackground: View {
    var body: some View {
        ZStack {
            MussolTheme.paper
            Canvas { context, size in
                var dots = Path()
                let spacing: CGFloat = 8
                var y: CGFloat = 3
                while y < size.height {
                    var x: CGFloat = 3
                    while x < size.width {
                        let wobble = CGFloat(Int(x + y) % 3) * 0.17
                        dots.addEllipse(in: CGRect(x: x + wobble, y: y, width: 0.7, height: 0.7))
                        x += spacing
                    }
                    y += spacing
                }
                context.fill(dots, with: .color(.black.opacity(0.055)))
            }
            .allowsHitTesting(false)
        }
    }
}

struct BrandMark: View {
    var size: CGFloat = 40

    var body: some View {
        Group {
            if let image = brandImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    MussolTheme.ink
                    Text("MF")
                        .font(.system(size: size * 0.34, weight: .black, design: .monospaced))
                        .foregroundStyle(MussolTheme.signalYellow)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: max(2, size * 0.08), style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: max(2, size * 0.08), style: .continuous)
                .stroke(MussolTheme.ink.opacity(0.65), lineWidth: 1)
        )
        .accessibilityHidden(true)
    }

    private var brandImage: NSImage? {
        guard let url = Bundle.main.url(forResource: "mussol-feiner-icon", withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }
}

struct InkCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .background(MussolTheme.paperLight)
            .overlay(
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .stroke(MussolTheme.ink.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
            .shadow(color: .black.opacity(0.07), radius: 0, x: 3, y: 3)
    }
}

struct BlockLabel: View {
    let text: String
    var color: Color = MussolTheme.ink

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(1.25)
            .foregroundStyle(color == MussolTheme.ink ? MussolTheme.paperLight : MussolTheme.ink)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(color)
            .accessibilityAddTraits(.isHeader)
    }
}

struct WorkModeDot: View {
    let color: Color
    var size: CGFloat = 10
    var selected = false

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: size, height: size)
            .overlay(Circle().stroke(MussolTheme.ink, lineWidth: selected ? 2 : 0.75))
            .padding(selected ? 3 : 0)
            .background(selected ? Circle().stroke(MussolTheme.ink, lineWidth: 1) : nil)
    }
}

struct PrimaryInkButtonStyle: ButtonStyle {
    var destructive = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 14)
            .frame(minHeight: 32)
            .background(destructive ? MussolTheme.signalRed : MussolTheme.ink)
            .opacity(configuration.isPressed ? 0.72 : 1)
            .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }
}

func formatClock(_ interval: TimeInterval) -> String {
    let total = max(0, Int(interval.rounded(.down)))
    return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
}

func formatHours(_ interval: TimeInterval) -> String {
    let hours = interval / 3600
    if hours < 1 {
        return "\(Int((interval / 60).rounded()))m"
    }
    return String(format: hours < 10 ? "%.1fh" : "%.0fh", hours)
}

func formatEnglishDate(_ date: Date, _ pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = .current
    formatter.dateFormat = pattern
    return formatter.string(from: date)
}
