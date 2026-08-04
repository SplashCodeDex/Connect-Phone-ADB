
# --- Wiggle-to-Open Feature ---
try {
    Add-Type -TypeDefinition @"
    using System;
    using System.Runtime.InteropServices;
    public class Win32Input {
        [DllImport("user32.dll")]
        public static extern short GetAsyncKeyState(int vKey);
        [DllImport("user32.dll")]
        public static extern int GetSystemMetrics(int nIndex);
    }
"@
} catch {}

$script:wiggleHistory = @()
$script:wiggleEnabled = $true
$script:wiggleReversalsThreshold = 3
$script:wiggleGraceTicks = 0
$script:wiggleLastTick = [DateTime]::Now
$script:wiggleTimer = New-Object System.Windows.Threading.DispatcherTimer
$script:wiggleTimer.Interval = [TimeSpan]::FromMilliseconds(20)

$script:wiggleTimer.Add_Tick({
    if ($script:wpfWindow.IsVisible) {
        if ($script:openedViaWiggle) {
            $btn = if ([Win32Input]::GetSystemMetrics(23) -ne 0) { 0x02 } else { 0x01 }
            $isDown = ([Win32Input]::GetAsyncKeyState($btn) -band 0x8000) -ne 0
            if (-not $isDown) {
                $script:openedViaWiggle = $false
                # Run at Background priority so WPF Drop events fire first before we hide
                $script:wpfWindow.Dispatcher.InvokeAsync({
                    if ($script:wpfWindow.IsVisible) {
                        $script:wpfWindow.Hide()
                        Reset-SpatialPanels
                        $script:lastDeactivated = [DateTime]::Now
                    }
                }, [System.Windows.Threading.DispatcherPriority]::Background) | Out-Null
            }
        }
        return
    }
    
    $now = [DateTime]::Now
    if (($now - $script:wiggleLastTick).TotalMilliseconds -gt 150) {
        $script:wiggleHistory = @()
    }
    $script:wiggleLastTick = $now

    $btn = if ([Win32Input]::GetSystemMetrics(23) -ne 0) { 0x02 } else { 0x01 }
    $isDown = ([Win32Input]::GetAsyncKeyState($btn) -band 0x8000) -ne 0
    if (-not $isDown) {
        $script:wiggleGraceTicks++
        if ($script:wiggleGraceTicks -gt 2) {
            $script:wiggleHistory = @()
        }
        return
    }
    $script:wiggleGraceTicks = 0

    $pos = [System.Windows.Forms.Cursor]::Position
    $script:wiggleHistory += $pos.X
    if ($script:wiggleHistory.Count -gt 20) {
        # Keep last 1 second of history (20 * 50ms = 1000ms)
        $script:wiggleHistory = $script:wiggleHistory[-20..-1]
    }

    # Wiggle detection logic: count direction reversals
    if ($script:wiggleHistory.Count -ge 5) {
        $reversals = 0
        $lastDir = 0 # 1 for right, -1 for left
        $minX = $script:wiggleHistory[0]
        $maxX = $script:wiggleHistory[0]
        
        for ($i = 1; $i -lt $script:wiggleHistory.Count; $i++) {
            $prev = $script:wiggleHistory[$i-1]
            $curr = $script:wiggleHistory[$i]
            if ($curr -lt $minX) { $minX = $curr }
            if ($curr -gt $maxX) { $maxX = $curr }
            
            $diff = $curr - $prev
            if ([Math]::Abs($diff) -gt 5) { # Minimum delta to be considered a movement
                $dir = if ($diff -gt 0) { 1 } else { -1 }
                if ($lastDir -ne 0 -and $dir -ne $lastDir) {
                    $reversals++
                }
                $lastDir = $dir
            }
        }
        
        $totalDist = $maxX - $minX
        # A wiggle is threshold or more reversals in a localized area (< 150 pixels)
        if ($script:wiggleEnabled -and $reversals -ge $script:wiggleReversalsThreshold -and $totalDist -lt 150) {
            # Wiggle detected! Reset history
            $script:wiggleHistory = @()
            
            # Show the menu near the cursor
            if (-not $script:wpfWindow.IsVisible) {
                # Prepare animations if needed
                $script:wpfWindow.FindName("winScale").ScaleX = 0.85
                $script:wpfWindow.FindName("winScale").ScaleY = 0.85
                $script:wpfWindow.FindName("winTrans").Y = 15
                $script:wpfWindow.FindName("menuTrans").Y = 20
                $script:wpfWindow.FindName("menuContentTrans").Y = 35
                $script:wpfWindow.FindName("menuContentPanel").Opacity = 0
                $script:wpfWindow.FindName("mainBorder").Opacity = 0
                
                # Show only nearby devices (dummies) for Wiggle menu
                $script:wpfWindow.FindName("TopActionsPanel").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("btnUserJoe").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("btnDeviceGalaxy").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("btnDeviceWindows").Visibility = 'Collapsed'
                $script:wpfWindow.FindName("NearbyExpandPanel").Visibility = 'Visible'
                $script:wpfWindow.FindName("NearbyExpandPanel").Opacity = 1
                $script:openedViaWiggle = $true

                try {
                    $sb = $script:wpfWindow.FindResource("PopIn")
                    if ($sb) {
                        $sb.Begin($script:wpfWindow, $true)
                        $sb.Pause($script:wpfWindow)
                    }
                } catch {}

                # Setup position (center window loosely around cursor)
                $winWidth = if ($script:wpfWindow.Width -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Width)) { $script:wpfWindow.Width } else { 1420 }
                $winHeight = if ($script:wpfWindow.Height -gt 0 -and -not [double]::IsNaN($script:wpfWindow.Height)) { $script:wpfWindow.Height } else { 760 }
                
                $targetLeft = $pos.X - ($winWidth / 2)
                $targetTop = $pos.Y - ($winHeight / 2)
                
                # Keep within work area of the correct monitor
                $workArea = [System.Windows.Forms.Screen]::FromPoint($pos).WorkingArea
                if ($targetLeft -lt $workArea.Left) { $targetLeft = $workArea.Left }
                if ($targetTop -lt $workArea.Top) { $targetTop = $workArea.Top }
                if ($targetLeft + $winWidth -gt $workArea.Right) { $targetLeft = $workArea.Right - $winWidth }
                if ($targetTop + $winHeight -gt $workArea.Bottom) { $targetTop = $workArea.Bottom - $winHeight }
                
                $script:wpfWindow.Left = $targetLeft
                $script:wpfWindow.Top = $targetTop
                $script:wpfWindow.Topmost = $true
                
                $script:wpfWindow.Show()
                # (Activate removed to prevent dragging focus loss)

                try {
                    if ($sb) { $sb.Resume($script:wpfWindow) }
                } catch {}
            }
        }
    }
})
$script:wiggleTimer.Start()
