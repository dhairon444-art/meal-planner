#!/bin/sh
set -eu
repo_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
check_dir=$(mktemp -d "${TMPDIR:-/tmp}/meal-planner-checks.XXXXXX")
trap 'rm -rf "$check_dir"' EXIT
xcrun --sdk macosx swiftc -sdk "$(xcrun --sdk macosx --show-sdk-path)" -module-cache-path "$check_dir/ModuleCache" \
  "$repo_root/Shared/Models.swift" "$repo_root/Shared/PlanningEngine.swift" \
  "$repo_root/App/Services.swift" "$repo_root/App/Store.swift" "$repo_root/Checks/RuleChecks.swift" \
  -o "$check_dir/checks"
"$check_dir/checks" "$repo_root/App/Resources/SeedRecipes.json"
