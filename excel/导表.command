#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
bundled_python="$HOME/.cache/codex-runtimes/codex-primary-runtime/dependencies/python/bin/python3"
if [[ -x "$bundled_python" ]]; then
    python_bin="$bundled_python"
else
    python_bin="$(command -v python3)"
fi

"$python_bin" "$script_dir/export.py" "$@"
