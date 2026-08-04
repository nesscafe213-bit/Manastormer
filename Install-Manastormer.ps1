param(
    [string]$AddOnsPath
)

$ErrorActionPreference = 'Stop'
$repository = 'nesscafe213-bit/Manastormer'

function Write-Step {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Get-InstalledVersion {
    param([string]$TocPath)
    if (-not (Test-Path -LiteralPath $TocPath)) {
        return 'not installed'
    }
    $versionLine = Get-Content -LiteralPath $TocPath | Where-Object { $_ -match '^## Version:' } | Select-Object -First 1
    if ($versionLine -match '^## Version:\s*(.+)$') {
        return $Matches[1].Trim()
    }
    return 'unknown'
}

if (-not $AddOnsPath) {
    $candidates = @(
        'H:\Ascension Launcher\Ascension Launcher\resources\client\Interface\AddOns',
        'C:\Program Files\Ascension Launcher\resources\client\Interface\AddOns',
        'C:\Program Files (x86)\Ascension Launcher\resources\client\Interface\AddOns',
        (Join-Path $env:LOCALAPPDATA 'Programs\Ascension Launcher\resources\client\Interface\AddOns')
    )
    $AddOnsPath = $candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Container } | Select-Object -First 1
}

if (-not $AddOnsPath -or -not (Test-Path -LiteralPath $AddOnsPath -PathType Container)) {
    throw "Ascension's AddOns folder was not found. Run this again with -AddOnsPath followed by the full path to Interface\AddOns."
}

$AddOnsPath = (Resolve-Path -LiteralPath $AddOnsPath).Path
$targetFolder = Join-Path $AddOnsPath 'Manastormer'
$targetToc = Join-Path $targetFolder 'Manastormer.toc'
$oldVersion = Get-InstalledVersion $targetToc

Write-Step "Ascension AddOns folder: $AddOnsPath"
Write-Step "Installed Manastormer version: $oldVersion"
Write-Step 'Checking GitHub for the newest release...'

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$release = Invoke-RestMethod -Uri "https://api.github.com/repos/$repository/releases/latest" `
    -Headers @{ 'User-Agent' = 'Manastormer-Updater' }
$asset = $release.assets | Where-Object { $_.name -match '^Manastormer-[0-9].*\.zip$' } | Select-Object -First 1
if (-not $asset) {
    throw 'The latest GitHub release does not contain a Manastormer ZIP.'
}

$releaseVersion = ([string]$release.tag_name).TrimStart('v')
if ($oldVersion -eq $releaseVersion) {
    Write-Host "Manastormer $releaseVersion is already installed. Reinstalling a clean copy..." -ForegroundColor Yellow
} else {
    Write-Step "Newest version: $releaseVersion"
}

$workingFolder = Join-Path $env:TEMP ("ManastormerUpdate-" + [guid]::NewGuid().ToString('N'))
$downloadZip = Join-Path $workingFolder $asset.name
$extractFolder = Join-Path $workingFolder 'Extracted'
New-Item -ItemType Directory -Path $extractFolder -Force | Out-Null

try {
    Write-Step "Downloading $($asset.name)..."
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $downloadZip -UseBasicParsing
    Expand-Archive -LiteralPath $downloadZip -DestinationPath $extractFolder -Force

    $sourceToc = Get-ChildItem -LiteralPath $extractFolder -Filter 'Manastormer.toc' -File -Recurse |
        Where-Object { $_.Directory.Name -eq 'Manastormer' } | Select-Object -First 1
    if (-not $sourceToc) {
        throw 'The downloaded ZIP does not contain a valid Manastormer addon folder.'
    }
    $sourceFolder = $sourceToc.Directory.FullName
    $packageVersion = Get-InstalledVersion $sourceToc.FullName
    if ($packageVersion -ne $releaseVersion) {
        throw "The ZIP version ($packageVersion) does not match the GitHub release ($releaseVersion)."
    }

    if (Test-Path -LiteralPath $targetFolder -PathType Container) {
        $backupRoot = Join-Path $env:LOCALAPPDATA 'Manastormer\Backups'
        New-Item -ItemType Directory -Path $backupRoot -Force | Out-Null
        $backupName = 'Manastormer-' + $oldVersion + '-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.zip'
        $backupZip = Join-Path $backupRoot $backupName
        Write-Step "Backing up the current addon to $backupZip"
        Compress-Archive -LiteralPath $targetFolder -DestinationPath $backupZip -CompressionLevel Optimal
    }

    New-Item -ItemType Directory -Path $targetFolder -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceFolder '*') -Destination $targetFolder -Recurse -Force

    $installedVersion = Get-InstalledVersion $targetToc
    if ($installedVersion -ne $releaseVersion) {
        throw 'The installation could not be verified.'
    }

    Write-Host ''
    Write-Host "Manastormer $installedVersion installed successfully." -ForegroundColor Green
    Write-Host 'Restart Ascension or type /reload in game.' -ForegroundColor Green
} finally {
    if (Test-Path -LiteralPath $workingFolder) {
        Remove-Item -LiteralPath $workingFolder -Recurse -Force
    }
}
