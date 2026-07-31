# Changelog

## [3.6.8.0] - 2026-07-31
### Changed
- **[patch]** The spatial menu drag handle now dynamically changes its color to the theme's secondary accent brush when active.
- **[patch]** Reduced the slide-out pin toggle size to fit cleanly within the 16px hit area, preventing layout shifting/stretching when revealed.

## [3.6.7.0] - 2026-07-31
### Added
- **[patch]** The spatial menu drag handle is now fully interactive. Double-clicking it snaps the menu back to the center of the primary screen. Single-clicking it reveals a sliding "Pin to Top" toggle that automatically fades out after 3 seconds to keep the UI clean.

## [3.6.3.0] - 2026-07-31
### Added
- **[patch]** Added a pill-shaped drag handle indicator above the quick action buttons to visually communicate that the spatial menu can be dragged.

## [3.6.2.0] - 2026-07-31
### Added
- **[patch]** Added `DragMove()` via `MouseLeftButtonDown` event to the WPF window to allow users to easily drag the spatial menu panel around natively without any external dependencies or bloated layout logic.

## [3.6.1.0] - 2026-07-31
### Fixed
- **[patch]** Wiggle-to-Open menu now automatically hides when the mouse button is released (after drag-and-drop ends). Delay execution added to ensure WPF Drop events are cleanly routed before collapsing the window.

## [3.6.0.0] - 2026-07-31
### Added
- **[minor]** Wiggle-to-Open now conditionally filters the spatial menu, hiding unneeded UI elements to exclusively show the Nearby Devices list for faster, focused device selection.

## [3.5.0.0] - 2026-07-31
### Added
- **[major] OmniMesh File Explorer:** Completely rewired the WPF File Explorer to use the blazing fast OmniMesh Ktor HTTP REST API (`/api/dex/browse` and `/api/dex/pull`) instead of sluggish `adb shell ls` and `adb pull` commands.
- **[minor]** Android Ktor Server now exposes `/api/dex/browse` and `/api/dex/pull` for direct native file streaming to PC.


## [3.2.0.0] - 2026-07-31
### Added
- **Wiggle-to-Open Feature:** Users can now rapidly move their mouse back and forth ("wiggle") while holding a file (during a drag operation) to instantly summon the Connect-Phone-ADB drop menu at the cursor's location. This feature can be toggled via the new Interaction section in the Settings panel.


## [3.1.8.8] - 2026-07-31
### Changed
- **[patch]** Optimized system theme listener: replaced the 2-second background `DispatcherTimer` polling loop with `UserPreferenceChanged` native event handler, eliminating idle timer overhead.
- **[patch]** Centralized theme UI label binding directly inside `Set-AppTheme`, removing duplicate text updating logic across settings handlers.

## [3.1.8.7] - 2026-07-31
### Fixed
- **[patch]** Fixed light mode theme transparency bug in `Set-AppTheme`. Removed over-engineered `ColorAnimation` loop targeting freezable `SolidColorBrush` resource objects (which failed silently in WPF causing transparent UI rendering) and replaced it with direct, native `MergedDictionaries` dictionary replacement.

## [3.1.8.6] - 2026-07-31
### Fixed
- **[patch]** Eliminated the ~1-second UI freeze when opening the Settings panel by replacing the sluggish `Get-ScheduledTask` cmdlet with the native `Schedule.Service` COM object for Auto-Connect status checks, allowing the animation to run instantly without dropping frames.

## [3.1.8.5] - 2026-07-31
### Fixed
- **[patch]** Fixed system tray menu double-opening flash bug caused by a tri-fold race condition: (1) Windows 11 tray focus shifts triggering `Deactivated` mid-animation were suppressed with an 800ms `isShowingMenu` guard flag, (2) stale `PopIn` animation fill clocks were cleared before hiding to prevent property override glitches, and (3) WinForms `NotifyIcon.MouseUp` double-fire events from single physical clicks were debounced.

## [3.1.8.4] - 2026-07-30
### Fixed
- **[patch]** Prevented the Exit button from needlessly animating its margin leftward when the menu is in the expanded state, as the avatar is already collapsed and the button natively occupies the full layout width.

