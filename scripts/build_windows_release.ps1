$ErrorActionPreference = 'Stop'

$RootDir = Split-Path -Parent $PSScriptRoot
Set-Location $RootDir

$VersionLine = (Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*(\S+)').Matches[0].Groups[1].Value
$VersionParts = $VersionLine.Split('+', 2)
$BuildName = $VersionParts[0]
$BuildNumber = if ($VersionParts.Count -gt 1) { $VersionParts[1] } else { '1' }

flutter pub get
flutter build windows --release --build-name=$BuildName --build-number=$BuildNumber

$BundleDir = Join-Path $RootDir 'build\windows\x64\runner\Release'
$DistDir = Join-Path $RootDir 'dist'
$ArchiveName = "PerfectCollage-$BuildName-windows-x64.zip"
$ArchivePath = Join-Path $DistDir $ArchiveName
$ChecksumPath = Join-Path $DistDir "PerfectCollage-$BuildName-windows-x64.sha256"

if (-not (Test-Path (Join-Path $BundleDir 'PerfectCollage.exe'))) {
  throw "Windows release executable was not found in $BundleDir"
}

New-Item -ItemType Directory -Path $DistDir -Force | Out-Null
Remove-Item $ArchivePath, $ChecksumPath -Force -ErrorAction SilentlyContinue
Compress-Archive -Path (Join-Path $BundleDir '*') -DestinationPath $ArchivePath -CompressionLevel Optimal

$Hash = (Get-FileHash -Path $ArchivePath -Algorithm SHA256).Hash.ToLowerInvariant()
Set-Content -Path $ChecksumPath -Value "$Hash *$ArchiveName" -Encoding ascii

Write-Host "Created $ArchivePath"
Write-Host "Created $ChecksumPath"
