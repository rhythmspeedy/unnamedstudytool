#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
. scripts/swift-toolchain.sh
configure_swift_toolchain
mkdir -p .build/checks
swiftc -sdk "$SDKROOT" -module-cache-path "$SWIFT_MODULE_CACHE_PATH" -parse-as-library Sources/StudyTool/Models.swift Sources/StudyTool/WorkspaceModels.swift Sources/StudyTool/NotesStore.swift Sources/StudyTool/WorkspaceState.swift Sources/StudyTool/WorkspaceBackup.swift Sources/StudyTool/StudySafety.swift Tests/RoadmapChecks.swift Tests/ModelChecks.swift -o .build/checks/model-checks
.build/checks/model-checks
swiftc -sdk "$SDKROOT" -module-cache-path "$SWIFT_MODULE_CACHE_PATH" -D STUDY_CHECKS -parse-as-library Sources/StudyTool/*.swift Tests/IntegrationChecks.swift -o .build/checks/integration-checks
.build/checks/integration-checks
