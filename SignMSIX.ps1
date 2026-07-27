$cert = New-SelfSignedCertificate -Type Custom -Subject "CN=CodeDeX" -KeyUsage DigitalSignature -FriendlyName "CodeDeX Developer Cert" -CertStoreLocation "Cert:\CurrentUser\My" -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3", "2.5.29.19={text}")

$pwd = ConvertTo-SecureString -String "1234" -Force -AsPlainText
Export-PfxCertificate -Cert $cert -FilePath "W:\CodeDeX\Connect-Phone-ADB\CodeDeX.pfx" -Password $pwd
Export-Certificate -Cert $cert -FilePath "W:\CodeDeX\Connect-Phone-ADB\CodeDeX.cer"

& "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe" sign /fd SHA256 /a /f "W:\CodeDeX\Connect-Phone-ADB\CodeDeX.pfx" /p "1234" "W:\CodeDeX\Connect-Phone-ADB\ConnectPhoneADB.msix"
