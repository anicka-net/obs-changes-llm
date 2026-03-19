#!/bin/bash
# obs-changes-format.sh — Reformat upstream changelog into openSUSE .changes format
# Uses a local LLM with GBNF grammar to enforce the output structure.
#
# Usage:
#   obs-changes-format.sh < NEWS.diff
#   obs-changes-format.sh --version 46.0 < NEWS.diff
#   cat osc-collab.NEWS | obs-changes-format.sh --version 46.0 --full
#
# Environment:
#   LLAMA_COMPLETION  path to llama-completion (default: llama-completion)
#   LLAMA_MODEL       path to GGUF model (required)
#   mailaddr          packager identity (same as osc vc convention)

set -euo pipefail

SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"
GRAMMAR="$SCRIPT_DIR/changes.gbnf"
LLAMA="${LLAMA_COMPLETION:-llama-completion}"
MODEL="${LLAMA_MODEL:-}"
VERSION=""
FULL_ENTRY=false
USE_GRAMMAR=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version|-v) VERSION="$2"; shift 2 ;;
        --model|-m)   MODEL="$2"; shift 2 ;;
        --full|-f)    FULL_ENTRY=true; shift ;;
        --grammar|-g) USE_GRAMMAR=true; shift ;;
        --help|-h)
            echo "Usage: obs-changes-format.sh [--version VER] [--model PATH] [--full] [--grammar] < NEWS.diff"
            echo ""
            echo "Reads upstream changelog from stdin, outputs .changes formatted text."
            echo "  --version VER   Prepend 'Update to version VER:' as first line"
            echo "  --model PATH    Path to GGUF model (or set LLAMA_MODEL)"
            echo "  --full          Output complete .changes entry with header"
            echo "  --grammar       Use GBNF grammar to enforce format (slower)"
            exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

if [ -z "$MODEL" ]; then
    echo "Error: Set LLAMA_MODEL or use --model PATH" >&2
    exit 1
fi

if [ ! -f "$GRAMMAR" ]; then
    echo "Error: Grammar file not found: $GRAMMAR" >&2
    exit 1
fi

# Read upstream changelog from stdin
INPUT=$(cat)

if [ -z "$INPUT" ]; then
    echo "Error: No input. Pipe upstream changelog to stdin." >&2
    exit 1
fi

# Truncate very long inputs (models have limited context)
INPUT=$(echo "$INPUT" | head -200)

# Build version prefix
VERSION_LINE=""
if [ -n "$VERSION" ]; then
    VERSION_LINE="The first line must be: - Update to version $VERSION:
The remaining items must use \"  * \" prefix (they are sub-items of the update).
"
fi

# Build the prompt using Qwen chat template
PROMPT="<|im_start|>system
You reformat upstream changelogs for openSUSE RPM .changes files.
Rules:
- L1 bullets: \"- \" prefix (dash space)
- L2 bullets: \"  * \" prefix (two spaces, asterisk, space)
- Max 67 characters per line; wrap with proper indent
- Be concise: summarize, do not copy verbatim
- REMOVE: Windows/macOS items, CI/CD, build system internals, contributor credits
- KEEP: bug fixes, features, performance, translations, security fixes
- Trim issue refs to #number
- Keep under 20 lines total
${VERSION_LINE}<|im_end|>
<|im_start|>user
EXAMPLE INPUT:
* Fixed crash on startup
* Windows: dark mode
* CI: migrate to Actions
* Thanks @alice
* Added plugin API

EXAMPLE OUTPUT:
- Fixed crash on startup
- Added plugin API

NOW REFORMAT:
${INPUT}<|im_end|>
<|im_start|>assistant
"

# Build llama-completion arguments
LLAMA_ARGS=(-m "$MODEL" -p "$PROMPT" --no-display-prompt -n 384 -t 4 --temp 0.3 -e)
if [ "$USE_GRAMMAR" = true ] && [ -f "$GRAMMAR" ]; then
    LLAMA_ARGS+=(--grammar-file "$GRAMMAR")
fi

# Run the model
RESULT=$("$LLAMA" "${LLAMA_ARGS[@]}" 2>/dev/null)

# Post-process: trim degenerate output and trailing junk
RESULT=$(echo "$RESULT" | \
    sed 's/  \*  \*.*$//' | \
    grep -v '^[[:space:]]*$' | \
    awk '{ if (seen[$0]++ > 0) exit; print }' | \
    sed '/^- *$/d; /^> /d')

if [ "$FULL_ENTRY" = true ]; then
    # Packager identity: $mailaddr (osc convention) > osc whois > oscrc email > git
    if [ -n "${mailaddr:-}" ]; then
        EMAIL="$mailaddr"
    elif command -v osc &>/dev/null; then
        EMAIL=$(osc whois 2>/dev/null | sed 's/^[^:]*: //')
    fi
    if [ -z "${EMAIL:-}" ]; then
        EMAIL=$(git config user.email 2>/dev/null || echo 'packager@example.com')
    fi
    TIMESTAMP=$(LC_ALL=C date -u)
    DASHES="-------------------------------------------------------------------"

    echo "$DASHES"
    echo "$TIMESTAMP - $EMAIL"
    echo ""
fi

echo "$RESULT"
