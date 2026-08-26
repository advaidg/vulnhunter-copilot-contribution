#!/usr/bin/env python3
"""Detect base-file changes that a full-file overlay in vulnhunt-copilot/
hasn't been re-synced against.

apply_substitutions.py closes this gap for the handful of tiny, well-defined
wording deltas it covers. It deliberately doesn't cover the overlay files
that genuinely diverge from base by a lot (SKILL.md, phase2_hunt.md) or by a
little for reasons other than tool-name wording (phase1_recon.md,
phase0_preflight.md, phase2_verify.md, phase3d_sweep.md, phase2_shared.md,
phase3_reproduce_test.md, parse_issues.md, phase4_emit.md) -- those still
exist as full files in vulnhunt-copilot/skills/. If someone fixes a bug in
one of those files' base counterpart and doesn't know (or forgets) that a
Copilot overlay of the same file exists, nothing previously caught that: the
overlay would keep serving the old, buggy content to every Copilot user
indefinitely.

This script pins the base file's content hash at the time each overlay file
was last deliberately synced (overlay_base_hashes.json) and fails if the
live base file's hash has since changed -- the same "fail loud, don't
silently drift" principle apply_substitutions.py uses, applied to overlay
files instead of substitution rules.

This does NOT mean every base change forces an overlay update -- most base
changes won't affect wording this overlay file actually diverges on. It
means a human has to look at the diff and make that call, instead of the
base and overlay silently disagreeing forever.

Usage:
    check_overlay_freshness.py <repo-root>              # verify (CI mode)
    check_overlay_freshness.py --generate <repo-root>   # regenerate the
                                                         # manifest after
                                                         # confirming each
                                                         # overlay file still
                                                         # reflects its base
"""

from __future__ import annotations

import hashlib
import json
import sys
from pathlib import Path

MANIFEST_NAME = "overlay_base_hashes.json"
SKILL_NAMES = ("vulnhunt", "vulnhunter-fix", "vulnhunt-fix-verify")


def sha256_of(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def discover_overlay_files(repo_root: Path) -> dict[str, Path]:
    """Map "skill/relpath" -> base file Path, for every overlay file that has
    a same-relative-path base counterpart. Files without a base counterpart
    (e.g. schema files copied in from elsewhere at install time) are not
    this script's concern -- there's nothing to drift against."""
    found: dict[str, Path] = {}
    for skill in SKILL_NAMES:
        overlay_root = repo_root / "vulnhunt-copilot" / "skills" / skill
        if not overlay_root.is_dir():
            continue
        for overlay_file in sorted(overlay_root.rglob("*")):
            if not overlay_file.is_file():
                continue
            relpath = overlay_file.relative_to(overlay_root)
            base_file = repo_root / skill / relpath
            if base_file.is_file():
                found[f"{skill}/{relpath.as_posix()}"] = base_file
    return found


def main() -> int:
    args = sys.argv[1:]
    generate = "--generate" in args
    args = [a for a in args if a != "--generate"]
    if len(args) != 1:
        print(
            "usage: check_overlay_freshness.py [--generate] <repo-root>",
            file=sys.stderr,
        )
        return 2
    repo_root = Path(args[0])
    manifest_path = Path(__file__).resolve().parent / MANIFEST_NAME

    overlay_files = discover_overlay_files(repo_root)
    if not overlay_files:
        print("error: no overlay files with a base counterpart found -- unexpected", file=sys.stderr)
        return 1

    if generate:
        manifest = {key: sha256_of(base) for key, base in overlay_files.items()}
        manifest_path.write_text(
            json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8"
        )
        print(f"wrote {len(manifest)} base-file hash(es) to {manifest_path}")
        print(
            "Only run this after confirming each changed overlay file's base "
            "counterpart was actually reviewed and (if needed) the overlay was "
            "updated to match -- this command trusts you, it doesn't verify."
        )
        return 0

    if not manifest_path.is_file():
        print(f"error: {manifest_path} not found -- run with --generate first", file=sys.stderr)
        return 1
    manifest: dict[str, str] = json.loads(manifest_path.read_text(encoding="utf-8"))

    had_error = False
    for key, base in sorted(overlay_files.items()):
        recorded = manifest.get(key)
        if recorded is None:
            print(
                f"error: {key} has an overlay file but no recorded base hash in "
                f"{MANIFEST_NAME} -- run check_overlay_freshness.py --generate "
                f"after confirming the overlay reflects the current base file.",
                file=sys.stderr,
            )
            had_error = True
            continue
        current = sha256_of(base)
        if current != recorded:
            print(
                f"error: {key}'s base file has changed since its Copilot overlay "
                f"was last synced (recorded {recorded[:12]}..., now {current[:12]}...). "
                f"Review the diff to {base}, update "
                f"vulnhunt-copilot/skills/{key} if the change affects it, then "
                f"run check_overlay_freshness.py --generate to record the new hash.",
                file=sys.stderr,
            )
            had_error = True

    if had_error:
        return 1
    print(f"All {len(overlay_files)} overlay file(s) match their recorded base hash.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
