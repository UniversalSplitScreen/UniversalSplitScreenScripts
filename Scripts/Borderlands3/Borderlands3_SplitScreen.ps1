# Using Epic launcher?
$Player1 = $true                                                           # Set to $true if launching from Epic games and $false if launching from steam
$Player2 = $false                                                          # If both are $true (Epic) then player 2 will be offline and cannot play DLC content. 
                                                                           # NOTE: SCRIPT DOES NOT YET WORK FOR 2 STEAM PLAYERS!

#Variables
$USS_Path = 'C:/Universal Split Screen 1.1.1/UniversalSplitScreen.exe'     # Universal Split Screen install path. Download from https://universalsplitscreen.github.io/
$Sandboxie_Path = 'C:\Program Files\Sandboxie\Start.exe'                   # Sandboxie path. Download from https://www.sandboxie.com/DownloadSandboxie

$sandboxie = $false                                                        # Set to '$true' if you want to run the offline instance in Sandboxie
$proc_aff_enabled = $true                                                  # Assigns half the CPU cores to one window, and half to the other. Can disable (set to $false) if you have a powerful CPU
$reposition_windows_enabled = $true                                        # Repositions the windows in a split screen configuration. Set to $false to disable
$split_mode = "horizontal"                                                 # "horizontal", "vertical" or "dual" (dual monitor - UNTESTED)
$config_ini_path = [environment]::getfolderpath("mydocuments") + "\My Games\Borderlands 3\Saved\Config\WindowsNoEditor\GameUserSettings.ini"

Add-Type -AssemblyName System.Windows.Forms

# Check if WASP is installed
if ($reposition_windows_enabled -and ($split_mode -ne "dual")) {
    try {
        $null = Select-Window -ErrorAction Stop
    }
    catch { 
        Write-Warning "Looks like the WASP module is not currently installed so cannot reposition the windows for splitscreen! Disabling window repositioning"
        Write-Host "Make sure WASP.dll is installed in $([environment]::getfolderpath("mydocuments") + "\WindowsPowershell\Modules\WASP\WASP.dll")"
        $reposition_windows_enabled = $false
    }
}

# Find monitors for dual screen mode
if ($split_mode -eq "dual") {
    try { 
        $monitors = Get-PnpDevice | where-object {($_.class -eq "Monitor") -and ($_.status -eq 'OK')}
        $monitors = $monitors.instanceid | foreach-object {$_.substring(8,7)}
    }
    catch {
        $monitors = Get-WmiObject win32_pnpentity -Filter "DeviceID LIKE 'Display%'" | Select-Object DeviceID
        $monitors = $monitors.deviceid | foreach-object {$_.substring(8,7)}
    }

    $monitors_names = [System.Windows.Forms.Screen]::AllScreens.DeviceName
}

# Edit the game settings to change window mode
try {
    Write-Host Changing window mode
    $config_ini = Get-Content $config_ini_path
    if (($monitors.count -gt 1) -and ($split_mode -eq "dual")) {
        Write-Host Setting up monitor $monitors[0]
        $line = $config_ini | Select-String PreferredMonitor=
        $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"PreferredMonitor=$($monitors[0])"}
        $line = $config_ini | Select-String PreferredMonitorDeviceName=
        $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"PreferredMonitorDeviceName=$($monitors_names[0])"}
    } elseif ($split_mode -eq "dual") {
        Write-Error "Unable to get monitor information for all monitors" -Category InvalidResult -ErrorAction Stop 
    }
    $line = $config_ini | Select-String FullscreenMode=
    $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],"FullscreenMode=1"} | Out-File $config_ini_path
}
catch [Microsoft.PowerShell.Commands.WriteErrorException] {
    Write-Error "Unable to get monitor information for all monitors" -ErrorAction Stop
}
catch {
    Write-Warning "Unable to set resolution and window mode in GameUserSettings.ini"
}

