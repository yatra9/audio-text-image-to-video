[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"
$DistroName = "libav-wasm-dev"
$ProjectDir = Split-Path -Parent $MyInvocation.MyCommand.Path

function Write-Step([string]$Message) {
    Write-Host ""
    Write-Host ("==> " + $Message) -ForegroundColor Cyan
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-Distros {
    try {
        $items = & wsl.exe --list --quiet 2>$null
        if ($LASTEXITCODE -ne 0) { return @() }
        return @(
            $items |
            ForEach-Object { ($_ -replace "`0", "").Trim() } |
            Where-Object { $_ -ne "" }
        )
    }
    catch {
        return @()
    }
}

function Get-DistroVersion([string]$Name) {
    try {
        # --list --verbose is localized, so parse only the final numeric VERSION column.
        $lines = & wsl.exe --list --verbose 2>$null
        foreach ($line in $lines) {
            $clean = ($line -replace "`0", "").Trim()
            if ($clean -match [regex]::Escape($Name)) {
                if ($clean -match "\s([12])\s*$") {
                    return [int]$Matches[1]
                }
            }
        }
    }
    catch {}
    return 0
}

function Enable-WSL2Features {
    Write-Step "Enabling Windows features required by WSL 2"

    & dism.exe /online /enable-feature /featurename:Microsoft-Windows-Subsystem-Linux /all /norestart | Out-Host
    $rc1 = $LASTEXITCODE

    & dism.exe /online /enable-feature /featurename:VirtualMachinePlatform /all /norestart | Out-Host
    $rc2 = $LASTEXITCODE

    if ($rc1 -ne 0 -and $rc1 -ne 3010) {
        throw ("Failed to enable Microsoft-Windows-Subsystem-Linux. Exit code: " + $rc1)
    }
    if ($rc2 -ne 0 -and $rc2 -ne 3010) {
        throw ("Failed to enable VirtualMachinePlatform. Exit code: " + $rc2)
    }

    try {
        & bcdedit.exe /set hypervisorlaunchtype auto | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("bcdedit returned exit code " + $LASTEXITCODE)
        }
    }
    catch {
        Write-Warning ("Could not set hypervisorlaunchtype: " + $_.Exception.Message)
    }

    try {
        & wsl.exe --set-default-version 2 | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("wsl --set-default-version 2 returned exit code " + $LASTEXITCODE)
        }
    }
    catch {
        Write-Warning ("Could not set default WSL version: " + $_.Exception.Message)
    }
}

function Exit-For-Reboot {
    Write-Host ""
    Write-Host "A Windows restart is required before WSL 2 can start." -ForegroundColor Yellow
    Write-Host "Restart Windows, then run build.cmd again." -ForegroundColor Yellow
    Write-Host "The installed Debian distro will be reused; the build will continue." -ForegroundColor Yellow
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 20
}

