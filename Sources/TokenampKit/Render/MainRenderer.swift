import CoreGraphics
import Foundation
import UsageModel

/// Draws the 275x116 main window and the 275x14 window-shade strip into any `SkinCanvas`.
/// Pure: no AppKit, no timers, no state of its own. The live `NSView` and `--snapshot` both
/// call straight into here, which is why what you see on screen is what lands in the PNG.
public enum MainRenderer {

    // MARK: - Main window

    /// True when `r` touches the rect the window asked us to repaint. During an animation frame
    /// the dirty rect is a few pixels wide, so most of the window is skipped outright.
    @inline(__always)
    static func needs(_ r: SpriteRect, _ state: ViewState) -> Bool {
        guard let d = state.dirtyRect else { return true }
        return r.x < d.x + d.w && d.x < r.x + r.w && r.y < d.y + d.h && d.y < r.y + r.h
    }

    public static func draw(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        let L = Layout.Main.self
        let font = skin.font

        // The background is always drawn; CoreGraphics clips it to the dirty rect for us.
        c.draw(skin.image(Spr.MAIN_WINDOW_BACKGROUND), at: SpriteRect(0, 0, L.size.w, L.size.h))

        if needs(L.titleBar, state) {
            c.draw(skin.image(state.mainIsKey ? Spr.MAIN_TITLE_BAR_SELECTED : Spr.MAIN_TITLE_BAR), at: L.titleBar)
            // Title-bar buttons: their normal state is baked into the title bar, only the pressed
            // sprite is overlaid (classic Winamp behaviour).
            if state.isPressed(.optionsButton) { c.draw(skin.image(Spr.MAIN_OPTIONS_BUTTON_DEPRESSED), at: L.optionsButton) }
            if state.isPressed(.minimizeButton) { c.draw(skin.image(Spr.MAIN_MINIMIZE_BUTTON_DEPRESSED), at: L.minimizeButton) }
            if state.isPressed(.shadeButton) { c.draw(skin.image(Spr.MAIN_SHADE_BUTTON_DEPRESSED), at: L.shadeButton) }
            if state.isPressed(.closeButton) { c.draw(skin.image(Spr.MAIN_CLOSE_BUTTON_DEPRESSED), at: L.closeButton) }
        }

        if needs(L.clutterBar, state) { drawClutterBar(c, skin: skin, state: state) }
        if needs(L.workIndicator, state) || needs(L.playPauseIndicator, state) {
            drawIndicators(c, skin: skin, snapshot: snapshot, state: state)
        }
        if needs(L.timeClickZone, state) { drawTime(c, skin: skin, snapshot: snapshot, state: state) }
        if needs(L.marquee, state) { drawMarquee(c, font: font, state: state) }
        if needs(L.kbps, state) || needs(L.khz, state) { drawFields(c, font: font, snapshot: snapshot) }
        if needs(L.mono, state) || needs(L.stereo, state) {
            drawLamps(c, skin: skin, snapshot: snapshot, state: state)
        }
        if needs(L.visualizer, state) { VisualizerRenderer.draw(c, skin: skin, state: state) }
        if needs(L.volume, state) || needs(L.balance, state) {
            drawGauges(c, skin: skin, snapshot: snapshot, state: state)
        }
        if needs(L.eqButton, state) || needs(L.plButton, state) { drawToggleButtons(c, skin: skin, state: state) }
        if needs(L.posbar, state) { drawPositionBar(c, skin: skin, snapshot: snapshot, state: state) }
        if needs(SpriteRect(L.previous.x, L.previous.y, L.`repeat`.x + L.`repeat`.w - L.previous.x,
                            L.previous.h), state) {
            drawTransport(c, skin: skin, state: state)
        }
    }

    private static func drawClutterBar(_ c: SkinCanvas, skin: Skin, state: ViewState) {
        for (letter, rect) in Layout.Main.clutterButtons {
            let lit = state.isPressed(.clutter(letter)) || state.latchedClutter.contains(letter)
            guard lit else { continue }
            guard let ref = SkinSpec.ref(.titlebar, "MAIN_CLUTTER_BAR_BUTTON_\(letter)_SELECTED") else { continue }
            c.draw(skin.image(ref), at: rect)
        }
    }

    private static func drawIndicators(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        let indicator: SpriteRef
        switch state.playState {
        case .playing: indicator = Spr.MAIN_PLAYING_INDICATOR
        case .paused: indicator = Spr.MAIN_PAUSED_INDICATOR
        case .stopped: indicator = Spr.MAIN_STOPPED_INDICATOR
        }
        c.draw(skin.image(indicator), at: Layout.Main.playPauseIndicator)
        // The work LED goes on top: it is the thing that blinks when data lands.
        c.draw(skin.image(state.workLED ? Spr.MAIN_WORKING_INDICATOR : Spr.MAIN_NOT_WORKING_INDICATOR),
               at: Layout.Main.workIndicator)
    }

