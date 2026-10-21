# Wonder launcher (source only, no game files). Sets NX_* environment variables, starts wonder.exe and shows its log live.
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\launcher\wonder-launcher.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$exe = Join-Path $root 'private\wonder\build\wonder.exe'
$logPath = Join-Path $root 'private\wonder\launcher.log'
$cfgPath = Join-Path $root 'private\wonder\launcher-settings.json'
$script:proc = $null
$script:logPos = 0L

function Add-Label($page, $text, $x, $y, $w) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Left = $x; $l.Top = $y + 3; $l.Width = $w
    $page.Controls.Add($l)
    $l
}
function Add-Hint($page, $text, $y, $h = 70) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Left = 15; $l.Top = $y; $l.Width = 560; $l.Height = $h
    $l.ForeColor = [System.Drawing.Color]::DimGray
    $page.Controls.Add($l)
}
function Add-Check($page, $text, $y) {
    $c = New-Object System.Windows.Forms.CheckBox
    $c.Text = $text; $c.Left = 15; $c.Top = $y; $c.Width = 560
    $page.Controls.Add($c)
    $c
}
function Add-Combo($page, $label, $items, $y, $editable = $false) {
    Add-Label $page $label 15 $y 190 | Out-Null
    $c = New-Object System.Windows.Forms.ComboBox
    $c.Left = 210; $c.Top = $y; $c.Width = 230
    if ($editable) { $c.DropDownStyle = 'DropDown' } else { $c.DropDownStyle = 'DropDownList' }
    [void]$c.Items.AddRange([object[]]$items)
    $c.SelectedIndex = 0
    $page.Controls.Add($c)
    $c
}
function Set-Combo($c, $v) {
    if ($null -eq $v) { return }
    if ($c.DropDownStyle -eq 'DropDownList') {
        if ($c.Items.Contains([string]$v)) { $c.SelectedItem = [string]$v }
    } else { $c.Text = [string]$v }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Super Mario Bros. Wonder - Launcher'
$form.ClientSize = New-Object System.Drawing.Size(620, 590)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'

$tabs = New-Object System.Windows.Forms.TabControl
$tabs.Left = 10; $tabs.Top = 10; $tabs.Width = 600; $tabs.Height = 410
$form.Controls.Add($tabs)
function New-Tab($title) {
    $p = New-Object System.Windows.Forms.TabPage
    $p.Text = $title
    [void]$tabs.TabPages.Add($p)
    $p
}

# ---- Display ----
$tDisp = New-Tab 'Display'
$cFull = Add-Check $tDisp 'Start in fullscreen (F11 or Alt+Enter toggles it in the game)' 15
$cMode = Add-Combo $tDisp 'Console mode' @('Docked (1080p, default)', 'Handheld (720p)') 50
$cUw = Add-Combo $tDisp 'Ultrawide view' @('Off', 'Match window', '21:9', '32:9') 85
$cWin = Add-Combo $tDisp 'Window shape / size' @('Default (16:9)', '1920x1080', '2560x1080', '3440x1440', '5120x1440') 120
Add-Hint $tDisp 'Handheld renders at 720p, docked at 1080p. Ultrawide shows more of the level instead of stretching it. Window shape only sets the aspect of the window (about 80 percent of the screen height).' 165

# ---- Graphics ----
$tGfx = New-Tab 'Graphics'
$cGpu = Add-Combo $tGfx 'GPU' @('Default', 'discrete', 'integrated') 15 $true
$cPipe = Add-Combo $tGfx 'Pipelined submits' @('Default', '0', '1', '2', '3', '4') 50
$cPad = Add-Check $tGfx 'Pad bound buffers (try it if text or characters glitch)' 85
Add-Hint $tGfx 'GPU: leave it on Default (the first discrete GPU). You can also type a GPU number or part of its name. Pipelined submits: Default is synchronous on Windows. 1 to 4 lets the CPU and GPU overlap and can raise fps, but it has drawn broken geometry in some courses on other platforms. Go back to Default if the picture breaks.' 130 90

# ---- Upscaler ----
$tUp = New-Tab 'Upscaler (FSR)'
$cFsr = Add-Check $tUp 'Enable FSR 1 (AMD FidelityFX Super Resolution)' 15
$cSharp = Add-Combo $tUp 'Sharpening (0 sharpest, 2 none)' @('Default (0.2)', '0', '0.5', '1.0', '1.5', '2') 50
Add-Hint $tUp 'FSR upscales the finished picture to the window size and then sharpens it. It works on any GPU, including AMD. It helps most with Handheld 720p on a big window or in fullscreen. DLSS is not offered: it only exists on NVIDIA RTX cards and the game runtime has no DLSS support.' 95 90

# ---- FPS ----
$tFps = New-Tab 'FPS'
$cFps = Add-Combo $tFps 'Frame rate limit' @('Default (game decides)', '30 fps') 15
Add-Hint $tFps 'The game advances one step per frame, so there is no unlock above 60 fps. 30 fps holds the game in its own 30 fps mode (steady and lighter on the GPU).' 60

# ---- Sound ----
$tSnd = New-Tab 'Sound'
$cMute = Add-Check $tSnd 'Mute (no sound device)' 15
Add-Hint $tSnd 'The game runtime has no volume setting yet, only mute.' 50 40

# ---- Controller ----
$tPad = New-Tab 'Controller'
Add-Hint $tPad 'Controller mapping is not available yet. It is not a startup switch: it needs a change in the game input code (read_pad in runtime\src\platform_win.cpp). That will be a separate step.' 15 70

# ---- Advanced ----
$tAdv = New-Tab 'Advanced'
$cLang = Add-Combo $tAdv 'Game language' @('Default', 'en-US', 'en-GB', 'es', 'es-419', 'fr', 'fr-CA', 'de', 'it', 'nl', 'pt', 'pt-BR', 'ru', 'ja', 'ko', 'zh-Hans', 'zh-Hant') 15
$cUser = Add-Combo $tAdv 'Save slot (user number)' @('Default', '1', '2', '3', '4') 50
$cMem = Add-Combo $tAdv 'Memory limit (GB)' @('Default (8)', '6', '8', '12', '16') 85
Add-Label $tAdv 'Extra variables, one per line as NX_NAME=value (see docs\nvn\SWITCHES.md):' 15 125 560 | Out-Null
$txtExtra = New-Object System.Windows.Forms.TextBox
$txtExtra.Multiline = $true; $txtExtra.ScrollBars = 'Vertical'; $txtExtra.AcceptsReturn = $true
$txtExtra.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtExtra.Left = 15; $txtExtra.Top = 155; $txtExtra.Width = 560; $txtExtra.Height = 190
$tAdv.Controls.Add($txtExtra)

# ---- Live log ----
$tLog = New-Tab 'Live log'
$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Both'; $txtLog.WordWrap = $false
$txtLog.MaxLength = 2000000
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Left = 8; $txtLog.Top = 8; $txtLog.Width = 576; $txtLog.Height = 320
$tLog.Controls.Add($txtLog)
$bClear = New-Object System.Windows.Forms.Button
$bClear.Text = 'Clear'; $bClear.Left = 8; $bClear.Top = 335; $bClear.Width = 100
$tLog.Controls.Add($bClear)
$bOpenLog = New-Object System.Windows.Forms.Button
$bOpenLog.Text = 'Open log file'; $bOpenLog.Left = 118; $bOpenLog.Top = 335; $bOpenLog.Width = 120
$tLog.Controls.Add($bOpenLog)

# ---- bottom area ----
$txtPrev = New-Object System.Windows.Forms.TextBox
$txtPrev.Multiline = $true; $txtPrev.ReadOnly = $true; $txtPrev.ScrollBars = 'Vertical'
$txtPrev.Font = New-Object System.Drawing.Font('Consolas', 8)
$txtPrev.Left = 10; $txtPrev.Top = 430; $txtPrev.Width = 600; $txtPrev.Height = 52
$form.Controls.Add($txtPrev)
function New-Btn($text, $x, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Left = $x; $b.Top = 492; $b.Width = $w; $b.Height = 34
    $form.Controls.Add($b)
    $b
}
$bLaunch = New-Btn 'Launch game' 10 150
$bStop = New-Btn 'Stop game' 170 110
$bReset = New-Btn 'Reset settings' 290 120
$bFolder = New-Btn 'Open data folder' 420 130
$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Left = 10; $lblStatus.Top = 540; $lblStatus.Width = 600; $lblStatus.Height = 40
$form.Controls.Add($lblStatus)

# ---- logic ----
function Get-NxEnv {
    $e = [ordered]@{}
    if ($cFull.Checked) { $e['NX_FULLSCREEN'] = '1' }
    if ([string]$cMode.SelectedItem -like 'Handheld*') { $e['NX_HANDHELD'] = '1' }
    $u = [string]$cUw.SelectedItem
    if ($u -eq 'Match window') { $e['NX_ULTRAWIDE'] = '1' } elseif ($u -eq '21:9' -or $u -eq '32:9') { $e['NX_ULTRAWIDE'] = $u }
    $w = [string]$cWin.SelectedItem
    if ($w -match '^\d+x\d+$') { $e['NX_RESOLUTION'] = $w }
    $g = $cGpu.Text.Trim()
    if ($g -ne '' -and $g -ne 'Default') { $e['NX_GPU'] = $g }
    $p = [string]$cPipe.SelectedItem
    if ($p -ne 'Default') { $e['NX_PIPELINED'] = $p }
    if ($cPad.Checked) { $e['NX_PAD_BUFFERS'] = '1' }
    if ($cFsr.Checked) {
        $e['NX_FSR'] = '1'
        $s = [string]$cSharp.SelectedItem
        if ($s -notlike 'Default*') { $e['NX_FSR_SHARP'] = $s }
    }
    if ([string]$cFps.SelectedItem -like '30*') { $e['NX_FPS_CAP'] = '30' }
    if ($cMute.Checked) { $e['NX_MUTE'] = '1' }
    $l = [string]$cLang.SelectedItem
    if ($l -ne 'Default') { $e['NX_LANGUAGE'] = $l }
    $us = [string]$cUser.SelectedItem
    if ($us -ne 'Default') { $e['NX_USER'] = $us }
    $m = [string]$cMem.SelectedItem
    if ($m -notlike 'Default*') { $e['NX_MEM_LIMIT_GB'] = $m }
    foreach ($line in ($txtExtra.Text -split "`r?`n")) {
        if ($line -match '^\s*(NX_[A-Za-z0-9_]+)\s*=\s*(.*?)\s*$') { $e[$matches[1]] = $matches[2] }
    }
    $e
}

function Update-Preview {
    $e = Get-NxEnv
    if ($e.Count -eq 0) { $t = '(no variables set: the game starts with its defaults)' }
    else { $t = (($e.Keys | ForEach-Object { "$_=$($e[$_])" }) -join '   ') }
    if ($txtPrev.Text -ne $t) { $txtPrev.Text = $t }
}

function Save-Settings {
    $o = [ordered]@{
        fullscreen = $cFull.Checked; mode = [string]$cMode.SelectedItem; uw = [string]$cUw.SelectedItem
        win = [string]$cWin.SelectedItem; gpu = $cGpu.Text; pipe = [string]$cPipe.SelectedItem; pad = $cPad.Checked
        fsr = $cFsr.Checked; sharp = [string]$cSharp.SelectedItem; fps = [string]$cFps.SelectedItem
        mute = $cMute.Checked; lang = [string]$cLang.SelectedItem; user = [string]$cUser.SelectedItem
        mem = [string]$cMem.SelectedItem; extra = $txtExtra.Text
    }
    try { $o | ConvertTo-Json | Set-Content -Path $cfgPath -Encoding UTF8 } catch {}
}

function Reset-Settings {
    foreach ($c in @($cMode, $cUw, $cWin, $cGpu, $cPipe, $cSharp, $cFps, $cLang, $cUser, $cMem)) { $c.SelectedIndex = 0 }
    foreach ($c in @($cFull, $cPad, $cFsr, $cMute)) { $c.Checked = $false }
    $txtExtra.Text = ''
}

function Load-Settings {
    if (-not (Test-Path $cfgPath)) { return }
    try { $o = Get-Content $cfgPath -Raw | ConvertFrom-Json } catch { return }
    if ($null -ne $o.fullscreen) { $cFull.Checked = [bool]$o.fullscreen }
    if ($null -ne $o.pad) { $cPad.Checked = [bool]$o.pad }
    if ($null -ne $o.fsr) { $cFsr.Checked = [bool]$o.fsr }
    if ($null -ne $o.mute) { $cMute.Checked = [bool]$o.mute }
    Set-Combo $cMode $o.mode; Set-Combo $cUw $o.uw; Set-Combo $cWin $o.win; Set-Combo $cGpu $o.gpu
    Set-Combo $cPipe $o.pipe; Set-Combo $cSharp $o.sharp; Set-Combo $cFps $o.fps; Set-Combo $cLang $o.lang
    Set-Combo $cUser $o.user; Set-Combo $cMem $o.mem
    if ($null -ne $o.extra) { $txtExtra.Text = [string]$o.extra }
}

function Read-Log {
    if (-not (Test-Path $logPath)) { return }
    try {
        $fs = [System.IO.File]::Open($logPath, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -lt $script:logPos) { $script:logPos = 0L }
            if ($fs.Length -gt $script:logPos) {
                [void]$fs.Seek($script:logPos, 'Begin')
                $len = [int][Math]::Min($fs.Length - $script:logPos, 262144)
                $buf = New-Object byte[] $len
                $n = $fs.Read($buf, 0, $len)
                $script:logPos += $n
                if ($txtLog.TextLength -gt 1500000) { $txtLog.Text = $txtLog.Text.Substring(750000) }
                $txtLog.AppendText([System.Text.Encoding]::UTF8.GetString($buf, 0, $n))
            }
        } finally { $fs.Close() }
    } catch {}
}

