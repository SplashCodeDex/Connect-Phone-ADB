# Changelog

## [v1.8.4.0]
- **[minor]** Virtualized the "Nearby Users" list by replacing static UI elements with dynamic `ListBox`es and `VirtualizingStackPanel`s bound to a PowerShell `ObservableCollection`. This ensures zero UI stutter when discovering large numbers of devices.
- **[minor]** Re-introduced a sleek, minimal scrollbar for the "Nearby Users" list using the custom spatial scrollbar template.
## [v1.8.3.3]
- **[fix]** Made the "Nearby Users" list scrollable by replacing the static `StackPanel` container with a `DockPanel` and a `ScrollViewer` (with hidden scrollbars) to prevent the user list from overflowing on smaller screens.
## [v1.8.2.4]
- **[fix]** Fixed File Explorer failing to load files due to `System.Diagnostics.Process` not resolving the `adb.exe` AppExecutionAlias (MSIX context) properly without `UseShellExecute`. Rewrote execution via `cmd.exe /c` to leverage native path resolution.
- **[fix]** Disabled buggy dynamic PowerShell WPF animations on incoming `ListBoxItem`s which left items stuck at `Opacity=0`. 
- **[minor]** Reworked the Top Bar into a fully functional filter/search bar as requested, with placeholder text and dynamic case-insensitive ListBox filtering.

## [v1.8.2.3]
- **[fix]** Fixed silent WPF data-binding failure by changing the File Explorer data items from `Hashtable` to `PSCustomObject`, resolving an issue where the file list rendered completely blank.
- **[minor]** Re-arranged the Top Bar UI so the Up/Back arrow is outside the rounded search bar, using a modern fluent icon.

## [v1.8.2.2]
- **[fix]** Fixed a long-standing bug where the File Explorer would fail to load files when the app was launched via the MSIX Start Menu shortcut due to a hardcoded relative path to `adb.exe`.
- **[minor]** Updated the File Explorer top bar to an editable `TextBox` (Search/Path bar) and changed the navigation icon to an Up Arrow to match typical folder navigation.

## [v1.8.2.1]
- **[fix]** Fixed a critical layout bug where the custom ScrollBar template was missing orientation triggers and repeat buttons, causing the `ScrollViewer` layout engine to silently fail and the `ListBox` to render completely blank.

## [v1.8.2.0]
- **[minor]** Redesigned the File Explorer UI to be sleek and premium.
- **[minor]** Added a custom, slim, rounded ScrollBar style to match the modern spatial UI.
- **[minor]** Rebuilt the top navigation bar into a modern padded capsule with the current path and Up button.
- **[minor]** Enhanced `FileGridTemplate` and `FolderGridTemplate` with soft CornerRadius, updated fonts, adjusted opacity, and responsive hover/press backgrounds that automatically adapt to light/dark themes.
- **[fix]** Increased inner margins of the File Explorer grid to completely prevent contents from clipping over the rounded corners of the main menu border.

## [v1.8.1.0]
- **[fix]** Close button now only appears when menu is expanded (hidden when contracted).
- **[fix]** Restored click-outside-to-close for the contracted menu state; only blocked when expanded.
- **[fix]** Galaxy S21 reverted to original phone-icon avatar instead of photo replacement — only `Visibility="Collapsed"` was removed to unhide it.
- **[fix]** 3 nearby users (Ama, Akua, Kwame) now wrapped in `NearbyExpandPanel` — hidden when contracted, stagger-in with fade animation when expanded into the gap between existing users and Exit Engine.
- **[fix]** ExpandMenu/ContractMenu storyboards now animate `btnCloseMenu` and `NearbyExpandPanel` visibility/opacity in sync.

## [v1.8.0.0]
- **[minor]** Menu UX overhaul: clicking outside the menu no longer closes it — added an animated close button (✕) at the top-right corner instead.
- **[minor]** Reduced the expanded menu size by 35% (width 1160→754px, height 300→195px) for a tighter footprint.
- **[minor]** Pinned 'Exit Engine' to the bottom of the menu using a DockPanel layout, so it no longer shifts upward when the menu expands.
- **[minor]** Added 3 nearby user placeholders (Ama Serwaa, Akua Donkor, Kwame Asante) with real avatar photos and online status indicators, staggered into the gap above Exit Engine.
- **[minor]** Enabled the previously hidden Galaxy S21 device entry with a real avatar and "CodeDeX · This device" subtitle.
- **[fix]** Escape key now properly resets expanded menu state (border dimensions, FileExplorer visibility, transforms) instead of just hiding.

