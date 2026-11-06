param(
    [string]$QtRoot = 'E:\Programmi\Qt\6.10.3\mingw_64',
    [string]$MinGwBin = 'E:\Programmi\Qt\Tools\mingw1310_64\bin',
    [string]$VcpkgRoot = '',
    [string]$DependenciesRoot = '',
    [ValidateRange(1, 64)][int]$Jobs = 6
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-Checked {
    param([string]$Description, [scriptblock]$Command)
    Write-Host "`n==> $Description"
    & $Command
    if ($LASTEXITCODE -ne 0) {
        throw "$Description non riuscito (codice $LASTEXITCODE)."
    }
}

$repository = $PSScriptRoot
$tools = Join-Path $repository 'build-qt6-tools'
$build = Join-Path $repository 'build-qt6'
$release = Join-Path $repository 'release-qt6'
if (-not $VcpkgRoot) { $VcpkgRoot = Join-Path $tools 'vcpkg' }
if (-not $DependenciesRoot) { $DependenciesRoot = Join-Path $tools 'installed' }

foreach ($file in @((Join-Path $QtRoot 'lib\cmake\Qt6\Qt6Config.cmake'),
                   (Join-Path $MinGwBin 'g++.exe'),
                   (Join-Path $MinGwBin 'mingw32-make.exe'))) {
    if (-not (Test-Path -LiteralPath $file)) { throw "File richiesto assente: $file" }
}
foreach ($program in @('git', 'cmake')) {
    if (-not (Get-Command $program -ErrorAction SilentlyContinue)) {
        throw "Programma richiesto non trovato nel PATH: $program"
    }
}

New-Item -ItemType Directory -Force -Path $tools, $DependenciesRoot | Out-Null
$env:TEMP = Join-Path $tools 'temp'
$env:TMP = $env:TEMP
New-Item -ItemType Directory -Force -Path $env:TEMP | Out-Null
$env:PATH = "$MinGwBin;$(Join-Path $QtRoot 'bin');$(Join-Path $DependenciesRoot 'x64-mingw-dynamic\bin');$(Join-Path $DependenciesRoot 'x64-mingw-dynamic\lib');$env:PATH"

if (-not (Test-Path -LiteralPath (Join-Path $VcpkgRoot 'vcpkg.exe'))) {
    if (-not (Test-Path -LiteralPath (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat'))) {
        Invoke-Checked 'Scarico vcpkg' { git clone https://github.com/microsoft/vcpkg.git $VcpkgRoot }
    }
    Invoke-Checked 'Preparo vcpkg' { & (Join-Path $VcpkgRoot 'bootstrap-vcpkg.bat') -disableMetrics }
}

# Readline is optional on Windows; its vcpkg port fails with this MinGW toolchain.
# Install the libraries the application actually requires instead of the whole manifest.
Push-Location $VcpkgRoot
try {
    Invoke-Checked 'Installo le dipendenze C++' {
        & (Join-Path $VcpkgRoot 'vcpkg.exe') install botan libqrencode minizip zlib `
            --triplet x64-mingw-dynamic --host-triplet x64-mingw-dynamic `
            "--x-install-root=$DependenciesRoot"
    }
}
finally { Pop-Location }

$prefix = "$(Join-Path $DependenciesRoot 'x64-mingw-dynamic');$QtRoot"
Invoke-Checked 'Configuro KeePassXC' {
    cmake -S $repository -B $build -G 'MinGW Makefiles' `
        "-DCMAKE_PREFIX_PATH=$prefix" `
        "-DCMAKE_C_COMPILER=$(Join-Path $MinGwBin 'gcc.exe')" `
        "-DCMAKE_CXX_COMPILER=$(Join-Path $MinGwBin 'g++.exe')" `
        "-DCMAKE_MAKE_PROGRAM=$(Join-Path $MinGwBin 'mingw32-make.exe')" `
        -DKPXC_FEATURE_DOCS=OFF -DWITH_TESTS=OFF
}
Invoke-Checked 'Compilo KeePassXC' { cmake --build $build --parallel $Jobs }
Invoke-Checked 'Preparo la cartella release-qt6' { cmake --install $build --prefix $release }

$application = Join-Path $release 'KeePassXC.exe'
if (-not (Test-Path -LiteralPath $application)) { throw "Eseguibile non trovato: $application" }
Write-Host "`nBuild completata: $application"
