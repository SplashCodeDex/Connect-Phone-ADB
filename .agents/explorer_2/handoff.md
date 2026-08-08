# Handoff Report — Explorer 2 (Backend & State Management Specialist)

## Executive Summary
This report provides a read-only investigation of the backend, state management, and storage layer in `DeX` (`W:\CodeDeX\DeX\DeX`). Specifically, it details the architecture, signatures, thread safety, and exact integration points for `DeviceManager`, `SafStorage`, `ClientEngine`, and `MainScreenViewModel`.

---

## 1. Observation

### 1.1 `DeviceManager`
* **File Path**: `W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\network\DeviceManager.kt`
* **Type**: `object` (Singleton)
* **Underlying Storage**: `SharedPreferences` named `"dex_device_prefs"`
  * `KEY_PAIRED_FINGERPRINTS = "paired_fingerprints"` (Set<String>)
  * `KEY_PAIRED_TOKENS = "paired_tokens"` (String, serialized via `TokenCodec`)
* **In-Memory State**: `AuthState` (defined in `W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\network\TransferState.kt:18-23`)
  * `AuthState.pairedFingerprints`: `MutableSet<String>`
  * `AuthState.pairedTokens`: `MutableMap<String, String>`
* **Public Methods**:
  ```kotlin
  fun init(context: Context)
  fun savePairedFingerprint(fingerprint: String)
  fun savePairedToken(fingerprint: String, token: String)
  fun removePairedFingerprint(fingerprint: String)
  ```
* **Method Details — `removePairedFingerprint(fingerprint: String)`**:
  * Lines 47–54 in `DeviceManager.kt`:
    ```kotlin
    fun removePairedFingerprint(fingerprint: String) {
        AuthState.pairedFingerprints.remove(fingerprint)
        AuthState.pairedTokens.remove(fingerprint)
        prefs.edit {
            putStringSet(KEY_PAIRED_FINGERPRINTS, AuthState.pairedFingerprints.toSet())
            putString(KEY_PAIRED_TOKENS, com.example.dex.network.TokenCodec.encode(AuthState.pairedTokens))
        }
    }
    ```
* **Thread Safety / Coroutines**: Executes synchronously using `SharedPreferences.edit`. Mutates `AuthState.pairedFingerprints` and `AuthState.pairedTokens` directly in memory.

### 1.2 `SafStorage`
* **File Path**: `W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\network\SafStorage.kt`
* **Type**: `object` (Singleton)
* **Underlying Storage**: `SharedPreferences` named `"dex_saf_prefs"`
  * `KEY_DOWNLOADS_DEX_URI = "downloads_dex_uri"` (String)
  * `KEY_GRANTED_FOLDERS = "granted_folders"` (JSON Object String mapping `folderName: String` -> `uriString: String`)
* **Public Methods**:
  ```kotlin
  fun getDownloadsDexUri(context: Context): Uri?
  fun setDownloadsDexUri(context: Context, uri: Uri)
  fun writeToDownloadsDex(context: Context, fileName: String, input: InputStream): Boolean
  fun writeFile(context: Context, dirUri: Uri, fileName: String, input: InputStream): Boolean
  fun openOutputStream(context: Context, dirUri: Uri, fileName: String): OutputStream?
  fun getGrantedFolders(context: Context): Map<String, String>
  fun addGrantedFolder(context: Context, name: String, uri: Uri)
  fun removeGrantedFolder(context: Context, name: String)
  fun listChildren(context: Context, treeUri: Uri): List<BrowseFileDto>
  fun readDocument(context: Context, docUri: Uri, out: OutputStream): Boolean
  fun readDocumentBytes(context: Context, docUri: Uri): ByteArray?
  ```
* **Method Details — `getGrantedFolders` and `removeGrantedFolder`**:
  * Lines 71–82 in `SafStorage.kt`: `getGrantedFolders(context)` reads JSON string from `"granted_folders"` preference and returns `Map<String, String>` (folder name -> URI string).
  * Lines 99–106 in `SafStorage.kt`:
    ```kotlin
    fun removeGrantedFolder(context: Context, name: String) {
        val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        val current = getGrantedFolders(context).toMutableMap()
        current.remove(name)
        val json = JSONObject()
        current.forEach { (k, v) -> json.put(k, v) }
        prefs.edit { putString(KEY_GRANTED_FOLDERS, json.toString()) }
    }
    ```
* **Thread Safety / Coroutines**: Operates synchronously using standard `SharedPreferences` and JSON parsing.

### 1.3 `ClientEngine`
* **File Path**: `W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\network\ClientEngine.kt`
* **Type**: `class ClientEngine(engine: HttpClientEngine? = null)` (Registered as Singleton in `AppModule.kt:16`)
* **StateFlows & Properties**:
  * `val uploadState: StateFlow<UploadState>` (backed by `_uploadState: MutableStateFlow<UploadState>`)
  * `var activeWorkId: java.util.UUID?`
* **Public Methods**:
  ```kotlin
  fun resetUploadState()
  fun finishUpload(successCount: Int, totalFiles: Int)
  fun cancelUpload(context: android.content.Context)
  suspend fun registerDevice(ip: String, port: Int, info: RegisterDto): Boolean
  suspend fun prepareUpload(ip: String, port: Int, request: PrepareUploadRequestDto, token: String? = null): PrepareUploadResponseDto?
  suspend fun uploadFile(ip: String, port: Int, sessionId: String, fileId: String, fileName: String, token: String, stream: java.io.InputStream, fileSize: Long, fileIndex: Int = 1, totalFiles: Int = 1, previousBatchBytes: Long = 0L, totalBatchSize: Long = fileSize, onProgress: suspend (Float) -> Unit = {}): Boolean
  suspend fun sendClipboard(ip: String, port: Int, text: String, targetFingerprint: String? = null): Boolean
  ```