## [v1.7.5.5]
- **[minor]** Upgraded the 'Phone Files' button into a seamless toggle! Built a brand new `ContractMenu` animation storyboard. If the menu is currently expanded, clicking 'Phone Files' will now gracefully reverse the animation, sliding the File Explorer away and shrinking the UI back to its compact state, rather than just doing nothing.

## [v1.7.5.4]
- **[major]** Completely decoupled WPF animations from Win32 Window bounds! Created a massive invisible 1420x760 static Window canvas, and shifted the expansion animations strictly to the inner WPF Grid container. This completely eliminates the Win32 transparent window resizing stutter and jitter, mathematically ensuring a flawless 60fps expansion, and instantly fixes the right-edge white space padding bug.

## [v1.7.5.3]
- **[fix]** Fixed the root cause of the "disappearing to the left" bug. PowerShell was dynamically injecting `SizeToContent = 'WidthAndHeight'` when the window was dismissed, instantly breaking the previous `CanResize` fix for the next launch. Replaced the runtime `SizeToContent` injection with explicit `Width=290` and `Height=460` resets to preserve OS animation support.

## [v1.7.5.2]
- **[fix]** Fixed the "disappearing to the left" animation glitch. Changed WPF `ResizeMode` to `CanResize`, allowing the OS to actually process the `DoubleAnimation` on the Window's `Width` and `Height` dimensions, instead of silently dropping them while still animating `Left` and `Top`.

## [v1.7.5.1]
- **[fix]** Fixed a bug where clicking 'Phone Files' caused the spatial menu to fly off-screen instead of expanding. Removed the conflicting `SizeToContent="WidthAndHeight"` property from the WPF Window and restored explicit `Width` and `Height` boundaries, allowing the `ExpandMenu` DoubleAnimations to properly scale the window bounds.

## [v1.7.5.2]
- **[minor]** Replaced the manual Theme toggle button with an automatic OS Theme Synchronization system. 
- The WPF engine now seamlessly queries the Windows 11 `AppsUseLightTheme` registry key at startup and instantly applies `LightTheme.xaml` or `DarkTheme.xaml` based on your global OS preferences.

## [v1.7.5.0]
- **[major]** Architectural refactor of the WPF rendering engine to support dynamic theming.
- Decoupled all hardcoded hex values in `Connect-Engine.ps1` into semantic `DynamicResource` tokens.
- Introduced `Themes/DarkTheme.xaml` and `Themes/LightTheme.xaml` as standalone dictionaries.
- Built a seamless runtime theme swapper (`Set-AppTheme`) utilizing XAML merged dictionary replacement.
- Added a "Toggle Theme" quick action button to the spatial menu UI to switch between Light and Dark mode instantly.

## [v1.7.4.9]
- **[fix]** Declared `<desktop2:FirewallRules>` in `AppxManifest.xml` to automatically provision Windows Defender Firewall rules for `adb.exe` during MSIX installation. This permanently prevents the UAC/Firewall prompt that was appearing after every update due to path changes and mDNS UDP listeners.

## [v1.7.4.8]
- **[minor]** Reverted the menu opening (`PopIn` and `ExpandMenu`) to use the original `ElasticEase` ("BouncyEase") with a starting scale of `0.85`, preserving the new dramatic `BackEase` overshoot/undershoot exclusively for the hover/leave interactions.

## [v1.7.4.7]
- **[minor]** Split global UI physics into two distinct resources (`HoverEase` Amplitude 1.22 and `PopInEase` Amplitude 3.53) to exactly target scale curves.

## [v1.7.4.6]
- **[minor]** Split global UI physics into two distinct resources: `HoverEase (Amplitude=1.22)` and `PopInEase (Amplitude=3.53)`. This forces the hover-exit to shrink exactly to `0.96` (from `1.08`) before snapping back to `1.0`, and the spatial menu pop-in to start from `0.90` and explode outward to `1.18` before settling to `1.0`, matching the desired bespoke physics curves perfectly.

