# Original User Request

## Initial Request — 2026-08-08T00:59:47Z

Build the UI for the remaining backend architecture features (Trusted Devices Manager, Shared Folders Manager, and Connection Handshake). Implementations must be well-factorized, highly modular, debuggable, and perfectly match the existing reusable design system (no hardcoded UI/UX).

Working directory: W:/CodeDeX/DeX/DeX
Integrity mode: development

## Requirements

### R1. Trusted Devices Menu (Bottom Sheet/Dialog)
Implement a UI (via Bottom Sheet or Dialog Overlay launched from the main view) to list and manage paired devices. Must wire up `DeviceManager.removePairedFingerprint` to allow users to forget trusted devices. Must use existing reusable components.

### R2. Manage Shared Folders Screen (Bottom Sheet/Dialog)
Implement a UI (via Bottom Sheet or Dialog Overlay launched from the main view) to list actively shared SAF folders. Must wire up `SafStorage.removeGrantedFolder` to allow users to revoke folder access. Must use existing reusable components.

### R3. Connection Handshake Flow
Update `MainScreenViewModel.sendHandshake` and the UI interaction layer so that tapping an "Untrusted" device triggers the pairing flow (via `ClientEngine.registerDevice`) instead of instantly opening the file picker.

## Acceptance Criteria

### Execution & Integration
- [ ] Code compiles successfully (`./gradlew assembleDebug` exits with 0).
- [ ] No new IDE inspection warnings or lint errors are introduced (`./gradlew lintDebug` passes).

### Architecture & Modularity
- [ ] UI is implemented strictly using existing design system components (e.g., `DeXPanel`, `DeXButton`, `DeXTextButton`) with zero hardcoded styling (colors, padding, shapes).
- [ ] The Trusted Devices and Manage Folders menus are implemented as Dialogs or Bottom Sheets, avoiding the need for dedicated navigation routing.
- [ ] Clicking a trusted device opens the file picker, while clicking an untrusted device triggers the `sendHandshake` protocol.