    private static func drawTime(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        let hero = HeroTrack.hero(in: snapshot, index: state.heroIndex)
        let readout = TimeFormatting.readout(hero: hero, mode: state.timeMode, now: state.now)
        let glyphs = Array(readout.glyphs)
        for (i, rect) in Layout.Main.digits.enumerated() where i < glyphs.count {
            c.draw(skin.digitSprite(glyphs[i]), at: rect)
        }
        // Minus sign: a full 9x13 cell on nums_ex, a 5x1 strip on legacy numbers.bmp.
        if skin.hasExtendedDigits {
            c.draw(skin.digitSprite(readout.minus ? "-" : " "), at: Layout.Main.minusSignEx)
        } else if let ref = SkinSpec.ref(.numbers, readout.minus ? "MINUS_SIGN" : "NO_MINUS_SIGN") {
            c.draw(skin.image(ref), at: Layout.Main.minusSignLegacy)
        }
    }

    private static func drawMarquee(_ c: SkinCanvas, font: BitmapFont, state: ViewState) {
        let rect = Layout.Main.marquee
        guard !state.marqueeText.isEmpty else { return }
        c.save()
        c.clip(to: rect)
        for g in Marquee.visibleGlyphs(text: state.marqueeText, offset: state.marqueeOffset, width: rect.w) {
            if let img = font.glyph(g.character) {
                c.draw(img, in: CGRect(x: CGFloat(rect.x + g.x), y: CGFloat(rect.y),
                                       width: CGFloat(BitmapFont.glyphWidth), height: CGFloat(BitmapFont.glyphHeight)))
            }
        }
        c.restore()
    }

    private static func drawFields(_ c: SkinCanvas, font: BitmapFont, snapshot: UsageSnapshot) {
        // kbps = burn rate in thousands of fresh tokens per minute, right-aligned, capped 999.
        let k = min(999, max(0, Int((snapshot.burnTokensPerMin / 1000).rounded())))
        c.textRightAligned("\(k)", font: font, x: Layout.Main.kbps.x, y: Layout.Main.kbps.y, glyphs: 3)
        // kHz = active sessions, capped 99.
        let a = min(99, max(0, snapshot.activeSessionCount))
        c.textRightAligned("\(a)", font: font, x: Layout.Main.khz.x, y: Layout.Main.khz.y, glyphs: 2)
    }

    private static func drawLamps(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        // mono lit = local transcripts only; stereo lit = live account data OK; neither when
        // paused or stopped (SPEC 2.1).
        let running = state.playState == .playing
        let liveOK = running && snapshot.liveStatus.isOK
        let localOnly = running && !liveOK
        c.draw(skin.image(localOnly ? Spr.MAIN_MONO_SELECTED : Spr.MAIN_MONO), at: Layout.Main.mono)
        c.draw(skin.image(liveOK ? Spr.MAIN_STEREO_SELECTED : Spr.MAIN_STEREO), at: Layout.Main.stereo)
    }

    private static func drawGauges(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        let L = Layout.Main.self
        if let v = Sliders.volume(snapshot) {
            c.draw(skin.frame(.volume, v.frame), at: L.volume)
            let pressed = state.isPressed(.volume)
            c.draw(skin.image(pressed ? Spr.MAIN_VOLUME_THUMB_SELECTED : Spr.MAIN_VOLUME_THUMB),
                   at: SpriteRect(v.thumbX, L.volumeThumbY, 14, 11))
        } else {
            c.draw(skin.frame(.volume, 0), at: L.volume)
        }
        if let b = Sliders.balance(snapshot) {
            c.draw(skin.frame(.balance, b.frame), at: L.balance)
            let pressed = state.isPressed(.balance)
            c.draw(skin.image(pressed ? Spr.MAIN_BALANCE_THUMB_SELECTED : Spr.MAIN_BALANCE_THUMB),
                   at: SpriteRect(b.thumbX, L.balanceThumbY, 14, 11))
        } else {
            c.draw(skin.frame(.balance, 0), at: L.balance)
        }
    }

    private static func drawToggleButtons(_ c: SkinCanvas, skin: Skin, state: ViewState) {
        let eqRef: SpriteRef
        switch (state.eqOpen, state.isPressed(.eqToggle)) {
        case (true, true): eqRef = Spr.MAIN_EQ_BUTTON_DEPRESSED_SELECTED
        case (true, false): eqRef = Spr.MAIN_EQ_BUTTON_SELECTED
        case (false, true): eqRef = Spr.MAIN_EQ_BUTTON_DEPRESSED
        case (false, false): eqRef = Spr.MAIN_EQ_BUTTON
        }
        c.draw(skin.image(eqRef), at: Layout.Main.eqButton)

        let plRef: SpriteRef
        switch (state.plOpen, state.isPressed(.plToggle)) {
        case (true, true): plRef = Spr.MAIN_PLAYLIST_BUTTON_DEPRESSED_SELECTED
        case (true, false): plRef = Spr.MAIN_PLAYLIST_BUTTON_SELECTED
        case (false, true): plRef = Spr.MAIN_PLAYLIST_BUTTON_DEPRESSED
        case (false, false): plRef = Spr.MAIN_PLAYLIST_BUTTON
        }
        c.draw(skin.image(plRef), at: Layout.Main.plButton)
    }

