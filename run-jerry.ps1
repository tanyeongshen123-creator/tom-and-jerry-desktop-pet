# Standalone Windows Desktop Pet Runner for Jerry (Tom and Jerry)
# Runs directly on Windows using built-in WPF (no third-party installs needed).
param(
    [string]$PetId = "jerry",
    [double]$Scale = 0.5
)

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

# Supported actions:
# stand (row 0), walk-right (row 1), walk-left (row 2),
# dizzy (rows 3..5, 24 frames), run-right (row 6), run-left (row 7),
# hungry (rows 8..10, 24 frames)
$rows = @{
    'stand'      = 0
    'walk-right' = 1
    'walk-left'  = 2
    'dizzy'      = 3
    'run-right'  = 6
    'run-left'   = 7
    'hungry'     = 8
}

$defaultHolds = @{
    'stand'      = @(200, 200, 200, 200, 200, 200)
    'walk-right' = @(120, 120, 120, 120, 120, 120, 120, 120)
    'walk-left'  = @(120, 120, 120, 120, 120, 120, 120, 120)
    'dizzy'      = @(60) * 24
    'run-right'  = @(65, 65, 65, 65, 65, 65, 65, 65)
    'run-left'   = @(65, 65, 65, 65, 65, 65, 65, 65)
    'hungry'     = @(140) * 24
}

$cellW = 192
$cellH = 208

$script:currentPetId = $PetId
$script:scale = $Scale
$script:mode = "Auto"          # "Auto" (Free Roam), "BottomWalk" (Taskbar Roam), "Chase", or "Fixed"
$script:state = "stand"
$script:frameIndex = 0
$script:frameElapsedMs = 0
$script:stateElapsedMs = 0
$script:stateDurationMs = 1800
$script:targetX = 0
$script:targetY = 0
$script:isDragging = $false
$script:dragMoved = $false
$script:dragStartMouse = [System.Drawing.Point]::Empty
$script:dragStartWin = [System.Windows.Point]::new(0, 0)
$script:lastClickUtc = [DateTime]::MinValue
$script:holds = $defaultHolds.Clone()
$script:croppedFrames = @{}
$script:random = [System.Random]::new()

function Load-PetSprites([string]$id) {
    $sheetPath = Join-Path $scriptDir "pets\$id\spritesheet.png"
    if (-not (Test-Path $sheetPath)) {
        $fallbackPath = Join-Path $HOME ".codex\pets\$id\spritesheet.png"
        if (Test-Path $fallbackPath) { $sheetPath = $fallbackPath }
        else { throw "Could not find spritesheet for '$id' at $sheetPath" }
    }

    $uri = [System.Uri]::new($sheetPath)
    $bitmap = [System.Windows.Media.Imaging.BitmapImage]::new()
    $bitmap.BeginInit()
    $bitmap.UriSource = $uri
    $bitmap.CacheOption = [System.Windows.Media.Imaging.BitmapCacheOption]::OnLoad
    $bitmap.EndInit()
    $bitmap.Freeze()

    $maxRows = [Math]::Min(11, [int][Math]::Floor($bitmap.PixelHeight / $cellH))
    $frames = @{}
    for ($r = 0; $r -lt $maxRows; $r++) {
        for ($c = 0; $c -lt 8; $c++) {
            $rect = [System.Windows.Int32Rect]::new($c * $cellW, $r * $cellH, $cellW, $cellH)
            $crop = [System.Windows.Media.Imaging.CroppedBitmap]::new($bitmap, $rect)
            $crop.Freeze()
            $frames["$r,$c"] = $crop
        }
    }
    $script:croppedFrames = $frames
    $script:currentPetId = $id
}

Load-PetSprites -id $script:currentPetId

# Create transparent topmost WPF window
$window = [System.Windows.Window]::new()
$window.Title = "Jerry Desktop Pet"
$window.WindowStyle = [System.Windows.WindowStyle]::None
$window.AllowsTransparency = $true
$window.Background = [System.Windows.Media.Brushes]::Transparent
$window.Topmost = $true
$window.ShowInTaskbar = $false
$window.ResizeMode = [System.Windows.ResizeMode]::NoResize
$window.Width = $cellW * $script:scale
$window.Height = $cellH * $script:scale

