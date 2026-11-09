#!/usr/bin/env python3
"""Copy OrigamiVerse Core (shared-core/addons/origamiverse_core) into every app.

Usage:
  python tools/sync_core.py          # copy the core into apps/*/addons/origamiverse_core
  python tools/sync_core.py --check  # exit 1 if any app copy differs from the source

The app copies are committed so each Godot project opens on its own, but they must never be
edited by hand. The --check mode runs in CI-style validation and in the Kiro hook.
"""
from __future__ import annotations


import hashlib
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / "shared-core" / "addons" / "origamiverse_core"
APPS = ["foldshift", "paperverse"]
IGNORED_SUFFIXES = {".tmp"}


def files(base: Path) -> dict[str, str]:
    out: dict[str, str] = {}
    for p in sorted(base.rglob("*")):
        if p.is_file() and p.suffix not in IGNORED_SUFFIXES:
            out[p.relative_to(base).as_posix()] = hashlib.sha256(p.read_bytes()).hexdigest()
    return out


def check() -> int:
    src = files(SOURCE)
    bad = 0
    for app in APPS:
        dst_dir = ROOT / "apps" / app / "addons" / "origamiverse_core"
        if not dst_dir.exists():
            print(f"[drift] {app}: core missing")
            bad += 1
            continue
        dst = files(dst_dir)
        for rel, digest in src.items():
            if dst.get(rel) != digest:
                print(f"[drift] {app}: {rel} differs or is missing")
                bad += 1
        for rel in dst.keys() - src.keys():
            print(f"[drift] {app}: extra file {rel}")
            bad += 1
    if bad == 0:
        print(f"OK: {len(src)} core files identical in {', '.join(APPS)}")
    return 1 if bad else 0


def sync() -> int:
    for app in APPS:
        app_dir = ROOT / "apps" / app
        if not app_dir.exists():
            continue
        dst = app_dir / "addons" / "origamiverse_core"
        if dst.exists():
            # Remove stale files first so deletions in the core propagate.
            for p in sorted(dst.rglob("*"), reverse=True):
                if p.is_file() and p.suffix not in IGNORED_SUFFIXES:
                    p.unlink()
        shutil.copytree(SOURCE, dst, dirs_exist_ok=True,
                        ignore=shutil.ignore_patterns(*[f"*{s}" for s in IGNORED_SUFFIXES]))
        # Remove now-empty folders left behind by deleted core files.
        for p in sorted(dst.rglob("*"), reverse=True):
            if p.is_dir() and not any(p.iterdir()):
                p.rmdir()
        print(f"synced core -> apps/{app}")
    return check()


if __name__ == "__main__":
    sys.exit(check() if "--check" in sys.argv else sync())
