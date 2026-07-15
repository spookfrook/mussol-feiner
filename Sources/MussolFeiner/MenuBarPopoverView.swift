import AppKit
import SwiftUI

struct MenuBarPopoverView: View {
    @ObservedObject var model: TrackerViewModel
    let openAnalytics: () -> Void
    let openSettings: () -> Void
    let quit: () -> Void

    @State private var projectCode = ""
    @State private var selectedMode: UIWorkMode = .deepWork
    @State private var elapsedInput = ""
    @FocusState private var projectFieldFocused: Bool

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                header
                Divider().overlay(MussolTheme.ink.opacity(0.4))
                timerPanel
                Divider().overlay(MussolTheme.ink.opacity(0.4))
                startPanel
                if model.pendingFocusEntryID != nil {
                    Divider().overlay(MussolTheme.ink.opacity(0.4))
                    FocusPromptView(model: model)
                }
                Divider().overlay(MussolTheme.ink.opacity(0.4))
                footer
            }
        }
        .frame(width: 340)
        .fixedSize(horizontal: false, vertical: true)
        .foregroundStyle(MussolTheme.ink)
        .tint(MussolTheme.ink)
        .environment(\.locale, Locale(identifier: "en_US"))
        .environment(\.colorScheme, .light)
        .onAppear {
            if let active = model.activeTimer {
                projectCode = active.projectCode
                selectedMode = active.mode
            }
            elapsedInput = ""
            focusProjectField()
        }
        .onChange(of: model.popoverFocusRequest) { _ in focusProjectField() }
        .alert("Mussol Feiner", isPresented: alertPresented) {
            Button("OK") { model.alertMessage = nil }
        } message: {
            Text(model.alertMessage ?? "Something went wrong.")
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            BrandMark(size: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text("MUSSOL FEINER")
                    .font(.system(size: 14, weight: .black, design: .monospaced))
                    .tracking(0.8)
                Text("Clock in. Know your hours.")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(MussolTheme.mutedInk)
            }
            Spacer()
            Button(action: openSettings) {
                Image(systemName: "slider.horizontal.3")
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.plain)
            .help("Work mode colors")
            .accessibilityLabel("Work mode color settings")
        }
        .padding(.horizontal, 14)
        .frame(height: 54)
    }

    private var timerPanel: some View {
        VStack(spacing: 7) {
            if let active = model.activeTimer {
                HStack(alignment: .center, spacing: 9) {
                    WorkModeDot(color: model.color(for: active.mode), size: 13)
                    Text(active.projectCode)
                        .font(.system(size: 20, weight: .black, design: .monospaced))
                    Spacer()
                    EditableElapsedText(elapsed: model.elapsed, fontSize: 22) {
                        model.commitElapsedEdit($0)
                    }
                }
                HStack {
                    Text("\(active.mode.label) · since \(formatEnglishDate(active.startedAt, "HH:mm"))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(MussolTheme.mutedInk)
                    Spacer()
                    Button("Stop") { model.stopTimer() }
                        .buttonStyle(PrimaryInkButtonStyle(destructive: true))
                        .keyboardShortcut("s", modifiers: [.command])
                }
            } else {
                HStack {
                    WorkModeDot(color: MussolTheme.mutedInk.opacity(0.35), size: 12)
                    Text("NOT CLOCKED IN")
                        .font(.system(size: 12, weight: .black, design: .monospaced))
                        .tracking(0.8)
                    Spacer()
                    Text("00:00:00")
                        .font(.system(size: 19, weight: .bold, design: .monospaced))
                        .foregroundStyle(MussolTheme.mutedInk)
                }
            }
        }
        .padding(14)
        .background(MussolTheme.paperLight.opacity(0.78))
    }

    private var startPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                BlockLabel(text: model.activeTimer == nil ? "Clock in" : "Switch project", color: MussolTheme.signalYellow)
                Spacer()
                Text("3 letters")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(MussolTheme.mutedInk)
            }

            HStack(spacing: 10) {
                ZStack {
                    if projectCode.isEmpty {
                        Text("ABC")
                            .font(.system(size: 25, weight: .black, design: .monospaced))
                            .tracking(3)
                            .foregroundStyle(MussolTheme.mutedInk.opacity(0.58))
                            .allowsHitTesting(false)
                    }
                    TextField("", text: projectBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 25, weight: .black, design: .monospaced))
                        .tracking(3)
                        .multilineTextAlignment(.center)
                        .focused($projectFieldFocused)
                        .accessibilityLabel("Three-letter project code")
                }
                .frame(width: 104, height: 40)
                .background(.white.opacity(0.82))
                .overlay(Rectangle().stroke(MussolTheme.ink, lineWidth: 1.5))

                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 13) {
                        ForEach(UIWorkMode.allCases) { mode in
                            Button {
                                selectedMode = mode
                            } label: {
                                WorkModeDot(
                                    color: model.color(for: mode),
                                    size: 15,
                                    selected: selectedMode == mode
                                )
                            }
                            .buttonStyle(.plain)
                            .help(mode.label)
                            .accessibilityLabel(mode.label)
                            .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                        }
                    }
                    Text("\(selectedMode.code)  ·  \(selectedMode.label)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 10) {
                ElapsedPrefillField(text: $elapsedInput)
                Button {
                    model.startTimer(projectCode: projectCode, mode: selectedMode, elapsedInput: elapsedInput)
                    if model.alertMessage == nil { elapsedInput = "" }
                } label: {
                    Label(model.activeTimer == nil ? "Start timer" : "Start new timer", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(PrimaryInkButtonStyle())
                .disabled(projectCode.count != 3)
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(14)
    }

    private var footer: some View {
        HStack {
            Button {
                openAnalytics()
            } label: {
                Label("Open analytics", systemImage: "chart.bar.xaxis")
            }
            .buttonStyle(.plain)
            .font(.system(size: 11, weight: .bold))
            Spacer()
            Button("Quit", action: quit)
                .buttonStyle(.plain)
                .font(.system(size: 10))
                .foregroundStyle(MussolTheme.mutedInk)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(MussolTheme.ink.opacity(0.05))
    }

    private var projectBinding: Binding<String> {
        Binding(
            get: { projectCode },
            set: { projectCode = $0.projectCode }
        )
    }

    private var alertPresented: Binding<Bool> {
        Binding(
            get: { model.alertMessage != nil },
            set: { if !$0 { model.alertMessage = nil } }
        )
    }

    private func focusProjectField() {
        DispatchQueue.main.async {
            projectFieldFocused = true
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }
}
