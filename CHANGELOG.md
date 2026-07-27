# Changelog

## [v1.5.1] - 2026-07-27

### [minor] Spatial Menu Folder Icon & Persist Open (v1.5.1)
- **Segoe Fluent Folder Icon**: Replaced `Phone Files` icon (`&#xE896;`) in spatial menu with official Segoe Fluent Icons / Segoe MDL2 Assets Folder glyph (`&#xE8B7;`).
- **Persistent Spatial Menu**: Removed auto-hide behavior on item click (`Connect`, `Disconnect`, `Phone Files`, `Toggle Auto-Connect`). The spatial menu remains open for multi-action execution with live UI state updates.
- **Keyboard Shortcut Acceleration**: Added `Esc` to instantly dismiss spatial menu overlay, alongside key handling (`C`, `D`, `P`, `Q`).

## [v1.4.5] - 2026-07-27

### [fix] GitHub Action Release Workflow Fixes (v1.4.5)
- **.NET 10 Prerelease Setup**: Added `include-prerelease: true` to `actions/setup-dotnet@v4` so GitHub Actions runner resolves `.NET 10` preview builds on `windows-latest`.
- **Manual Trigger Support**: Added `workflow_dispatch` to allow manual execution of build & release pipeline from GitHub Actions web UI.
- **Isolated Release Notes Extractor**: Enhanced regex parsing in PowerShell step to capture the exact top tag heading and notes verbatim into `RELEASE_NOTES.md` without pulling trailing historical changelog entries.

## [v1.5.0] - 2026-07-27

### [major] Native C# File Picker (v1.5.0)
- **UI Overhaul:** Completely ripped out the primitive PowerShell `TreeView` file picker and replaced it with a gorgeous, natively compiled C# WPF `PickerWindow`.
- **Segoe Fluent Icons:** Added native support for `&#xE8B7;` (Folder) and `&#xE7C3;` (File) modern glyphs, leveraging system-level Segoe Fluent UI rather than bringing in bloatware external dependencies.
- **Performance:** Migrated the ADB folder scraping logic (`adb shell ls -1aF`) to run entirely asynchronously on native C# thread pools for zero UI lag.
- **Glassmorphism Base:** Laid the architectural groundwork for standard WPF blurring and acrylics without needing heavy toolkits like Tauri or WPF-UI.

## [v1.4.4] - 2026-07-27

### [fix] Deep Edge-Case Audit (v1.4.4)
- **UI Responsiveness:** Fixed a bug where polling the remote file size blocked the WPF UI thread, causing the transfer window to temporarily hang before the transfer started.
- **ADB Path Escaping:** Fixed a critical bug where transferring files with single quotes (e.g. `O'Brian.mp4`) would completely crash the ADB shell syntax during standard input streaming.
- **Missing Binaries:** Added explicit verification for `adb.exe` presence before executing streams.

## [v1.4.3] - 2026-07-27

### [fix] TreeView Scope Crash (v1.4.3)
- Fixed a fatal scoping bug where PowerShell's `.add_Expanded()` threw a silent `MethodNotFound` exception on the WPF TreeView because `TreeView` does not expose `Expanded` directly. Refactored to use standard WPF `AddHandler` for `TreeViewItem::ExpandedEvent`.

## [v1.4.2] - 2026-07-27

### [fix] WPF Threading & Installation Bump (v1.4.2)
- Fixed a bug where `Phone Files` would crash instantly due to calling `.Show()` instead of `.ShowDialog()` inside a WinForms thread.
- Bumped AppxManifest version to `1.4.2.0` to resolve Windows package identity installation blocks.

### [major] The Blip Engine Rewrite (v1.4.0)
- **Hardcore C# Transfer Engine**: Completely retired `Send-To-Phone.ps1`. The C# `ConnectPhoneShareTarget` application is now a fully-fledged WPF streaming engine.
- **Byte-Level Auto-Resume**: The engine now polls the Android device for existing file sizes and streams bytes directly via `adb shell cat >>`, enabling seamless mid-byte resume if a transfer fails or network drops.
- **Live Progress UI**: Replaced standard Toast notifications with a beautiful, floating WPF window that displays a live progress bar, precise megabytes-per-second (MB/s) speed tracker, and taskbar progress states.

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
