#!/bin/bash
set -e

# HOME guard: destinations (and the rm -rf below) derive from HOME. An empty
# HOME turns "rm -rf $dst" into "rm -rf /.copilot/..." — refuse cleanly.
if [ -z "${HOME:-}" ]; then
    echo "error: HOME unset — refusing to run install-copilot.sh" >&2
    exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILLS_PARENT="$HOME/.copilot/skills"

# vulnhunter-fix runtime deps. Same pin as install.sh's VULNFIX_DEPS —
# keep the two in sync (see preflight.py REQ-GRA-001).
VULNFIX_DEPS=("jsonschema>=4.18" "graphifyy>=0.8.14,<0.9.0")

find_python() {
    if command -v python3.11 >/dev/null 2>&1; then
        command -v python3.11; return 0
    fi
    for candidate in \
        /opt/homebrew/opt/python@3.11/bin/python3.11 \
        /usr/local/opt/python@3.11/bin/python3.11 \
        /usr/bin/python3.11; do
        if [ -x "$candidate" ]; then echo "$candidate"; return 0; fi
    done
    for cand in python3.13 python3.12 python3; do
        if command -v "$cand" >/dev/null 2>&1 && \
           "$cand" -c 'import sys; sys.exit(0 if sys.version_info[:2] >= (3,11) else 1)' 2>/dev/null; then
            command -v "$cand"; return 0
        fi
    done
    return 1
}

build_vulnfix_venv() {
    local skill_dir="$1"
    local py
    if ! py="$(find_python)"; then
        echo "error: python3.11+ not found (needed for vulnhunter-fix's bundled venv)." >&2
        echo "install python 3.11 (e.g. 'brew install python@3.11') and re-run ./install-copilot.sh." >&2
        exit 1
    fi
    local venv="$skill_dir/.venv"
    if [ -d "$venv" ]; then rm -rf "$venv"; fi
    echo "  creating bundled venv with $py"
    "$py" -m venv "$venv"
    "$venv/bin/pip" install --quiet --disable-pip-version-check --upgrade pip
    echo "  installing runtime deps into venv: ${VULNFIX_DEPS[*]}"
    if ! "$venv/bin/pip" install --quiet --disable-pip-version-check "${VULNFIX_DEPS[@]}"; then
        echo "error: failed to install bundled deps into $venv" >&2
        exit 1
    fi
    if ! "$py" -c "
import sys
sys.path.insert(0, '$skill_dir/scripts')
import _skill_bootstrap  # loads .venv onto sys.path (re-execs under venv python if needed)
import jsonschema, graphify  # noqa: F401
" >/dev/null 2>&1; then
        echo "error: bootstrap smoke test failed — venv built but jsonschema/graphify not importable." >&2
        echo "       check $venv/lib/python3.*/site-packages/" >&2
        exit 1
    fi
    echo "  bundled venv ready: $venv"
}

# Each Copilot Agent Skill is assembled from two sources at install time
# rather than stored fully duplicated in the repo:
#   base    - the existing Claude Code skill directory (unmodified)
#   overlay - vulnhunt-copilot/skills/<name>/, containing only the files
#             that differ because Copilot's tool set (subagent dispatch,
#             terminal tool) differs from Claude Code's
# Copying base then overlay on top means the two skills share one copy of
# every file that doesn't need to differ — most importantly, vulnhunter-fix's
# Python package and its test suite are never duplicated.
SKILLS=(vulnhunt vulnhunt-fix-verify vulnhunter-fix)

if [ ! -d "$SKILLS_PARENT" ]; then
    echo "Creating directory $SKILLS_PARENT"
    mkdir -p "$SKILLS_PARENT"
fi

installed_any=0
for name in "${SKILLS[@]}"; do
    base="$SCRIPT_DIR/$name"
    overlay="$SCRIPT_DIR/vulnhunt-copilot/skills/$name"
    dst="$SKILLS_PARENT/$name"

    if [ ! -f "$base/SKILL.md" ]; then
        if [ "$name" = "vulnhunt" ]; then
            echo "Error: base skill not found at $base" >&2
            echo "Make sure you are running this script from the repository root." >&2
            exit 1
        else
            echo "Skipping $name — $base/SKILL.md not present on this branch."
            continue
        fi
    fi
    if [ ! -d "$overlay" ]; then
        echo "Error: Copilot overlay not found at $overlay" >&2
        echo "Make sure you are running this script from the repository root." >&2
        exit 1
    fi

    if [ -L "$dst" ]; then
        echo "Removing old symlink for $name..."
        rm "$dst"
    elif [ -d "$dst" ]; then
        echo "Removing old copy of $name..."
        rm -rf "$dst"
    fi

    # Base first, overlay on top. Files (not symlinks — symlinks can break
    # workspace search tooling), and the trailing "/." on each source copies
    # directory *contents* into $dst rather than nesting a subdirectory.
    mkdir -p "$dst"
    cp -R "$base/." "$dst/"
    # The base directory's own README.md documents the Claude Code skill
    # ("The core VulnHunter scanner skill for Claude Code...") — leaving it
    # in the installed Copilot skill folder would be actively misleading.
    # SKILL.md (the actual functional entry point) is unaffected.
    rm -f "$dst/README.md"
    cp -R "$overlay/." "$dst/"

    # vulnhunt-fix-verify references verify_disposition.schema.json, which
    # lives in vulnhunter-agent/ today rather than in either skill's own
    # tree — copy it in from its real location instead of duplicating it a
    # second time inside the overlay directory.
    if [ "$name" = "vulnhunt-fix-verify" ]; then
        cp "$SCRIPT_DIR/vulnhunter-agent/verify_disposition.schema.json" "$dst/verify_disposition.schema.json"
    fi

    # Record the source commit so a skill's staleness check (e.g.
    # vulnhunter-fix SKILL.md Step 0b) can compare the installed copy
    # against upstream main. Best-effort: skipped outside a git checkout.
    git -C "$SCRIPT_DIR" rev-parse HEAD > "$dst/.installed-from" 2>/dev/null || true
    echo "Installed $name (copied to $dst)"

    if [ "$name" = "vulnhunter-fix" ]; then
        build_vulnfix_venv "$dst"
    fi

    installed_any=1
done

echo ""
if [ "$installed_any" -eq 1 ]; then
    echo "These are Copilot Agent Skills: VS Code, JetBrains, and GitHub Copilot"
    echo "CLI all auto-discover them from ~/.copilot/skills/ — no further"
    echo "configuration needed."
    echo ""
    echo "Next steps:"
    echo "1. Open the repo you want to scan/fix in your editor."
    echo "2. Open Copilot Chat, switch to Agent mode."
    echo "3. Run: /vulnhunt   (scanner)"
    echo "   or:  /vulnhunter-fix   (fixer, run after a scan)"
    echo "   or:  /vulnhunt-fix-verify   (independent fix verifier)"
    echo ""
    echo "To update after pulling changes: re-run ./install-copilot.sh"
    echo "To uninstall: ./uninstall-copilot.sh"
else
    echo "No skills were installed."
fi
