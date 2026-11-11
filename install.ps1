# Installs the Jerry desktop pet into the Codex pets folder on Windows.
$ErrorActionPreference = 'Stop'

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$codexHome = if ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME '.codex' }
$petFolder = Join-Path (Join-Path $codexHome 'pets') 'jerry'

New-Item -ItemType Directory -Force -Path $petFolder | Out-Null
foreach ($fileName in @('pet.json', 'spritesheet.png')) {
    Copy-Item -Path (Join-Path $scriptDir "pets\jerry\$fileName") -Destination (Join-Path $petFolder $fileName) -Force
}

Write-Host "Installed jerry -> $petFolder"
Write-Host "Done. Restart Codex and pick Jerry from its pet list, or run .\run-jerry.bat directly."
