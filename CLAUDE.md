# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

Tokenamp is a native Swift/AppKit macOS app that shows Claude plan usage as a Winamp 2.x player
with real classic `.wsz` skin support. `docs/SPEC.md` is the contract for everything; its
amendments (A1–A6) at the top override older text and older code. Read the relevant SPEC section
before changing behaviour.

## Toolchain

Command Line Tools only: **no Xcode, no XCTest, no xcodebuild**. The `.app` is assembled by hand
and ad-hoc signed. Python 3 with `numpy` and `Pillow` for the skins.

## Commands

```sh
scripts/build_app.sh [--debug]            # swift build (scratch .build-app) -> build/Tokenamp.app
build/Tokenamp.app/Contents/MacOS/Tokenamp --demo          # run on deterministic synthetic data

# Tests: suites are compiled into the binaries; each runs whole (no per-test filter).
build/Tokenamp.app/Contents/MacOS/Tokenamp --selftest      # UI/skin-engine logic
swift run usage-dump --selftest                            # data layer
cd skins && python3 -m skinkit.selftest                    # Python painting toolkit

# Visual verification: offscreen PNGs, no Screen Recording permission needed
build/Tokenamp.app/Contents/MacOS/Tokenamp --snapshot <dir> --demo --skin skins/dist/Walnut76.wsz --scale 2
#   writes main/eq/playlist/shade/all.png and one field-<configuration>.png per Token Flow mode;
#   --state pressed renders the alternate sprites; --at <unix-seconds> moves the demo clock

# Data layer without UI
swift run usage-dump --once | --json | --no-live

# Skins
python3 skins/build.py --all              # every skins/<name>/theme.py -> skins/dist/<Name>.wsz
python3 skins/build.py bookcloth          # one skin; writes out/, preview/, then validates
cd skins && python3 -m skinkit.validate dist/Base.wsz

# Generated code and docs images
python3 scripts/gen_sprites_swift.py [--check]   # sprites.json -> Sources/TokenampKit/Skin/Sprites.generated.swift
python3 scripts/make_screenshots.py              # README images from the built app (deterministic)
```

When building a single target in parallel with other work, give SwiftPM its own scratch path
(`swift build --scratch-path .build-<name> --target <Target>`); `.build*/` is gitignored.

## Architecture

**Target graph (`Package.swift`, keep it acyclic, do not restructure):**

- `UsageModel` — value types (`UsageSnapshot`), the `UsageProvider` protocol, `DemoUsageProvider`.
  No I/O. Treated as frozen.
- `UsageCore` — real data: `TranscriptScanner` over `~/.claude/projects` JSONL, `LimitsClient` for
  the OAuth usage endpoint, pricing, scan cache, FSEvents watcher → `LiveUsageProvider`.
- `TokenampKit` — skin engine, renderers, windows. Depends on `UsageModel` only, **never on
  `UsageCore`**.
- `Tokenamp` — the executable; `ProviderFactory.swift` is the only place `UsageCore` and
  `TokenampKit` meet (picks demo vs live provider, formats live diagnostics as plain strings).
- `usage-dump` — CLI over `UsageCore`.

No SwiftPM resources anywhere (`Bundle.module` breaks in a hand-assembled `.app`); skins are found
by `TokenampKit/Skin/ResourceLocator.swift` (`Contents/Resources/Skins`, else `$TOKENAMP_RESOURCES`,
else walk up to `skins/dist`).

**Usage → Winamp metaphor (SPEC §2):** each plan limit is a "track"; the hero track drives the time
display (countdown to reset), seek bar and marquee; volume/balance sliders are session/weekly
utilisation; the playlist window is "Sessions"; the equalizer is the "Usage Equalizer" (closed by
default). Token Flow (SPEC §2.9, §3.3) is a separate phosphor-field visualiser window with five
configurations (scope, strata, web, orbit, phase). Default layout: main → Sessions → Token Flow.

**TokenampKit layers:** `Logic/` holds pure models (docking, scale, sliders, marquee, visualiser,
field) that the selftest covers; `Render/` draws each window into a CGContext in skin pixels;
`UI/` owns the borderless `NSWindow`s, docking, menus, preferences; `App/` holds the controller,
argument parsing, `SelfTest.swift` and `SnapshotRunner.swift`.

**Skin pipeline:** `skinspec/sprites.json` is the single source of truth for every sprite rect and
window layout. It feeds both the Python toolkit (`skins/skinkit/spec.py`) and Swift (via the
generated `Sprites.generated.swift`). Never hand-type a coordinate that lives in the JSON, in
either language; edit the JSON, then re-run `gen_sprites_swift.py`. A skin is a `Theme` subclass in
`skins/<name>/theme.py` that paints widgets in *window* coordinates; `skinkit/builder.py` cuts them
into sheets and bakes normal states over a shared underlay (see `skins/skinkit/README.md`, the
artist's manual). Unoverridden painters fall back to Base, and Base is also the app's runtime
fallback for any sheet a third-party skin lacks.

## Rules that are easy to break

- **Data privacy:** the app only *reads* the `Claude Code-credentials` keychain item and never
  writes, refreshes or exchanges the token. From transcripts it parses only timestamp, message id,
  model, token counts and the session cwd; never read, print or store message content.
- **No system fonts inside skinned windows.** All text is bitmap: `text.bmp` for the classic
  face, and each skin's own `plfont` (SPEC §3.2, a Tokenamp extension) for Sessions rows.
- `gen.bmp` is a Tokenamp extension (Token Flow frame, exactly 152×50), not Winamp's sheet of that
  name; nothing may be baked into its title plate. Details in `skins/README.md`.
- Scale is device pixels per skin pixel with half steps on Retina and a screen-derived default
  (SPEC §2.8); render sprites with interpolation off, and watch the flipped-view image trap.
- `.wsz` builds are reproducible (fixed zip timestamps). A rebuild that leaves `git status` clean
  means the art did not change. A valid `skins/dist/*.wsz` only proves the last pack was good, so
  run `python3 skins/build.py --all` before trusting skin source.
- Skin art is judged by looking at snapshot/preview PNGs, not by reasoning about code. Behaviour
  and defaults are judged by launching the app (`defaults delete local.tokenamp.app` for a first run).
- The repo is public: check staged changes for secrets and personal details (home paths, emails,
  real session/project names) before pushing.