## [v1.7.3.1]
- **[fix]** Critical app startup failure where the tray icon would load but the WPF window would fail to parse entirely (making all menu items null) because the `JoeAvatar.jpg` image path incorrectly referenced `bin/Assets` instead of `Assets/`. 

## [v1.7.3] - 2026-07-28

## [v1.7.2] - 2026-07-28

### [fix] Spatial Menu Tray Click — Duplicate Deactivated Handler (v1.7.2)
- **Root Cause:** Two separate `Add_Deactivated` handlers were registered on the WPF window. The first (line 773) fired unconditionally — no debounce guard — hiding the window instantly on any focus loss. The second (line 993) had the 200ms debounce but was useless because the first handler already killed the window before it could act. When `Show()` + `Activate()` ran from the tray click, WPF's focus transfer briefly triggered `Deactivated`, and the unguarded handler won the race every time.
- **Fix:** Removed the unconditional handler; merged its state-reset logic (Width/Height/FileExplorer collapse) into the single debounced handler. One handler, one code path, zero race.
- **Project Rules:** Added version bump rule to `GEMINI.md` — all versions must be bumped in `AppxManifest.xml` before build/sign/push.

## [v1.7.1] - 2026-07-27

### [fix] Spatial Menu Tray Click Debouncer (v1.7.1)
- **Root Cause:** The `ApplicationIdle` dispatcher queue was being starved by the WinForms message pump, preventing the menu from opening.
- **Fix:** Implemented a robust 200ms Deactivation Debouncer that ignores spurious `Deactivated` events firing immediately after `Show()`.


## [v1.7.0] - 2026-07-27

### [fix] Spatial Menu Tray Click — Dispatcher ApplicationIdle Fix (v1.7.0)
- **True Root Cause:** When clicking a `NotifyIcon`, Windows queues a WM_ACTIVATE/Deactivate message to the WPF window as part of the tray click sequence. Calling `Show()` synchronously inside `MouseUp` races against this queued message — `Deactivated` fired *after* `Show()`, calling `Hide()` before the user ever saw anything. Neither `AppActivate` nor `Activate()` resolved this because the problem was message ordering, not focus ownership.
- **Fix:** Wrapped `Show()` + `Activate()` + `PopIn` inside `$wpfWindow.Dispatcher.BeginInvoke(ApplicationIdle)`. This defers the open path until all pending WM_ACTIVATE/Deactivated messages have drained from the WPF Dispatcher queue, guaranteeing `Deactivated` fires *before* `Show()`, not after.


## [v1.6.9] - 2026-07-27

### [fix] Spatial Menu Tray Click — Deactivated Race Fix (v1.6.9)
- **Root Cause Identified:** `AppActivate` was called on the PowerShell *process*, not the WPF window. This gave OS focus to the wrong target, causing `Deactivated` to fire on the WPF window the instant it became visible, which called `Hide()` before the user ever saw it.
- **Fix:** Replaced `AppActivate` with `$wpfWindow.Activate()` called immediately after `Show()`. This issues `SetForegroundWindow` on the WPF window's own HWND — correct window gets focus, `Deactivated` only fires when the user genuinely clicks away.


## [v1.6.8] - 2026-07-27

### [fix] WorkArea-Anchored Positioning & Tray Click Race Fix (v1.6.8)
- **WorkArea Anchor (Windows 11 UX):** Replaced cursor-follow positioning with `SystemParameters.WorkArea`-anchored placement. The spatial menu now always opens flush against the taskbar corner (bottom-right by default), matching the Windows 11 Fluent Design language used by Volume, Quick Settings, and Clock flyouts.
- **Tray Click Race Condition:** Fixed the spatial menu silently failing to open. The root cause was a double Visibility guard — `Update-WpfUI` blocks on `adb devices` while the second `Visibility` check ran immediately after and could see a stale Collapsed state. Removed the redundant inner check; `IsVisible` is now the single gatekeeper, and `Show()` is called unconditionally on the open path.
- **Removed Unnecessary Measure:** Cut the `Measure(Infinity)` call that was called on a hidden window before layout; the window has fixed dimensions so `Width`/`Height` are directly usable for positioning.

