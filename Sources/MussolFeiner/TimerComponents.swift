import AppKit
import SwiftUI

/// Elapsed-time readout that turns into a text field on click so the running
/// timer can be corrected in place, Linear-style.
struct EditableElapsedText: View {
    let elapsed: TimeInterval
    var fontSize: CGFloat = 22
    let commit: (String) -> Void

    @State private var isEditing = false
    @State private var draft = ""
    @State private var originalDraft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if isEditing {
                TextField("", text: $draft)
                    .textFieldStyle(.plain)
                    .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                    .multilineTextAlignment(.trailing)
                    .focused($fieldFocused)
                    .padding(.horizontal, 4)
                    .frame(width: fontSize * 5.5)
                    .background(.white.opacity(0.82))
                    .overlay(Rectangle().stroke(MussolTheme.ink, lineWidth: 1.5))
                    .onSubmit { finishEditing(commitChanges: true) }
                    .onExitCommand { finishEditing(commitChanges: false) }
                    .onChange(of: fieldFocused) { focused in
                        if !focused { finishEditing(commitChanges: true) }
                    }
                    .accessibilityLabel("Edit elapsed time")
            } else {
                Button(action: beginEditing) {
                    HStack(spacing: 5) {
                        Text(formatClock(elapsed))
                            .font(.system(size: fontSize, weight: .bold, design: .monospaced))
                            .monospacedDigit()
                        Image(systemName: "pencil")
                            .font(.system(size: fontSize * 0.42, weight: .bold))
                            .foregroundStyle(MussolTheme.mutedInk)
                    }
                }
                .buttonStyle(.plain)
                .help("Click to edit elapsed time, like 45m, 1h 30m, or 01:30:00")
                .accessibilityLabel("Elapsed time \(formatClock(elapsed)). Click to edit.")
            }
        }
    }

    private func beginEditing() {
        draft = formatClock(elapsed)
        originalDraft = draft
        isEditing = true
        DispatchQueue.main.async {
            fieldFocused = true
            DispatchQueue.main.async {
                NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
            }
        }
    }

    private func finishEditing(commitChanges: Bool) {
        guard isEditing else { return }
        isEditing = false
        if commitChanges, draft != originalDraft {
            commit(draft)
        }
    }
}

/// Compact input for time already worked before pressing start, e.g. "5m".
struct ElapsedPrefillField: View {
    @Binding var text: String
    var width: CGFloat = 76

    var body: some View {
        ZStack {
            if text.isEmpty {
                Text("0m")
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundStyle(MussolTheme.mutedInk.opacity(0.58))
                    .allowsHitTesting(false)
            }
            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .accessibilityLabel("Time already worked before starting")
        }
        .frame(width: width, height: 32)
        .background(.white.opacity(0.82))
        .overlay(Rectangle().stroke(MussolTheme.ink.opacity(0.55), lineWidth: 1.25))
        .help("Started already? Add the time you've worked, like 5m or 1h 30m. The timer begins with it counted.")
    }
}

/// Optional 1-to-5 self-assessment for the most recently stopped timer.
struct FocusPromptView: View {
    @ObservedObject var model: TrackerViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("HOW FOCUSED WERE YOU?")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                    Text("Optional self-assessment for the timer you stopped.")
                        .font(.system(size: 10))
                        .foregroundStyle(MussolTheme.mutedInk)
                    if let pendingEntry {
                        Text("\(pendingEntry.projectCode) · \(pendingEntry.mode.label) · \(formatClock(pendingEntry.duration))")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .foregroundStyle(MussolTheme.mutedInk)
                    }
                }
                Spacer()
                Button("Skip") { model.skipPendingFocus() }
                    .buttonStyle(.link)
            }

            HStack(spacing: 5) {
                ForEach(1...5, id: \.self) { score in
                    Button {
                        model.setPendingFocus(score)
                    } label: {
                        VStack(spacing: 3) {
                            Text("\(score)")
                                .font(.system(size: 15, weight: .black, design: .monospaced))
                            Text(focusLabel(score))
                                .font(.system(size: 7, weight: .semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, minHeight: 38)
                    }
                    .buttonStyle(.plain)
                    .background(MussolTheme.paperLight)
                    .overlay(Rectangle().stroke(MussolTheme.ink.opacity(0.45), lineWidth: 1))
                }
            }
            .frame(maxWidth: 460, alignment: .leading)
        }
        .padding(14)
        .background(MussolTheme.signalYellow.opacity(0.20))
    }

    private var pendingEntry: UIEntry? {
        guard let id = model.pendingFocusEntryID else { return nil }
        return model.entries.first(where: { $0.id == id })
    }

    private func focusLabel(_ score: Int) -> String {
        switch score {
        case 1: return "Distracted"
        case 2: return "Fragmented"
        case 3: return "Steady"
        case 4: return "Focused"
        default: return "Locked in"
        }
    }
}

