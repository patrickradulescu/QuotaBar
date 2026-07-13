#!/bin/zsh
set -euo pipefail

ROOT="${0:A:h:h}"
PLIST="$ROOT/Packaging/Info.plist"

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$PLIST")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST")"

if [[ ! "$VERSION" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]]; then
  echo "Invalid CFBundleShortVersionString: $VERSION" >&2
  exit 1
fi

if [[ ! "$BUILD" =~ '^[1-9][0-9]*$' ]]; then
  echo "Invalid CFBundleVersion: $BUILD" >&2
  exit 1
fi

if [[ "${GITHUB_REF_TYPE:-}" == "tag" ]]; then
  if [[ "${GITHUB_REF_NAME:-}" != "v$VERSION" ]]; then
    echo "Tag ${GITHUB_REF_NAME:-<missing>} does not match app version v$VERSION" >&2
    exit 1
  fi
  PATTERN_VERSION="${VERSION//./\\.}"
  /usr/bin/grep -Eq "^## \\[$PATTERN_VERSION\\] - [0-9]{4}-[0-9]{2}-[0-9]{2}$" "$ROOT/CHANGELOG.md" || {
    echo "CHANGELOG.md has no exact H2 release heading for $VERSION" >&2
    exit 1
  }
fi

echo "Verified QuotaBar $VERSION (build $BUILD)"
