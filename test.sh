#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc -parse-as-library Sources/StudyTool/Models.swift Sources/StudyTool/WorkspaceModels.swift Sources/StudyTool/NotesStore.swift Sources/StudyTool/WorkspaceState.swift Sources/StudyTool/WorkspaceBackup.swift Sources/StudyTool/StudySafety.swift Tests/RoadmapChecks.swift Tests/ModelChecks.swift -o .build/checks/model-checks
.build/checks/model-checks
swiftc -D STUDY_CHECKS -parse-as-library Sources/StudyTool/*.swift Tests/IntegrationChecks.swift -o .build/checks/integration-checks
.build/checks/integration-checks
