
Add-Type -AssemblyName PresentationFramework
$syncHash = [hashtable]::Synchronized(@{})
$syncHash.Window = New-Object System.Windows.Window
$syncHash.Window.Title = "Test"

[System.Threading.Tasks.Task]::Run([Action]{
    Start-Sleep -Seconds 1
    $syncHash.Window.Dispatcher.Invoke([Action]{
        $syncHash.Window.Title = "Updated from Task"
    })
})

$syncHash.Window.ShowDialog()

