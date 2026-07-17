#!/bin/bash
# LOCAL-ONLY (gitignored): build + relaunch DiskAura signed with a STABLE self-signed identity so
# macOS keeps its Full Disk Access / Automation grants across rebuilds. The committed project.yml
# stays ad-hoc ("-") for the public repo; this override applies only to local dev builds.
set -e
# Team-ID-anchored Apple Development identity: macOS TCC pins Full Disk Access to the signing
# identity (not the per-build hash), so the grant survives every rebuild. A self-signed no-team
# cert gets hash-pinned instead, which is why FDA kept resetting.
IDENTITY="Apple Development: Kristian Dimitrov (JQ56325A45)"
cd "$(dirname "$0")"
xcodegen generate >/dev/null 2>&1 || true
xcodebuild -project DiskAura.xcodeproj -scheme DiskAura -configuration Debug -destination 'platform=macOS' \
  CODE_SIGN_IDENTITY="$IDENTITY" CODE_SIGN_STYLE=Manual OTHER_CODE_SIGN_FLAGS="--deep" build \
  | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED" | tail -5
SRC=$(xcodebuild -project DiskAura.xcodeproj -scheme DiskAura -configuration Debug -showBuildSettings 2>/dev/null \
  | awk -F' = ' '/ BUILT_PRODUCTS_DIR /{print $2}')/DiskAura.app
killall DiskAura 2>/dev/null || true
sleep 1
# Deploy to a STABLE path (/Applications) so Full Disk Access — granted once to this path + stable
# signing identity — persists across every rebuild, and the app is trivial to find in the FDA picker.
# Use `ditto` (not rm+cp): it replaces the bundle in place preserving the code signature exactly, so
# TCC keeps matching the same designated requirement and the FDA grant is NOT reset each rebuild.
ditto "$SRC" /Applications/DiskAura.app
xattr -dr com.apple.quarantine /Applications/DiskAura.app 2>/dev/null || true
open /Applications/DiskAura.app
echo "Launched (stable-signed): /Applications/DiskAura.app"