function Test-Running { return (($null -ne $script:proc) -and (-not $script:proc.HasExited)) }

function Start-Game {
    if (-not (Test-Path $exe)) {
        [void][System.Windows.Forms.MessageBox]::Show("wonder.exe not found:`n$exe", 'Launcher')
        return
    }
    if (Test-Running) { return }
    Save-Settings
    $envs = Get-NxEnv
    $envs['NX_LOG'] = $logPath
    try { Remove-Item $logPath -ErrorAction SilentlyContinue } catch {}
    $script:logPos = 0L
    $txtLog.Clear()
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $exe
    $psi.WorkingDirectory = $root
    $psi.UseShellExecute = $false
    foreach ($k in $envs.Keys) { $psi.EnvironmentVariables[$k] = [string]$envs[$k] }
    try { $script:proc = [System.Diagnostics.Process]::Start($psi) }
    catch { [void][System.Windows.Forms.MessageBox]::Show("Could not start the game:`n$_", 'Launcher') }
}

$bLaunch.Add_Click({ Start-Game })
$bStop.Add_Click({ if (Test-Running) { try { $script:proc.Kill() } catch {} } })
$bReset.Add_Click({ Reset-Settings })
$bFolder.Add_Click({ Start-Process explorer.exe (Join-Path $root 'private\wonder') })
$bClear.Add_Click({ $txtLog.Clear() })
$bOpenLog.Add_Click({ if (Test-Path $logPath) { Start-Process notepad.exe $logPath } })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 500
$timer.Add_Tick({
    Update-Preview
    Read-Log
    $running = Test-Running
    if ($running) { $lblStatus.Text = 'Game running (process ' + $script:proc.Id + '). Settings apply the next time you launch.' }
    else { $lblStatus.Text = 'Game not running. Game folder: ' + $root }
    $bLaunch.Enabled = -not $running
    $bStop.Enabled = $running
})

Load-Settings
Update-Preview
$timer.Start()
$form.Add_FormClosing({ Save-Settings; $timer.Stop() })
[void]$form.ShowDialog()