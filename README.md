# Connect Phone ADB

## Installation (Windows)

Because this app is not yet on the Microsoft Store, it uses a self-signed certificate. Windows will block the installation unless you trust the certificate first.

### Option 1: The Easy Way (Recommended)
1. Download the latest release (`ConnectPhoneADB.msix`, `CodeDeX.cer`, and `Install-App.ps1`).
2. Right-click `Install-App.ps1` and select **Run with PowerShell**.
3. Accept the Admin prompt. It will install the certificate and the app automatically.

### Option 2: The Manual Way
1. Download `ConnectPhoneADB.msix` and `CodeDeX.cer`.
2. Double-click `CodeDeX.cer`.
3. Click **Install Certificate...**
4. Select **Local Machine** -> Next.
5. Select **Place all certificates in the following store** -> Browse.
6. Select **Trusted Root Certification Authorities** -> OK -> Next -> Finish.
7. Double-click `ConnectPhoneADB.msix` to install the app.
