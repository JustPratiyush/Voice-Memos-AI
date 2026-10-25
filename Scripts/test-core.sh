#!/bin/bash
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/VoiceMemosCoreChecks.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
xcrun swiftc -D CORE_STANDALONE_TESTS -parse-as-library -swift-version 5 \
    -target "$(uname -m)-apple-macosx14.0" \
    "$project_dir"/Sources/VoiceMemosCore/*.swift \
    "$project_dir"/Tests/VoiceMemosCoreTests/*.swift \
    -o "$test_dir/core-checks"
"$test_dir/core-checks"
