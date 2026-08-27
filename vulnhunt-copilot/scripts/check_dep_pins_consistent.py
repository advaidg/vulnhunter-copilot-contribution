#!/usr/bin/env python3
"""Assert vulnhunter-fix's runtime dependency pins are identical across the
shared install-helper files.

install.sh and install-copilot.sh both source _install_common.sh; install.cmd
and install-copilot.cmd both call into _install_common.cmd -- both shared
files define their own VULNFIX_DEPS (the venv the install scripts build for
vulnhunter-fix bundles jsonschema and graphifyy at a pinned version range).
Each file's comments say to keep the two in sync by hand -- nothing enforced
it. This is a case where duplicating a value across a .sh and a .cmd file is
unavoidable (there's no single syntax both can source), as long as something
catches the two copies drifting apart. This is that something -- run in CI
on every PR.

Usage:
    check_dep_pins_consistent.py <repo-root>
"""

from __future__ import annotations

import re
import sys
from pathlib import Path

# One regex per file, each capturing the exact pin list text so a
# byte-for-byte comparison is possible despite the surrounding syntax
# differing (bash array literal vs. cmd `set` with quoted tokens).
FILES: dict[str, re.Pattern[str]] = {
    "_install_common.sh": re.compile(r'^VULNFIX_DEPS=\((.+)\)$', re.MULTILINE),
    "_install_common.cmd": re.compile(r'^set VULNFIX_DEPS=(.+)$', re.MULTILINE),
}


def extract_pins(text: str, pattern: re.Pattern[str]) -> list[str]:
    match = pattern.search(text)
    if not match:
        return []
    # Both syntaxes are space-separated "package>=x.y" tokens, each
    # double-quoted -- strip quotes and split on whitespace to get a
    # comparable, order-sensitive list of pin strings.
    return [tok.strip('"') for tok in match.group(1).split()]


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: check_dep_pins_consistent.py <repo-root>", file=sys.stderr)
        return 2
    repo_root = Path(sys.argv[1])

    pins_by_file: dict[str, list[str]] = {}
    for relpath, pattern in FILES.items():
        target = repo_root / relpath
        if not target.is_file():
            print(f"error: {target} not found", file=sys.stderr)
            return 1
        pins = extract_pins(target.read_text(encoding="utf-8"), pattern)
        if not pins:
            print(f"error: could not find VULNFIX_DEPS in {relpath}", file=sys.stderr)
            return 1
        pins_by_file[relpath] = pins

    reference_file, reference_pins = next(iter(pins_by_file.items()))
    mismatches = {
        relpath: pins
        for relpath, pins in pins_by_file.items()
        if pins != reference_pins
    }
    if mismatches:
        print(
            f"error: vulnhunter-fix dependency pins have drifted apart between "
            f"the shared install-helper files. {reference_file} has "
            f"{reference_pins!r}; mismatched file(s):",
            file=sys.stderr,
        )
        for relpath, pins in mismatches.items():
            print(f"  {relpath}: {pins!r}", file=sys.stderr)
        print(
            "Update both _install_common.sh and _install_common.cmd's "
            "VULNFIX_DEPS to match, then re-run.",
            file=sys.stderr,
        )
        return 1

    print(f"Both shared install-helper files agree: {reference_pins!r}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
