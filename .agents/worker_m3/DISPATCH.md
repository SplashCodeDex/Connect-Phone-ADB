## 2026-08-08T01:05:35Z
You are Worker 3 implementing Milestone 3: Connection Handshake Flow & Untrusted Device Pairing.
Your working directory for metadata/handoff is: W:\CodeDeX\DeX\.agents\worker_m3
Project source root: W:\CodeDeX\DeX\DeX

Read ORIGINAL_REQUEST.md at W:\CodeDeX\DeX\.agents\ORIGINAL_REQUEST.md.
Read Explorer reports at W:\CodeDeX\DeX\.agents\explorer_1\handoff.md, explorer_2\handoff.md, explorer_3\handoff.md.

Task & Requirements:
1. Update `MainScreenViewModel.kt` (`W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\ui\main\MainScreenViewModel.kt`):
   - Implement `sendHandshake(device: DiscoveredDevice, onResult: (Boolean) -> Unit = {})`:
     - Construct `RegisterDto` representing the local device (obtain alias, model, fingerprint, port from `DeviceConfig` or defaults).
     - Launch coroutine (`viewModelScope.launch`) calling `clientEngine.registerDevice(device.ip, device.info.port, localRegisterDto)`.
     - If `registerDevice` succeeds (returns `true`), call `DeviceManager.savePairedFingerprint(device.info.fingerprint)`.
     - Invoke `onResult(success)`.

2. Update `MainScreen.kt` (`W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\ui\main\MainScreen.kt`):
   - Update device click logic in `DeviceListItem`:
     - Check `isTrusted = AuthState.pairedFingerprints.contains(device.info.fingerprint)`.
     - If `isTrusted`: set `selectedDevice = device` and launch `filePickerLauncher.launch(arrayOf("*/*"))`.
     - If NOT `isTrusted`: invoke `viewModel.sendHandshake(device)` and show Toast feedback ("Pairing with [alias]..." / "Paired successfully!" or "Pairing failed!").

3. Update `DeviceListItem.kt` (`W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\ui\components\DeviceListItem.kt`):
   - Add a visual trust indicator (e.g., lock icon or "Paired"/"Guest" chip) so users can distinguish trusted vs. untrusted devices. Use existing design system styling and Material theme colors.

4. Verify build & quality:
   - Run `./gradlew assembleDebug` in `W:\CodeDeX\DeX\DeX`.
   - Run `./gradlew lintDebug` in `W:\CodeDeX\DeX\DeX`.
