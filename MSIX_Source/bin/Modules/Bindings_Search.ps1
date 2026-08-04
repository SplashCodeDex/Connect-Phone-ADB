$script:txtSearch = $script:wpfWindow.FindName("txtSearch")
$script:txtSearch.Add_GotFocus({
    if ($script:txtSearch.Text -eq "Search transfers...") {
        $script:txtSearch.Text = ""
        $script:txtSearch.Foreground = $script:wpfWindow.FindResource("PrimaryTextBrush")
    }
})
$script:txtSearch.Add_LostFocus({
    if ([string]::IsNullOrWhiteSpace($script:txtSearch.Text)) {
        $script:txtSearch.Text = "Search transfers..."
        $script:txtSearch.Foreground = $script:wpfWindow.FindResource("SecondaryTextBrush")
    }
})
$script:searchTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:searchTimer.Interval = [TimeSpan]::FromMilliseconds(150)
$script:searchTimer.Add_Tick({
    $script:searchTimer.Stop()
    $query = $script:txtSearch.Text.ToLower()
    if ($query -eq "search transfers...") { $query = "" }
    foreach ($item in $script:lbFiles.Items) {
        $name = if ($item.Content -and $item.Content.Name) { $item.Content.Name.ToLower() } else { "" }
        if ([string]::IsNullOrWhiteSpace($query) -or $name.Contains($query)) {
            $item.Visibility = 'Visible'
        } else {
            $item.Visibility = 'Collapsed'
        }
    }
})

$script:txtSearch.Add_TextChanged({
    if ($null -ne $script:searchTimer) {
        $script:searchTimer.Stop()
        $script:searchTimer.Start()
    }
})
