#!/usr/bin/env bash
# Refresh the shared ledger fixtures from the canonical copy in corebari-apps.
#
# The rules live in one file, in the app that owns the database. This copy
# exists because a Dart test cannot reach across repositories, and the recorded
# hash is what stops the copy silently going stale: `fixtures_test.dart` fails
# when the two differ, which is the point at which somebody runs this.
set -euo pipefail

CANONICAL="${1:-$HOME/WorkGround/Studio/corebari-apps/apps/agentkhata/src/server/ledger.fixtures.json}"
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ ! -f "$CANONICAL" ]; then
  echo "canonical fixtures not found at $CANONICAL" >&2
  echo "pass the path as the first argument" >&2
  exit 1
fi

cp "$CANONICAL" "$HERE/test/fixtures/ledger_cases.json"
sha256sum "$HERE/test/fixtures/ledger_cases.json" | cut -d' ' -f1 > "$HERE/test/fixtures/FIXTURES_SHA"
echo "fixtures refreshed from $CANONICAL"