try {
    if (-not (Test-Admin)) {
        Write-Step "Restarting as Administrator"
        $scriptPath = $MyInvocation.MyCommand.Path
        $argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
        Start-Process -FilePath "powershell.exe" -Verb RunAs -ArgumentList $argLine
        exit 0
    }

    Write-Host "libav.js AAC/MP3 single-HTML builder v1.38" -ForegroundColor Green
    Write-Host ("Project: " + $ProjectDir)

    if (-not (Get-Command wsl.exe -ErrorAction SilentlyContinue)) {
        throw "wsl.exe is not available on this Windows installation."
    }

    Write-Step "Checking WSL"
    try {
        & wsl.exe --status | Out-Host
    }
    catch {}

    # Always make sure the required optional components are enabled.
    Enable-WSL2Features

    try {
        Write-Step "Updating WSL"
        & wsl.exe --update | Out-Host
        if ($LASTEXITCODE -ne 0) {
            Write-Warning ("wsl --update returned exit code " + $LASTEXITCODE)
        }
    }
    catch {
        Write-Warning ("wsl --update failed: " + $_.Exception.Message)
    }

    $distros = Get-Distros
    if ($distros -notcontains $DistroName) {
        Write-Step ("Installing Debian as WSL distro: " + $DistroName)

        & wsl.exe --install Debian --name $DistroName --no-launch --web-download
        if ($LASTEXITCODE -ne 0) {
            throw ("Failed to install Debian WSL distro. Exit code: " + $LASTEXITCODE)
        }

        # A newly enabled VirtualMachinePlatform often requires a reboot before
        # the just-installed distro can be switched/launched as WSL 2.
        $versionAfterInstall = Get-DistroVersion $DistroName
        if ($versionAfterInstall -ne 2) {
            try {
                & wsl.exe --shutdown 2>$null
            }
            catch {}
        }
    }
    else {
        Write-Step ("Using existing WSL distro: " + $DistroName)
    }

    $version = Get-DistroVersion $DistroName
    Write-Host ("Detected distro version: " + $version)

    if ($version -ne 2) {
        Write-Step "Converting distro to WSL 2"
        try {
            & wsl.exe --shutdown 2>$null
        }
        catch {}

        & wsl.exe --set-version $DistroName 2 | Out-Host
        $setVersionExit = $LASTEXITCODE

        if ($setVersionExit -ne 0) {
            # WSL_E_VM_MODE_INVALID_STATE commonly means the Windows feature /
            # hypervisor change needs a reboot. Do not mark the project failed.
            Enable-WSL2Features
            Exit-For-Reboot
        }
    }

    Write-Step "Starting Debian"
    & wsl.exe -d $DistroName -u root -- bash -lc "echo WSL-ready" | Out-Host
    if ($LASTEXITCODE -ne 0) {
        Enable-WSL2Features
        Exit-For-Reboot
    }

    Write-Step "Converting the Windows project path to a WSL path"

    # Do not pass a Windows path through wsl.exe/wslpath here.
    # Backslashes can be consumed by command-line translation on some systems.
    # Convert a normal drive-letter path locally instead:
    #   C:\Users\name\project -> /mnt/c/Users/name/project
    if ($ProjectDir -match '^([A-Za-z]):\\(.*)$') {
        $drive = $Matches[1].ToLowerInvariant()
        $tail = $Matches[2] -replace '\\', '/'
        $wslProject = "/mnt/" + $drive + "/" + $tail
    }
    else {
        throw ("Unsupported project path. Put this builder on a normal Windows drive, for example C:\work\libav-wasm-wsl-builder. Current path: " + $ProjectDir)
    }

    Write-Host ("WSL project path: " + $wslProject)

    # Verify the path exists from inside the selected WSL distro.
    & wsl.exe -d $DistroName -u root -- test -f "$wslProject/wsl-build.sh"
    if ($LASTEXITCODE -ne 0) {
        throw ("WSL cannot see the project files at: " + $wslProject)
    }

    Write-Step "Building custom libav.js with AAC support"
    Write-Host "The first build can take a long time."

    & wsl.exe -d $DistroName -u root -- bash "$wslProject/wsl-build.sh" "$wslProject"
    if ($LASTEXITCODE -ne 0) {
        throw ("WSL build failed. Exit code: " + $LASTEXITCODE)
    }

    $final = Join-Path $ProjectDir "index.html"
    if (-not (Test-Path -LiteralPath $final)) {
        throw ("Build finished, but the final HTML was not found: " + $final)
    }

    Write-Host ""
    Write-Host "BUILD SUCCESS" -ForegroundColor Green
    Write-Host ("Final HTML: " + $final) -ForegroundColor Green
    $size = (Get-Item -LiteralPath $final).Length / 1MB
    Write-Host ("Size: {0:N1} MB" -f $size)
    Write-Host ""
    Read-Host "Press Enter to exit"
}
catch {
    Write-Host ""
    Write-Host "BUILD FAILED" -ForegroundColor Red
    Write-Host $_.Exception.ToString() -ForegroundColor Red
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}
