# Variables
$USS_Path = 'C:/Universal Split Screen 1.1.1/UniversalSplitScreen.exe'     # Universal Split Screen install path. Download from https://universalsplitscreen.github.io/
$proc_aff_enabled = $true                                                  # Assigns half the CPU cores to one window, and half to the other. Can disable (set to $false) if you have a powerful CPU
$reposition_windows_enabled = $true                                        # Repositions the windows in a split screen configuration. Set to $false to disable
$vert_split = $true                                                        # Set to $true for vertical split. $false is horizontal 
$FullscreenMode = 2                                                        # Set to 2 for splitscreen, or 1 for dual monitor
$config_ini_path = [environment]::getfolderpath("mydocuments") + "\My Games\Borderlands 3\Saved\Config\WindowsNoEditor\GameUserSettings.ini"

Add-Type -AssemblyName System.Windows.Forms

# Check if WASP is installed
if ($reposition_windows_enabled) {
    try {
        $null = Select-Window -ErrorAction Stop
    }
    catch { 
        Write-Warning "Looks like the WASP module is not currently installed! The WASP module is used for repositioning the windows" 
        Write-Error "Please install WASP or disable window repositioning" -ErrorAction Stop
    }
}

# Edit the game settings to change window mode
$monitors = Get-PnpDevice | where-object {($_.class -eq "Monitor") -and ($_.status -eq 'OK')}
$monitors = $monitors.instanceid | foreach-object {$_.substring(8,7)}
$monitors_names = [System.Windows.Forms.Screen]::AllScreens.DeviceName

try {
    Write-Host Changing window mode
    $config_ini = Get-Content $config_ini_path
    if (($monitors.count -gt 1) -and ($FullscreenMode -eq 1)) {
        Write-Host Setting up monitor $monitors[0]
        $line = $config_ini | Select-String PreferredMonitor=
        $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"PreferredMonitor=$($monitors[0])"}
        $line = $config_ini | Select-String PreferredMonitorDeviceName=
        $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"PreferredMonitorDeviceName=$($monitors_names[0])"}
    } elseif ($FullscreenMode -eq 1) {
        Write-Error "Unable to get monitor information for all monitors" -Category InvalidResult -ErrorAction Stop 
    }
    $line = $config_ini | Select-String FullscreenMode=
    $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"FullscreenMode=$($FullscreenMode)"} | Out-File $config_ini_path
}
catch [Microsoft.PowerShell.Commands.WriteErrorException] {
    Write-Error "Unable to get monitor information for all monitors" -ErrorAction Stop
}
catch {
    Write-Warning "Unable to set resolution and windowed mode in GameUserSettings.ini"
}

# Start an instance of Borderlands 3 using the Epic Launcher
try {
    Write-Host Starting Borderlands 3 using Epic Launcher
    Start-Process -FilePath "com.epicgames.launcher://apps/Catnip?action=launch&silent=true"
}
catch {
    Write-Error "Unable to launch Borderlands 3 using Epic Launcher. Quitting..." -ErrorAction Stop
}

# Launch an offline instance of Borderlands 3
try {
    # Search through Epic Launcher logs to find the launch parameters for Borderlands 3.Wait until Epic copy has launched before it can start
    Write-Host Finding offline launch arguments
    while (($Launch_Info -eq $null) -or ($bl3_windows -eq $null)) {
        sleep -s 1
        # $bl3_processes = Get-Process borderlands3 -ErrorAction SilentlyContinue
        $bl3_windows = Select-Window borderlands3 
        $Launch_Info = Get-Content $env:USERPROFILE\AppData\Local\EpicGamesLauncher\Saved\Logs\EpicGamesLauncher.log | `
                       Where-Object {$_ -like '*FCommunityPortalLaunchAppTask: Launching app*Borderlands3.exe*'} | `
                       Select-Object -First 1
    }

    # Reformat it, split out the arguments, and point to the actual binary
    $null, $bl3_bin = $Launch_Info -split "Launching app "
    $bl3_bin = $bl3_bin -replace "'",""
    $bl3_bin, $bl3_arg = $bl3_bin -split "with commandline "
    $bl3_bin = $bl3_bin -replace "Borderlands3.exe","OakGame/Binaries/Win64/Borderlands3.exe"

    # Make sure it exists
    $null = Test-Path -Path $bl3_bin -ErrorAction stop
    Write-Host Found Borderlands 3 in $bl3_bin

    # Update config for second monitor
    if ($FullscreenMode -eq 1) {
        try {
            Write-Host Setting up monitor $monitors[1]
            $config_ini = Get-Content $config_ini_path 
            $line = $config_ini | Select-String PreferredMonitor=
            $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"PreferredMonitor=$($monitors[1])"}
            $line = $config_ini | Select-String PreferredMonitorDeviceName=
            $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"PreferredMonitorDeviceName=$($monitors_names[1])"} 
            $line = $config_ini | Select-String bPrimaryIsPreferredMonitor=
            $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"bPrimaryIsPreferredMonitor=False"} | Out-File $config_ini_path
        }
        catch {
            Write-Warning "Unable update GameUserSettings.ini"
        }
    }

    Write-Host Starting offline instance of Borderlands 3
    Start-Process -FilePath $bl3_bin -ArgumentList $bl3_arg
}
catch {
    Write-Error "Unable to launch offline copy of Borderlands 3. Quitting..." -ErrorAction Stop
}

