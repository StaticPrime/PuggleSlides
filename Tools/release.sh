#!/bin/bash
# Releases the next version of the app. Versions are MAJOR.MINOR.FIX.
#
#   Tools/release.sh            a fix:          1.2.3 → 1.2.4 (the default)
#   Tools/release.sh minor      a minor update: 1.2.3 → 1.3.0
#   Tools/release.sh major      a major update: 1.2.3 → 2.0.0
#   Tools/release.sh --dry-run  shows the next version and changes nothing (works with any of the above)
#
# It raises the version (MARKETING_VERSION) and the build number (CURRENT_PROJECT_VERSION) in the
# Xcode project, commits "Release version X.Y.Z", tags it vX.Y.Z and pushes both to GitHub. The tag
# starts the Release workflow (.github/workflows/release.yml), which runs the package tests, builds
# the installer with Tools/make-installer.sh and publishes it as a GitHub release.
set -euo pipefail

cd "$(dirname "$0")/.."
fail() { echo "release: $*" >&2; exit 1; }

BUMP=fix
DRY_RUN=false
for arg in "$@"; do
    case "$arg" in
        fix|minor|major) BUMP=$arg ;;
        --dry-run) DRY_RUN=true ;;
        *) fail "unknown argument \"$arg\". Use fix, minor or major, and optionally --dry-run." ;;
    esac
done

PROJECTS=(*.xcodeproj)
[ ${#PROJECTS[@]} -eq 1 ] && [ -d "${PROJECTS[0]}" ] || fail "expected one .xcodeproj in $PWD"
APP=$(basename "${PROJECTS[0]}" .xcodeproj)
PBXPROJ="$APP.xcodeproj/project.pbxproj"

# The single value of a build setting, which must be the same in every configuration.
setting() {
    local values
    values=$(grep -o "$1 = [^;]*;" "$PBXPROJ" | sed -E "s/^$1 = \"?([^\";]*)\"?;$/\1/" | sort -u)
    [ -n "$values" ] || fail "$1 isn't set in $PBXPROJ"
    [ "$(printf '%s\n' "$values" | wc -l | tr -d ' ')" -eq 1 ] || fail "$PBXPROJ has more than one $1: $(echo $values)"
    printf '%s' "$values"
}
CURRENT=$(setting MARKETING_VERSION)
BUILD=$(setting CURRENT_PROJECT_VERSION)
[[ $CURRENT =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]] || fail "MARKETING_VERSION \"$CURRENT\" isn't MAJOR.MINOR.FIX"
MAJOR=${BASH_REMATCH[1]} MINOR=${BASH_REMATCH[2]} FIX=${BASH_REMATCH[3]}
[[ $BUILD =~ ^[0-9]+$ ]] || fail "CURRENT_PROJECT_VERSION \"$BUILD\" isn't a whole number"

case "$BUMP" in
    major) NEXT="$((MAJOR + 1)).0.0" ;;
    minor) NEXT="$MAJOR.$((MINOR + 1)).0" ;;
    fix)   NEXT="$MAJOR.$MINOR.$((FIX + 1))" ;;
esac
NEXT_BUILD=$((BUILD + 1))
TAG="v$NEXT"

echo "$APP $CURRENT (build $BUILD) → $NEXT (build $NEXT_BUILD), tag $TAG"
if $DRY_RUN; then
    echo "Dry run: nothing changed."
    exit 0
fi

# Release only what's on GitHub's main, with nothing left out.
[ "$(git rev-parse --abbrev-ref HEAD)" = main ] || fail "switch to the main branch first"
git diff --quiet && git diff --cached --quiet || fail "commit or stash your changes first"
[ -z "$(git ls-files --others --exclude-standard)" ] || fail "there are untracked files; commit or remove them first"
git fetch --quiet --tags origin main
[ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ] || fail "main isn't the same as GitHub's; pull or push first"
! git rev-parse --quiet --verify "refs/tags/$TAG" > /dev/null || fail "the tag $TAG already exists"

sed -i '' -E \
    -e "s/MARKETING_VERSION = [^;]*;/MARKETING_VERSION = $NEXT;/" \
    -e "s/CURRENT_PROJECT_VERSION = [^;]*;/CURRENT_PROJECT_VERSION = $NEXT_BUILD;/" \
    "$PBXPROJ"
[ "$(setting MARKETING_VERSION)" = "$NEXT" ] && [ "$(setting CURRENT_PROJECT_VERSION)" = "$NEXT_BUILD" ] \
    || fail "couldn't update the version in $PBXPROJ"

git commit --quiet -m "Release version $NEXT" -- "$PBXPROJ"
git tag -a "$TAG" -m "$APP $NEXT"
git push --quiet --atomic origin main "$TAG"

REPO=$(git remote get-url origin | sed -E 's#^(git@github\.com:|https://github\.com/)##; s#\.git$##')
echo "Pushed $TAG. GitHub is building the installer: https://github.com/$REPO/actions"
echo "When it's done: https://github.com/$REPO/releases/tag/$TAG"
