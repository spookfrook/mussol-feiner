import AppKit
import Combine
#if canImport(MussolFeinerCore)
import MussolFeinerCore
#endif
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class MussolFeinerAppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var analyticsWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var model: TrackerViewModel!
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        configureMainMenu()

        do {
            model = TrackerViewModel(store: try TimeTrackingStore())
        } catch {
            let alert = NSAlert(error: error)
            alert.messageText = "Mussol Feiner could not open its local data."
            alert.informativeText = error.localizedDescription
            alert.runModal()
            NSApp.terminate(nil)
            return
        }

        configureStatusItem()
        configurePopover()
        bindModel()
        updateStatusItem()
        // Wait until the first run-loop turn so an accessory app can safely
        // create and focus its initial window.
        DispatchQueue.main.async { [weak self] in
            self?.showAnalytics()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showAnalytics()
        return true
    }

    private func configureStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem.button else { return }
        button.target = self
        button.action = #selector(togglePopover)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        button.imagePosition = .noImage
        button.toolTip = "Mussol Feiner"
        button.setAccessibilityLabel("Mussol Feiner timer")
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
        popover.appearance = NSAppearance(named: .aqua)
        popover.contentSize = NSSize(width: 340, height: 446)
        let controller = NSHostingController(
            rootView: MenuBarPopoverView(
                model: model,
                openAnalytics: { [weak self] in self?.showAnalytics() },
                openSettings: { [weak self] in self?.showSettings() },
                quit: { NSApp.terminate(nil) }
            )
        )
        controller.view.appearance = NSAppearance(named: .aqua)
        popover.contentViewController = controller
    }

    private func bindModel() {
        Publishers.CombineLatest3(model.$activeTimer, model.$elapsed, model.$modeColorHexes)
            .receive(on: RunLoop.main)
            .sink { [weak self] _, _, _ in self?.updateStatusItem() }
            .store(in: &cancellables)

        model.$pendingFocusEntryID
            .receive(on: RunLoop.main)
            .sink { [weak self] pendingID in
                self?.popover.contentSize = NSSize(width: 340, height: pendingID == nil ? 446 : 562)
            }
            .store(in: &cancellables)
    }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let modeColor: NSColor
        let text: String
        if let active = model.activeTimer {
            modeColor = NSColor(model.color(for: active.mode))
            text = " \(active.projectCode) \(formatClock(model.elapsed))"
            button.setAccessibilityValue("\(active.mode.label), project \(active.projectCode), \(formatClock(model.elapsed))")
        } else {
            modeColor = .secondaryLabelColor
            text = " 00:00:00"
            button.setAccessibilityValue("No active timer")
        }

        let title = NSMutableAttributedString(
            string: "●",
            attributes: [
                .foregroundColor: modeColor,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .black)
            ]
        )
        title.append(NSAttributedString(
            string: text,
            attributes: [
                .foregroundColor: NSColor.labelColor,
                .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .semibold)
            ]
        ))
        button.attributedTitle = title
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            return
        }
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
    }

    func popoverDidShow(_ notification: Notification) {
        model.requestProjectFieldFocus()
    }

    @objc func showAnalytics() {
        popover.performClose(nil)
        if analyticsWindow == nil {
            let root = AnalyticsWindowView(
                model: model,
                export: { [weak self] format, interval in self?.export(format: format, interval: interval) }
            )
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "Mussol Feiner"
            window.appearance = NSAppearance(named: .aqua)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 980, height: 760))
            window.minSize = NSSize(width: 820, height: 640)
            window.isReleasedWhenClosed = false
            window.center()
            window.setFrameAutosaveName("MussolFeinerAnalyticsWindow")
            analyticsWindow = window
        }
        analyticsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let root = SettingsView(
                model: model,
                close: { [weak self] in self?.settingsWindow?.close() }
            )
            let controller = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: controller)
            window.title = "Mussol Feiner Settings"
            window.appearance = NSAppearance(named: .aqua)
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 480, height: 440))
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func export(format: UIExportFormat, interval: DateInterval?) {
        let panel = NSSavePanel()
        let coreFormat = exportFormat(format)
        panel.title = interval == nil ? "Export all time data" : "Export current view"
        panel.prompt = "Export"
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = exportFilename(format: coreFormat, allData: interval == nil)
        if let type = UTType(filenameExtension: coreFormat.fileExtension) {
            panel.allowedContentTypes = [type]
        }

        let completion: (NSApplication.ModalResponse) -> Void = { [weak self] response in
            guard response == .OK, let url = panel.url, let self else { return }
            do {
                let scope: ExportScope = interval.map(ExportScope.range) ?? .all
                let entries = try self.exportEntriesSnapshot(at: Date())
                try DataExporter.write(
                    entries: entries,
                    format: coreFormat,
                    scope: scope,
                    to: url
                )
            } catch {
                self.model.alertMessage = "Export failed: \(error.localizedDescription)"
            }
        }

        if let window = analyticsWindow, window.isVisible {
            panel.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(panel.runModal())
        }
    }

    /// Includes elapsed active time in exports without stopping or persisting the timer.
    private func exportEntriesSnapshot(at date: Date) throws -> [TimeEntry] {
        var entries = model.store.entries
        if let active = model.store.activeTimer, date > active.start {
            entries.append(
                try TimeEntry(
                    projectCode: active.projectCode,
                    workMode: active.workMode,
                    start: active.start,
                    end: date
                )
            )
        }
        return entries
    }

    private func exportFormat(_ format: UIExportFormat) -> ExportFormat {
        switch format {
        case .json: return .json
        case .csv: return .csv
        case .markdown: return .markdown
        }
    }

    private func exportFilename(format: ExportFormat, allData: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let scope = allData ? "all" : "view"
        return "mussol-feiner-\(scope)-\(formatter.string(from: Date())).\(format.fileExtension)"
    }

    private func configureMainMenu() {
        let menu = NSMenu(title: "Main Menu")

        let appItem = NSMenuItem()
        let appMenu = NSMenu(title: "Mussol Feiner")
        appMenu.addItem(menuItem(title: "Open Analytics", action: #selector(showAnalytics), key: "o", target: self))
        appMenu.addItem(menuItem(title: "Settings…", action: #selector(showSettings), key: ",", target: self))
        appMenu.addItem(.separator())
        appMenu.addItem(menuItem(title: "Quit Mussol Feiner", action: #selector(NSApplication.terminate(_:)), key: "q", target: NSApp))
        appItem.submenu = appMenu
        menu.addItem(appItem)

        let editItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(menuItem(title: "Undo", action: Selector(("undo:")), key: "z"))
        editMenu.addItem(menuItem(title: "Redo", action: Selector(("redo:")), key: "z", modifiers: [.command, .shift]))
        editMenu.addItem(.separator())
        editMenu.addItem(menuItem(title: "Cut", action: #selector(NSText.cut(_:)), key: "x"))
        editMenu.addItem(menuItem(title: "Copy", action: #selector(NSText.copy(_:)), key: "c"))
        editMenu.addItem(menuItem(title: "Paste", action: #selector(NSText.paste(_:)), key: "v"))
        editMenu.addItem(menuItem(title: "Select All", action: #selector(NSStandardKeyBindingResponding.selectAll(_:)), key: "a"))
        editItem.submenu = editMenu
        menu.addItem(editItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(menuItem(title: "Close", action: #selector(NSWindow.performClose(_:)), key: "w"))
        windowMenu.addItem(menuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), key: "m"))
        windowItem.submenu = windowMenu
        menu.addItem(windowItem)
        NSApp.mainMenu = menu
        NSApp.windowsMenu = windowMenu
    }

    private func menuItem(
        title: String,
        action: Selector?,
        key: String,
        modifiers: NSEvent.ModifierFlags = [.command],
        target: AnyObject? = nil
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = modifiers
        item.target = target
        return item
    }
}
