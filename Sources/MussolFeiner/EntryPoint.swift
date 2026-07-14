import AppKit

@main
enum MussolFeinerEntryPoint {
    private static var retainedDelegate: MussolFeinerAppDelegate?

    @MainActor
    static func main() {
        let application = NSApplication.shared
        let delegate = MussolFeinerAppDelegate()
        retainedDelegate = delegate
        application.delegate = delegate
        application.setActivationPolicy(.regular)
        application.run()
    }
}
