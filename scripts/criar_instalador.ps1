# Gera o instalador do MapLong para Windows (MapLong-Setup-<versao>.exe).
#
# Uso (na pasta do projeto):
#   powershell -ExecutionPolicy Bypass -File scripts\criar_instalador.ps1
#
# Requisitos: Flutter e Inno Setup 6
#   winget install JRSoftware.InnoSetup

$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

# Lê a versão do pubspec.yaml (ex.: "version: 2.0.0+3" -> 2.0.0).
$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*([0-9.]+)').Matches[0].Groups[1].Value
Write-Host "MapLong $version" -ForegroundColor Cyan

# Procura o compilador do Inno Setup nos lugares comuns.
$iscc = @(
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $iscc) {
    throw 'Inno Setup 6 não encontrado. Instale com: winget install JRSoftware.InnoSetup'
}

Write-Host '1/4 Baixando dependências...' -ForegroundColor Cyan
flutter pub get
if ($LASTEXITCODE -ne 0) { throw 'flutter pub get falhou.' }

Write-Host '2/4 Rodando os testes...' -ForegroundColor Cyan
flutter test
if ($LASTEXITCODE -ne 0) { throw 'Os testes falharam: corrija antes de gerar o instalador.' }

Write-Host '3/4 Compilando o app (Release)...' -ForegroundColor Cyan
flutter build windows --release
if ($LASTEXITCODE -ne 0) { throw 'A compilação do Windows falhou.' }

Write-Host '4/4 Gerando o instalador...' -ForegroundColor Cyan
& $iscc "/DMyAppVersion=$version" installer\maplong.iss
if ($LASTEXITCODE -ne 0) { throw 'O Inno Setup não conseguiu gerar o instalador.' }

$out = Resolve-Path "installer\Output\MapLong-Setup-$version.exe"
Write-Host "Pronto! Instalador em: $out" -ForegroundColor Green
