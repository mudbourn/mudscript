# Deploy mudscript into the Hammerspoon config #
    [CmdletBinding()]
    param(
        [string]$Repo,
        [string]$HS,
        [switch]$NoBackup
    )
# END #

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

# Paths #
    if (-not $Repo) { $Repo = Split-Path -Parent $PSScriptRoot }

    if (-not $HS) { $HS = Join-Path $env:USERPROFILE '.hammerspoon' }

    if (-not (Test-Path $HS)) { New-Item -ItemType Directory -Force -Path $HS | Out-Null }

    $Repo = (Resolve-Path $Repo).Path
    $HS = (Resolve-Path $HS).Path
    $localBin = Join-Path $env:USERPROFILE '.local\bin'

    Write-Host "deploy: source = $Repo"
    Write-Host "deploy: target = $HS"
# END #

# Preflight: no native dialogs in shell UI #
    $nativeRe = 'hs\.dialog\.blockAlert|hs\.dialog\.textPrompt|hs\.alert\.show|hs\.chooser'
    $scanFiles = @()
    $libDir = Join-Path $Repo 'mac\lib'

    if (Test-Path $libDir) { $scanFiles += Get-ChildItem $libDir -Recurse -File -Filter *.lua }

    $scanFiles += Get-ChildItem (Join-Path $Repo 'mac') -File -Filter *.lua
    $hits = @()

    foreach ($f in $scanFiles) {
        if ($f.Name -eq 'ms_guardian.lua') { continue }

        $ln = 0

        foreach ($line in [System.IO.File]::ReadAllLines($f.FullName)) {
            $ln++

            if ($line -match '^\s*--') { continue }

            if ($line -match $nativeRe) { $hits += ("{0}:{1}: {2}" -f $f.Name, $ln, $line.Trim()) }
        }
    }

    if ($hits.Count -gt 0) {
        Write-Error ("deploy: native macOS dialog in shell UI - use ms.ui.modal instead:`n" + ($hits -join "`n"))
        exit 1
    }
# END #

