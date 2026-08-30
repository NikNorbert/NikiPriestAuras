[CmdletBinding()]
param(
    [string]$Version
)

$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$tocPath = Join-Path $repositoryRoot "NikiPriestAuras.toc"
$tocVersionLine = Select-String -LiteralPath $tocPath -Pattern '^## Version:\s*(.+)$'

if (-not $tocVersionLine) {
    throw "Could not read the addon version from NikiPriestAuras.toc."
}

$tocVersion = $tocVersionLine.Matches[0].Groups[1].Value.Trim()
if ([string]::IsNullOrWhiteSpace($Version)) {
    $Version = $tocVersion
} else {
    $Version = $Version.TrimStart('v')
    if ($Version -ne $tocVersion) {
        throw "Tag/package version '$Version' does not match TOC version '$tocVersion'."
    }
}

$distributionRoot = Join-Path $repositoryRoot "dist"
$stagingRoot = Join-Path $distributionRoot "staging"
$addonRoot = Join-Path $stagingRoot "NikiPriestAuras"
$textureRoot = Join-Path $addonRoot "Textures"
$documentationImageRoot = Join-Path $addonRoot "docs\images"
$archivePath = Join-Path $distributionRoot "NikiPriestAuras-$Version.zip"

if (Test-Path -LiteralPath $stagingRoot) {
    Remove-Item -LiteralPath $stagingRoot -Recurse -Force
}
if (Test-Path -LiteralPath $archivePath) {
    Remove-Item -LiteralPath $archivePath -Force
}

New-Item -ItemType Directory -Path $textureRoot -Force | Out-Null
New-Item -ItemType Directory -Path $documentationImageRoot -Force | Out-Null

$runtimeFiles = @(
    "NikiPriestAuras.toc",
    "NikiPriestAuras.lua",
    "ShieldTracker.lua",
    "README.md",
    "README.txt",
    "CHANGELOG.md",
    "LICENSE"
)

$runtimeTextures = @(
    "CureDiseaseReminder_256.tga",
    "DispelMagicReminder_256.tga",
    "DivineSpiritReminder_256.tga",
    "EnlightenedAuraRays_512.tga",
    "EnlightenReminder_256.tga",
    "FortitudeReminder_256.tga",
    "InnerFireReminder_256.tga",
    "PowerWordShieldReminder_256.tga",
    "SearingLightProc_256.tga"
)

$documentationTextures = @(
    "InnerFireReminder-preview.png",
    "SearingLightProc-preview.png"
)

$documentationImages = @(
    "custom-reminder-icons.png",
    "settings-window-ru.png"
)

foreach ($relativePath in $runtimeFiles) {
    $sourcePath = Join-Path $repositoryRoot $relativePath
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required runtime file is missing: $relativePath"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $addonRoot
}

foreach ($textureName in $runtimeTextures) {
    $sourcePath = Join-Path (Join-Path $repositoryRoot "Textures") $textureName
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required runtime texture is missing: Textures/$textureName"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $textureRoot
}

foreach ($textureName in $documentationTextures) {
    $sourcePath = Join-Path (Join-Path $repositoryRoot "Textures") $textureName
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required documentation texture is missing: Textures/$textureName"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $textureRoot
}

foreach ($imageName in $documentationImages) {
    $sourcePath = Join-Path (Join-Path $repositoryRoot "docs\images") $imageName
    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required documentation image is missing: docs/images/$imageName"
    }
    Copy-Item -LiteralPath $sourcePath -Destination $documentationImageRoot
}

Compress-Archive -LiteralPath $addonRoot -DestinationPath $archivePath
Remove-Item -LiteralPath $stagingRoot -Recurse -Force

Write-Output $archivePath