/// Full-width strip below the analytics header: clock in, watch or correct the
/// running timer, and score a stopped one without opening the menu bar popover.
struct TimerControlBar: View {
    @ObservedObject var model: TrackerViewModel

    @State private var projectCode = ""
    @State private var selectedMode: UIWorkMode = .deepWork
    @State private var elapsedInput = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                if let active = model.activeTimer {
                    runningControls(active)
                } else {
                    idleControls
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 58)

            if model.pendingFocusEntryID != nil {
                Divider().overlay(MussolTheme.ink.opacity(0.4))
                FocusPromptView(model: model)
            }
        }
        .background(MussolTheme.paperLight.opacity(0.5))
        .onAppear { adoptActiveTimer() }
        .onChange(of: model.activeTimer) { _ in adoptActiveTimer() }
    }

    @ViewBuilder
    private func runningControls(_ active: UIActiveTimer) -> some View {
        WorkModeDot(color: model.color(for: active.mode), size: 13)
        Text(active.projectCode)
            .font(.system(size: 18, weight: .black, design: .monospaced))
        VStack(alignment: .leading, spacing: 1) {
            Text(active.mode.label)
                .font(.system(size: 11, weight: .semibold))
            Text("since \(formatEnglishDate(active.startedAt, "HH:mm"))")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(MussolTheme.mutedInk)
        }
        Spacer()
        EditableElapsedText(elapsed: model.elapsed, fontSize: 20) { model.commitElapsedEdit($0) }
        Button("Stop") { model.stopTimer() }
            .buttonStyle(PrimaryInkButtonStyle(destructive: true))
    }

    @ViewBuilder
    private var idleControls: some View {
        BlockLabel(text: "Clock in", color: MussolTheme.signalYellow)

        ZStack {
            if projectCode.isEmpty {
                Text("ABC")
                    .font(.system(size: 16, weight: .black, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(MussolTheme.mutedInk.opacity(0.58))
                    .allowsHitTesting(false)
            }
            TextField("", text: projectBinding)
                .textFieldStyle(.plain)
                .font(.system(size: 16, weight: .black, design: .monospaced))
                .tracking(2)
                .multilineTextAlignment(.center)
                .onSubmit { startFromBar() }
                .accessibilityLabel("Three-letter project code")
        }
        .frame(width: 84, height: 32)
        .background(.white.opacity(0.82))
        .overlay(Rectangle().stroke(MussolTheme.ink, lineWidth: 1.5))

        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 11) {
                ForEach(UIWorkMode.allCases) { mode in
                    Button {
                        selectedMode = mode
                    } label: {
                        WorkModeDot(
                            color: model.color(for: mode),
                            size: 13,
                            selected: selectedMode == mode
                        )
                    }
                    .buttonStyle(.plain)
                    .help(mode.label)
                    .accessibilityLabel(mode.label)
                    .accessibilityAddTraits(selectedMode == mode ? .isSelected : [])
                }
            }
            Text("\(selectedMode.code) · \(selectedMode.label)")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(MussolTheme.mutedInk)
                .lineLimit(1)
        }

        ElapsedPrefillField(text: $elapsedInput)
            .onSubmit { startFromBar() }

        Button {
            startFromBar()
        } label: {
            Label("Start timer", systemImage: "play.fill")
        }
        .buttonStyle(PrimaryInkButtonStyle())
        .disabled(projectCode.count != 3)

        Spacer()

        Text("NOT CLOCKED IN")
            .font(.system(size: 10, weight: .black, design: .monospaced))
            .tracking(0.8)
            .foregroundStyle(MussolTheme.mutedInk)
    }

    private var projectBinding: Binding<String> {
        Binding(
            get: { projectCode },
            set: { projectCode = $0.projectCode }
        )
    }

    private func startFromBar() {
        guard projectCode.count == 3 else { return }
        model.startTimer(projectCode: projectCode, mode: selectedMode, elapsedInput: elapsedInput)
        if model.alertMessage == nil { elapsedInput = "" }
    }

    private func adoptActiveTimer() {
        guard let active = model.activeTimer else { return }
        projectCode = active.projectCode
        selectedMode = active.mode
        elapsedInput = ""
    }
}