    private static func drawPositionBar(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        c.draw(skin.image(Spr.MAIN_POSITION_SLIDER_BACKGROUND), at: Layout.Main.posbar)
        guard let p = Sliders.position(snapshot, heroIndex: state.heroIndex, now: state.now) else { return }
        let ref = state.isPressed(.posbar) ? Spr.MAIN_POSITION_SLIDER_THUMB_SELECTED : Spr.MAIN_POSITION_SLIDER_THUMB
        c.draw(skin.image(ref), at: SpriteRect(p.thumbX, Layout.Main.posbar.y, 29, 10))
    }

    private static func drawTransport(_ c: SkinCanvas, skin: Skin, state: ViewState) {
        let L = Layout.Main.self
        let buttons: [(ControlID, SpriteRef, SpriteRef, SpriteRect)] = [
            (.previous, Spr.MAIN_PREVIOUS_BUTTON, Spr.MAIN_PREVIOUS_BUTTON_ACTIVE, L.previous),
            (.play, Spr.MAIN_PLAY_BUTTON, Spr.MAIN_PLAY_BUTTON_ACTIVE, L.play),
            (.pause, Spr.MAIN_PAUSE_BUTTON, Spr.MAIN_PAUSE_BUTTON_ACTIVE, L.pause),
            (.stop, Spr.MAIN_STOP_BUTTON, Spr.MAIN_STOP_BUTTON_ACTIVE, L.stop),
            (.next, Spr.MAIN_NEXT_BUTTON, Spr.MAIN_NEXT_BUTTON_ACTIVE, L.next),
            (.eject, Spr.MAIN_EJECT_BUTTON, Spr.MAIN_EJECT_BUTTON_ACTIVE, L.eject),
        ]
        for (id, normal, active, rect) in buttons {
            c.draw(skin.image(state.isPressed(id) ? active : normal), at: rect)
        }

        let shuffle: SpriteRef
        switch (state.shuffleOn, state.isPressed(.shuffle)) {
        case (true, true): shuffle = Spr.MAIN_SHUFFLE_BUTTON_SELECTED_DEPRESSED
        case (true, false): shuffle = Spr.MAIN_SHUFFLE_BUTTON_SELECTED
        case (false, true): shuffle = Spr.MAIN_SHUFFLE_BUTTON_DEPRESSED
        case (false, false): shuffle = Spr.MAIN_SHUFFLE_BUTTON
        }
        c.draw(skin.image(shuffle), at: L.shuffle)

        let rep: SpriteRef
        switch (state.repeatOn, state.isPressed(.repeatToggle)) {
        case (true, true): rep = Spr.MAIN_REPEAT_BUTTON_SELECTED_DEPRESSED
        case (true, false): rep = Spr.MAIN_REPEAT_BUTTON_SELECTED
        case (false, true): rep = Spr.MAIN_REPEAT_BUTTON_DEPRESSED
        case (false, false): rep = Spr.MAIN_REPEAT_BUTTON
        }
        c.draw(skin.image(rep), at: L.`repeat`)
    }

    // MARK: - Window shade (SPEC 2.2)