$workArea = [System.Windows.SystemParameters]::WorkArea
$window.Left = [Math]::Max(40, $workArea.Right - $window.Width - 120)
$window.Top = [Math]::Max(40, $workArea.Bottom - $window.Height - 10)

$image = [System.Windows.Controls.Image]::new()
$image.Stretch = [System.Windows.Media.Stretch]::Fill
[System.Windows.Media.RenderOptions]::SetBitmapScalingMode($image, [System.Windows.Media.BitmapScalingMode]::HighQuality)
$image.Source = $script:croppedFrames["0,0"]
$window.Content = $image

function Set-PetState([string]$newState, [int]$durationMs = 3000) {
    $script:state = $newState
    $script:frameIndex = 0
    $script:frameElapsedMs = 0
    $script:stateElapsedMs = 0
    $script:stateDurationMs = $durationMs
}

function Start-RandomMove([bool]$bottomOnly = $false, [bool]$run = $false) {
    $wa = [System.Windows.SystemParameters]::WorkArea
    $minX = [int]($wa.Left + 20)
    $maxX = [int][Math]::Max($minX + 50, $wa.Right - $window.Width - 20)
    $minY = [int]($wa.Top + 20)
    $maxY = [int][Math]::Max($minY + 50, $wa.Bottom - $window.Height - 5)

    $minDist = if ($run) { 220 } else { 120 }
    for ($attempt = 0; $attempt -lt 6; $attempt++) {
        $candidateX = $script:random.Next($minX, $maxX)
        if ([Math]::Abs($candidateX - $window.Left) -gt $minDist) {
            $script:targetX = $candidateX
            break
        }
        $script:targetX = $candidateX
    }

    if ($bottomOnly) {
        $script:targetY = $wa.Bottom - $window.Height - 5
    }
    else {
        $script:targetY = $script:random.Next($minY, $maxY)
    }

    $goingRight = ($script:targetX -ge $window.Left)
    if ($run) {
        $dir = if ($goingRight) { "run-right" } else { "run-left" }
        Set-PetState $dir 6000
    }
    else {
        $dir = if ($goingRight) { "walk-right" } else { "walk-left" }
        Set-PetState $dir 8000
    }
}

function Pick-NextAutoAction([bool]$bottomOnly = $false) {
    $wasMoving = ($script:state -in @("walk-right", "walk-left", "run-right", "run-left"))
    $roll = $script:random.Next(100)

    if ($wasMoving) {
        # After finishing a walk/run, either stand or act hungry
        if ($roll -lt 65) {
            Set-PetState "stand" ($script:random.Next(1500, 3000))
        }
        else {
            Set-PetState "hungry" 3360
        }
    }
    elseif ($script:state -eq "dizzy" -or $script:state -eq "hungry") {
        Set-PetState "stand" ($script:random.Next(1400, 2600))
    }
    else {
        # From stand: 40% walk, 30% run, 18% hungry, 12% keep standing
        if ($roll -lt 40) {
            Start-RandomMove -bottomOnly:$bottomOnly -run:$false
        }
        elseif ($roll -lt 70) {
            Start-RandomMove -bottomOnly:$bottomOnly -run:$true
        }
        elseif ($roll -lt 88) {
            Set-PetState "hungry" 3360
        }
        else {
            Set-PetState "stand" ($script:random.Next(1500, 2800))
        }
    }
}

function Set-PetScale([double]$newScale) {
    $centerBottomX = $window.Left + $window.Width / 2
    $bottomY = $window.Top + $window.Height
    $script:scale = $newScale
    $window.Width = $cellW * $script:scale
    $window.Height = $cellH * $script:scale
    $window.Left = $centerBottomX - $window.Width / 2
    $window.Top = $bottomY - $window.Height
}

function Get-CursorPositionDip() {
    $pt = [System.Windows.Forms.Cursor]::Position
    $source = [System.Windows.PresentationSource]::FromVisual($window)
    if ($source -and $source.CompositionTarget) {
        $matrix = $source.CompositionTarget.TransformFromDevice
        return $matrix.Transform([System.Windows.Point]::new($pt.X, $pt.Y))
    }
    return [System.Windows.Point]::new($pt.X, $pt.Y)
}

