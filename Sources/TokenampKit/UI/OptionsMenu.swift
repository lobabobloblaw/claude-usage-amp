import AppKit
import Foundation

/// The options menu tree of SPEC 2.6, shown from the options button, clutterbar O, or a
/// right-click anywhere.
public enum OptionsMenu {

    public static func header(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    public static func build(app: TokenampController) -> NSMenu {
        let target = MenuTarget.shared
        target.app = app
        let menu = NSMenu()
        menu.autoenablesItems = false

        // Skins
        let skins = NSMenu()
        let entries = SkinCatalog.entries()
        let current = app.skin.name
        var sawBundled = false
        for e in entries where e.isBundled {
            sawBundled = true
            skins.addItem(target.item(e.name, #selector(MenuTarget.pickSkin(_:)), object: e.url.path,
                                      on: e.name == current))
        }
        let userEntries = entries.filter { !$0.isBundled }
        if sawBundled, !userEntries.isEmpty { skins.addItem(.separator()) }
        for e in userEntries {
            skins.addItem(target.item(e.name, #selector(MenuTarget.pickSkin(_:)), object: e.url.path,
                                      on: e.name == current))
        }
        if entries.isEmpty { skins.addItem(header("(no skins found)")) }
        skins.addItem(.separator())
        skins.addItem(target.item("Load Skin\u{2026}", #selector(MenuTarget.loadSkin)))
        skins.addItem(target.item("Open Skins Folder", #selector(MenuTarget.openSkinsFolder)))
        skins.addItem(target.item("Reload Current", #selector(MenuTarget.reloadSkin)))
        menu.addItem(submenu("Skins", skins))

        // Scale: exactly the scales that render as whole device pixels on this screen (SPEC 2.8).
        let scale = NSMenu()
        for s in ScaleModel.validPointScales(backing: app.backingFactor) {
            let item = target.item(ScaleModel.label(s), #selector(MenuTarget.pickScale(_:)), object: s,
                                   on: abs(app.scale - s) < 1e-9)
            item.toolTip = "\(ScaleModel.ppsp(points: s, backing: app.backingFactor)) device pixels per skin pixel"
            scale.addItem(item)
        }
        menu.addItem(submenu("Scale", scale))

        menu.addItem(target.item("Always on Top", #selector(MenuTarget.toggleAlwaysOnTop),
                                 on: app.prefs.alwaysOnTop))

        // Windows
        let windows = NSMenu()
        windows.addItem(target.item("Equalizer", #selector(MenuTarget.toggleEqualizer),
                                    on: app.equalizer?.window.isVisible ?? false))
        windows.addItem(target.item("Playlist", #selector(MenuTarget.togglePlaylist),
                                    on: app.playlist?.window.isVisible ?? false))
        windows.addItem(target.item("Token Flow", #selector(MenuTarget.toggleField),
                                    on: app.field?.isVisible ?? false))
        windows.addItem(target.item("Window Shade", #selector(MenuTarget.toggleShade),
                                    on: app.mainWindow?.isShade ?? false))
        menu.addItem(submenu("Windows", windows))

        // Visualizer
        let vis = NSMenu()
        for mode in VisualizerMode.allCases {
            vis.addItem(target.item(mode.title, #selector(MenuTarget.pickVisualizer(_:)), object: mode.rawValue,
                                    on: app.visualizerMode == mode))
        }
        menu.addItem(submenu("Visualizer", vis))

        // Data
        let data = NSMenu()
        data.addItem(target.item("Live Plan Limits", #selector(MenuTarget.toggleLive), on: app.prefs.liveEnabled))
        data.addItem(target.item("Refresh Now", #selector(MenuTarget.refreshNow)))
        let poll = NSMenu()
        for (title, seconds) in [("30 s", 30.0), ("1 min", 60.0), ("2 min", 120.0), ("5 min", 300.0)] {
            poll.addItem(target.item(title, #selector(MenuTarget.pickPoll(_:)), object: seconds,
                                     on: abs(app.prefs.pollInterval - seconds) < 0.5))
        }
        data.addItem(submenu("Poll Every", poll))
        let shows = NSMenu()
        shows.addItem(target.item("Cost", #selector(MenuTarget.showCost), on: app.prefs.playlistShowsCost))
        shows.addItem(target.item("Tokens", #selector(MenuTarget.showTokens), on: !app.prefs.playlistShowsCost))
        data.addItem(submenu("Playlist Shows", shows))
        let demo = target.item("Demo Data", #selector(MenuTarget.toggleDemo), on: app.isUsingDemoData)
        if !app.liveProviderAvailable {
            demo.isEnabled = false
            demo.toolTip = "The live data layer is not wired into this build yet."
        }
        data.addItem(demo)
        menu.addItem(submenu("Data", data))

        menu.addItem(target.item("Menu Bar Readout", #selector(MenuTarget.toggleMenuBar), on: app.prefs.menuBarReadout))
        menu.addItem(.separator())
        menu.addItem(target.item("About Tokenamp", #selector(MenuTarget.about)))
        menu.addItem(target.item("Quit", #selector(MenuTarget.quit)))
        return menu
    }

    private static func submenu(_ title: String, _ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = menu
        menu.autoenablesItems = false
        return item
    }
}

/// One long-lived target for every options-menu item. `NSMenu` does not retain its target, so a
/// per-invocation object would be deallocated before the click arrives.
final class MenuTarget: NSObject {
    static let shared = MenuTarget()
    weak var app: TokenampController?

    func item(_ title: String, _ action: Selector, object: Any? = nil, on: Bool = false) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.representedObject = object
        i.state = on ? .on : .off
        i.isEnabled = true
        return i
    }

    @objc func pickSkin(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        app?.loadSkin(at: URL(fileURLWithPath: path), install: false)
    }

    @objc func loadSkin() { app?.presentLoadSkinPanel() }
    @objc func openSkinsFolder() { app?.openSkinsFolder() }
    @objc func reloadSkin() { app?.reloadSkin() }

    @objc func pickScale(_ sender: NSMenuItem) {
        guard let n = sender.representedObject as? Double else { return }
        app?.setScale(n)
    }

    @objc func toggleAlwaysOnTop() { app?.toggleAlwaysOnTop() }
    @objc func toggleEqualizer() { app?.toggleEqualizer() }
    @objc func togglePlaylist() { app?.togglePlaylist() }
    @objc func toggleShade() { app?.toggleShade() }
    @objc func toggleField() { app?.toggleField() }

    @objc func pickVisualizer(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let m = VisualizerMode(rawValue: raw) else { return }
        app?.setVisualizerMode(m)
    }

    @objc func toggleLive() {
        guard let app else { return }
        app.setLiveEnabled(!app.prefs.liveEnabled)
    }

    @objc func refreshNow() { app?.refreshNow() }

    @objc func pickPoll(_ sender: NSMenuItem) {
        guard let s = sender.representedObject as? Double else { return }
        app?.setPollInterval(s)
    }

    @objc func showCost() { app?.setPlaylistShowsCost(true) }
    @objc func showTokens() { app?.setPlaylistShowsCost(false) }

    @objc func toggleDemo() {
        guard let app else { return }
        app.setDemoData(!app.isUsingDemoData)
    }

    @objc func toggleMenuBar() {
        guard let app else { return }
        app.setMenuBarReadout(!app.prefs.menuBarReadout)
    }

    @objc func about() { app?.showAbout() }
    @objc func quit() { app?.quit() }
}
