Add-Type -AssemblyName System.Drawing
$b = New-Object System.Drawing.Bitmap(150,150)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.Clear([System.Drawing.Color]::CornflowerBlue)
$b.Save("W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\Assets\Square150x150Logo.png", [System.Drawing.Imaging.ImageFormat]::Png)

$b = New-Object System.Drawing.Bitmap(44,44)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.Clear([System.Drawing.Color]::CornflowerBlue)
$b.Save("W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\Assets\Square44x44Logo.png", [System.Drawing.Imaging.ImageFormat]::Png)

$b = New-Object System.Drawing.Bitmap(310,150)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.Clear([System.Drawing.Color]::CornflowerBlue)
$b.Save("W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\Assets\Wide310x150Logo.png", [System.Drawing.Imaging.ImageFormat]::Png)

$b = New-Object System.Drawing.Bitmap(50,50)
$g = [System.Drawing.Graphics]::FromImage($b)
$g.Clear([System.Drawing.Color]::CornflowerBlue)
$b.Save("W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\Assets\StoreLogo.png", [System.Drawing.Imaging.ImageFormat]::Png)

Copy-Item -Path "W:\CodeDeX\Connect-Phone-ADB\ConnectPhoneShareTarget\bin\Debug\net10.0-windows10.0.19041.0\*" -Destination "W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\" -Force -Recurse
Copy-Item -Path "W:\CodeDeX\Connect-Phone-ADB\bin\*" -Destination "W:\CodeDeX\Connect-Phone-ADB\MSIX_Source\bin\" -Force -Recurse

# Create the MSIX
& "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\makeappx.exe" pack /d "W:\CodeDeX\Connect-Phone-ADB\MSIX_Source" /p "W:\CodeDeX\Connect-Phone-ADB\ConnectPhoneADB.msix" /o