# Build right-click context menu
$contextMenu = [System.Windows.Controls.ContextMenu]::new()

function Add-MenuOption([string]$header, [scriptblock]$action) {
    $item = [System.Windows.Controls.MenuItem]::new()
    $item.Header = $header
    $item.Add_Click($action)
    [void]$contextMenu.Items.Add($item)
    return $item
}

Add-MenuOption "Mode: Free Roam Anywhere (Default)" {
    $script:mode = "Auto"
    Start-RandomMove -bottomOnly:$false -run:$false
} | Out-Null

Add-MenuOption "Mode: Roam Along Bottom (Taskbar)" {
    $script:mode = "BottomWalk"
    Start-RandomMove -bottomOnly:$true -run:$false
} | Out-Null

Add-MenuOption "Mode: Chase Cursor" {
    $script:mode = "Chase"
    Set-PetState "stand" 999999
} | Out-Null

[void]$contextMenu.Items.Add([System.Windows.Controls.Separator]::new())

$motionMenu = [System.Windows.Controls.MenuItem]::new()
$motionMenu.Header = "Lock Single Action"
foreach ($motion in @('stand', 'walk-right', 'walk-left', 'run-right', 'run-left', 'dizzy', 'hungry')) {
    $mItem = [System.Windows.Controls.MenuItem]::new()
    $mItem.Header = $motion
    $mItem.Tag = $motion
    $mItem.Add_Click({
            param($sender, $e)
            $script:mode = "Fixed"
            Set-PetState $sender.Tag 999999
        })
    [void]$motionMenu.Items.Add($mItem)
}
[void]$contextMenu.Items.Add($motionMenu)

$sizeMenu = [System.Windows.Controls.MenuItem]::new()
$sizeMenu.Header = "Size"
foreach ($s in @(0.5, 0.75, 1.0, 1.25, 1.5)) {
    $sItem = [System.Windows.Controls.MenuItem]::new()
    $sItem.Header = if ($s -eq 0.5) { "0.5x (Default)" } else { "$($s)x" }
    $sItem.Tag = $s
    $sItem.Add_Click({
            param($sender, $e)
            Set-PetScale ([double]$sender.Tag)
        })
    [void]$sizeMenu.Items.Add($sItem)
}
[void]$contextMenu.Items.Add($sizeMenu)

[void]$contextMenu.Items.Add([System.Windows.Controls.Separator]::new())

Add-MenuOption "Exit Pet" {
    $window.Close()
} | Out-Null

$window.ContextMenu = $contextMenu

# Mouse drag, single-click & double-click interaction
$window.Add_MouseLeftButtonDown({
        param($sender, $e)
        $now = [DateTime]::UtcNow
        $msSinceLast = ($now - $script:lastClickUtc).TotalMilliseconds

        if ($e.ClickCount -ge 2 -or $msSinceLast -lt 380) {
            # Double left-click -> trigger dizzy action!
            $script:lastClickUtc = [DateTime]::MinValue
            $script:isDragging = $false
            $window.ReleaseMouseCapture()
            Set-PetState "dizzy" 2880
            return
        }

        $script:lastClickUtc = $now
        $script:isDragging = $true
        $script:dragMoved = $false
        $script:dragStartMouse = [System.Windows.Forms.Cursor]::Position
        $script:dragStartWin = [System.Windows.Point]::new($window.Left, $window.Top)
        $window.CaptureMouse() | Out-Null
    })

$window.Add_MouseMove({
        param($sender, $e)
        if ($script:isDragging) {
            $cur = [System.Windows.Forms.Cursor]::Position
            $dx = $cur.X - $script:dragStartMouse.X
            $dy = $cur.Y - $script:dragStartMouse.Y
            if ([Math]::Abs($dx) -gt 4 -or ([Math]::Abs($dy) -gt 4)) {
                $script:dragMoved = $true
            }
            $source = [System.Windows.PresentationSource]::FromVisual($window)
            $scaleX = 1.0
            $scaleY = 1.0
            if ($source -and $source.CompositionTarget) {
                $m = $source.CompositionTarget.TransformFromDevice
                $scaleX = $m.M11
                $scaleY = $m.M22
            }
            $window.Left = $script:dragStartWin.X + ($dx * $scaleX)
            $window.Top = $script:dragStartWin.Y + ($dy * $scaleY)
        }
    })

