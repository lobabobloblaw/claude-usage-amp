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
    /// A skin opened from Finder before the controller exists (see `application(_:open:)`).
    private var launchSkins = PendingSkinOpen()

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
        if let url = launchSkins.takeQueued() { c.loadSkin(at: url, install: true) }
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

    /// A double-clicked `.wsz` that launches the app arrives here *before*
    /// `applicationDidFinishLaunching`, while there is no controller yet; it waits and is applied
    /// once the controller has started, instead of being dropped.
    public func application(_ application: NSApplication, open urls: [URL]) {
        guard let url = launchSkins.receive(urls, ready: controller != nil) else { return }
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
        controller?.mainWindow.showOptionsMenuUnderButton()
    }
}

/// The skin a Finder open asks for, held until there is a controller to apply it. AppKit delivers
/// launch documents before `applicationDidFinishLaunching`; the last one opened wins.
struct PendingSkinOpen {
    private(set) var queued: URL?

    /// The skin among `urls` to apply now, or nil when there is none or it has been queued
    /// because the app is not `ready` yet.
    mutating func receive(_ urls: [URL], ready: Bool) -> URL? {
        guard let url = urls.first(where: { SkinCatalog.isSkinURL($0) }) else { return nil }
        guard ready else {
            queued = url
            return nil
        }
        return url
    }

    /// The queued skin, once; the queue is empty afterwards.
    mutating func takeQueued() -> URL? {
        defer { queued = nil }
        return queued
    }
}