## [3.1.8.3] - 2026-07-30
### Added
- **[feature]** Restored fluid animations to the Exit Engine sequence while strictly enforcing layout stability. The Exit button now animates its margin to slide left, while the parent grid width is explicitly locked to perfectly prevent any window-resizing pops. The avatar image subtly shrinks and scales behind the expanding solid AccentBrush overlay, creating a premium visual effect.

## [3.1.8.2] - 2026-07-30
### Fixed
- **[patch]** Corrected the negative margin calculation for the expanded Exit Engine button (`-62` instead of `-46`) to account for internal padding offsets inside the `SpatialListItem` control template, perfectly aligning it with the avatar's left edge.
- **[patch]** Fixed a variable scoping issue inside the PowerShell `DispatcherTimer` scriptblock that prevented the button from reverting to its initial state after 3 seconds.

## [3.1.8.1] - 2026-07-30
### Fixed
- **[patch]** Fixed a toggle-loop edge case where clicking the Start Menu shortcut while the main UI was already visible would hide it instead of focusing it.
- **[patch]** Suppressed the redundant "Connect ADB Active" startup toast notification during explicit launches, as the main UI now opens instantly instead.
- **[patch]** Refactored the exit button overlapping logic to strictly follow ponytail protocol: removed the `ThicknessAnimation` entirely as it caused brief UI stretch-and-contract artifacts due to width recalibrations. The button now instantly overlaps the avatar using native negative margins and locks onto the solid `AccentBrush` background fill, perfectly hiding the avatar without opacity animations and completely preventing any window resizing bugs.

## [3.1.8.0] - 2026-07-30
### Added
- **[minor]** Launching the app explicitly from the Start menu now immediately displays the main UI instead of just starting silently in the system tray. This works seamlessly for both cold starts and warm starts (when the engine is already running in the background), achieved efficiently using `EventWaitHandle` IPC and Windows Startup Task activation context detection.

## [3.1.7.3] - 2026-07-30
### Added
- **[feature]** Added fluid WPF `ThicknessAnimation` and `DoubleAnimation` to the Exit Engine sequence. The exit button now smoothly sweeps left to cover the avatar's space, while the avatar elegantly fades out, fulfilling the original overlapping design intention without triggering any abrupt layout reflows or snap-shifts.

## [3.1.7.2] - 2026-07-30
### Fixed
- **[patch]** Completely removed the profile avatar visibility toggling logic during the exit sequence to eliminate all visual layout shifting. The new compact text ("Cancel / Shift+Click Exit") fits seamlessly into the existing button space, ensuring zero snapping or popping when the exit sequence resets.

## [3.1.7.1] - 2026-07-30
### Changed
- **[patch]** Shortened the exit cancellation text to "Cancel / Shift+Click Exit" for a cleaner appearance when expanded.

## [3.1.7.0] - 2026-07-30
### Fixed
- **[patch]** Fixed a UI distortion issue where clicking 'Exit Engine' forced the menu to expand horizontally off-screen. The root cause was a storyboard animation `HoldEnd` on the Profile Avatar's Visibility preventing it from collapsing. The fix explicitly clears the animation hold via `BeginAnimation` before applying the `Collapsed` state, allowing the Exit button to properly overlap into the avatar's freed space.

## [3.1.6.0] - 2026-07-30
### Fixed
- **[patch]** Restored WPF Storyboard `.Begin($true)` and `.Pause()` initialization prior to `Show()` to definitively resolve the spatial menu 1-frame pop-in flash. This mathematically locks the DWM composite frame to the absolute start state of the `PopIn` animation sequence before rendering occurs.

## [3.1.5.0] - 2026-07-30
### Fixed
- **[patch]** Resolved the root cause of the WPF menu flash. Storyboard `HoldEnd` precedence was overriding local property assignments on `Reset-SpatialPanels`. The engine now correctly calls `.Stop()` on all active storyboards when the window hides, releasing the layout holds so that local properties (Opacity 0) correctly apply on the next `Show()` invocation.

## [3.1.4.0] - 2026-07-30
### Fixed
- **[patch]** Completely eliminated the residual 1-frame visual pop-in (visible before animation) when opening the spatial menu by utilizing WPF Storyboard `.Begin($true)` and `.Pause()` directly prior to `Show()`. This mathematically locks the DWM composite frame to the absolute start state of the `PopIn` animation sequence, bypassing previous storyboard `HoldEnd` precedence.