## [v1.6.7] - 2026-07-27

### [feature] Spatial Menu Bouncy Entrance (v1.6.7)
- **Fluid Animation Physics**: Integrated the signature `BouncyEase` (ElasticEase overshoot-with-reverse-subtle-overshoot) physics directly into the spatial menu's opening sequence. The main window now seamlessly scales up from 85% and glides upwards into position natively using WPF Storyboards when clicking the tray icon.
## [v1.6.5] - 2026-07-27

### [minor] Embedded Avatar Asset (v1.6.5)
- **Asset Integrity Verification**: Copied the explicitly provided user picture directly into the `MSIX_Source\Assets` payload as `JoeAvatar.jpg`. This inherently avoids missing file WPF parsing errors (`XamlParseException`) upon initialization and successfully complies with the zero placeholder asset project rule (`@GEMINI.md`).

## [v1.6.6] - 2026-07-27

### [fix] Spatial Menu Opening Lag (v1.6.6)
- **UI Responsiveness:** Refactored the System Tray click handler (`Connect-Engine.ps1`) to consolidate redundant `adb devices` calls and cache the `Get-AutoConnectStatus` Task Scheduler query. This eliminates UI thread blocking and noticeable opening lag caused by synchronously querying COM objects and spawning external processes on every single click.

## [v1.6.5] - 2026-07-27

