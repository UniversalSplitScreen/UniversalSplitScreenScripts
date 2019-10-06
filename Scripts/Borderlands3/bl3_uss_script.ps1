# Variables
$x_res = 1920
$y_res = (1080/2)-15                                                       # Tweak this until you find a value that works for your setup. Offset is for the titlebar
$USS_Path = 'C:/Universal Split Screen 1.1.1/UniversalSplitScreen.exe'     # Universal Split Screen install path. Download from https://universalsplitscreen.github.io/
$proc_aff_enabled = $true                                                  # Assigns half the CPU cores to one window, and half to the other. Can disable if you have a powerful CPU

# Edit the game settings to launch in windowed mode
try {
    $config_ini_path = $env:USERPROFILE + "\Documents\My Games\Borderlands 3\Saved\Config\WindowsNoEditor\GameUserSettings.ini"
    Write-Host Setting game to windowed mode
    $config_ini = Get-Content $config_ini_path
    $line = $config_ini | Select-String ResolutionSizeX=
    $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],('ResolutionSizeX=' + $x_res)}
	$line = $config_ini | Select-String ResolutionSizeY=
    $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],('ResolutionSizeY=' + $y_res)}
    $line = $config_ini | Select-String FullscreenMode=
    $config_ini = $config_ini | ForEach-Object {$_ -replace $line[0],'FullscreenMode=2'} | Out-File $config_ini_path
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
    # Search through Epic Launcher logs to find the launch parameters for Borderlands 3. Might have to wait until Epic copy has launched before it can start
    Write-Host Finding offline launch arguments
    while (($Launch_Info -eq $null) -and ($bl3_processes -eq $null)) {
        sleep 1
        $bl3_processes = Get-Process borderlands3 -ErrorAction SilentlyContinue
        $Launch_Info = Get-Content $env:USERPROFILE\AppData\Local\EpicGamesLauncher\Saved\Logs\EpicGamesLauncher.log | `
                       Where-Object {$_ -like '*FCommunityPortalLaunchAppTask: Launching app*Borderlands3.exe*'} | `
                       Select-Object -First 1
    }

    # Reformat it, split out the arguments, and point to the actual binary
    $null, $bl3_bin = $Launch_Info -split "Launching app "
    $bl3_bin = $bl3_bin -replace "'",""
    $bl3_bin, $bl3_arg = $bl3_bin -split "with commandline "
    $bl3_bin = $bl3_bin -replace "Borderlands3.exe","OakGame/Binaries/Win64/Borderlands3.exe"

    # Make sure it exists then launch
    $null = Test-Path -Path $bl3_bin -ErrorAction stop
    Write-Host Found Borderlands 3 in $bl3_bin
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
        sleep 1
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
Write-Host All done!
