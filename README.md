# obs-changes-llm

Reformat upstream changelogs into openSUSE `.changes` file format using a local LLM.

Takes messy upstream NEWS/changelog text on stdin, outputs properly formatted `.changes` entries — with correct bullet point syntax, filtering of irrelevant items, and optional header generation.

## What it does

- Formats output with `- ` (L1) and `  * ` (L2) bullet points per [openSUSE guidelines](https://en.opensuse.org/openSUSE:Creating_a_changes_file_(RPM))
- Filters out Windows/macOS-specific items, CI/CD changes, build system internals, and contributor credits
- Keeps bug fixes, features, performance improvements, translations, security fixes
- Trims issue references to `#number` format
- Generates the full `.changes` header (dashes + timestamp + email) with `--full`
- Runs entirely locally on CPU, ~15 seconds per changelog

## Setup

### 1. Build llama.cpp

```bash
git clone https://github.com/ggerganov/llama.cpp
cd llama.cpp
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

### 2. Download a model

Qwen2.5-3B-Instruct (Q4_K_M, ~2GB) works well — good instruction following at minimal size:

```bash
mkdir -p models
curl -L -o models/qwen2.5-3b-instruct-q4_k_m.gguf \
    "https://huggingface.co/Qwen/Qwen2.5-3B-Instruct-GGUF/resolve/main/qwen2.5-3b-instruct-q4_k_m.gguf"
```

Qwen2.5-1.5B-Instruct (~1GB) also works if you want faster/smaller, but filters less aggressively.

### 3. Set environment

```bash
export LLAMA_COMPLETION=/path/to/llama.cpp/build/bin/llama-completion
export LLAMA_MODEL=/path/to/models/qwen2.5-3b-instruct-q4_k_m.gguf
```

## Usage

```bash
# Basic: pipe upstream changelog, get formatted output
cat NEWS.diff | ./obs-changes-format.sh

# With version line
cat NEWS.diff | ./obs-changes-format.sh --version 46.0

# Full .changes entry with header (dashes + timestamp + email)
cat NEWS.diff | ./obs-changes-format.sh --version 46.0 --full

# Use GBNF grammar for strict format enforcement (slower)
cat NEWS.diff | ./obs-changes-format.sh --version 46.0 --grammar
```

### Example

Input (upstream NEWS):
```
* Added new keyboard shortcut Ctrl+Shift+P for command palette
* Fixed memory leak in the document parser (#4521)
* The Windows installer now supports silent mode
* Updated French and German translations
* Fixed crash with files larger than 2GB (#4532)
* CI: Switch from Travis CI to GitHub Actions
* macOS: Fixed notarization for Apple Silicon builds
* Thanks to all contributors for their patches
```

Output (`--version 46.0 --full`):
```
-------------------------------------------------------------------
Thu Mar 19 14:19:13 UTC 2026 - packager@example.com

- Update to version 46.0:
  * Added keyboard shortcut Ctrl+Shift+P for command palette
  * Fixed memory leak in the document parser (#4521)
  * Updated French and German translations
  * Fixed crash with files larger than 2GB (#4532)
```

Note: Windows, macOS, CI, and credits lines are filtered out automatically.

### Integration with obs_scm-update.sh

Replace the manual changelog step:

```bash
# Before (manual)
echo "- Update to version $VERSION:" > .NEWS
grep "^+" osc-collab.NEWS | sed 's/^+//g' >> .NEWS
osc vc -F .NEWS

# After (LLM-formatted)
grep "^+" osc-collab.NEWS | sed 's/^+//g' | \
    obs-changes-format.sh --version "$VERSION" > .NEWS
osc vc -F .NEWS
```

## How it works

The script builds a prompt with a few-shot example that demonstrates the filtering rules, feeds it to a local LLM via `llama-completion`, and post-processes the output to trim any model degeneration (repeated lines, trailing junk).

An optional GBNF grammar (`changes.gbnf`) can enforce the `- ` / `  * ` bullet point structure at the token sampling level, but the 3B model produces correct format reliably without it.

## Files

| File | Purpose |
|------|---------|
| `obs-changes-format.sh` | Main script |
| `changes.gbnf` | GBNF grammar for `.changes` format (optional, use with `--grammar`) |

## License

MIT