### [minor] Staggered Physics Cascades & DRY Architecture (v1.6.5)
- **Centralized Animation Physics:** Extracted duplicated inline `ElasticEase` overshoot definitions across dozens of XAML elements into a single, highly refined `StaticResource` (`BouncyEase`), cutting massive code bloat and strictly enforcing DRY (Don't Repeat Yourself) architecture.
- **Cascading Grid Entrance:** Programmatically injected index-based staggering to the File Explorer grid! When loading phone directories, folders and files now gracefully cascade upwards sequentially with a 35ms stagger, dynamically inheriting the global `BouncyEase` physics curve for a breathtaking load-in effect.

## [v1.6.4] - 2026-07-27

### [feature] Spatial Menu User List & Devices (v1.6.4)
- **Profile Customization**: Refined the User List UI to display `joe.belfiore@gmail.com` as the subtext and bound the avatar to a real image placeholder (`Assets/JoeAvatar.jpg`).
- **Device Ecosystem Integration**: Replaced the placeholder "Bill Gates" entry with a sleek, multi-platform device list. Added a `Galaxy S21` mobile node and a `Windows` laptop node, both styled with vibrant purple (`#6200EE`) backgrounds and matching `Segoe Fluent Icons` device glyphs (`&#xE8EA;` and `&#xE7F8;`).

## [v1.6.3] - 2026-07-27

### [fix] WPF ShowDialog Deadlock (v1.6.3)
- **Tray Icon Unresponsiveness**: Replaced `$script:wpfWindow.ShowDialog()` with `$script:wpfWindow.Show()`. Since the Spatial Menu is repeatedly hidden using `.Hide()` on deactivation, `ShowDialog()` was leaving the window stuck in a hidden modal loop, preventing the menu from re-opening on subsequent tray icon clicks and locking users out of the UI.

## [v1.6.2] - 2026-07-27

### [feature] Spatial Menu User List (v1.6.2)
- **UI Overhaul**: Replaced the redundant legacy text buttons (Connect, Mirror, Pull) with a beautifully animated `Nearby Users` list for upcoming local/global file sharing features.
- **Premium Aesthetics**: Implemented fluid floating parallax micro-animations, vibrant online presence badges with stroke cutouts, and 34px corner-radii matching the primary app window.
- **Shortcut Hardening**: Migrated keyboard shortcuts (`Ctrl+C`, `Ctrl+D`) to depend on the Quick Action icons' visibility, guaranteeing shortcuts continue to function flawlessly despite UI restructuring.

## [v1.6.1] - 2026-07-27

### [minor] Ponytail Cuts (v1.6.1)
- **Removed Dead Code**: Eliminated `dwmapi.dll` PInvoke hook and `System.Runtime.InteropServices` type definitions since dark mode is already forced via solid dark background and WPF `AllowsTransparency="True"`.
- **Removed Legacy Fallbacks**: Cut out the WinForms BalloonTip fallback in `Show-Toast` (YAGNI on Windows 10+).
- **Simplified ADB Paths**: Centralized `$global:AdbExePath` resolution at the root scope, eliminating duplicate `Split-Path`/`Join-Path` logic inside the Async Pull worker job.

## [v1.6.1] - 2026-07-27

### [minor] Massive Diagonal Expansion & Fly-Off Fix (v1.6.1)
- **Massive Spatial Expansion:** Dramatically increased the `ExpandMenu` animation target size (Width expands `By=1160` up to `1450px` total width, Height `By=300`), resulting in a sweeping diagonal (top-left) flyout effect that gives you enormous visual space to explore the Phone Files grid view.
- **State Constraint Fix:** Fixed a critical animation flaw where repeatedly clicking "Phone Files" would cumulatively push the window's spatial coordinates permanently off-screen.
- **Deactivated Reset:** The menu now flawlessly collapses back to its default compact 290x460 size whenever you click away (losing focus), ensuring a fresh state every time it's reopened.

## [v1.6.0] - 2026-07-27

### [major] Purple-Black Gradient Restoration & Mica Purge (v1.6.0)
- **Gradient Background Restored:** Re-introduced the signature deep purple-to-black linear gradient (`#1D1226` to `#09090D`) as the primary background for the entire unified Spatial Menu.
- **Glassmorphism Purged:** Completely stripped all traces of Windows 11 Mica, acrylic blur, and transparent glass backdrop styling from the visual tree to ensure the gradient perfectly renders as a solid, sleek 34px rounded spatial shape.

## [v1.6.1] - 2026-07-27

### [hotfix] XAML UI Tree Syntax Repair (v1.6.1)
- **NotifyIcon Crash Resolved:** Fixed a critical regression where the UI would silently fail to parse its XAML due to an unmatched `<Border>` tag generated during the Parallax upgrade. This previously caused `FindName` bindings to remain null, resulting in the `Text` property exception when clicking the tray icon.

## [v1.5.8] - 2026-07-27

### [fix] Hardened Connections & File Explorer UX (v1.5.8)
- **Zombie Process Prevention**: Optimized the Async File Explorer (`Load-Directory`) to explicitly kill previously spawned `adb shell ls` processes before generating new ones, preventing background CPU bloat during rapid folder navigation.
- **WPF Close() Crash Fix**: Fixed a fatal bug in the File Explorer where double-clicking a file to pull it would call `$script:wpfWindow.Close()`, permanently destroying the WPF object and crashing the app upon subsequent tray clicks. Now uses `.Hide()`.
- **Target Connection Hardening**: Refactored device parsing logic across `Sync-AdbStatus`, `Mirror`, and `Pull` actions to strictly prioritize wireless connections (`*:5555`) over USB or emulators.

## [v1.5.7] - 2026-07-27

### [minor] Spatial Menu Visual Revert (v1.5.7)
- **Reverted Mica & Restored 34px Corners**: Dropped the Windows 11 Mica backdrop (`DWMWA_SYSTEMBACKDROP_TYPE`) due to fundamental DWM incompatibility with custom corner geometries. 
- Restored `AllowsTransparency="True"` and a solid `#1C1C1E` background to guarantee pixel-perfect 34px rounded corners.
- **Process Reaping**: Exiting the engine (`btnExit` or `Q`) now forcefully reaps any stray `adb.exe` and `scrcpy.exe` background processes.

## [v1.5.7] - 2026-07-27

### [minor] Global UI Spring Physics & Parallax (v1.5.7)
- **Universal ElasticEase:** Applied the advanced WPF `ElasticEase` (Oscillations=1, Springiness=4/5) to absolutely every interactive element in the app. This creates that highly-requested organic, physical bouncy feel (overshoot with a subtle reverse-overshoot recoil).
- **Parallax Translations:** Upgraded every single button hover, press, and menu expansion state to include subtle spatial `TranslateTransform` parallax shifts. Elements now physically move and scale organically on hover and click rather than just instantly snapping states.

## [v1.5.6] - 2026-07-27

### [fix] Absolute Compilation Cleanup & MSIX Packaging Pipeline (v1.5.6)
- **Compiler Purge:** Triggered a hard re-compile (`dotnet build`) to physically obliterate the deprecated `PickerWindow` from the underlying `ConnectPhoneShareTarget.dll` assembly. The previous MSIX build only contained the source deletions without recompiling the binary.
- **Automated Pipeline Fix:** Updated `PackMSIX.ps1` to actively trigger `dotnet build -c Release` prior to packaging, ensuring the compiled C# binaries and MSIX payload are fundamentally permanently synced.

## [v1.5.5] - 2026-07-27
### [major] Unified Spatial File Explorer & Overshoot UI Rewrite (v1.5.5)
- **Nuked PickerWindow:** Eliminated the standalone C# File Picker EXE (`PickerWindow.xaml`), consolidating everything back into the core PowerShell engine to honor the strict minimalist protocol.
- **Fluid Overshoot Shape-Shifting:** Clicking 'Phone Files' now triggers a gorgeous `BackEase` WPF DoubleAnimation that dynamically scales the Spatial Menu diagonally to reveal a nested phone grid-view directly within the Mica surface.
- **Async ADB Runspace Bypass:** Engineered a raw `OutputDataReceived` pipeline in PowerShell to scrape directories from `adb` asynchronously in the background. Completely negates UI freezing without needing external C# assemblies.

## [v1.5.4] - 2026-07-27
### [fix] Spatial Menu Focus & Hide Reliability (v1.5.4)
- **ShowDialog Crash Fix**: Fixed a bug where clicking the tray icon when the spatial menu was already active would throw an `InvalidOperationException` due to re-invoking `ShowDialog()`. The tray icon now properly toggles visibility.
- **Deactivated Event Reliability**: Forced the underlying PowerShell process to gain OS-level foreground lock (`AppActivate`) before showing the WPF overlay. This guarantees that clicking outside the spatial menu reliably fires the `Deactivated` event to auto-hide it.

## [v1.5.3] - 2026-07-27
### [minor] Spatial Menu Mica Integration (v1.5.3)
- **Mica Backdrop**: Applied native Windows 11 Mica Glass (`DWMWA_SYSTEMBACKDROP_TYPE = 2`) to the Spatial Menu (Tray UI), stripping away the solid black background via `WindowChrome` while retaining the native floating UI characteristics.

## [v1.5.2] - 2026-07-27
### [fix] Dynamic Connection Syncing & Auto-Connect Fallback (v1.5.2)
- **Auto-Connect Fallback:** Clicking 'Phone Files' when no device is connected now automatically attempts to connect using the supplied IP Address before pulling.
- **Dynamic Connection Syncing:** Refactored the Tray Menu connection logic to actively resync and extract the `<ip:port>` natively every time the menu is opened, addressing edge-cases where background connections didn't update the UI.

## [v1.5.2] - 2026-07-27
### [minor] Mirror Phone Quick Action & Shortcut (v1.5.2)
- **CellPhone Segoe Fluent Icon**: Added Phone icon button (`&#xE8EA;`) to the top spatial quick action bar and spatial menu list item (`Mirror Phone`).
- **Scrcpy Auto-Detection & Launch**: Integrated zero-latency screen mirroring launcher via `scrcpy.exe -s <target>`. Auto-detects `scrcpy` in system `PATH` or local `bin` folder, and gracefully prompts if missing.
- **Keyboard Shortcut**: Bound key `M` (`⌘M`) to trigger Mirror Phone instantly.

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

## [v1.5.1] - 2026-07-27

### [fix] Execution Path Bug & Acrylic Aesthetics (v1.5.1)
- **Execution Fix:** Fixed a silent crash where the System Tray `Connect-Engine.ps1` was resolving `ConnectPhoneShareTarget.exe` inside the `bin` directory instead of the application root.
- **Acrylic Aesthetics:** Wired in `dwmapi.dll` P/Invoke calls to inject native Windows 11 Acrylic (`DWMWA_SYSTEMBACKDROP_TYPE = 3`) into the WPF window background for a gorgeous translucent glass effect.

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
