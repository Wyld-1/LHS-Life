#!/bin/sh
# Runs the Worker's tests against "APNS Worker.json" in the repo root.
#
#   ./Worker\ Tests/run.sh
#
# Uses `node` if it's installed. Otherwise it borrows the Node runtime built
# into GitHub Desktop (any Electron app can run as plain Node with
# ELECTRON_RUN_AS_NODE=1), so nothing has to be installed on this Mac.
set -e
here="$(cd "$(dirname "$0")" && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
# The Worker is plain JavaScript in a .json-named file; Node needs .mjs to import it.
cp "$here/../APNS Worker.json" "$tmp/worker.mjs"
export WORKER_MODULE="file://$tmp/worker.mjs"

if command -v node >/dev/null 2>&1; then
  node "$here/worker.test.mjs" "$@"
elif [ -x "/Applications/GitHub Desktop.app/Contents/MacOS/GitHub Desktop" ]; then
  ELECTRON_RUN_AS_NODE=1 "/Applications/GitHub Desktop.app/Contents/MacOS/GitHub Desktop" "$here/worker.test.mjs" "$@"
else
  echo "No Node found. Install Node (nodejs.org) or GitHub Desktop." >&2
  exit 1
fi