# Backup #
    $ts = Get-Date -Format 'yyyy-MM-dd_HHmmss'

    if (-not $NoBackup) {
        $bakRoot = Join-Path $HS ("data\deploy_backups\" + $ts)
        New-Item -ItemType Directory -Force -Path $bakRoot | Out-Null

        foreach ($item in @('ms_core.lua', 'init.lua', 'MANIFEST.json', 'lib', 'ui', 'templates')) {
            $src = Join-Path $HS $item

            if (Test-Path $src) {
                Copy-Item -Path $src -Destination (Join-Path $bakRoot $item) -Recurse -Force
            }
        }

        Write-Host "deploy: backed up prior tree -> $bakRoot"
    }
# END #

# Copy helpers #
    function Copy-File($srcPath, $dstPath) {
        $dstDir = Split-Path -Parent $dstPath

        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }

        Copy-Item -LiteralPath $srcPath -Destination $dstPath -Force
    }

    function Copy-Tree($srcDir, $dstDir) {
        if (-not (Test-Path $srcDir)) { return }

        if (-not (Test-Path $dstDir)) { New-Item -ItemType Directory -Force -Path $dstDir | Out-Null }

        Get-ChildItem -LiteralPath $srcDir -Recurse -File | ForEach-Object {
            $rel = $_.FullName.Substring($srcDir.Length).TrimStart('\', '/')

            Copy-File $_.FullName (Join-Path $dstDir $rel)
        }
    }
# END #

# Core and bootstrap #
    Copy-File (Join-Path $Repo 'mac\ms_core.lua') (Join-Path $HS 'ms_core.lua')

    Copy-File (Join-Path $Repo 'mac\init.lua') (Join-Path $HS 'init.lua')
# END #

# UI #
    Get-ChildItem (Join-Path $Repo 'ui') -File -Filter *.html | ForEach-Object {
        Copy-File $_.FullName (Join-Path $HS ("ui\" + $_.Name))
    }

    $legacyUi = Join-Path $HS 'ui\ms_settings_ui.html'

    if (Test-Path $legacyUi) { Remove-Item -Force $legacyUi }

    foreach ($sub in @('fonts', 'modules', 'svg')) {
        Copy-Tree (Join-Path $Repo ("ui\" + $sub)) (Join-Path $HS ("ui\" + $sub))
    }
# END #

# Lua lib modules #
    $dstLib = Join-Path $HS 'lib'

    if (Test-Path $dstLib) { Remove-Item -Recurse -Force $dstLib }

    Copy-Tree (Join-Path $Repo 'mac\lib') $dstLib
# END #

# Shipped spoons #
    $spoons = Join-Path $HS 'Spoons'

    if (Test-Path $spoons) {
        Get-ChildItem $spoons -Directory -Filter 'Ms*.spoon' -ErrorAction SilentlyContinue |
            ForEach-Object { Remove-Item -Recurse -Force $_.FullName }
    }
# END #

# Sounds #
    foreach ($d in @('defaults', 'active', 'macro')) {
        Copy-Tree (Join-Path $Repo ("sounds\" + $d)) (Join-Path $HS ("sounds\" + $d))
    }
# END #

# Manifest #
    Copy-File (Join-Path $Repo 'MANIFEST.json') (Join-Path $HS 'MANIFEST.json')
# END #

# Templates and macros #
    $templates = Join-Path $Repo 'mac\templates'

    Copy-Tree $templates (Join-Path $HS 'templates')

    $macrosDst = Join-Path $HS 'ms_macros.lua'

    if (-not (Test-Path $macrosDst)) {
        Copy-File (Join-Path $templates 'ms_macros.lua') $macrosDst
    }
# END #

# Command line #
    New-Item -ItemType Directory -Force -Path $localBin | Out-Null

    Copy-File (Join-Path $Repo 'win\bin\mscli.cmd') (Join-Path $localBin 'mscli.cmd')

    Write-Host "deploy: mscli -> $localBin\mscli.cmd"
# END #

# Gamepad reader #
    $readerSrc = Join-Path $Repo 'win\bin\ms_gc_read.exe'

    if (Test-Path $readerSrc) {
        New-Item -ItemType Directory -Force -Path $localBin | Out-Null

        Copy-File $readerSrc (Join-Path $localBin 'ms_gc_read.exe')

        $sdlSrc = Join-Path $Repo 'win\bin\SDL2.dll'

        if (Test-Path $sdlSrc) {
            Copy-File $sdlSrc (Join-Path $localBin 'SDL2.dll')

            Write-Host "deploy: gamepad reader -> $localBin\ms_gc_read.exe (+ SDL2.dll)"
        } else {
            Write-Warning "deploy: ms_gc_read.exe deployed but SDL2.dll missing beside it. The reader will not start until SDL2.dll is present in $localBin."
        }
    } else {
        Write-Host "deploy: no win\bin\ms_gc_read.exe yet (build with win\bin\build.bat to enable controller input), skipping."
    }
# END #

# Layer daemon #
    $layerDir = Join-Path $Repo 'native\ms_layer'
    $layerExe = Join-Path $layerDir 'target\release\ms_layer.exe'
    $layerDest = Join-Path $localBin 'ms_layer.exe'

    Remove-Item "$layerDest.old" -Force -ErrorAction SilentlyContinue

    if ((Test-Path (Join-Path $layerDir 'Cargo.toml')) -and (Get-Command cargo -ErrorAction SilentlyContinue)) {
        $layerStale = -not (Test-Path $layerExe)

        if (-not $layerStale) {
            $exeTime = (Get-Item $layerExe).LastWriteTimeUtc
            $layerInputs = @(Get-ChildItem (Join-Path $layerDir 'src') -Recurse -File -ErrorAction SilentlyContinue)
            $layerInputs += Get-Item (Join-Path $layerDir 'Cargo.toml'), (Join-Path $layerDir 'Cargo.lock') -ErrorAction SilentlyContinue
            $newer = $layerInputs |
                Where-Object { $_.LastWriteTimeUtc -gt $exeTime } | Select-Object -First 1
            $layerStale = $null -ne $newer
        }

        if ($layerStale) {
            Write-Host "deploy: building ms_layer (cargo build --release)"

            & cargo build --release --manifest-path (Join-Path $layerDir 'Cargo.toml')

            if ($LASTEXITCODE -ne 0) { Write-Warning "deploy: cargo build of ms_layer failed, using any existing binary." }
        }
    }

    if (Test-Path $layerExe) {
        New-Item -ItemType Directory -Force -Path $localBin | Out-Null

        try {
            if (Test-Path $layerDest) {
                try {
                    Copy-File $layerExe $layerDest
                } catch {
                    Move-Item $layerDest "$layerDest.old" -Force

                    Copy-File $layerExe $layerDest
                }
            } else {
                Copy-File $layerExe $layerDest
            }

            Write-Host "deploy: layer daemon -> $layerDest"
        } catch {
            Write-Warning "deploy: could not replace $localBin\ms_layer.exe (daemon running?). Stop ms_layer and redeploy to update it."
        }
    } else {
        Write-Host "deploy: no native\ms_layer\target\release\ms_layer.exe yet (cargo build --release in native\ms_layer), skipping."
    }
# END #

# Spy daemon #
    $spyDir = Join-Path $Repo 'native\ms_spy'
    $spyExe = Join-Path $spyDir 'target\release\ms_spy.exe'
    $spyDest = Join-Path $localBin 'ms_spy.exe'

    Remove-Item "$spyDest.old" -Force -ErrorAction SilentlyContinue

    if ((Test-Path (Join-Path $spyDir 'Cargo.toml')) -and (Get-Command cargo -ErrorAction SilentlyContinue)) {
        $spyStale = -not (Test-Path $spyExe)

        if (-not $spyStale) {
            $exeTime = (Get-Item $spyExe).LastWriteTimeUtc
            $spyInputs = @(Get-ChildItem (Join-Path $spyDir 'src') -Recurse -File -ErrorAction SilentlyContinue)
            $spyInputs += Get-Item (Join-Path $spyDir 'Cargo.toml'), (Join-Path $spyDir 'Cargo.lock') -ErrorAction SilentlyContinue
            $newer = $spyInputs |
                Where-Object { $_.LastWriteTimeUtc -gt $exeTime } | Select-Object -First 1
            $spyStale = $null -ne $newer
        }

        if ($spyStale) {
            Write-Host "deploy: building ms_spy (cargo build --release)"

            & cargo build --release --manifest-path (Join-Path $spyDir 'Cargo.toml')

            if ($LASTEXITCODE -ne 0) { Write-Warning "deploy: cargo build of ms_spy failed, using any existing binary." }
        }
    }

    if (Test-Path $spyExe) {
        New-Item -ItemType Directory -Force -Path $localBin | Out-Null

        try {
            if (Test-Path $spyDest) {
                try {
                    Copy-File $spyExe $spyDest
                } catch {
                    Move-Item $spyDest "$spyDest.old" -Force

                    Copy-File $spyExe $spyDest
                }
            } else {
                Copy-File $spyExe $spyDest
            }

            Write-Host "deploy: spy daemon -> $spyDest"
        } catch {
            Write-Warning "deploy: could not replace $localBin\ms_spy.exe (daemon running?). Stop ms_spy and redeploy to update it."
        }
    } else {
        Write-Host "deploy: no native\ms_spy\target\release\ms_spy.exe yet (cargo build --release in native\ms_spy), skipping."
    }
# END #

# Data seeding #
    $dataDir = Join-Path $HS 'data'

    if (-not (Test-Path $dataDir)) { New-Item -ItemType Directory -Force -Path $dataDir | Out-Null }

    # Registry index #
        $regSrc = Join-Path $Repo 'registry\index.json'

        if (Test-Path $regSrc) {
            Copy-File $regSrc (Join-Path $dataDir 'registry_index.json')

            Write-Host "deploy: bundled registry index -> data\registry_index.json"
        } else {
            Write-Warning "deploy: $regSrc missing, leaving data\registry_index.json as-is (Browse may be stale or empty offline)."
        }
    # END #

    # Build number #
        $buildNumFile = Join-Path $dataDir '.ms_build_num'
        $buildBaseFile = Join-Path $dataDir '.ms_build_base'
        $manifestJson = Get-Content (Join-Path $HS 'MANIFEST.json') -Raw | ConvertFrom-Json
        $stableVer = $manifestJson.version
        $prevBase = if (Test-Path $buildBaseFile) { (Get-Content $buildBaseFile -Raw).Trim() } else { '' }

        if ($stableVer -ne $prevBase) {
            Set-Content -Path $buildNumFile -Value '0' -Encoding ascii -NoNewline

            Set-Content -Path $buildBaseFile -Value $stableVer -Encoding ascii -NoNewline
        } else {
            $old = if (Test-Path $buildNumFile) { [int]((Get-Content $buildNumFile -Raw).Trim()) } else { 0 }

            Set-Content -Path $buildNumFile -Value ([string]($old + 1)) -Encoding ascii -NoNewline
        }
    # END #

    # Trusted hash #
        function Rel($full) { $full.Substring($HS.Length).TrimStart('\', '/').Replace('\', '/') }

        $trackedAbs = New-Object System.Collections.Generic.List[string]
        $trackedAbs.Add((Join-Path $HS 'ms_core.lua'))
        $uiRoot = Join-Path $HS 'ui'

        if (Test-Path $uiRoot) {
            Get-ChildItem $uiRoot -Recurse -File | Where-Object {
                $_.Extension -eq '.js' -or ($_.Extension -eq '.html' -and $_.Name -notlike '_popout_*')
            } | ForEach-Object { $trackedAbs.Add($_.FullName) }
        }

        $binRoot = Join-Path $HS 'bin'

        if (Test-Path $binRoot) {
            Get-ChildItem $binRoot -File -Filter *.sh | ForEach-Object { $trackedAbs.Add($_.FullName) }
        }

        $libRoot = Join-Path $HS 'lib'

        if (Test-Path $libRoot) {
            Get-ChildItem $libRoot -Recurse -File -Filter *.lua | ForEach-Object { $trackedAbs.Add($_.FullName) }
        }

        $map = @{}

        foreach ($abs in $trackedAbs) {
            if (Test-Path $abs) {
                $h = (Get-FileHash -LiteralPath $abs -Algorithm SHA256).Hash.ToLower()

                $map[(Rel $abs)] = $h
            }
        }

        $entries = foreach ($k in ($map.Keys | Sort-Object)) { '"{0}":"{1}"' -f $k, $map[$k] }
        $trustJson = '{' + ($entries -join ',') + '}'
        $trustPath = Join-Path $dataDir '.ms_trusted_hash'

        Set-Content -Path $trustPath -Value $trustJson -Encoding ascii -NoNewline

        $fileManifest = Join-Path $dataDir '.ms_file_manifest.json'

        if (Test-Path $fileManifest) { Remove-Item -Force $fileManifest }
    # END #
# END #

# Verify #
    $bad = 0

    foreach ($k in $map.Keys) {
        $abs = Join-Path $HS $k
        $cur = (Get-FileHash -LiteralPath $abs -Algorithm SHA256).Hash.ToLower()

        if ($cur -ne $map[$k]) {
            $bad++

            Write-Warning "reseed mismatch: $k"
        }
    }

    $build = (Get-Content $buildNumFile -Raw).Trim()
    $coreHash = $map['ms_core.lua']

    Write-Host ""
    Write-Host ("Deployed. {0} tracked files hashed, {1} mismatched." -f $map.Count, $bad)
    Write-Host ("ms_core.lua: {0}...  (build {1}-pre.{2})" -f $coreHash.Substring(0, 16), $stableVer, $build)

    if ($bad -eq 0) { Write-Host "Trusted manifest is self-consistent with disk." }
# END #
