# Handoff Report: Device Interaction & Handshake Flow Investigation (R3)

## 1. Observation

### A. Device List UI Components
- **File:** `DeX/app/src/main/java/com/example/dex/ui/main/MainScreen.kt` (lines 252-272)
  - `LazyColumn` renders discovered devices collected from `viewModel.uiState`.
  - For each `DiscoveredDevice` in `devices`, it invokes `DeviceListItem`.
- **File:** `DeX/app/src/main/java/com/example/dex/ui/components/DeviceListItem.kt` (lines 24-83)
  ```kotlin
  @Composable
  fun DeviceListItem(
      device: DiscoveredDevice,
      onClick: () -> Unit,
      onSendClipboard: (String) -> Unit,
      modifier: Modifier = Modifier
  ) { ... }
  ```
  - Wraps item layout in `DeXPanel` with `.clickable { onClick() }`.
  - Displays alias (`device.info.alias`), endpoint (`${device.ip}:${device.info.port}`), clipboard send button, and send file icon.
  - Does NOT currently inspect whether `device.info.fingerprint` is trusted or untrusted inside `DeviceListItem`, nor does it render a trust badge.

### B. Current Click Behavior (Trusted vs Untrusted)
- **File:** `DeX/app/src/main/java/com/example/dex/ui/main/MainScreen.kt` (lines 257-264)
  ```kotlin
  DeviceListItem(
      modifier = Modifier.animateItem(),
      device = device,
      onClick = {
          selectedDevice = device
          filePickerLauncher.launch(arrayOf("*/*"))
      },
      ...
  )
  ```
  - **Direct Trace:** When a user taps ANY device row (trusted OR untrusted), `onClick` sets `selectedDevice = device` and unconditionally calls `filePickerLauncher.launch(arrayOf("*/*"))`.
  - `MainScreenViewModel.sendHandshake(device)` is NEVER called in the current click handler.

### C. Current `MainScreenViewModel.sendHandshake` Implementation
- **File:** `DeX/app/src/main/java/com/example/dex/ui/main/MainScreenViewModel.kt` (lines 25-27)
  ```kotlin
  fun sendHandshake(device: DiscoveredDevice) {
      // Intended for future logic where we launch ClientEngine to send files or handshake
  }
  ```
  - `sendHandshake` is an empty stub.

### D. ClientEngine & Pairing / Device Registration Backend Infrastructure
- **File:** `DeX/app/src/main/java/com/example/dex/network/ClientEngine.kt` (lines 76-87)
  ```kotlin
  suspend fun registerDevice(ip: String, port: Int, info: RegisterDto): Boolean = withContext(Dispatchers.IO) {
      try {
          val response = client.post("https://$ip:$port/api/localsend/v2/register") {
              contentType(ContentType.Application.Json)
              setBody(info)
          }
          response.status.isSuccess()
      } catch (e: Exception) {
          e.printStackTrace()
          false
      }
  }
  ```
- **File:** `DeX/app/src/main/java/com/example/dex/network/DeviceManager.kt` (lines 37-45)
  - `DeviceManager.savePairedFingerprint(fingerprint)` updates `AuthState.pairedFingerprints` set and persists it to SharedPreferences (`dex_device_prefs`).
- **File:** `DeX/app/src/main/java/com/example/dex/network/TransferState.kt` (lines 18-22)
  - `AuthState.pairedFingerprints` holds the set of currently paired device fingerprints.
- **File:** `DeX/app/src/main/java/com/example/dex/network/DeviceApi.kt` (lines 27-56)
  - Server endpoints handle `/api/localsend/v2/register` and `/api/localsend/v2/pair-prompt`.
- **File:** `DeX/app/src/main/java/com/example/dex/ui/components/ErrorDialogs.kt` (lines 72-153)
  - `PairingRequestDialog(alias, onAccept, onReject)` composable exists and prompts for 6-digit PIN.
- **File:** `DeX/app/src/main/java/com/example/dex/Navigation.kt` (lines 120-133)
  - Observes `AuthState.incomingPairRequest` and displays `PairingRequestDialog` when another device requests pairing.

---

## 2. Logic Chain

```
[User Taps Device in MainScreen.kt]
       │
       ▼
Is device.info.fingerprint in AuthState.pairedFingerprints?
       │
       ├─── YES (Trusted Device) ───────────────────────────────► Open filePickerLauncher.launch(arrayOf("*/*"))
       │                                                         Set selectedDevice = device
       │
       └─── NO (Untrusted Device) ──────────────────────────────► Invoke viewModel.sendHandshake(device)
                                                                       │
                                                                       ▼
                                                          [MainScreenViewModel.sendHandshake]
                                                                       │
                                                                       ▼
                                                       Call clientEngine.registerDevice(...)
                                                       (or pairing request API)
                                                                       │
                                               ┌───────────────────────┴───────────────────────┐
                                               ▼                                               ▼
                                         [Success (200 OK)]                             [Failure / Exception]
                                               │                                               │
                                               ▼                                               ▼
                                  Call DeviceManager.savePairedFingerprint(...)    Show error Toast/Dialog
                                  Update AuthState & trigger Toast feedback       "Pairing failed"
```

