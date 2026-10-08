#!/bin/bash
# Verifica os dados sem depender do XCTest (Xcode completo).
set -euo pipefail
cd "$(dirname "$0")"
mkdir -p .build/checks
swiftc Sources/UsoIA/Models.swift Sources/UsoIA/UsageFetcher.swift \
    Sources/UsoIA/TokenActivity.swift Sources/UsoIA/BarPlacement.swift Tests/UsoIATests/UsageTests.swift \
    -o .build/checks/UsageTests
.build/checks/UsageTests