# Start first instance of Borderlands 3
if (!$Player1 -and !$Player2) {
    Write-Error "Launching two Steam sessions is not yet supported. Quitting... " -ErrorAction Stop
} elseif ($Player1 -or $Player2) {    
    # At least one player using Epic, so launch an Epic session
    try {
        Write-Host Starting Borderlands 3 using Epic Launcher
        Start-Process -FilePath "com.epicgames.launcher://apps/Catnip?action=launch&silent=true"
    }
    catch {
        Write-Error "Unable to launch Borderlands 3 using Epic Launcher. Quitting..." -ErrorAction Stop
    }
} 
if (!$Player1 -xor !$Player2) {    
    # At least one player is using Steam, so launch a steam session
    try {
        Write-Host Starting Borderlands 3 using Steam
        $steam_bin = Get-ChildItem HKLM:\SOFTWARE\wow6432node\Microsoft\Windows\CurrentVersion\Uninstall | ` # Finding the Steam install path
            % { Get-ItemProperty $_.PsPath } | `
            Where-Object {$_.DisplayName -eq 'Steam'} | `
            ft UninstallString -HideTableHeaders | Out-String | `
            ForEach-Object {$_ -replace "uninstall", "Steam"}
        
        $steam_bin = $steam_bin -replace "`n","" -replace "`r",""

        $null = Test-Path -Path $steam_bin -ErrorAction Stop
        Start-Process -FilePath $steam_bin -ArgumentList ("-applaunch 397540" )
    }
    catch {
        Write-Error "Unable to launch Borderlands 3 using Steam. Quitting..." -ErrorAction Stop
    }
}

# Start second instance of Borderlands 3
if ($Player1 -and $Player2) {
    # Start offline copy of Borderlands 3 through Epic
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
        $null = Test-Path -Path $bl3_bin -ErrorAction Stop
        Write-Host Found Borderlands 3 in $bl3_bin

        # Update config for second monitor
        if ($split_mode -eq "dual") {
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
        if ($sandboxie) {
            $null = Test-Path -Path $Sandboxie_Path -ErrorAction stop
            Start-Process -FilePath $Sandboxie_Path -ArgumentList ("/box:BL3 " + $bl3_bin + $bl3_arg)
        } else {
            $null = Test-Path -Path $bl3_bin -ErrorAction Stop
            Start-Process -FilePath $bl3_bin -ArgumentList $bl3_arg
        }
    }
    #catch [Microsoft.PowerShell.Commands.WriteErrorException] {
    #    Write-Warning "Check $bl3_bin exists. $Launch_Info"
    #}
    catch {
        Write-Error "Unable to launch offline copy of Borderlands 3. Quitting..." -ErrorAction Stop
    }
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
        $bl3_processes = Get-Process *borderlands3* | Sort-Object pm | Select-Object -last 2
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
if (($reposition_windows_enabled -eq $true) -and (($split_mode -eq "vertical") -or ($split_mode -eq "horizontal"))) {
    while ($bl3_windows.count -lt 2) {
        sleep -s 1
        $bl3_windows = Select-Window borderlands3
    }
    Write-Host Repositioning windows. Switch to Universal Split Screen to setup the input devices
    Write-Host Press s to swap position of the windows. Press d to toggle between vertical and horizontal split
    $invert = $false
    while ($bl3_windows.count -eq 2) {
        $i = 0
        foreach ($window in $bl3_windows) {
            if ($split_mode -eq "vertical") {
                $x_res = (([System.Windows.Forms.Screen]::AllScreens.Bounds.Width) / 2) + 1
                $y_res = ([System.Windows.Forms.Screen]::AllScreens.Bounds.Height) + 1
                $x_pos = ($i*$x_res)-1
                $y_pos = -1
            
            } else {
                $x_res = ([System.Windows.Forms.Screen]::AllScreens.Bounds.Width) + 1
                $y_res = (([System.Windows.Forms.Screen]::AllScreens.Bounds.Height) / 2) + 2
                $x_pos = -1
                $y_pos = ($i*$y_res)-1
            }
            $window_position = $window | Get-WindowPosition
            if (($window_position.y -ne ($y_pos)) -or ($window_position.x -ne ($x_pos)) -or ($window_position.height -ne ($y_res)) -or ($window_position.width -ne ($x_res))) {
                Set-WindowPosition -left $x_pos -top $y_pos -height $y_res -width $x_res -window $window            
            }
            $i++
        }
        sleep -m 100
        $bl3_windows = Select-Window borderlands3
        if ([console]::KeyAvailable) {
            $key = [system.console]::readkey($true)
            if ($key.key -eq "s") {$invert = !$invert; Write-Host Swapping windows }
            elseif ($key.key -eq "d") {
                if ($split_mode -eq "horizontal") {$split_mode = "vertical"; Write-Host Changing to vertical split}
                elseif ($split_mode -eq "vertical") {$split_mode = "horizontal"; Write-Host Changing to horizontal split}
                }
        }
        if ($invert) {$null = [array]::Reverse($bl3_windows) }
    }
}
Write-Host All done!
