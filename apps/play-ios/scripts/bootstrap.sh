#!/bin/bash
# Generates Pounce.xcodeproj from project.yml (installing XcodeGen if needed).
set -euo pipefail
command -v xcodegen >/dev/null || brew install xcodegen
cd "$(dirname "$0")/.."
xcodegen generate