## [3.1.2.0] - 2026-07-30
### Fixed
- **[patch]** Added missing `-STA` flag to the `powershell.exe` launch arguments inside the C# `ConnectPhoneShareTarget` wrapper. Without this flag, the engine launched from the Start Menu in MTA mode, which caused WPF's `XamlReader::Load` to crash instantly and silently.
- **[patch]** Fixed spatial menu flashing animation (double-animation jump) by pre-setting scale and translation explicitly before the window executes its first render frame.
- **[patch]** Fixed 'Phone Files' quick action button becoming out-of-sync (unchecked when open) when the menu is collapsed via the Close button or click-outside.

## [3.1.1.0] - 2026-07-30
### Fixed
- **[patch]** Fixed spatial menu double-animation glitch (1-frame pop-in flash) by pre-zeroing window opacity right before display.
- **[patch]** Fixed static elements (close button, profiles, nearby users panel) improperly re-animating when swapping directly between the File Explorer and Settings panels.
- **[patch]** Fixed quick action buttons staying highlighted by ensuring the Pull button is explicitly unchecked when the Settings panel is opened.

## [3.1.0.0] - 2026-07-30
### Added
- **[minor]** Live device telemetry on OmniMesh peer buttons. When a nearby phone broadcasts its UDP beacon, the engine now queries `adb` for `ro.product.model` and battery level. Peer slots now display `📱 Samsung Galaxy S21 • 🔋 84%` instead of the plain `OmniMesh (IP)` string. Gracefully falls back to IP when the device isn't yet ADB-connected.

### Changed
- **[minor]** Ponytail audit cleanup: removed 4 unused `PSDataCollection` allocations from Runspace factories, deduplicated identical storyboard-clone blocks in `$actionSettings` and `$actionPull`, extracted `Invoke-ExitEngine` to eliminate duplicate exit sequences across button and keyboard handlers, and merged the redundant double-mutex into a single engine guard.
- **[minor]** Clarified intentional UI scaffold comment blocks in `EngineUtils.ps1` and `TrayUIBindings.ps1` with prominent boxed banners so no future contributor accidentally "fixes" them.

## [3.0.0.0] - 2026-07-30
### Changed
- **[major]** Refactored background tasks (mDNS polling and Omni-Mesh transfer server) to use raw, in-process `.NET` PowerShell Runspaces (`[powershell]::Create()`) instead of `Start-Job`.
  - Eliminates the 30-second initialization delay and completely resolves the random console window flashes on startup.
  - Implements a thread-safe `ConcurrentQueue` for nanosecond-fast inter-thread communication.
  - Fixes notorious infinite-loop Runspace memory leaks by aggressively piping internal output streams to `[void]` and ensuring the UI explicitly disposes of unmanaged `Runspace` resources via a robust application-exit hook.

## [2.7.18.0] - 2026-07-30
### Fixed
- **[fix]** Reverted the spatial menu `menuTrans` parallax exit animation introduced in v2.7.15.0. It caused severe visual clipping on the left edge of the main menu during window contraction because the `To="-30"` X-axis translation collided with the shrinking Win32 window bounds.

## [2.7.17.0] - 2026-07-30
### Fixed
- **[fix]** Restored absolute height constraint logic in `TrayUIHandlers.ps1` that was lost during a previous refactoring. This completely resolves the bug where rapidly swapping between the Settings and File Explorer panels caused the spatial menu contents to shift upward off-screen due to relative height accumulation (`By="195"`).

## [2.7.15.0] - 2026-07-30
### Added
- **[patch]** Added reciprocal 3D parallax depth to the `ContractMenu` and `ContractSettings` exit animations. The spatial menu now subtly slides back out of frame (`X=-30`) as the window contracts, perfectly matching the physics of the `ExpandMenu` entrance.

## [2.7.14.0] - 2026-07-30
### Fixed
- **[patch]** Fixed spatial menu fluidity and opening lag. `Update-WpfUI` now fetches connected `adb devices` asynchronously via a background process instead of blocking the UI thread before the entrance animation.
- **[patch]** Fixed micro-stutter when opening the File Explorer or Settings panels by running `Load-Directory` asynchronously (`InvokeAsync`), ensuring the `ExpandMenu` animation triggers instantly without dropped frames.

