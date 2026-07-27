# Changelog

All notable changes to the Connect Phone ADB project will be documented in this file.

## [v1.3.23] - 2026-07-27

### [major] TreeView File Explorer (v1.3.18)
- **Dynamic Phone Files**: Replaced the static, path-restricted ListBox file picker with a dynamic, lazy-loading WPF `<TreeView>` file explorer.
- **Zero-Lag Loading**: Introduced a "Dummy Node" pattern that only queries the Android filesystem via `adb shell ls` when a folder is actively expanded, enabling instantaneous UI responsiveness.
- **Recursive Directory Pulling**: Users can now select an entire directory in the TreeView and download it recursively in the background.

### [fix] MSIX Deployment and AppExecutionAlias Syntax (v1.3.19)
- **Alias Registration Crash**: Fixed `0x8007007E` MSIX deployment failure by correctly defining the `Executable` and `EntryPoint` attributes in the `<uap3:Extension Category="windows.appExecutionAlias">` tag for `adb.exe`.

### [fix] UTF-8 Mojibake Crash (v1.3.20)
- **Silent Background Crash**: Resolved an issue where literal folder (📁) and file (📄) emojis in the PowerShell script caused a fatal `XmlNodeReader` parse exception under certain encoding environments. Replaced with robust `[DIR]` text prefixes.

### [fix] WPF Icon Decoder Crash (v1.3.21)
- **WPF BitmapFrame Bug**: Wrapped the `BitmapFrame::Create` icon assignment for the TreeView window in a `try/catch` block to prevent silent execution termination when Windows Presentation Foundation fails to decode `app-icon.ico`.

### [fix] ShareTarget Batching and Disconnection Edge-Cases (v1.3.22)
- **CPU/Memory Resource Bomb**: Completely rewrote the C# `ConnectPhoneShareTarget` application to batch multiple shared file paths into a temporary text file, preventing the app from spawning dozens of concurrent PowerShell background instances when sharing multiple files.
- **Disconnected ADB Ghost Files**: Implemented offline detection in the TreeView parser. If ADB is disconnected silently in the background, the UI now displays `(Disconnected)` instead of parsing `error: device offline` into fake UI file nodes.
- **Task Scheduler UAC Audit**: Verified the Auto-Connect Task Scheduler logic natively executes under `TASK_LOGON_INTERACTIVE_TOKEN`, confirming standard non-elevated users can correctly toggle the functionality.

### [minor] Spatial Menu Icon & Persistent Interaction Enhancements
- **UI Glyph Update**: Replaced `btnQAPull` icon with official Segoe Fluent Icons / Segoe MDL2 Assets **Folder** glyph (`&#xE8B7;`).
- **Persistent Spatial Menu**: Removed auto-hiding behavior on `Connect`, `Disconnect`, `Phone Files`, and `Auto-Connect` menu actions so the menu stays open for interactive use.
- **Dynamic UI State Sync**: Added immediate `Update-WpfUI` triggers on menu actions to update connect/disconnect states and auto-connect highlights live.
- **Project Rule Protocol**: Configured workspace rules enforcing `/ponytail` ladder, deep edge-case resolution, MSIX build & signing pipelines, and automated release commits.
