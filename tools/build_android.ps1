# Builds signed release APK + AAB for one or both apps.
# Usage: powershell -File tools/build_android.ps1 [-App foldshift|paperverse|all] [-Install] [-ApkOnly]
# Signing credentials are read from C:\dev\keys\f7developer-release.env (never committed) or existing env vars.
param(
    [string]$App = "all",
    [switch]$Install,
    [switch]$ApkOnly,
    [int]$TimeoutMinutes = 15,
    [string]$Godot = "C:\dev\godot\Godot_v4.7.2-stable_win64_console.exe"
)
# Native tools write progress to stderr; failures are detected by checking outputs instead.
$ErrorActionPreference = "Continue"
$root = Split-Path -Parent $PSScriptRoot
$envFile = "C:\dev\keys\f7developer-release.env"
if (Test-Path $envFile) {
    Get-Content $envFile | ForEach-Object {
        $k, $v = $_ -split "=", 2
        if ($k) { Set-Item -Path "env:$k" -Value $v }
    }
}
if (-not $env:GODOT_ANDROID_KEYSTORE_RELEASE_PATH) { throw "Release keystore env vars are not set." }
# A lingering Gradle daemon inherits Godot's output pipe and keeps the export process alive; run Gradle without it.
$env:GRADLE_OPTS = "-Dorg.gradle.daemon=false"

python "$root\tools\sync_core.py" --check
if ($LASTEXITCODE -ne 0) { throw "Core copies drifted. Run python tools/sync_core.py" }

$apps = if ($App -eq "all") { @("foldshift", "paperverse") } else { @($App) }
foreach ($a in $apps) {
    $proj = Join-Path $root "apps\$a"
    $out = Join-Path $root "build\$a"
    New-Item -ItemType Directory -Force $out | Out-Null
    # Install the Gradle build template (same layout the editor creates via Project > Install Android Build Template).
    if (-not (Test-Path "$proj\android\.build_version")) {
        $zip = Join-Path $env:APPDATA "Godot\export_templates\4.7.2.stable\android_source.zip"
        python -c "import zipfile,sys; zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])" $zip "$proj\android\build"
        Set-Content "$proj\android\.build_version" "4.7.2.stable" -NoNewline
        Set-Content "$proj\android\.gdignore" "" -NoNewline
    }
    & $Godot --headless --path $proj --import 2>&1 | Out-Null
    $presets = if ($ApkOnly) { @("Android APK") } else { @("Android APK", "Android AAB") }
    foreach ($preset in $presets) {
        Write-Host "[$a] exporting $preset"
        $ext = if ($preset -like "*AAB") { "aab" } else { "apk" }
        $name = (Get-Culture).TextInfo.ToTitleCase($a) -replace "Foldshift", "FoldShift" -replace "Paperverse", "PaperVerse"
        $target = Join-Path $out "$name-1.0.0.$ext"
        if (Test-Path $target) { Remove-Item $target -Force }
        $log = Join-Path $out "$ext-export.log"
        $p = Start-Process -FilePath $Godot -ArgumentList @("--headless", "--path", "`"$proj`"", "--export-release", "`"$preset`"", "`"$target`"") `
            -RedirectStandardOutput $log -RedirectStandardError "$log.err" -PassThru -NoNewWindow
        # Godot can stay alive after a finished export because Gradle keeps its output pipe open.
        # Stop waiting once the log reports the export step done and the file exists.
        $deadline = (Get-Date).AddMinutes($TimeoutMinutes)
        while (-not $p.HasExited) {
            Start-Sleep -Seconds 2
            $done = (Test-Path $target) -and (Select-String -Path $log -Pattern "DONE.*export" -Quiet)
            if ($done -or (Get-Date) -gt $deadline) {
                Start-Sleep -Seconds 3
                if (-not $p.HasExited) { $p | Stop-Process -Force }
                & "$proj\android\build\gradlew.bat" --stop 2>&1 | Out-Null
                if (-not (Test-Path $target)) { throw "[$a] $preset export timed out after $TimeoutMinutes min (see $log)" }
                break
            }
        }
        Select-String -Path $log, "$log.err" -Pattern "ERROR|FAILED" | ForEach-Object { Write-Host $_.Line }
        if (-not (Test-Path $target)) { throw "[$a] $preset export failed (see $log)" }
        Write-Host ("[$a] {0}  {1:N1} MB" -f $target, ((Get-Item $target).Length / 1MB))
    }
    if ($Install) {
        $sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "C:\Android\Sdk" }
        $adb = "$sdk\platform-tools\adb.exe"
        $apk = Get-ChildItem $out -Filter *.apk | Select-Object -First 1
        & $adb install -r $apk.FullName
    }
}