1. **Device Trust Evaluation:**
   Currently, `AuthState.pairedFingerprints` contains fingerprints of paired devices. A device is untrusted if `!AuthState.pairedFingerprints.contains(device.info.fingerprint)`.
2. **Branching Click Logic:**
   - For trusted devices: Launch `filePickerLauncher.launch(arrayOf("*/*"))`.
   - For untrusted devices: Trigger `viewModel.sendHandshake(device)` which performs network registration/pairing via `ClientEngine.registerDevice`.
3. **Handshake Protocol Execution:**
   - `sendHandshake` builds `RegisterDto` representing the local device (using injected `DeviceConfig` or context helper).
   - Calls `clientEngine.registerDevice(device.ip, device.info.port, localRegisterDto)`.
   - Upon receiving HTTP 2xx response, `DeviceManager.savePairedFingerprint(device.info.fingerprint)` is invoked to save fingerprint.
   - UI feedback (e.g. Toast or Snackbar "Device paired successfully") is presented to the user.

---

## 3. Caveats

- **State Reactivity of `AuthState.pairedFingerprints`:** `AuthState.pairedFingerprints` is currently a standard `mutableSetOf<String>()`. When `DeviceManager.savePairedFingerprint` or `removePairedFingerprint` is called, Compose components reading raw `AuthState.pairedFingerprints` may not automatically recompose unless `pairedFingerprints` is exposed via a reactive flow (e.g. `MutableStateFlow<Set<String>>`) or updated in ViewModel state.
- **PIN Pairing Protocol vs Register Protocol:** LocalSend v2 has both `/api/localsend/v2/register` and `/api/localsend/v2/pair-prompt`. `ClientEngine.registerDevice` posts to `/register`. If explicit PIN exchange is desired for untrusted devices, `ClientEngine` can be extended with `pairDevice(ip, port, pairRequestDto)`.
- No caveats regarding read-only source constraints — no source code files outside metadata directory were modified during this investigation.

---

## 4. Conclusion & Step-by-Step Modification Requirements

To fulfill Requirement R3 of `ORIGINAL_REQUEST.md`, the implementer must execute the following step-by-step modifications:

### Step 1: Update `MainScreenViewModel.kt`
- Inject `DeviceConfig` into `MainScreenViewModel` constructor.
- Expose paired fingerprints or trust status flow from `DeviceManager`/`AuthState`.
- Implement `sendHandshake(device: DiscoveredDevice, onResult: (Boolean) -> Unit = {})`:
  ```kotlin
  fun sendHandshake(device: DiscoveredDevice, onResult: (Boolean) -> Unit = {}) {
      viewModelScope.launch {
          val localInfo = RegisterDto(
              alias = getDeviceName(), // or deviceConfig alias helper
              version = "2.0",
              deviceModel = android.os.Build.MODEL ?: "Android",
              deviceType = "mobile",
              fingerprint = deviceConfig.fingerprint,
              port = 53317,
              protocol = "https",
              download = true,
              identityHash = deviceConfig.identityHash
          )
          val success = clientEngine.registerDevice(device.ip, device.info.port, localInfo)
          if (success) {
              DeviceManager.savePairedFingerprint(device.info.fingerprint)
          }
          onResult(success)
      }
  }
  ```

### Step 2: Update `MainScreen.kt` Click Logic
- In `LazyColumn` item rendering (`MainScreen.kt` lines 257–268):
  ```kotlin
  val isTrusted = AuthState.pairedFingerprints.contains(device.info.fingerprint)
  DeviceListItem(
      modifier = Modifier.animateItem(),
      device = device,
      onClick = {
          if (isTrusted) {
              selectedDevice = device
              filePickerLauncher.launch(arrayOf("*/*"))
          } else {
              viewModel.sendHandshake(device) { success ->
                  if (success) {
                      Toast.makeText(context, "Paired with ${device.info.alias}", Toast.LENGTH_SHORT).show()
                  } else {
                      Toast.makeText(context, "Pairing failed with ${device.info.alias}", Toast.LENGTH_SHORT).show()
                  }
              }
          }
      },
      onSendClipboard = { ... }
  )
  ```

### Step 3: (Optional Enhancement) Update `DeviceListItem.kt` UI
- Render a trust status indicator (e.g. lock/shield icon or "Paired"/"Guest" chip) in `DeviceListItem` so the user visually distinguishes trusted from untrusted devices.

---

## 5. Verification Method

1. **Compilation Verification:**
   - Run `./gradlew assembleDebug` to ensure all Kotlin files and Koin dependency injections compile cleanly.
2. **Unit Test Verification:**
   - Run `./gradlew test` (or `./gradlew testDebugUnitTest`).
   - Add unit test in `MainScreenViewModelTest.kt` verifying `sendHandshake` invokes `clientEngine.registerDevice` and saves fingerprint on success.
3. **Invalidation Conditions:**
   - If clicking an untrusted device still immediately triggers `filePickerLauncher`, R3 verification fails.
   - If `sendHandshake` fails silently without user feedback or does not record fingerprint in `DeviceManager`, verification fails.
