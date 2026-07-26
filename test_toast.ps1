try {
    [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
    [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom, ContentType = WindowsRuntime] | Out-Null
    $xmlString = @"
<toast>
  <visual>
    <binding template="ToastGeneric">
      <text>Test Icon</text>
      <text>Testing yuzu-emu.ico</text>
      <image placement="appLogoOverride" hint-crop="none" src="file:///C:/ICO/yuzu-emu.ico"/>
    </binding>
  </visual>
</toast>
"@
    $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
    $xml.LoadXml($xmlString)
    $toast = [Windows.UI.Notifications.ToastNotification]::new($xml)
    $notifier = [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Connect Phone ADB")
    $notifier.Show($toast)
    Write-Host "Success!"
} catch {
    Write-Host "Failed: $_"
}
