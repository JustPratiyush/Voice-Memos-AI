#!/bin/bash
set -euo pipefail

configuration=release
case "${1:-}" in
    "") ;;
    --debug) configuration=debug ;;
    --help|-h)
        printf 'Usage: %s [--debug]\nBuilds and ad-hoc signs build/Voice Memos Replica.app. Does not install or launch it.\n' "$0"
        exit 0
        ;;
    *)
        printf 'Unknown argument: %s\nUsage: %s [--debug]\n' "$1" "$0" >&2
        exit 2
        ;;
esac
if [[ $# -gt 1 ]]; then
    printf 'Expected at most one argument.\n' >&2
    exit 2
fi

project_dir="$(cd "$(dirname "$0")/.." && pwd)"
build_dir="$project_dir/build"
app_path="$build_dir/Voice Memos Replica.app"

xcrun swift build --package-path "$project_dir" --configuration "$configuration" --product VoiceMemosReplica \
    -Xswiftc -strict-concurrency=complete
binary_dir="$(xcrun swift build --package-path "$project_dir" --configuration "$configuration" --show-bin-path)"
if [[ ! -x "$binary_dir/VoiceMemosReplica" ]]; then
    printf 'The Swift package did not produce the expected executable.\n' >&2
    exit 1
fi

mkdir -p "$build_dir"
stage_dir="$(mktemp -d "$build_dir/.VoiceMemosReplica.bundle.XXXXXX")"
trap 'rm -rf "$stage_dir"' EXIT
staged_app="$stage_dir/Voice Memos Replica.app"
mkdir -p "$staged_app/Contents/MacOS" "$staged_app/Contents/Resources"
cp "$binary_dir/VoiceMemosReplica" "$staged_app/Contents/MacOS/VoiceMemosReplica"

python3 - "$project_dir/Resources/Info.plist" "$staged_app/Contents/Info.plist" <<'PY'
import plistlib
import re
import sys

variables = {
    "EXECUTABLE_NAME": "VoiceMemosReplica",
    "PRODUCT_BUNDLE_IDENTIFIER": "dev.recreation.VoiceMemos",
    "PRODUCT_NAME": "Voice Memos Replica",
    "MARKETING_VERSION": "0.1.0",
    "CURRENT_PROJECT_VERSION": "1",
    "MACOSX_DEPLOYMENT_TARGET": "14.0",
}

def expand(value):
    if isinstance(value, str):
        return re.sub(r"\$\(([^)]+)\)", lambda match: variables[match[1]], value)
    if isinstance(value, list):
        return [expand(item) for item in value]
    if isinstance(value, dict):
        return {key: expand(item) for key, item in value.items()}
    return value

with open(sys.argv[1], "rb") as source:
    info = expand(plistlib.load(source))
info["CFBundleSupportedPlatforms"] = ["MacOSX"]
info["NSPrincipalClass"] = "NSApplication"
with open(sys.argv[2], "wb") as output:
    plistlib.dump(info, output, sort_keys=False)
PY

for resource in "$project_dir"/Resources/*; do
    [[ -e "$resource" ]] || continue
    case "$(basename "$resource")" in
        Info.plist|*.entitlements|*.xcassets) continue ;;
    esac
    cp -R "$resource" "$staged_app/Contents/Resources/"
done
printf 'APPL????' > "$staged_app/Contents/PkgInfo"
plutil -lint "$staged_app/Contents/Info.plist"
codesign --force --sign - --timestamp=none \
    --entitlements "$project_dir/Resources/VoiceMemos.entitlements" "$staged_app"
codesign --verify --deep --strict "$staged_app"

# Keep a previous generated bundle until the replacement has moved successfully.
# A failed replacement restores it and preserves both bundles if rollback fails.
python3 - "$staged_app" "$app_path" "$stage_dir/previous.app" <<'PY'
import os
import sys

staged, destination, previous = sys.argv[1:]
had_previous = os.path.lexists(destination)
if had_previous:
    os.rename(destination, previous)
try:
    os.rename(staged, destination)
except BaseException:
    if had_previous:
        try:
            os.rename(previous, destination)
        except OSError:
            # Move the prior bundle outside shell-trap cleanup before propagating failure.
            recovery = destination + ".recovery"
            if not os.path.lexists(recovery):
                os.rename(previous, recovery)
            raise
    raise
PY
printf 'Built %s (%s, ad-hoc signed with App Sandbox).\n' "$app_path" "$configuration"