$window.Add_MouseLeftButtonUp({
        param($sender, $e)
        if ($script:isDragging) {
            $script:isDragging = $false
            $window.ReleaseMouseCapture()
        }
    })

# Main animation & behavior loop (ticks every 20ms)
$tickMs = 20
$timer = [System.Windows.Threading.DispatcherTimer]::new()
$timer.Interval = [TimeSpan]::FromMilliseconds($tickMs)

$timer.Add_Tick({
        $script:stateElapsedMs += $tickMs
        $cursor = Get-CursorPositionDip

        if (-not $script:isDragging) {
            if (($script:state -eq "dizzy" -or $script:state -eq "hungry") -and $script:mode -ne "Fixed") {
                # Keep playing dizzy or hungry animation in place until duration finishes
                if ($script:stateElapsedMs -ge $script:stateDurationMs) {
                    Pick-NextAutoAction -bottomOnly:($script:mode -eq "BottomWalk")
                }
            }
            elseif ($script:mode -eq "Chase") {
                $petCenterX = $window.Left + ($window.Width / 2.0)
                $petFootY = $window.Top + ($window.Height * 0.90)
                $dx = $cursor.X - $petCenterX
                $dy = $cursor.Y - $petFootY
                $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
                if ($dist -gt (260 * $script:scale)) {
                    $moveDir = if ($dx -ge 0) { "run-right" } else { "run-left" }
                    if ($script:state -ne $moveDir) {
                        $script:state = $moveDir
                        $script:frameIndex = 0
                        $script:frameElapsedMs = 0
                    }
                    $speed = 7.8 * $script:scale
                    $window.Left += ($dx / $dist) * $speed
                    $window.Top += ($dy / $dist) * $speed
                }
                elseif ($dist -gt (110 * $script:scale)) {
                    $moveDir = if ($dx -ge 0) { "walk-right" } else { "walk-left" }
                    if ($script:state -ne $moveDir) {
                        $script:state = $moveDir
                        $script:frameIndex = 0
                        $script:frameElapsedMs = 0
                    }
                    $speed = 4.2 * $script:scale
                    $window.Left += ($dx / $dist) * $speed
                    $window.Top += ($dy / $dist) * $speed
                }
                else {
                    $script:state = "stand"
                }
            }
            elseif ($script:mode -eq "Auto" -or $script:mode -eq "BottomWalk") {
                $bottomOnly = ($script:mode -eq "BottomWalk")
                $isRunning = ($script:state -eq "run-right" -or $script:state -eq "run-left")
                $isWalking = ($script:state -eq "walk-right" -or $script:state -eq "walk-left")
                if ($isRunning -or $isWalking) {
                    $dx = $script:targetX - $window.Left
                    $dy = $script:targetY - $window.Top
                    $dist = [Math]::Sqrt($dx * $dx + $dy * $dy)
                    $speed = if ($isRunning) { 7.5 * $script:scale } else { 4.0 * $script:scale }
                    if ($dist -le $speed -or $script:stateElapsedMs -ge $script:stateDurationMs) {
                        Pick-NextAutoAction -bottomOnly:$bottomOnly
                    }
                    else {
                        $window.Left += ($dx / $dist) * $speed
                        $window.Top += ($dy / $dist) * $speed
                    }
                }
                elseif ($script:stateElapsedMs -ge $script:stateDurationMs) {
                    Pick-NextAutoAction -bottomOnly:$bottomOnly
                }
            }
        }

        # Select current frame from spritesheet
        $baseRow = $rows[$script:state]
        $stateHolds = $script:holds[$script:state]
        $script:frameElapsedMs += $tickMs
        if ($script:frameElapsedMs -ge $stateHolds[$script:frameIndex]) {
            $script:frameElapsedMs = 0
            $script:frameIndex = ($script:frameIndex + 1) % $stateHolds.Count
        }
        $row = $baseRow + [int][Math]::Floor($script:frameIndex / 8)
        $col = $script:frameIndex % 8
        $key = "$row,$col"
        $image.Source = $script:croppedFrames[$key]
    })

$window.Add_Closed({
        $timer.Stop()
    })

$timer.Start()
[void]$window.ShowDialog()
