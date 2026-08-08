# Project Execution Plan — DeX UI Enhancements

## Overview
Implement remaining backend architecture features:
1. Trusted Devices Menu (Bottom Sheet/Dialog) - list paired devices, integrate `DeviceManager.removePairedFingerprint`.
2. Manage Shared Folders Screen (Bottom Sheet/Dialog) - list actively shared SAF folders, integrate `SafStorage.removeGrantedFolder`.
3. Connection Handshake Flow - update `MainScreenViewModel.sendHandshake` and UI interaction layer so tapping an Untrusted device triggers pairing flow (`ClientEngine.registerDevice`) instead of instantly opening file picker.

## Orchestration Methodology
Project Pattern with Explorer -> Worker -> Reviewer -> Challenger -> Auditor iteration loop.

## Phase 0: Survey & Architecture Discovery
- Dispatch 3 Explorers in parallel to inspect existing codebase:
  - Explorer 1: Discover design system components (`DeXPanel`, `DeXButton`, `DeXTextButton`, dialog/bottom sheet patterns, themes, colors, typography).
  - Explorer 2: Inspect `DeviceManager`, `SafStorage`, `ClientEngine`, `MainScreenViewModel`, state flows, and data layer models.
  - Explorer 3: Inspect UI layer (`MainScreen`, device list item, click handlers, existing dialog/bottom sheet implementations).

## Phase 1: Test Suite & Infrastructure Setup
- Spawn E2E / Unit Test Writer subagent to create tests for:
  - DeviceManager pairing/unpairing state handling.
  - SafStorage granted folders state handling.
  - MainScreenViewModel sendHandshake behavior (untrusted vs trusted device clicks).

## Phase 2: Milestone Execution (Implementation Track)
- **Milestone 1**: Trusted Devices Manager UI (Dialog/Bottom Sheet, DeviceManager wiring).
- **Milestone 2**: Shared Folders Manager UI (Dialog/Bottom Sheet, SafStorage wiring).
- **Milestone 3**: Connection Handshake Flow & Untrusted Device Pairing (`sendHandshake`, `registerDevice`, UI integration).

## Phase 3: Final Verification, Build, Version Bump & Packaging
- Run `./gradlew assembleDebug` and `./gradlew lintDebug`.
- Version bump in `AppxManifest.xml` if applicable / Pack & Sign MSIX if applicable.
- Git commit & release documentation in `CHANGELOG.md`.
