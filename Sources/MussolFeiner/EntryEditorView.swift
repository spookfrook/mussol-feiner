import SwiftUI

struct EntryEditorView: View {
    @ObservedObject var model: TrackerViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var draft: EntryDraft

    init(model: TrackerViewModel, draft: EntryDraft) {
        self.model = model
        _draft = State(initialValue: draft)
    }

    var body: some View {
        ZStack {
            PaperBackground()
            VStack(spacing: 0) {
                header
                Divider().overlay(MussolTheme.ink.opacity(0.45))
                Form {
                    Section("Project") {
                        HStack {
                            TextField("ABC", text: projectBinding)
                                .font(.system(size: 22, weight: .black, design: .monospaced))
                                .tracking(3)
                                .frame(width: 100)
                            Text("Exactly three letters. Codes with the same value are grouped automatically.")
                                .font(.system(size: 10))
                                .foregroundStyle(MussolTheme.mutedInk)
                        }
                    }

                    Section("Work mode") {
                        HStack(spacing: 8) {
                            ForEach(UIWorkMode.allCases) { mode in
                                Button {
                                    draft.mode = mode
                                } label: {
                                    HStack(spacing: 6) {
                                        WorkModeDot(
                                            color: model.color(for: mode),
                                            size: 11,
                                            selected: draft.mode == mode
                                        )
                                        Text(mode.label)
                                            .font(.system(size: 10, weight: .semibold))
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 35)
                                }
                                .buttonStyle(.plain)
                                .background(draft.mode == mode ? model.color(for: mode).opacity(0.16) : .white.opacity(0.34))
                                .overlay(Rectangle().stroke(MussolTheme.ink.opacity(draft.mode == mode ? 0.75 : 0.18), lineWidth: 1))
                                .accessibilityAddTraits(draft.mode == mode ? .isSelected : [])
                            }
                        }
                    }

                    Section("Time") {
                        DatePicker("Start", selection: $draft.startDate, displayedComponents: [.date, .hourAndMinute])
                        DatePicker("End", selection: $draft.endDate, displayedComponents: [.date, .hourAndMinute])
                        LabeledContent("Duration") {
                            Text(draft.endDate > draft.startDate ? formatClock(draft.endDate.timeIntervalSince(draft.startDate)) : "Invalid range")
                                .font(.system(size: 12, weight: .bold, design: .monospaced))
                                .foregroundStyle(draft.endDate > draft.startDate ? MussolTheme.ink : MussolTheme.signalRed)
                        }
                    }

                    Section("Focus Score · optional") {
                        Picker("Self-assessed performance", selection: $draft.focusScore) {
                            Text("Not scored").tag(Int?.none)
                            Text("1 · Distracted").tag(Int?.some(1))
                            Text("2 · Fragmented").tag(Int?.some(2))
                            Text("3 · Steady").tag(Int?.some(3))
                            Text("4 · Focused").tag(Int?.some(4))
                            Text("5 · Locked in").tag(Int?.some(5))
                        }
                        .pickerStyle(.menu)
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)
                .padding(.top, 4)
                footer
            }
        }
        .frame(width: 590, height: 505)
        .foregroundStyle(MussolTheme.ink)
        .tint(MussolTheme.ink)
    }

    private var header: some View {
        HStack {
            BlockLabel(text: draft.editingID == nil ? "Manual entry" : "Edit entry", color: MussolTheme.signalYellow)
            Spacer()
            Text(draft.editingID == nil ? "ADD TIME" : "CORRECT TIME")
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(0.8)
                .foregroundStyle(MussolTheme.mutedInk)
        }
        .padding(.horizontal, 20)
        .frame(height: 54)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(draft.editingID == nil ? "Add entry" : "Save changes") {
                model.save(draft)
                if model.alertMessage == nil { dismiss() }
            }
            .buttonStyle(PrimaryInkButtonStyle())
            .disabled(draft.projectCode.count != 3 || draft.endDate <= draft.startDate)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 20)
        .frame(height: 58)
        .background(MussolTheme.paperLight.opacity(0.7))
        .overlay(Divider(), alignment: .top)
    }

    private var projectBinding: Binding<String> {
        Binding(
            get: { draft.projectCode },
            set: { draft.projectCode = $0.projectCode }
        )
    }
}