## [2.6.10.0] - 2026-07-30
### Fixed
- **[fix]** Resolved severe UI expansion bug where rapidly swapping between File Explorer and Settings Panel caused the window to infinitely grow vertically off-screen. (The `ExpandMenu` and `ExpandSettings` height animations are now strictly constrained to absolute values instead of relative accumulation).

## [2.6.9.0] - 2026-07-30
### Added
- **[minor]** Added a secondary inner-parallax animation to the spatial menu's child content (`menuContentTrans`). The content now slides up from a deeper offset (`Y=35`) and fades in slightly slower than the menu container, creating a beautiful staggered 3D depth effect during the `PopIn` sequence.

## [2.6.8.0] - 2026-07-30
### Fixed
- **[fix]** Resolved UI overlap bug where rapidly switching between File Explorer and Settings Panel caused both grids to render on top of each other due to lingering XAML storyboard state.

## [2.6.6.0] - 2026-07-30
### Added
- **[minor]** Added a dynamic Y-axis parallax slide-up effect to the spatial menu container (`menuTrans`) during the initial system tray `PopIn` sequence, giving it an elastic bouncy entrance distinct from the main window scaling.

## [2.6.5.0] - 2026-07-29
### Removed
- **[minor]** Reverted dynamic Windows System Accent Color adaptation to lock in the signature Green \#0AE66D\ as the permanent \SecondaryBrush\.

## [2.6.4.0] - 2026-07-29
### Fixed
- **[fix]** Resolved WPF DoubleAnimation stacking bugs when switching between Settings and File Explorer.
- **[fix]** Prevented fatal boot crashes by purging dead UI event bindings from the deprecated avatar popup.

## [2.6.3.0] - 2026-07-29
### Added
- **[minor]** Integrated native Windows 11 Accent Color syncing. The \SecondaryBrush\ now dynamically inherits the user's active DWM ColorizationColor (with our smooth 300ms fallback crossfade intact).

## [2.6.2.0] - 2026-07-29
### Added
- **[fix]** Implemented \AppThemeMode\ state manager to resolve a bug where the automatic background OS theme listener would forcefully override a user's manual theme toggle selection.

