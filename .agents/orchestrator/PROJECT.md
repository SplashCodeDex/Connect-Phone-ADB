# Project: DeX UI Enhancements & Backend Wiring

## Architecture
- Language & Framework: Kotlin / Compose Multiplatform / Android (Gradle)
- UI Components: Reusable design system (`DeXPanel`, `DeXButton`, `DeXTextButton`, `DeXIconButton`, `bubbleFluidity`, `MaterialTheme.colorScheme`)
- Overlay Pattern: In-layout `Box` overlay with dim background + `DeXPanel` container (no dedicated navigation routes)
- State & ViewModel: `MainScreenViewModel`, `AuthState`, `StateFlow`
- Backend Managers: `DeviceManager`, `SafStorage`, `ClientEngine`

## Feature Inventory
| # | Feature | Description | Milestone | Source |
|---|---------|-------------|-----------|--------|
| 1 | Trusted Devices Menu | In-layout Dialog/Overlay listing paired fingerprints with unpair action (`DeviceManager.removePairedFingerprint`) | M1 | ORIGINAL_REQUEST R1 |
| 2 | Manage Shared Folders Menu | In-layout Dialog/Overlay listing SAF folders with revoke access action (`SafStorage.removeGrantedFolder`) | M2 | ORIGINAL_REQUEST R2 |
| 3 | Connection Handshake Flow | Update `MainScreenViewModel.sendHandshake` to register untrusted devices via `ClientEngine.registerDevice` & branch device click in `MainScreen` | M3 | ORIGINAL_REQUEST R3 |
| 4 | E2E & Unit Test Infra | Comprehensive tests for DeviceManager, SafStorage, and ViewModel handshake branching | M0 | E2E Testing Track |
| 5 | Build & Release Verification | Gradle build, lint, version bump in AppxManifest, MSIX packaging/signing, changelog, git commit | M4 | Acceptance Criteria & GEMINI.md |

## Milestones
| # | Name | Scope | Dependencies | Status |
|---|------|-------|-------------|--------|
| M0 | Test Infra Track | Unit/E2E test suite for DeviceManager, SafStorage, Handshake flow | none | DONE |
| M1 | Trusted Devices UI | `TrustedDevicesDialog.kt`, top bar action, `DeviceManager` wiring | M0 | DONE |
| M2 | Shared Folders UI | `SharedFoldersDialog.kt`, top bar action, `SafStorage` wiring | M0 | DONE |
| M3 | Handshake & Pairing | `MainScreenViewModel.sendHandshake`, `MainScreen` click branching | M0 | DONE |
| M4 | Integration & Release | `./gradlew assembleDebug`, `lintDebug`, AppxManifest bump, MSIX, git | M1, M2, M3 | IN_PROGRESS |

## Interface Contracts
### MainScreen ↔ TrustedDevicesDialog / SharedFoldersDialog
- Trigger state: `var showTrustedDevicesDialog by remember { mutableStateOf(false) }`, `var showSharedFoldersDialog by remember { mutableStateOf(false) }`
- Dialog Actions: `onDismiss: () -> Unit`, `onRemoveDevice: (String) -> Unit`, `onRemoveFolder: (String) -> Unit`

### MainScreen ↔ MainScreenViewModel
- `sendHandshake(device: DiscoveredDevice, onResult: (Boolean) -> Unit)`
- `isTrustedDevice(fingerprint: String): Boolean` / reactive StateFlow of paired fingerprints

## Code Layout
- `DeX/app/src/main/java/com/example/dex/ui/components/TrustedDevicesDialog.kt` (New)
- `DeX/app/src/main/java/com/example/dex/ui/components/SharedFoldersDialog.kt` (New)
- `DeX/app/src/main/java/com/example/dex/ui/components/FloatingTopAppBar.kt` (Modified for menu buttons)
- `DeX/app/src/main/java/com/example/dex/ui/main/MainScreen.kt` (Modified for dialog state management & click branching)
- `DeX/app/src/main/java/com/example/dex/ui/main/MainScreenViewModel.kt` (Modified for `sendHandshake` implementation)
- `DeX/app/src/test/java/com/example/dex/` (Unit test suite)
