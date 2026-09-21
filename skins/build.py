#!/usr/bin/env python3
"""Build one skin, or all of them.

::

    python3 skins/build.py base
    python3 skins/build.py base walnut76
    python3 skins/build.py --all
    python3 skins/build.py base --no-preview

Each skin lives in ``skins/<name>/`` and must contain a ``theme.py`` that
defines ``THEME = SomeTheme()``.  Building writes

* ``skins/<name>/out/``       -- the loose sheets and text files
* ``skins/dist/<Name>.wsz``   -- the flat, deflated archive the app loads
* ``skins/<name>/preview/``   -- mocked-up window PNGs at 1x and 4x

and then runs the validator.  Exit status is non-zero if anything failed.
"""

from __future__ import annotations

import argparse
import importlib.util
import sys
import traceback
from pathlib import Path

SKINS = Path(__file__).resolve().parent
if str(SKINS) not in sys.path:
    sys.path.insert(0, str(SKINS))

from skinkit import builder, preview, validate as validate_mod  # noqa: E402


def load_theme(folder: Path):
    """Import ``<folder>/theme.py`` and return its ``THEME``."""
    theme_py = folder / "theme.py"
    if not theme_py.is_file():
        raise FileNotFoundError(f"{folder.name}: no theme.py")
    mod_name = f"_skin_{folder.name}"
    spec_ = importlib.util.spec_from_file_location(mod_name, theme_py)
    if spec_ is None or spec_.loader is None:  # pragma: no cover
        raise ImportError(f"cannot load {theme_py}")
    mod = importlib.util.module_from_spec(spec_)
    sys.modules[mod_name] = mod
    spec_.loader.exec_module(mod)
    if not hasattr(mod, "THEME"):
        raise AttributeError(f"{theme_py} must define THEME = SomeTheme()")
    return mod.THEME


#: Folders that hold a ``theme.py`` but are not skins.  ``skinkit`` is the
#: toolkit package itself -- its ``theme.py`` defines the Theme base class, not
#: a THEME instance, so ``--all`` must not try to build it.
NOT_SKINS = {"skinkit", "dist"}


def skin_folders() -> list[Path]:
    return sorted(p for p in SKINS.iterdir()
                  if p.is_dir() and p.name not in NOT_SKINS
                  and (p / "theme.py").is_file())


def build_one(folder: Path, do_preview: bool = True, do_validate: bool = True) -> bool:
    print(f"[{folder.name}]")
    try:
        theme = load_theme(folder)
    except Exception:
        traceback.print_exc()
        return False
    try:
        result = builder.build_skin(theme, folder)
    except Exception:
        traceback.print_exc()
        return False
    ok = True
    if do_preview:
        try:
            preview.render_previews(folder / "out", folder / "preview")
            print(f"  previews -> {folder / 'preview'}")
        except Exception:
            traceback.print_exc()
            ok = False
    if do_validate:
        for target in (folder / "out", result.wsz):
            problems = validate_mod.validate(target, require_plfont=True)
            for msg in getattr(problems, "warnings", []):
                print(f"  warn {target.name}: {msg}")
            if problems:
                ok = False
                print(f"  FAIL {target} ({len(problems)} problem(s))")
                for msg in problems:
                    print(f"    - {msg}")
            else:
                print(f"  OK   {target}")
    return ok


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Build Tokenamp skins with skinkit.")
    ap.add_argument("names", nargs="*", help="skin folder names under skins/")
    ap.add_argument("--all", action="store_true", help="build every folder with a theme.py")
    ap.add_argument("--no-preview", action="store_true")
    ap.add_argument("--no-validate", action="store_true")
    args = ap.parse_args(argv)

    if args.all:
        folders = skin_folders()
    elif args.names:
        folders = [SKINS / n for n in args.names]
    else:
        ap.error("give one or more skin folder names, or --all")
        return 2
    if not folders:
        print("no skins to build", file=sys.stderr)
        return 1

    failed = []
    for folder in folders:
        if not folder.is_dir():
            print(f"[{folder.name}] no such folder: {folder}", file=sys.stderr)
            failed.append(folder.name)
            continue
        if not build_one(folder, not args.no_preview, not args.no_validate):
            failed.append(folder.name)
    if failed:
        print(f"\nFAILED: {', '.join(failed)}", file=sys.stderr)
        return 1
    print("\nall good")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
