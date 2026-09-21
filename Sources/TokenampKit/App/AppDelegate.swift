import AppKit
import Foundation
import UsageModel

/// The app shell: a regular Dock app with a minimal main menu (SPEC 2.6).
public final class AppDelegate: NSObject, NSApplicationDelegate {

    private let arguments: Arguments
    private let providerFactory: (Bool) -> UsageProvider
    private let liveProviderAvailable: Bool
    private let providerDiagnostics: ((UsageProvider) -> [String])?
    public private(set) var controller: TokenampController?

    public init(arguments: Arguments, providerFactory: @escaping (Bool) -> UsageProvider,
                liveProviderAvailable: Bool,
                providerDiagnostics: ((UsageProvider) -> [String])? = nil) {
        self.arguments = arguments
        self.providerFactory = providerFactory
        self.liveProviderAvailable = liveProviderAvailable
        self.providerDiagnostics = providerDiagnostics
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        buildMainMenu()
        let c = TokenampController(providerFactory: providerFactory,
                                   liveProviderAvailable: liveProviderAvailable,
                                   forceDemo: arguments.demo,
                                   skinOverride: arguments.skinPath)
        c.providerDiagnostics = providerDiagnostics
        // --scale is ppsp; turn it into the points-scale this screen can honour.
        if arguments.scale != nil {
            let backing = NSScreen.main?.backingScaleFactor ?? 1
            c.prefs.pointsScale = ScaleModel.nearest(Double(arguments.resolvedScale) / Double(max(1, Int(backing.rounded()))),
                                                     backing: backing)
        }
        c.start()
        controller = c
        NSApp.activate(ignoringOtherApps: true)
    }

    public func applicationWillTerminate(_ notification: Notification) {
        controller?.stopAndSave()
    }

    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    public func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        controller?.mainWindow.window.makeKeyAndOrderFront(nil)
        return true
    }

    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = urls.first(where: { SkinCatalog.isSkinURL($0) }) else { return }
        controller?.loadSkin(at: url, install: true)
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About Tokenamp", action: #selector(showAbout), keyEquivalent: "")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Preferences\u{2026}", action: #selector(showOptions), keyEquivalent: ",")
            .target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide Tokenamp", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit Tokenamp", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let windowItem = NSMenuItem()
        let windowMenu = NSMenu(title: "Window")
        windowMenu.addItem(withTitle: "Main Window", action: #selector(focusMain), keyEquivalent: "1")
            .target = self
        windowMenu.addItem(withTitle: "Equalizer", action: #selector(toggleEqualizer), keyEquivalent: "2")
            .target = self
        windowMenu.addItem(withTitle: "Playlist", action: #selector(togglePlaylist), keyEquivalent: "3")
            .target = self
        windowMenu.addItem(.separator())
        windowMenu.addItem(withTitle: "Window Shade", action: #selector(toggleShade), keyEquivalent: "w")
            .target = self
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        windowItem.submenu = windowMenu
        main.addItem(windowItem)

        NSApp.mainMenu = main
        NSApp.windowsMenu = windowMenu
    }

    @objc private func showAbout() { controller?.showAbout() }
    @objc private func focusMain() { controller?.mainWindow.window.makeKeyAndOrderFront(nil) }
    @objc private func toggleEqualizer() { controller?.toggleEqualizer() }
    @objc private func togglePlaylist() { controller?.togglePlaylist() }
    @objc private func toggleShade() { controller?.toggleShade() }

    @objc private func showOptions() {
        guard let c = controller else { return }
        let view = c.mainWindow.view
        c.showOptionsMenu(at: NSPoint(x: 10, y: view.bounds.height), in: view)
    }
}
