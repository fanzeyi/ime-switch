#!/bin/bash
# Cuts a release: bumps the version, builds and notarizes with `make dist`, tags,
# publishes a GitHub release with the zip, and updates the Homebrew cask.
#
# Usage: scripts/release.sh <version> [notes-file]
# Without a notes file, GitHub generates the release notes.
set -euo pipefail

REPO=fanzeyi/ime-switch
TAP_REPO=fanzeyi/homebrew-tap
CASK=Casks/imeswitch.rb
ZIP=build/IMESwitch.zip

version=${1:-}
notes=${2:-}
die() { echo "error: $*" >&2; exit 1; }

[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "usage: $0 <x.y.z> [notes-file]"
[[ -z $notes || -f $notes ]] || die "notes file not found: $notes"
[[ -z $notes ]] || notes="$(cd "$(dirname "$notes")" && pwd)/$(basename "$notes")"
cd "$(dirname "$0")/.."

# Releases come from an up-to-date, clean main.
[[ $(git branch --show-current) == main ]] || die "not on main"
[[ -z $(git status --porcelain) ]] || die "working tree is not clean"
git fetch --quiet origin main --tags
[[ $(git rev-parse HEAD) == $(git rev-parse origin/main) ]] || die "main is not in sync with origin/main"
! git rev-parse --quiet --verify "refs/tags/$version" >/dev/null || die "tag $version already exists"

# Bump the marketing version and the build number.
build=$(sed -n 's/^ *CFBundleVersion: "\([0-9]*\)"$/\1/p' project.yml)
[[ -n $build ]] || die "CFBundleVersion not found in project.yml"
sed -i '' \
    -e "s/^\( *CFBundleShortVersionString:\) \".*\"$/\1 \"$version\"/" \
    -e "s/^\( *CFBundleVersion:\) \"$build\"$/\1 \"$((build + 1))\"/" \
    project.yml
git diff --stat

make dist
built=$(defaults read "$PWD/build/dist/Build/Products/Release/IMESwitch.app/Contents/Info.plist" CFBundleShortVersionString)
[[ $built == "$version" ]] || die "built app reports version $built, expected $version"
sha=$(shasum -a 256 "$ZIP" | cut -d' ' -f1)

read -r -p "Built $version ($sha). Commit, tag, push and publish? [y/N] " answer
[[ $answer == [yY] ]] || { echo "Stopped. The version bump is left uncommitted; git checkout project.yml IMESwitch/Info.plist to undo."; exit 1; }

# make dist regenerated Info.plist from project.yml.
git commit --quiet -m "Release $version" project.yml IMESwitch/Info.plist
git tag -a "$version" -m "IMESwitch $version"
git push --quiet origin main "$version"

if [[ -n $notes ]]; then
    gh release create "$version" "$ZIP" --repo "$REPO" --title "IMESwitch $version" --notes-file "$notes"
else
    gh release create "$version" "$ZIP" --repo "$REPO" --title "IMESwitch $version" --generate-notes
fi

# Point the cask at the new release.
tap=$(mktemp -d)
trap 'rm -rf "$tap"' EXIT
gh repo clone "$TAP_REPO" "$tap" -- --quiet
sed -i '' \
    -e "s/^  version \".*\"$/  version \"$version\"/" \
    -e "s/^  sha256 \".*\"$/  sha256 \"$sha\"/" \
    "$tap/$CASK"
git -C "$tap" commit --quiet -am "imeswitch $version"
git -C "$tap" push --quiet

echo "Released $version: https://github.com/$REPO/releases/tag/$version"
