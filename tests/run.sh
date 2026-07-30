#!/usr/bin/env bash
# Runs the config test suite in isolation from the user's real config.
# Usage: tests/run.sh [health|startup|gd]
set -uo pipefail

export NVIM_APPNAME=nvim-dev
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$REPO" || exit 1

if [ ! -L "$HOME/.config/nvim-dev" ] || [ ! -d "$HOME/.config/nvim-dev" ]; then
  echo "ERROR: ~/.config/nvim-dev is not a symlink to a directory. Run:"
  echo "  ln -sfn $REPO ~/.config/nvim-dev"
  exit 1
fi

# Assert the symlink points HERE. Existence alone is not enough: a stale link
# would silently run these tests against a different checkout's config.
LINKED="$(cd -P "$HOME/.config/nvim-dev" && pwd)"
if [ "$LINKED" != "$REPO" ]; then
  echo "ERROR: ~/.config/nvim-dev -> $LINKED, but tests live in $REPO"
  echo "  ln -sfn $REPO ~/.config/nvim-dev"
  exit 1
fi

rc=0
run_one() {
  local name="$1" script="$2"
  echo "=== $name ==="
  # -u is REQUIRED: `nvim -l` skips user config unless -u is given (:help -l),
  # so without it init.lua never runs and every assertion is meaningless.
  if nvim --headless -u "$HOME/.config/nvim-dev/init.lua" -l "$script"; then
    echo "--- $name PASSED"
  else
    echo "--- $name FAILED"
    rc=1
  fi
  echo
}

case "${1:-all}" in
  health)  run_one health  tests/health.lua ;;
  startup) run_one startup tests/startup.lua ;;
  gd)      run_one gd      tests/gd_latency.lua ;;
  all)
    run_one health tests/health.lua
    [ -f tests/startup.lua ]   && run_one startup tests/startup.lua
    [ -f tests/gd_latency.lua ] && run_one gd tests/gd_latency.lua
    ;;
  *) echo "usage: tests/run.sh [health|startup|gd|all]"; exit 2 ;;
esac

exit $rc
