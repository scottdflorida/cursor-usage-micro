#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h}
module_cache="$project_dir/build/StrictModuleCache"
source_files=("$project_dir"/Sources/*.swift)
test_files=("$project_dir"/Tests/*.swift)
# The test binary excludes CursorUsageMicro.swift (conflicting @main) and AppDelegate.swift (app-lifecycle glue).
test_sources=(${source_files:#*/CursorUsageMicro.swift})
test_sources=(${test_sources:#*/AppDelegate.swift})
test_binary="$project_dir/build/CursorUsageMicroTests"

mkdir -p "$module_cache"

xcrun swift-format lint \
  --strict \
  --recursive \
  --configuration "$project_dir/.swift-format" \
  "$project_dir/Sources" \
  "$project_dir/Tests"

swiftc \
  -typecheck \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework Foundation \
  -lsqlite3 \
  "${source_files[@]}"

swiftc \
  -parse-as-library \
  -swift-version 6 \
  -strict-concurrency=complete \
  -warnings-as-errors \
  -target "$(uname -m)-apple-macosx13.0" \
  -module-cache-path "$module_cache" \
  -framework AppKit \
  -framework Foundation \
  -lsqlite3 \
  "${test_sources[@]}" \
  "${test_files[@]}" \
  -o "$test_binary"

"$test_binary"