    public static func drawShade(_ c: SkinCanvas, skin: Skin, snapshot: UsageSnapshot, state: ViewState) {
        let L = Layout.Shade.self
        c.draw(skin.image(state.mainIsKey ? Spr.MAIN_SHADE_BACKGROUND_SELECTED : Spr.MAIN_SHADE_BACKGROUND),
               at: SpriteRect(0, 0, L.size.w, L.size.h))

        if state.isPressed(.optionsButton) { c.draw(skin.image(Spr.MAIN_OPTIONS_BUTTON_DEPRESSED), at: L.optionsButton) }
        if state.isPressed(.minimizeButton) { c.draw(skin.image(Spr.MAIN_MINIMIZE_BUTTON_DEPRESSED), at: L.minimizeButton) }
        c.draw(skin.image(state.isPressed(.shadeButton) ? Spr.MAIN_SHADE_BUTTON_SELECTED_DEPRESSED
                                                        : Spr.MAIN_SHADE_BUTTON_SELECTED), at: L.shadeButton)
        if state.isPressed(.closeButton) { c.draw(skin.image(Spr.MAIN_CLOSE_BUTTON_DEPRESSED), at: L.closeButton) }

        VisualizerRenderer.drawMini(c, skin: skin, state: state)

        // Hero countdown as four text-font glyphs.
        let hero = HeroTrack.hero(in: snapshot, index: state.heroIndex)
        let readout = TimeFormatting.readout(hero: hero, mode: state.timeMode, now: state.now)
        let glyphs = Array(readout.glyphs)
        let font = skin.font
        for (i, pos) in L.timeGlyphs.enumerated() where i < glyphs.count {
            c.text(String(glyphs[i]), font: font, x: pos.x, y: pos.y)
        }

        // Mini position bar: 17x7 well, 3 px thumb whose sprite is the left/centre/right third.
        c.draw(skin.image(Spr.MAIN_SHADE_POSITION_BACKGROUND), at: L.position)
        if let p = Sliders.position(snapshot, heroIndex: state.heroIndex, now: state.now) {
            let s = Sliders.shadePosition(fraction: p.fraction)
            let ref: SpriteRef
            switch s.piece {
            case .left: ref = Spr.MAIN_SHADE_POSITION_THUMB_LEFT
            case .centre: ref = Spr.MAIN_SHADE_POSITION_THUMB
            case .right: ref = Spr.MAIN_SHADE_POSITION_THUMB_RIGHT
            }
            c.draw(skin.image(ref), at: SpriteRect(s.x, L.position.y, 3, 7))
        }
    }

    // MARK: - Hit regions

    public static func mainRegions() -> [HitRegion] {
        let L = Layout.Main.self
        var out: [HitRegion] = [
            HitRegion(.optionsButton, L.optionsButton),
            HitRegion(.minimizeButton, L.minimizeButton),
            HitRegion(.shadeButton, L.shadeButton),
            HitRegion(.closeButton, L.closeButton),
        ]
        for (letter, rect) in L.clutterButtons { out.append(HitRegion(.clutter(letter), rect)) }
        out += [
            HitRegion(.timeDisplay, L.timeClickZone, showsPressed: false),
            HitRegion(.visualizer, L.visualizer, showsPressed: false, hasHoverReading: true),
            HitRegion(.marquee, L.marquee, showsPressed: false),
            HitRegion(.kbps, L.kbps, showsPressed: false, hasHoverReading: true),
            HitRegion(.khz, L.khz, showsPressed: false, hasHoverReading: true),
            HitRegion(.monoster, SpriteRect(L.mono.x, L.mono.y, L.stereo.x + L.stereo.w - L.mono.x, L.mono.h),
                      showsPressed: false, hasHoverReading: true),
            HitRegion(.volume, L.volume, hasHoverReading: true),
            HitRegion(.balance, L.balance, hasHoverReading: true),
            HitRegion(.eqToggle, L.eqButton),
            HitRegion(.plToggle, L.plButton),
            HitRegion(.posbar, L.posbar, hasHoverReading: true),
            HitRegion(.previous, L.previous),
            HitRegion(.play, L.play),
            HitRegion(.pause, L.pause),
            HitRegion(.stop, L.stop),
            HitRegion(.next, L.next),
            HitRegion(.eject, L.eject),
            HitRegion(.shuffle, L.shuffle),
            HitRegion(.repeatToggle, L.`repeat`),
            HitRegion(.aboutLogo, L.aboutLogo, showsPressed: false),
            HitRegion(.titleBar, L.titleBar, showsPressed: false, dragsWindow: true),
            // SPEC 2.1: the whole background drags too (but does not toggle shade).
            HitRegion(.background, SpriteRect(0, 0, L.size.w, L.size.h), showsPressed: false, dragsWindow: true),
        ]
        return out
    }

    public static func shadeRegions() -> [HitRegion] {
        let L = Layout.Shade.self
        return [
            HitRegion(.optionsButton, L.optionsButton),
            HitRegion(.minimizeButton, L.minimizeButton),
            HitRegion(.shadeButton, L.shadeButton),
            HitRegion(.closeButton, L.closeButton),
            HitRegion(.visualizer, L.miniVisualizer, showsPressed: false, hasHoverReading: true),
            HitRegion(.previous, L.previous, showsPressed: false),
            HitRegion(.play, L.play, showsPressed: false),
            HitRegion(.pause, L.pause, showsPressed: false),
            HitRegion(.stop, L.stop, showsPressed: false),
            HitRegion(.next, L.next, showsPressed: false),
            HitRegion(.eject, L.eject, showsPressed: false),
            HitRegion(.posbar, L.position, showsPressed: false, hasHoverReading: true),
            HitRegion(.titleBar, SpriteRect(0, 0, L.size.w, L.size.h), showsPressed: false, dragsWindow: true),
        ]
    }
}
