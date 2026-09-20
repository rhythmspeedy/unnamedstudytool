#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc -parse-as-library Sources/StudyTool/Models.swift Sources/StudyTool/WorkspaceModels.swift Sources/StudyTool/NotesStore.swift Tests/ModelChecks.swift -o .build/checks/model-checks
.build/checks/model-checks