* **Method Details — `registerDevice(ip: String, port: Int, info: RegisterDto)`**:
  * Lines 76–87 in `ClientEngine.kt`:
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
* **Thread Safety / Coroutines**: Network suspend functions execute inside `withContext(Dispatchers.IO)`. Safe to call from view models or coroutine scopes.

### 1.4 `MainScreenViewModel`
* **File Path**: `W:\CodeDeX\DeX\DeX\app\src\main\java\com\example\dex\ui\main\MainScreenViewModel.kt`
* **Type**: `class MainScreenViewModel(val discoveryEngine: DiscoveryEngine, val clientEngine: ClientEngine) : ViewModel()`
* **StateFlows & Properties**:
  * `val uiState: StateFlow<MainScreenUiState>`
  * Maps `discoveryEngine.devices` (`StateFlow<Map<String, DiscoveredDevice>>`) to `MainScreenUiState.Success(devicesMap.values.toList())`.
  * Sealed interface `MainScreenUiState`: `Loading`, `Error(val throwable: Throwable)`, `Success(val data: List<DiscoveredDevice>)`.
* **Public Methods**:
  ```kotlin
  fun sendHandshake(device: DiscoveredDevice)
  fun sendClipboard(device: DiscoveredDevice, text: String, onResult: (Boolean) -> Unit)
  ```
* **Method Details — `sendHandshake(device: DiscoveredDevice)`**:
  * Lines 25–27 in `MainScreenViewModel.kt`:
    ```kotlin
    fun sendHandshake(device: DiscoveredDevice) {
        // Intended for future logic where we launch ClientEngine to send files or handshake
    }
    ```
    Currently an empty stub awaiting implementation.

---

## 2. Logic Chain

1. **R1: Trusted Devices Manager (Unpair / Forget Device)**
   - `AuthState.pairedFingerprints` contains all fingerprints of paired/trusted devices loaded by `DeviceManager.init(context)`.
   - `DeviceManager.removePairedFingerprint(fingerprint)` removes the fingerprint from `AuthState.pairedFingerprints` and `AuthState.pairedTokens` and updates `SharedPreferences`.
   - UI bottom sheet / dialog can read `AuthState.pairedFingerprints` (or a helper/flow) and pass selected fingerprint to `DeviceManager.removePairedFingerprint(fingerprint)`.

2. **R2: Shared Folders Manager (Revoke Folder Access)**
   - `SafStorage.getGrantedFolders(context)` returns a `Map<String, String>` of granted folder name to URI.
   - `SafStorage.removeGrantedFolder(context, folderName)` removes the folder from the JSON preference `"granted_folders"`.
   - UI bottom sheet / dialog can retrieve the map via `SafStorage.getGrantedFolders(context)` and invoke `SafStorage.removeGrantedFolder(context, folderName)` on user request.

3. **R3: Connection Handshake Flow**
   - In `MainScreen.kt`, when a user taps a device item in `LazyColumn`:
     - If device is trusted (`AuthState.pairedFingerprints.contains(device.info.fingerprint)`), directly open file picker (`filePickerLauncher.launch(arrayOf("*/*"))`).
     - If device is untrusted (`!AuthState.pairedFingerprints.contains(device.info.fingerprint)`), call `viewModel.sendHandshake(device)`.
   - In `MainScreenViewModel.kt`, implement `sendHandshake(device)` to launch a coroutine (`viewModelScope.launch`) calling `clientEngine.registerDevice(device.ip, device.info.port, localRegisterDto)` (or sending pairing request).
   - Upon successful response, mark device as paired via `DeviceManager.savePairedFingerprint(device.info.fingerprint)`.

---

## 3. Caveats

1. **AuthState Reactivity**: `AuthState.pairedFingerprints` is currently a plain `MutableSet<String>`, not a `StateFlow`. UI components observing paired devices need either a trigger or a `StateFlow` wrapper to automatically re-render when a device is removed/added.
2. **SafStorage Perms**: `removeGrantedFolder` updates `SharedPreferences` but does not explicitly call `releasePersistableUriPermission`. This is safe because removal from preferences revokes access within the app, but worth noting.
3. **RegisterDto Creation in ViewModel**: To call `clientEngine.registerDevice`, `MainScreenViewModel` needs access to the local device's `RegisterDto` info (which can be obtained via `DeviceConfig` or `DiscoveryEngine`).

---

## 4. Conclusion

The existing backend architecture is clean and well-structured:
* `DeviceManager.removePairedFingerprint` is fully implemented and ready for UI wiring.
* `SafStorage.removeGrantedFolder` and `SafStorage.getGrantedFolders` are fully implemented and ready for UI wiring.
* `ClientEngine.registerDevice` is fully implemented for device registration/handshake over HTTPS.
* `MainScreenViewModel.sendHandshake` is an explicit stub ready to be filled with coroutine logic using `clientEngine.registerDevice`.

---

## 5. Verification Method

1. **Build & Unit Tests**:
   - Run `./gradlew test` or `./gradlew testDebugUnitTest` to verify backend state tests.
2. **File Inspection**:
   - Confirm `DeviceManager.kt`, `SafStorage.kt`, `ClientEngine.kt`, and `MainScreenViewModel.kt` locations and signatures match this report.
3. **Integration Verification**:
   - Verify `DeviceManager.removePairedFingerprint` clears both set and tokens map.
   - Verify `SafStorage.removeGrantedFolder` updates JSON prefs.
   - Verify `MainScreenViewModel.sendHandshake` invokes `ClientEngine.registerDevice`.
