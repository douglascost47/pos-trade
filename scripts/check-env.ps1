#Requires -Version 5.1
# Atalho mantido por compatibilidade: equivale a '.\scripts\ambiente.ps1 verificar'.
& (Join-Path $PSScriptRoot "ambiente.ps1") verificar
exit $LASTEXITCODE
