#!/bin/zsh
set -euo pipefail

project_dir="${1:-$PWD}"
project_dir="$(cd "$project_dir" && pwd)"

osascript "/Users/adofe/Desktop/HexGo/tools/ghostty/open_ai_layout.applescript" "$project_dir"
