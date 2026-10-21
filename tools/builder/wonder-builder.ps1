# Wonder Builder (source only, no game files): checks the build prerequisites and installs only the missing ones with winget.
# Run:  powershell -NoProfile -ExecutionPolicy Bypass -STA -File tools\builder\wonder-builder.ps1
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$root = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$logDir = Join-Path $root 'private\builder'
New-Item -ItemType Directory -Force $logDir | Out-Null
$outLog = Join-Path $logDir 'builder-out.log'
$errLog = Join-Path $logDir 'builder-err.log'
$script:queue = New-Object System.Collections.ArrayList
$script:cur = $null
$script:pos = @{ out = 0L; err = 0L }
$script:items = @()
$script:found = @{}

function Test-Admin {
    ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Update-SessionPath {
    $m = [Environment]::GetEnvironmentVariable('Path', 'Machine')
    $u = [Environment]::GetEnvironmentVariable('Path', 'User')
    $env:Path = $m + ';' + $u
    $v = [Environment]::GetEnvironmentVariable('VULKAN_SDK', 'Machine')
    if ($v) { $env:VULKAN_SDK = $v }
}

function Find-Python {
    Update-SessionPath
    $cands = @()
    $c = Get-Command python -ErrorAction SilentlyContinue | Where-Object { $_.Source -notlike '*WindowsApps*' } | Select-Object -First 1
    if ($c) { $cands += $c.Source }
    foreach ($d in @("$env:LOCALAPPDATA\Programs\Python", $env:ProgramFiles, 'C:\')) {
        if (Test-Path $d) {
            $cands += @(Get-ChildItem $d -Directory -Filter 'Python3*' -ErrorAction SilentlyContinue | ForEach-Object { Join-Path $_.FullName 'python.exe' })
        }
    }
    foreach ($p in $cands) {
        if ($p -and (Test-Path $p)) {
            $v = ((& $p --version 2>&1) -replace 'Python ', '')
            if ($v -match '^\d+\.\d+' -and ([version]($v -replace '[^\d\.].*', '') -ge [version]'3.11')) { return @{ Path = $p; Version = $v } }
        }
    }
    return $null
}

function Get-Checks {
    Update-SessionPath
    $r = New-Object System.Collections.ArrayList
    $script:found = @{}
    function Add-Result($key, $name, $needed, $ok, $found, $fix) {
        [void]$r.Add([pscustomobject]@{ Key = $key; Name = $name; Needed = $needed; Ok = [bool]$ok; Found = [string]$found; Fix = $fix })
    }

    $wg = Get-Command winget -ErrorAction SilentlyContinue
    $wv = ''; if ($wg) { try { $wv = (& winget --version) } catch {} }
    Add-Result 'winget' 'winget (installer)' 'Required' ($null -ne $wg) $wv $null
    $git = Get-Command git -ErrorAction SilentlyContinue
    $gv = ''; if ($git) { try { $gv = (& git --version) } catch {} }
    Add-Result 'git' 'Git' 'Optional' ($null -ne $git) $gv $null

    $vsPath = $null
    $vw = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (Test-Path $vw) { $vsPath = (& $vw -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath | Select-Object -First 1) }
    $script:found['vs'] = $vsPath
    Add-Result 'vs' 'Visual Studio C++ build tools' 'Required' ([bool]$vsPath) $vsPath 'vs'
    $clang = $null; if ($vsPath) { $clang = Join-Path $vsPath 'VC\Tools\Llvm\x64\bin\clang-cl.exe' }
    $clangOk = [bool]($clang -and (Test-Path $clang))
    $clangText = ''; if ($clangOk) { $clangText = $clang }
    Add-Result 'clang' 'C++ Clang tools (clang-cl)' 'Required' $clangOk $clangText 'vs'

    $cmExe = $null
    if ($vsPath) { $c = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe'; if (Test-Path $c) { $cmExe = $c } }
    if (-not $cmExe) { $c = Get-Command cmake -ErrorAction SilentlyContinue; if ($c) { $cmExe = $c.Source } }
    $cmVer = ''; if ($cmExe) { $cmVer = ((& $cmExe --version | Select-Object -First 1) -replace 'cmake version ', '') }
    $cmOk = $false
    if ($cmExe) { try { $cmOk = ([version]($cmVer -replace '-.*', '') -ge [version]'3.28') } catch {} }
    Add-Result 'cmake' 'CMake 3.28 or newer' 'Required' $cmOk "$cmVer  $cmExe" 'vs'
    $nj = $null
    if ($vsPath) { $n = Join-Path $vsPath 'Common7\IDE\CommonExtensions\Microsoft\CMake\Ninja\ninja.exe'; if (Test-Path $n) { $nj = $n } }
    if (-not $nj) { $n = Get-Command ninja -ErrorAction SilentlyContinue; if ($n) { $nj = $n.Source } }
    Add-Result 'ninja' 'Ninja' 'Required' ($null -ne $nj) $nj 'vs'

    $py = Find-Python
    $script:found['py'] = $py
    $pyText = ''; if ($py) { $pyText = $py.Version + '  ' + $py.Path }
    Add-Result 'python' 'Python 3.11 or newer' 'Required' ($null -ne $py) $pyText 'python'
    $vpy = Join-Path $root 'private\venv\Scripts\python.exe'
    $pk = $false
    if (Test-Path $vpy) { & $vpy -c "import capstone, lz4, zstandard, fontTools" 2>$null; $pk = ($LASTEXITCODE -eq 0) }
    Add-Result 'venv' 'Project venv + Python packages' 'Required' $pk $vpy 'venv'

    $vk = $env:VULKAN_SDK
    if (-not $vk -and (Test-Path 'C:\VulkanSDK')) { $vk = (Get-ChildItem 'C:\VulkanSDK' -Directory | Sort-Object Name | Select-Object -Last 1).FullName }
    $vkVer = ''
    if ($vk) {
        $h = Join-Path $vk 'Include\vulkan\vulkan_core.h'
        if (Test-Path $h) { $m = Select-String -Path $h -Pattern '#define VK_HEADER_VERSION\s+(\d+)' | Select-Object -First 1; if ($m) { $vkVer = [int]$m.Matches[0].Groups[1].Value } }
    }
    $sv = $null; if ($vk) { $sv = Join-Path $vk 'Bin\spirv-val.exe' }
    $vkOk = (($vkVer -is [int]) -and ($vkVer -ge 357) -and $sv -and (Test-Path $sv))
    Add-Result 'vulkan' 'Vulkan SDK 1.4.357+ (with spirv-val)' 'Required' $vkOk "1.4.$vkVer  $vk" 'vulkan'

    $dn = Get-Command dotnet -ErrorAction SilentlyContinue
    $sdks = @(); if ($dn) { $sdks = @(& dotnet --list-sdks) }
    $dnOk = (@($sdks | Where-Object { $_ -like '10.*' }).Count -gt 0)
    Add-Result 'dotnet' '.NET SDK 10' 'Required' $dnOk (($sdks | ForEach-Object { ($_ -split ' ')[0] }) -join ', ') 'dotnet'

    $drive = (Get-Item $root).PSDrive.Name
    $free = [math]::Round((Get-PSDrive $drive).Free / 1GB)
    Add-Result 'disk' 'Free disk space (20 GB advised)' 'Advice' ($free -ge 20) "$free GB on ${drive}:" $null
    $ram = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)
    Add-Result 'ram' 'RAM (14 GB advised)' 'Advice' ($ram -ge 14) "$ram GB" $null
    return $r
}

function Get-WingetArgs($id, $override) {
    $a = 'install --id ' + $id + ' -e --silent --accept-package-agreements --accept-source-agreements'
    if ($override) { $a += ' --override "' + $override + '"' }
    return $a
}

function Get-FixSteps($key) {
    $winget = { (Get-Command winget -ErrorAction Stop).Source }
    switch ($key) {
        'vs' {
            $inst = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\setup.exe'
            if ($script:found['vs'] -and (Test-Path $inst)) {
                $a = 'modify --installPath "' + $script:found['vs'] + '" --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset --add Microsoft.VisualStudio.Component.VC.CMake.Project --passive --norestart'
                return @(@{ Title = 'Add the Clang and CMake tools to Visual Studio'; Exe = $inst; Args = $a })
            }
            $o = '--passive --wait --norestart --add Microsoft.VisualStudio.Workload.VCTools --add Microsoft.VisualStudio.Component.VC.Llvm.Clang --add Microsoft.VisualStudio.Component.VC.Llvm.ClangToolset --add Microsoft.VisualStudio.Component.VC.CMake.Project --includeRecommended'
            return @(@{ Title = 'Install Visual Studio 2022 Build Tools (large, takes a while)'; Exe = $winget; Args = (Get-WingetArgs 'Microsoft.VisualStudio.2022.BuildTools' $o) })
        }
        'python' { return @(@{ Title = 'Install Python 3.13'; Exe = $winget; Args = (Get-WingetArgs 'Python.Python.3.13' $null) }) }
        'venv' {
            $vp = Join-Path $root 'private\venv'
            $steps = @()
            $steps += @{ Title = 'Create the Python venv'; Exe = { $p = Find-Python; if (-not $p) { throw 'Python 3.11+ not found' }; $p.Path }; Args = ('-m venv "' + $vp + '"') }
            $steps += @{ Title = 'Install the Python packages (capstone lz4 zstandard fonttools)'; Exe = (Join-Path $vp 'Scripts\python.exe'); Args = '-m pip install --upgrade capstone lz4 zstandard fonttools' }
            return $steps
        }
        'vulkan' { return @(@{ Title = 'Install the Vulkan SDK'; Exe = $winget; Args = (Get-WingetArgs 'KhronosGroup.VulkanSDK' $null) }) }
        'dotnet' { return @(@{ Title = 'Install the .NET 10 SDK'; Exe = $winget; Args = (Get-WingetArgs 'Microsoft.DotNet.SDK.10' $null) }) }
    }
    return @()
}

# ---- window ----
$form = New-Object System.Windows.Forms.Form
$adminText = ''; if (Test-Admin) { $adminText = ' (administrator)' }
$form.Text = 'Super Mario Bros. Wonder - Builder' + $adminText
$form.ClientSize = New-Object System.Drawing.Size(760, 640)
$form.FormBorderStyle = 'FixedSingle'
$form.MaximizeBox = $false
$form.StartPosition = 'CenterScreen'

$lv = New-Object System.Windows.Forms.ListView
$lv.View = 'Details'; $lv.FullRowSelect = $true; $lv.GridLines = $true
$lv.Left = 10; $lv.Top = 10; $lv.Width = 740; $lv.Height = 250
[void]$lv.Columns.Add('Requirement', 230)
[void]$lv.Columns.Add('Needed', 70)
[void]$lv.Columns.Add('Status', 70)
[void]$lv.Columns.Add('Found', 350)
$form.Controls.Add($lv)

function New-Btn($text, $x, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Left = $x; $b.Top = 270; $b.Width = $w; $b.Height = 32
    $form.Controls.Add($b)
    return $b
}
$bCheck = New-Btn 'Re-check' 10 110
$bInstall = New-Btn 'Install missing' 130 140
$bTest = New-Btn 'Test live log' 280 120
$bFolder = New-Btn 'Open log folder' 410 130
$bBuild = New-Btn 'Build game (next stage)' 550 200
$bBuild.Enabled = $false

$lblSum = New-Object System.Windows.Forms.Label
$lblSum.Left = 10; $lblSum.Top = 310; $lblSum.Width = 740; $lblSum.Height = 22
$form.Controls.Add($lblSum)

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true; $txtLog.ReadOnly = $true; $txtLog.ScrollBars = 'Both'; $txtLog.WordWrap = $false
$txtLog.MaxLength = 2000000
$txtLog.Font = New-Object System.Drawing.Font('Consolas', 9)
$txtLog.Left = 10; $txtLog.Top = 335; $txtLog.Width = 740; $txtLog.Height = 295
$form.Controls.Add($txtLog)

function Add-Log($t) {
    if ($txtLog.TextLength -gt 1500000) { $txtLog.Text = $txtLog.Text.Substring(750000) }
    $txtLog.AppendText($t + "`r`n")
}

function Set-Busy($v) { foreach ($b in @($bCheck, $bInstall, $bTest)) { $b.Enabled = -not $v } }

function Run-Checks {
    $script:items = @(Get-Checks)
    $lv.Items.Clear()
    foreach ($i in $script:items) {
        $li = New-Object System.Windows.Forms.ListViewItem($i.Name)
        [void]$li.SubItems.Add($i.Needed)
        if ($i.Ok) { $st = 'OK' } elseif ($i.Needed -eq 'Required') { $st = 'MISSING' } else { $st = 'LOW' }
        [void]$li.SubItems.Add($st)
        [void]$li.SubItems.Add($i.Found)
        if ($i.Ok) { $li.ForeColor = [System.Drawing.Color]::Green }
        elseif ($i.Needed -eq 'Required') { $li.ForeColor = [System.Drawing.Color]::Firebrick }
        else { $li.ForeColor = [System.Drawing.Color]::DarkOrange }
        [void]$lv.Items.Add($li)
    }
    $m = @($script:items | Where-Object { -not $_.Ok -and $_.Needed -eq 'Required' }).Count
    if ($m -eq 0) { $lblSum.Text = 'All required tools were found. Nothing to install.' }
    else { $lblSum.Text = "$m required item(s) missing. Press 'Install missing'." }
}

function Read-Tail($path, $key) {
    if (-not (Test-Path $path)) { return }
    try {
        $fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
        try {
            if ($fs.Length -lt $script:pos[$key]) { $script:pos[$key] = 0L }
            if ($fs.Length -gt $script:pos[$key]) {
                [void]$fs.Seek($script:pos[$key], 'Begin')
                $len = [int][Math]::Min($fs.Length - $script:pos[$key], 262144)
                $buf = New-Object byte[] $len
                $n = $fs.Read($buf, 0, $len)
                $script:pos[$key] = $script:pos[$key] + $n
                $text = [System.Text.Encoding]::UTF8.GetString($buf, 0, $n)
                foreach ($line in ($text -split "[`r`n]+")) {
                    if ($line.Trim() -eq '') { continue }
                    if ($line -match '^[\s\-\\|/]+$') { continue }
                    if ($line -match '[\u2588\u2592]') { continue }
                    Add-Log $line
                }
            }
        } finally { $fs.Close() }
    } catch {}
}

function Start-NextStep {
    if ($script:queue.Count -eq 0) {
        $script:cur = $null
        Add-Log '=== All steps finished. Checking again... ==='
        Run-Checks
        Set-Busy $false
        return
    }
    $s = $script:queue[0]
    $script:queue.RemoveAt(0)
    Add-Log ''
    Add-Log ('>>> ' + $s.Title)
    try {
        if ($s.Exe -is [scriptblock]) { $exe = & $s.Exe } else { $exe = $s.Exe }
        Add-Log ('    ' + $exe + ' ' + $s.Args)
        $script:pos['out'] = 0L; $script:pos['err'] = 0L
        $p = Start-Process -FilePath $exe -ArgumentList $s.Args -WorkingDirectory $root -WindowStyle Hidden -PassThru -RedirectStandardOutput $outLog -RedirectStandardError $errLog
        $null = $p.Handle
        $script:cur = $p
    } catch {
        Add-Log ('    FAILED to start: ' + $_)
        Start-NextStep
    }
}

function Start-Install {
    if (-not (@($script:items | Where-Object { $_.Key -eq 'winget' -and $_.Ok }).Count)) {
        [void][System.Windows.Forms.MessageBox]::Show('winget was not found. Install "App Installer" from the Microsoft Store, then press Re-check.', 'Builder')
        return
    }
    $miss = @($script:items | Where-Object { -not $_.Ok -and $_.Needed -eq 'Required' -and $_.Fix })
    if ($miss.Count -eq 0) { [void][System.Windows.Forms.MessageBox]::Show('Nothing to install.', 'Builder'); return }
    $names = ($miss | ForEach-Object { '  - ' + $_.Name }) -join "`n"
    $ans = [System.Windows.Forms.MessageBox]::Show("These are missing and will be installed:`n`n$names`n`nSome installers are several GB and can take a long time. Continue?", 'Builder', 'YesNo')
    if ($ans -ne 'Yes') { return }
    if (-not (Test-Admin)) {
        $a2 = [System.Windows.Forms.MessageBox]::Show('Installing needs administrator rights. Restart the builder as administrator now?', 'Builder', 'YesNo')
        if ($a2 -eq 'Yes') {
            try {
                Start-Process powershell.exe -Verb RunAs -ArgumentList ('-NoProfile -ExecutionPolicy Bypass -STA -File "' + $PSCommandPath + '"')
                $form.Close()
            } catch { Add-Log ('Could not restart as administrator: ' + $_) }
        }
        return
    }
    $script:queue.Clear()
    foreach ($k in @('vs', 'python', 'venv', 'vulkan', 'dotnet')) {
        if (@($miss | Where-Object { $_.Fix -eq $k }).Count -gt 0) {
            foreach ($st in @(Get-FixSteps $k)) { [void]$script:queue.Add($st) }
        }
    }
    Set-Busy $true
    Start-NextStep
}

function Start-Test {
    $script:queue.Clear()
    [void]$script:queue.Add(@{ Title = 'Test: winget version'; Exe = { (Get-Command winget -ErrorAction Stop).Source }; Args = '--version' })
    [void]$script:queue.Add(@{ Title = 'Test: 4 pings (output arrives line by line)'; Exe = 'cmd.exe'; Args = '/c ping -n 4 127.0.0.1' })
    Set-Busy $true
    Start-NextStep
}

$bCheck.Add_Click({ Run-Checks })
$bInstall.Add_Click({ Start-Install })
$bTest.Add_Click({ Start-Test })
$bFolder.Add_Click({ Start-Process explorer.exe $logDir })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 400
$timer.Add_Tick({
    Read-Tail $outLog 'out'
    Read-Tail $errLog 'err'
    if ($script:cur -and $script:cur.HasExited) {
        Read-Tail $outLog 'out'
        Read-Tail $errLog 'err'
        Add-Log ('<<< exit code ' + $script:cur.ExitCode)
        $script:cur = $null
        Start-NextStep
    }
})

Run-Checks
$timer.Start()
$form.Add_FormClosing({ $timer.Stop(); $script:queue.Clear() })
[void]$form.ShowDialog()