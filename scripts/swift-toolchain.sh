#!/bin/bash

# Select an SDK that the installed Swift compiler can actually import. Apple
# Command Line Tools updates can briefly leave the compiler and default SDK at
# different patch versions; probing avoids an opaque SwiftShims failure.
configure_swift_toolchain() {
  local cache_dir="$(pwd)/.build/module-cache"
  local default_sdk
  local candidate

  mkdir -p "$cache_dir"
  default_sdk="$(xcrun --sdk macosx --show-sdk-path)"

  for candidate in "$default_sdk" /Library/Developer/CommandLineTools/SDKs/MacOSX*.sdk; do
    [[ -d "$candidate" ]] || continue
    if printf 'import Foundation\n' | swiftc \
      -module-cache-path "$cache_dir" \
      -sdk "$candidate" \
      -typecheck - >/dev/null 2>&1; then
      export SDKROOT="$candidate"
      export CLANG_MODULE_CACHE_PATH="$cache_dir"
      export SWIFT_MODULE_CACHE_PATH="$cache_dir"
      export SWIFTPM_MODULECACHE_OVERRIDE="$cache_dir"
      return 0
    fi
  done

  echo "No installed macOS SDK is compatible with $(swiftc --version | head -1)." >&2
  echo "Reinstall or update Apple's Command Line Tools, then try again." >&2
  return 1
}
