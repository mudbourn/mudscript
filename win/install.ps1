# Install mudscript on Windows #
    # Usage: irm https://raw.githubusercontent.com/mudbourn/mudscript/main/win/install.ps1 | iex
# END #

& {
    $ErrorActionPreference = 'Stop'
    $ProgressPreference = 'SilentlyContinue'

    [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12

    # Config #
        $HostRepo = 'mudbourn/mudspoon'
        $Repo = 'mudbourn/mudscript'
        $UninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{8F4C2D1A-6B3E-4C7A-9D52-3E1B7A0C94F6}_is1'
        $HS = Join-Path $env:USERPROFILE '.hammerspoon'
        $Tmp = Join-Path $env:TEMP ('mudscript-install-' + [guid]::NewGuid().ToString('N'))
        $Headers = @{ 'User-Agent' = 'mudscript-installer' }
        $DevFlag = Join-Path $env:ProgramData ('mudscript\devmode\' + $env:USERNAME)
        $Stamp = Get-Date -Format 'yyyy-MM-dd_HHmmss'
        $Backup = $HS + '-backup-' + $Stamp
    # END #

    # Helpers #
        function Step($m) {
            Write-Host ""
            Write-Host $m
        }

        function Ok($m) { Write-Host "   OK   $m" -ForegroundColor Green }

        function Warn($m) { Write-Host "   WARN $m" -ForegroundColor Yellow }

        function Ask($question, $default) {
            if (-not [Environment]::UserInteractive) { return $default }

            try {
                $answer = Read-Host "   $question"
            }
            catch {
                return $default
            }

            if ([string]::IsNullOrWhiteSpace($answer)) { return $default }

            return $answer.Trim().Substring(0, 1).ToUpper()
        }

        function Get-HostDir {
            $key = Get-ItemProperty $UninstallKey -ErrorAction SilentlyContinue

            if (-not $key -or -not $key.InstallLocation) { return $null }

            $app = Join-Path $key.InstallLocation 'app'

            if (Test-Path (Join-Path $app 'main.lua')) { return $app }

            return $null
        }

        function Stop-Host($dir) {
            $stop = if ($dir) { Join-Path $dir 'stop.ps1' } else { $null }

            if ($stop -and (Test-Path $stop)) {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $stop -Root $dir -Tray | Out-Null
            }

            $hostProcs = @(Get-CimInstance Win32_Process -Filter "Name = 'lua.exe' OR Name = 'powershell.exe' OR Name = 'wscript.exe'" |
                Where-Object { $_.ProcessId -ne $PID -and $_.CommandLine -match '(main|run_mudscript)\.lua|watchdog\.ps1|Mudspoon\.vbs' })

            foreach ($p in $hostProcs) { Stop-Process -Id $p.ProcessId -Force -ErrorAction SilentlyContinue }

            $log = Join-Path $HS 'hammerspoon.log'

            for ($i = 0; $i -lt 40 -and (Test-Path $log); $i++) {
                try {
                    [IO.File]::Open($log, 'Open', 'ReadWrite', 'None').Close()
                    break
                }
                catch {
                    Start-Sleep -Milliseconds 250
                }
            }
        }

        function Uninstall-All {
            $dir = Get-HostDir
            $removeHost = $dir -and ((Ask 'Also remove Hammerspoon for Windows? (y/N)' 'N') -eq 'Y')

            Step "1. Stopping Hammerspoon if it is running ..."

            Stop-Host $dir

            Ok "Stopped"

            Step "2. Moving $HS aside ..."

            if (Test-Path $HS) {
                Move-Item -LiteralPath $HS -Destination $Backup

                Ok "Your macros and settings are kept in $Backup"
            }
            else {
                Ok "Nothing to move"
            }

            if ($removeHost) {
                Step "3. Removing Hammerspoon for Windows ..."

                $key = Get-ItemProperty $UninstallKey -ErrorAction SilentlyContinue
                $exe = if ($key -and $key.UninstallString) { $key.UninstallString.Trim('"') } else { $null }

                if ($exe -and (Test-Path $exe)) {
                    $proc = Start-Process $exe -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait -PassThru

                    if ($proc.ExitCode -ne 0) { Warn "The uninstaller exited with code $($proc.ExitCode)." }
                    else { Ok "Removed" }
                }
                else {
                    Warn "No uninstaller found. Remove it from Settings -> Apps."
                }

                Remove-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run' -Name 'Mudspoon' -ErrorAction SilentlyContinue
            }

            Write-Host ""
            Write-Host "mudscript is uninstalled. Delete $Backup when you no longer need it."
        }

        function Get-LatestRelease($repo) {
            $releases = Invoke-RestMethod "https://api.github.com/repos/$repo/releases?per_page=100" -Headers $Headers

            $stable = @($releases | Where-Object { -not $_.draft -and -not $_.prerelease -and $_.tag_name -match '^v\d+(\.\d+)+$' })

            if ($stable.Count -eq 0) { throw "$repo has no stable release." }

            return $stable | Sort-Object { [version]($_.tag_name.TrimStart('v')) } -Descending | Select-Object -First 1
        }

        function Get-HostVersion($dir) {
            if (-not $dir) { return $null }

            $file = Join-Path $dir 'VERSION'

            if (-not (Test-Path $file)) { return $null }

            try {
                return [version]((Get-Content $file -Raw).Trim())
            }
            catch {
                return $null
            }
        }
    # END #

    Write-Host ""
    Write-Host "mudscript :// Windows Installer"

    New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

    try {
        # Install or uninstall #
            if ((Get-HostDir) -or (Test-Path (Join-Path $HS 'ms_core.lua'))) {
                Step "0. Found an existing install."

                if ((Ask '[I]nstall or update, or [U]ninstall? (I/u)' 'I') -eq 'U') {
                    Uninstall-All
                    return
                }
            }
        # END #

        # Existing config #
            $clean = $false

            if ((Test-Path $HS) -and (Get-ChildItem $HS -Force -ErrorAction SilentlyContinue | Select-Object -First 1)) {
                Step "0. Found an existing $HS folder."

                Write-Host "   Clean install moves it to $Backup and starts fresh."
                Write-Host "   Update keeps your profiles, settings and update channel."

                $clean = (Ask '[C]lean install or [U]pdate in place? (C/u)' 'C') -ne 'U'
            }

            $devOff = $false

            if (Test-Path $DevFlag) {
                Step "0b. Developer mode is on for $env:USERNAME ($DevFlag)."

                Write-Host "   It skips integrity checks and the plugin gate, and survives reinstalls."

                $devOff = (Ask 'Turn developer mode off? Needs administrator approval. (Y/n)' 'Y') -ne 'N'
            }
        # END #

        # Hammerspoon for Windows #
            Step "1. Checking for Hammerspoon for Windows ..."

            $hostDir = Get-HostDir
            $installed = Get-HostVersion $hostDir

            $release = Get-LatestRelease $HostRepo
            $latest = [version]($release.tag_name.TrimStart('v'))
            $asset = $release.assets | Where-Object { $_.name -eq 'Mudspoon-Setup.exe' } | Select-Object -First 1

            if ($hostDir -and $installed -and $installed -ge $latest) {
                Ok "v$installed is current at $hostDir"
            }
            elseif ($hostDir -and -not $asset) {
                Warn "The latest $HostRepo release has no Mudspoon-Setup.exe yet. Keeping the install at $hostDir."
            }
            else {
                if (-not $asset) { throw "The latest $HostRepo release has no Mudspoon-Setup.exe." }

                $setup = Join-Path $Tmp 'Mudspoon-Setup.exe'

                if ($hostDir) {
                    Write-Host "   Upgrading from $(if ($installed) { "v$installed" } else { 'an unknown version' }) to $($release.tag_name) ..."
                }

                Write-Host "   Downloading $($release.tag_name) ..."

                Invoke-WebRequest $asset.browser_download_url -OutFile $setup -Headers $Headers

                Write-Host "   Installing ..."

                $proc = Start-Process $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART', '/SP-' -Wait -PassThru

                if ($proc.ExitCode -ne 0) { throw "Mudspoon-Setup.exe exited with code $($proc.ExitCode)." }

                $hostDir = Get-HostDir

                if (-not $hostDir) { throw "Hammerspoon for Windows did not register its install folder." }

                Ok "Installed $($release.tag_name) at $hostDir"
            }
        # END #

        # mudscript source #
            $msRelease = Get-LatestRelease $Repo

            Step "2. Downloading mudscript $($msRelease.tag_name) ..."

            $zip = Join-Path $Tmp 'mudscript.zip'

            Invoke-WebRequest "https://github.com/$Repo/archive/refs/tags/$($msRelease.tag_name).zip" -OutFile $zip -Headers $Headers

            Expand-Archive $zip -DestinationPath $Tmp -Force

            $src = Get-ChildItem $Tmp -Directory | Where-Object { Test-Path (Join-Path $_.FullName 'win\deploy.ps1') } | Select-Object -First 1

            if (-not $src) { throw "The downloaded archive has no win\deploy.ps1." }

            $src = $src.FullName

            Ok "Downloaded"
        # END #

        # Stop the host #
            Step "3. Stopping Hammerspoon if it is running ..."

            Stop-Host $hostDir

            Ok "Stopped"
        # END #

        # Clean install #
            if ($clean) {
                Step "3b. Moving the existing config aside ..."

                Move-Item -LiteralPath $HS -Destination $Backup

                Ok "Backed up to $Backup"
            }
        # END #

        # Developer mode #
            if ($devOff) {
                Step "3c. Turning developer mode off ..."

                $cmd = "Remove-Item -LiteralPath '" + $DevFlag.Replace("'", "''") + "' -Force"
                $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($cmd))

                try {
                    $p = Start-Process powershell -Verb RunAs -Wait -PassThru -WindowStyle Hidden -ArgumentList '-NoProfile', '-NonInteractive', '-EncodedCommand', $encoded

                    if ($p.ExitCode -ne 0) { throw "exit code $($p.ExitCode)" }
                }
                catch {
                    Warn "Could not remove the flag ($_). Turn it off in Settings -> Developer."
                }

                if (-not (Test-Path $DevFlag)) { Ok "Developer mode is off" }
            }
        # END #

        # Deploy #
            Step "4. Installing mudscript into $HS ..."

            $freshProfiles = -not (Test-Path (Join-Path $HS 'profiles'))

            & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $src 'win\deploy.ps1') -Repo $src -HS $HS

            if ($LASTEXITCODE -ne 0) { throw "win\deploy.ps1 failed ($LASTEXITCODE)." }

            Ok "Deployed"
        # END #

        # Default profile #
            $defaultProfile = Join-Path $src 'profiles\Default'

            if ($freshProfiles -and (Test-Path $defaultProfile)) {
                Step "5. Installing the Default profile ..."

                $profiles = Join-Path $HS 'profiles'

                New-Item -ItemType Directory -Force -Path $profiles | Out-Null

                Copy-Item $defaultProfile $profiles -Recurse -Force

                Set-Content (Join-Path $profiles '.layout') '2' -Encoding Ascii

                Set-Content (Join-Path $profiles '.active') 'Default' -Encoding Ascii

                Get-ChildItem $src -File -Filter *.mspkg | Copy-Item -Destination $HS -Force

                Ok "Default profile installed"
            }
        # END #

        # Beta tester #
            Step "5b. Beta testing ..."

            $debugFlag = Join-Path $HS 'data\.ms_debug_on'

            if ((Ask 'Are you a beta tester? Debug logging will start from first launch. (y/N)' 'N') -eq 'Y') {
                New-Item -ItemType Directory -Force -Path (Join-Path $HS 'data') | Out-Null

                Set-Content $debugFlag '1' -Encoding Ascii

                Ok "Debug mode on. Turn it off in Settings > Developer."
            }
            else {
                Ok "Debug mode left as is"
            }
        # END #

        # Start #
            Step "6. Starting Hammerspoon ..."

            Start-Process (Join-Path $env:WINDIR 'System32\wscript.exe') -ArgumentList ('"' + (Join-Path $hostDir 'Mudspoon.vbs') + '"') -WorkingDirectory $hostDir

            Ok "Started"

            Write-Host ""
            Write-Host "Done. Run this command again and pick Update to update mudscript in place."
        # END #
    }
    finally {
        Remove-Item $Tmp -Recurse -Force -ErrorAction SilentlyContinue
    }
}
