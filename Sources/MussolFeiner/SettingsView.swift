import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: TrackerViewModel
    @Environment(\.dismiss) private var dismiss
    var close: (() -> Void)?

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                HStack {
                    BlockLabel(text: "Work mode colors", color: MussolTheme.signalYellow)
                    Spacer()
                    Text("THE DOT IS THE MODE")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .foregroundStyle(MussolTheme.mutedInk)
                }
                .padding(.horizontal, 20)
                .frame(height: 56)
                Divider().overlay(MussolTheme.ink.opacity(0.45))

                VStack(spacing: 0) {
                    ForEach(UIWorkMode.allCases) { mode in
                        HStack(spacing: 14) {
                            WorkModeDot(color: model.color(for: mode), size: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.label)
                                    .font(.system(size: 13, weight: .bold))
                                Text(mode.code)
                                    .font(.system(size: 9, weight: .black, design: .monospaced))
                                    .foregroundStyle(MussolTheme.mutedInk)
                            }
                            Spacer()
                            Text(model.modeColorHexes[mode] ?? mode.defaultColorHex)
                                .font(.system(size: 10, weight: .medium, design: .monospaced))
                                .foregroundStyle(MussolTheme.mutedInk)
                            ColorPicker("", selection: colorBinding(for: mode), supportsOpacity: false)
                                .labelsHidden()
                                .accessibilityLabel("\(mode.label) color")
                        }
                        .frame(height: 58)
                        if mode != UIWorkMode.allCases.last {
                            Divider().padding(.leading, 46)
                        }
                    }
                }
                .padding(.horizontal, 20)

                Text("These colors appear in the menu-bar dot, entries, breakdowns and charts. Project codes stay typographic, so work mode remains the dominant signal.")
                    .font(.system(size: 10))
                    .foregroundStyle(MussolTheme.mutedInk)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(20)

                Spacer()
                HStack {
                    Button("Restore defaults") { model.resetColors() }
                    Spacer()
                    Button("Done") {
                        if let close { close() } else { dismiss() }
                    }
                        .buttonStyle(PrimaryInkButtonStyle())
                        .keyboardShortcut(.defaultAction)
                }
                .padding(.horizontal, 20)
                .frame(height: 58)
                .background(MussolTheme.paperLight.opacity(0.7))
                .overlay(Divider(), alignment: .top)
            }
        }
        .frame(width: 480, height: 440)
        .foregroundStyle(MussolTheme.ink)
        .tint(MussolTheme.ink)
    }

    private func colorBinding(for mode: UIWorkMode) -> Binding<Color> {
        Binding(
            get: { model.color(for: mode) },
            set: { model.setColor($0, for: mode) }
        )
    }
}