# Start Universal SplitScreen
Write-Host Starting Universal SplitScreen
try {
    Start-Process -FilePath $USS_Path
}
catch {
    Write-Warning 'Cannot start Universal Split Screen'
    Write-Warning "Download from https://universalsplitscreen.github.io/ and install here: $USS_Path"
}

# Set processor affinity. Assigns half the CPU cores to one window, and half to the other
if ($proc_aff_enabled) {
    while ($bl3_processes.count -lt 2) { 
        sleep -s 1 
        $bl3_processes = Get-Process borderlands3 | Sort-Object pm | Select-Object -last 2
    }
    Write-Host Setting processor affinity and priority
    
    $all_cores = "{0:X}" -f [int]$bl3_processes[0].processoraffinity
    $proc_aff = '0x'
    foreach ($char in [char[]]$all_cores) { $proc_aff = $proc_aff + 'A' }
    $bl3_processes[0].processoraffinity = [int]$proc_aff
    $proc_aff = '0x'
    foreach ($char in [char[]]$all_cores) { $proc_aff = $proc_aff + '5' }
    $bl3_processes[1].processoraffinity = [int]$proc_aff
    $bl3_processes | ForEach-Object {$_.priorityclass = 'High'}
}

# Positioning windows
if (($reposition_windows_enabled -eq $true) -and ($FullscreenMode -eq 2)) {
    while ($bl3_windows.count -lt 2) {
        sleep -s 1
        $bl3_windows = Select-Window borderlands3
    }
    Write-Host Repositioning windows. Switch to Universal Split Screen to setup the input devices and hide window borders
    Write-Host Press s to swap position of the windows. Press d to toggle between vertical and horizontal split
    $invert = $false
    while ($bl3_windows.count -eq 2) {
        $i = 0
        foreach ($window in $bl3_windows) {
            if ($vert_split) {
                $x_res = ([System.Windows.Forms.Screen]::AllScreens.Bounds.Width) / 2
                $y_res = [System.Windows.Forms.Screen]::AllScreens.Bounds.Height
                $x_pos = ($i*$x_res)-1
                $y_pos = -1
            
            } else {
                $x_res = [System.Windows.Forms.Screen]::AllScreens.Bounds.Width
                $y_res = ([System.Windows.Forms.Screen]::AllScreens.Bounds.Height) / 2
                $x_pos = -1
                $y_pos = ($i*$y_res)-1
            }
            $window_position = $window | Get-WindowPosition
            if (($window_position.y -ne ($y_pos)) -or ($window_position.x -ne ($x_pos)) -or ($window_position.height -ne ($y_res)) -or ($window_position.width -ne ($x_res))) {
                Set-WindowPosition -left $x_pos -top $y_pos -height $y_res -width $x_res -window $window            
            }
            $i++
        }
        sleep -s 1
        $bl3_windows = Select-Window borderlands3
        if ([console]::KeyAvailable) {
            $key = [system.console]::readkey($true)
            if ($key.key -eq "s") {$invert = !$invert; Write-Host Swapping windows }
            elseif ($key.key -eq "d") {$vert_split = !$vert_split; Write-Host Changing orientation }
        }
        if ($invert) {$null = [array]::Reverse($bl3_windows) }
    }
}
Write-Host All done!
