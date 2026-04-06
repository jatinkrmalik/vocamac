#!/bin/bash
# release.sh — Release VocaMac to GitHub and Bitbucket
# Usage: ./scripts/release.sh <version>
# Example: ./scripts/release.sh 0.3.0
#
# This script:
# 1. Syncs main from GitHub to Bitbucket
# 2. Rebases Bitbucket's release branch (which has bitbucket-pipelines.yml)
# 3. Tags on both remotes to trigger CI/CD
#
# Prerequisites:
#   - Two remotes configured: origin (GitHub) and atlassian (Bitbucket)
#   - Bitbucket 'release' branch exists with bitbucket-pipelines.yml commit

set -euo pipefail

VERSION="${1:?Usage: ./scripts/release.sh <version> (e.g., 0.3.0)}"
TAG="v${VERSION}"

# Validate we're not already on a tag
if git rev-parse "$TAG" >/dev/null 2>&1; then
    echo "❌ Tag ${TAG} already exists. Aborting."
    exit 1
fi

# Validate remotes exist
for remote in origin atlassian; do
    if ! git remote get-url "$remote" >/dev/null 2>&1; then
        echo "❌ Remote '${remote}' not found. Run: git remote add ${remote} <url>"
        exit 1
    fi
done

echo "🚀 Releasing VocaMac ${TAG}"
echo ""

# Step 1: Ensure we're on main and up to date
echo "📥 Pulling latest main from GitHub..."
git checkout main
git pull origin main

# Step 2: Sync main to Bitbucket (main-mirror branch)
echo "📤 Syncing main to Bitbucket..."
git push atlassian main:main-mirror

# Step 3: Rebase Bitbucket's release branch onto updated main
echo "🔄 Rebasing Bitbucket release branch..."
git fetch atlassian release
git checkout -B bb-release atlassian/release
git rebase main

# Step 4: Push the rebased release branch to Bitbucket
git push atlassian bb-release:release --force-with-lease

# Step 5: Tag on main (for GitHub) and push
git checkout main
git tag "${TAG}"
echo "🏷️  Pushing tag ${TAG} to GitHub..."
git push origin "${TAG}"

# Step 6: Tag on release branch (for Bitbucket) and push
git checkout bb-release
git tag -f "${TAG}"
echo "🏷️  Pushing tag ${TAG} to Bitbucket..."
git push atlassian "${TAG}" --force

# Clean up local temp branch
git checkout main
git branch -D bb-release

echo ""
echo "✅ Release ${TAG} triggered on both remotes!"
echo ""
echo "   📦 GitHub Actions (ad-hoc signed):"
echo "      https://github.com/jatinkrmalik/vocamac/actions"
echo ""
echo "   📦 Bitbucket Pipelines (signed + notarized):"
echo "      https://bitbucket.org/atlassian/vocamac/pipelines"
echo ""
echo "   Once the Bitbucket pipeline completes, download the signed DMG"
echo "   from the pipeline artifacts and attach it to the GitHub Release."