## [2.6.1.0] - 2026-07-29
### Added
- **[fix]** Unified the \SecondaryBrush\ to identically use the signature Green (#0AE66D) across both Light and Dark themes for consistency. \SecondaryForegroundBrush\ in Light mode is also synced to absolute black to maintain high contrast.

## [2.6.0.0] - 2026-07-29
### Added
- **[minor]** Injected a WPF \ColorAnimation\ storyboard into the theme-swapping engine, enabling a premium 300ms smooth crossfade for all backgrounds, text, and surfaces when toggling between Light and Dark mode.

## [2.5.2.0] - 2026-07-29
### Added
- **[fix]** Set \SecondaryForegroundBrush\ to absolute black (#000000) in dark theme and updated Quick Action buttons to utilize this dynamic brush for maximum contrast when active.

## [2.5.1.0] - 2026-07-29
### Added
- **[fix]** Added `SecondaryForegroundBrush` to ensure device avatars maintain high visual contrast against the dynamic `SecondaryBrush` background in both Light and Dark modes.

## [2.5.0.0] - 2026-07-29
### Added
- **[major]** Refactored local network discovery to use standard mDNS (Multicast DNS) natively via `Makaretu.Dns` and Android's `NsdManager`, entirely bypassing raw UDP broadcast storms and ensuring enterprise router compatibility.
- **[major]** Enabled `HttpProtocols.Http1AndHttp2AndHttp3` in the Kestrel server to natively support QUIC transport streams for P2P transfers.
- **[patch]** Added automatic native Windows Firewall Rules for `ConnectPhoneShareTarget.exe` inside the AppxManifest to silently allow mDNS and QUIC connections without triggering UAC blocks.

## [2.4.0.0] - 2026-07-29
### Added
- **[minor]** Integrated an automatic Windows System Theme Listener. The UI dynamically detects the \AppsUseLightTheme\ registry key and instantly syncs its XAML theme (Light/Dark) to match the host OS without requiring restarts.
- **[minor]** Streamlined the core UI Semantic Color Dictionary down to a strict 3-color base (\PrimaryBrush\, \SecondaryBrush\, \AccentBrush\), completely eliminating redundant tags like \SuccessBrush\ and \TertiaryBrush\ to perfectly align with the project design system.

## [2.2.4.0] - 2026-07-28
### Added
- **[patch]** Constrained the spatial menu's contracted layout to a minimum width of 335px.
- **[patch]** Implemented a dynamic layout animation engine in `Update-WpfUI` that provides a fluid overshoot (bouncy) transition when the menu expands to accommodate new elements (like the IP copy button), eliminating abrupt snapping.

## [2.2.3.0] - 2026-07-28
### Added
- **[minor]** Updated the Connect Quick Action into a seamless ToggleButton that persists the active state (highlighted in accent color) when connected. Consolidated Connect and Disconnect into a single intuitive toggle.
- **[minor]** Added a new Clipboard Quick Action icon (currently un-wired).
- **[minor]** Updated the Close menu (X) button to utilize a new Danger style for destructive action signaling.

## [2.2.2.0] - 2026-07-28
### Added
- **[minor]** Reassigned the power-switch icon to the Exit Engine button and updated the Disconnect button icon. Added an active/pressed light-green accent state to all Quick Action icons.

## [2.2.1.0] - 2026-07-28
### Added
- **[minor]** Repositioned the menu Close (X) button directly into the Quick Actions strip when expanded to visually streamline the interface and fill the layout gap.

## [2.2.0.0] - 2026-07-28
### Added
- **[minor]** Added a native WPF popup flyout card attached to the Gmail profile avatar. Clicking the avatar now displays a floating card showing user details.
- **[minor]** Moved the Theme Toggler out of a standard context menu and integrated it into the new profile flyout card to match the project's spatial aesthetics.
- **[minor]** Relocated the "Auto connect ADB" quick action button into the profile flyout card to de-clutter the main quick actions strip.

## [2.1.1.5] - 2026-07-28
### Hotfix: File Explorer UI Scope Isolation
- **[fix]** Fixed the File Explorer logic (double-clicking to load directories) which was silently failing. This was caused because `EngineUtils.psm1` was still loaded as an isolated module, preventing its `Load-Directory` function from accessing the UI elements in `Connect-Engine.ps1`. Converted `EngineUtils` to a dot-sourced script to perfectly unify the UI scope.
## [2.1.1.4] - 2026-07-28
### Hotfix: Silent Failure on mDNS Discovered Devices
- **[fix]** Fixed a major logic regression where clicking on a discovered device via the mDNS 'Nearby' menu would silently fail. The `Invoke-AdbConnect` function was never updated to accept the `-Target` parameter passed to it by the mDNS menu, causing it to ignore the selected device and default back to calculating the local Hotspot Gateway IP. The function signature has been fixed to fully accept and prioritize targeted connections.
## [2.1.1.3] - 2026-07-28
### Hotfix: Major Event Registration Duplication
- **[fix]** Surgically removed a massive 163-line duplicated event block in `TrayUIBindings.ps1` that was incorrectly pasted during the v2.0.0.0 monolithic script decoupling. This bug caused `Add_KeyDown`, `btnExit.Add_Click`, `wpfWindow.Add_KeyDown`, and `Add_Deactivated` to register and fire twice, creating ghost timers, doubling UI operations, and causing massive application state race conditions.
## [2.1.1.2] - 2026-07-28
### Hotfix: System Tray Icon Image Loss (Colored Dot Bug)
- **[fix]** Resolved a relative pathing issue where `$PSScriptRoot` was resolving to `MSIX_Source\bin\Modules` instead of `MSIX_Source\bin` due to the recent architectural decoupling. This caused `app-icon.ico` to fail to load, resulting in the System Tray falling back to generating a blank 16x16 image with just a colored status dot.
- **[fix]** Fixed broken `ToastNotification` icon paths and `Themes` directory paths in `UIComponents.ps1` caused by the same `$PSScriptRoot` module context shift.
## [2.1.1.1] - 2026-07-28
### Hotfix: System Tray Icon Unresponsiveness
- **[fix]** Restored the missing `Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle)` wrapper for the System Tray `MouseUp` event handler in `TrayUIBindings.ps1`. This fixes a critical UI regression (race condition) that caused tray icon clicks to instantly deactivate and swallow the main window.
- **[fix]** Removed redundant, corrupted duplicate block of `MouseUp` and `KeyDown` bindings left over from the v2.0.0.0 architecture decoupling refactor.
## [2.1.0.0] - 2026-07-28
### Features & UX Overhaul
- **[minor] Intelligent Pairing & mDNS Overhaul**: 
  - Upgraded mDNS parsing regex to cleanly extract IP, Port, Type, and GUID.
  - Added robust Wi-Fi pairing natively using a custom decoupled WPF prompt (`Show-PairingPrompt`) that dynamically merges the active app themes (`DarkTheme.xaml` / `LightTheme.xaml`) for 100% aesthetic parity.
  - Built a CI Pester testing suite (`AdbManager.Tests.ps1`) to strictly validate connect and pairing flows via `Validate-Build.ps1`.
- **[minor] Share Target UX Modernization**: 
  - Overhauled the C# Share Target (`TransferWindow.cs`) to drop rigid C# grid construction in favor of an injected, deeply styled XAML layout.
  - Added Fluent Windows 11 aesthetics: `CornerRadius=12`, native DropShadows, Acrylic transparency illusions, and seamless `DoubleAnimation` for smooth progress bar gliding instead of abrupt snapping.
  - Fully mapped to the Vibrant Green (`#00E676`) success accent.
## [2.0.0.0] - 2026-07-28
### Major Architecture Overhaul (Part 2)
- **UI Decoupling**: Completely extracted the raw XAML overlay from `Connect-Engine.ps1` into `MSIX_Source\Themes\MainWindow.xaml`.
- **UI Bindings**: Moved ~600 lines of WPF UI events into `MSIX_Source\bin\TrayUIBindings.ps1`. `Connect-Engine.ps1` is now purely an orchestrator script under 250 lines.
- **C# Refactoring**: Decoupled `TransferWindow.cs` from `Program.cs` within the Share Target, keeping all files lean (<1,000 lines).
- **Intelligent Connectivity**: Added `Start-MdnsDiscovery` to `AdbManager.psm1`. Android 11+ devices broadcasting `_adb-tls-connect._tcp` are now automatically discovered and connected in the background.

## [v2.0.0.0]
- **[major]** Architecture Overhaul: Refactored the monolithic `Connect-Engine.ps1` (~1,900 lines) into modern PowerShell modules (`.psm1`).
- Extracted ADB logic into `AdbManager.psm1`.
- Extracted UI/WPF generation functions into `UIComponents.psm1`.
- Extracted Task Scheduler bindings into `TaskScheduler.psm1`.
- Extracted common utilities into `EngineUtils.psm1`.
- Rebuilt and signed MSIX package. Removed old 70KB temporary scripts (`temp.ps1`, `temp2.ps1`).
## [v1.9.4.1]
- **[fix]** Restored true fix for swallowed tray clicks (previously documented in v1.7.0 but reverted): wrapped `Show()`, `Activate()`, and `PopIn` inside `$wpfWindow.Dispatcher.BeginInvoke([System.Windows.Threading.DispatcherPriority]::ApplicationIdle)` to prevent `Deactivated` race condition. Reverted `MouseClick` back to `MouseUp`.


## [v1.9.3.0]
- **[minor]** Hid bulky vertical WPF scrollbars in both the Nearby Users panel and File Explorer list (`VerticalScrollBarVisibility="Hidden"`) for a cleaner, modern aesthetic while fully retaining mouse-wheel scrolling capability.

## [v1.9.6.5]
- **[fix]** Resolved application launch failure caused by string encoding corruption (`"✓"`) and ampersand entity parsing in PowerShell by using safe character literals `[char]0x2713` and `[char]0xE8C8`. Verified AST parse with 0 syntax errors.

## [v1.9.6.0]
- **[fix]** Added 5-second process execution timeout guard to `Load-Directory` to prevent hanging ADB processes on unreachable phone daemons.
- **[minor]** Added middle-ellipsis path truncation to floating download dock text when path length exceeds 35 characters while preserving full path in ToolTip.
- **[minor]** Added `Alt + Up Arrow` and `Backspace` keyboard navigation shortcuts for parent directory navigation (`btnUpDir`).
- **[fix]** Implemented dynamic screen working area bounds clipping protection to ensure spatial menu never gets cut off by taskbars docked on top, left, right, or bottom.
- **[fix]** Added explicit window activation and focus synchronization on tray icon clicks.

## [v1.9.5.0]
- **[minor]** Added `Ctrl+A` Select All (visible items only) and `Escape` deselect support to `lbFiles`.
- **[minor]** Added 400ms double-click speed thresholding guard (`$script:lastDoubleClickTime`) to prevent rapid accidental triple-click job duplication.
- **[minor]** Added floating dock auto-hide pause on mouse hover (`MouseEnter`/`MouseLeave`).
- **[fix]** Wired `btnProfileTop` click handler to open profile ContextMenu directly when expanded.
- **[fix]** Added application exit job & process cleanup (`Stop-Job`, `Remove-Job`, `adbLsProc.Kill()`).

## [v1.9.2.8]
- **[minor]** Changed the background fill color of the 'Windows' and 'Galaxy S21' device avatars from `PrimaryBrush` (Purple) to `SecondaryBrush` (Light-Green) for a more unified status indicator aesthetic.

## [v1.9.4.0]
- **[minor]** Enabled `SelectionMode="Extended"` on `lbFiles` to support Shift+Click range selection and Ctrl+Click multi-selection with persistent green highlight across all selected items.
- **[minor]** Upgraded `MouseDoubleClick` to support batch multi-file pulling into `Downloads\dex` (or custom directory) with dynamic notification count ("Saved X files to Downloads\dex").
- **[fix]** Added `emptyFolderState` overlay to display clean visual feedback when a directory contains zero files/folders.
- **[fix]** Implemented in-flight lock guard (`$script:isLoadingDir`) on `Load-Directory` to prevent rapid re-click process collisions.
- **[minor]** Added visual checkmark confirmation on `btnCopyIP` button icon upon copying IP address to clipboard.

## [v1.9.3.5]
- **[fix]** Replaced hardcoded status indicator dot colors (`#1D1226` and `#4CAF50`) in Nearby Users list with dynamic `{DynamicResource SecondaryBrush}` and `{DynamicResource SecondaryBackgroundBrush}` tokens for 100% theme compliance.
- **[minor]** Upgraded floating download dock entrance animation to a springy `BackEase` overshoot effect and exit to a 0.35s `CubicEase` slide-down.

## [v1.9.3.0]
- **[minor]** Added springy `BackEase` overshoot pop-in entrance animation and smooth scale/translate slide-down exit animation to floating download dock (`dockDownloadToast`).
- **[fix]** Added root directory detection to `btnUpDir`: automatically dims `btnUpDir` (Opacity 0.4, Arrow cursor) when at `/sdcard/` root and activates (Opacity 1.0, Hand cursor) in subdirectories.
- **[fix]** Added directory creation fallback logic to `Downloads\dex` pulling so restricted/locked paths fall back to `$env:TEMP\dex` without failing.

## [v1.9.2.6]
- **[fix]** Removed redundant hardcoded color logic for the 'Exit Engine' confirmation state to ensure it exclusively pulls from the dynamic `AccentBrush` theme resource.

## [v1.9.2.5]
- **[fix]** Filtered out ADB error outputs (`ls:`, `error:`, `Permission denied`) to prevent invalid items from being parsed into the File Explorer grid.
- **[fix]** Auto-reset search bar filter text upon subfolder navigation so subfolder contents are never hidden by stale parent query strings.
- **[fix]** Stopped pending search debouncer timers before navigating directories to eliminate cross-directory item mutation conflicts.

## [v1.9.2.0]
- **[minor]** Implemented dual highlighters for File Explorer items: persistent greenish highlight for single-clicked `IsSelected` items and a separate active hover highlight for `IsMouseOver` items.
- **[minor]** Calibrated Light Mode highlight brushes (`ItemHoverBrush`, `ItemSelectedBrush`, `ItemSelectedHoverBrush`, `ItemSelectedBorderBrush`) with deeper green shades (`#34C759`) for crisp visibility against light backgrounds.
- **[minor]** Enhanced floating download dock with smooth 0.2s `FadeIn` and 4-second auto-hide `FadeOut` animations.
- **[fix]** Ensured zero hardcoded colors in floating dock layout; fully compliant with dynamic theme tokens (`{DynamicResource}`).

## [v1.9.1.0]
- **[minor]** Updated File Explorer download destination path to `Downloads\dex`.
- **[minor]** Added a subtle floating dock notification banner ("Saved to Downloads\dex") with an interactive `Change` button to choose a custom save directory.
- **[fix]** Removed WPF's default blueish highlighter border/background when hovering over or selecting files and folders in the ListBox.

## [v1.9.0.6]
- **[minor]** Added 150ms search debouncing using `DispatcherTimer` to ensure 60 FPS ultra-smooth real-time filtering in large directories without CPU spikes.
- **[minor]** Added Escape key quick-clear logic to reset active search query before unfocusing or contracting the menu.

## [v1.9.0.5]
- **[fix]** Fixed searchbar text input and accidental disconnection bug: WPF `TextBox.IsFocused` evaluated to false when keyboard focus was active in `txtSearch`, causing top-level hotkeys ('D' for disconnect, 'C' for connect, 'P' for pull, 'M' for mirror, 'Q' for quit) to hijack typing and swallow characters.
- **[fix]** Implemented multi-layered focus and `OriginalSource` detection (`IsKeyboardFocused`, `IsKeyboardFocusWithin`, `OriginalSource -match "TextBox"`) so search terms like 'DCIM', 'Downloads', 'Documents', 'Pictures', 'Movies' type smoothly without triggering shortcuts or disconnecting.
- **[fix]** Added dynamic `CaretBrush="{DynamicResource PrimaryTextBrush}"` for clean cursor visibility in both Light and Dark themes.

## [v1.9.0.4]
- **[fix]** Removed explicit width and height constraints on profile avatars, allowing them to size naturally within the list item container margins and preventing horizontal clipping.

## [v1.9.0.3]
- **[fix]** Adjusted the margins of the Profile Avatars to prevent them from being clipped by the main window's rounded corners or overlapping with the spatial menu borders.

## [v1.9.0.2]
- **[fix]** Restored the Profile Avatar to the bottom-left 'Exit Engine' area when the menu is contracted, and animated it to instantly jump to the top right of the File Explorer search bar only when the menu is expanded.
- **[minor]** Replaced the Exit button's 'bin' icon with the avatar and tightened the spacing.
- **[minor]** Made the ScrollViewer scrollbar even slimmer and shorter.

## [v1.8.9.3]
- **[minor]** Replaced the MessageBox exit dialog with an inline double-click state on the Exit Engine button itself to match the application aesthetic minimally.

## [v1.8.8.3]
- **[minor]** Made the ScrollViewer scrollbar significantly thinner and shorter for a cleaner look.
- **[minor]** Relocated the Profile Avatar button to sit directly to the right of the File Explorer searchbar when the spatial menu is expanded.

## [v1.8.7.3]
- **[fix]** Reverted Nearby Users list from a virtualized ListBox back to a hardcoded StackPanel wrapped in a single auto-scrollbar per user preference.

## [v1.8.6.3]
- **[minor]** Added a confirmation dialog prompt to the 'Exit Engine' button to prevent accidental exits.

## [v1.8.5.3]
- **[minor]** Added a generic profile avatar button to the left of the Exit Engine button to prepare for Google Sign-in and premium gating.

## [v1.8.4.3]
- **[minor]** Re-introduced a sleek, slim scrollbar to the Nearby Users list and fully virtualized the user data structure using a dynamically populated `ListBox` and `VirtualizingStackPanel` for robust rendering performance.

## [v1.8.3.3]
- **[fix]** Made the "Nearby Users" list scrollable by replacing the static `StackPanel` container with a `DockPanel` and a `ScrollViewer` (with hidden scrollbars) to prevent the user list from overflowing on smaller screens.
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
- **Profile Customization**: Refined the User List UI to display `joe.belfiore@dex.net` as the subtext and bound the avatar to a real image placeholder (`Assets/JoeAvatar.jpg`).
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
