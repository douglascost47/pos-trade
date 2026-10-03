#Requires -Version 5.1
<#
.SYNOPSIS
    Comandos do dia a dia do ambiente local (Docker) no Windows.

.EXAMPLE
    .\scripts\ambiente.ps1 verificar      # sobe tudo, espera ficar pronto e roda o smoke test
.EXAMPLE
    .\scripts\ambiente.ps1 subir          # só sobe e espera ficar pronto
.EXAMPLE
    .\scripts\ambiente.ps1 logs servicebus
.EXAMPLE
    .\scripts\ambiente.ps1 zerar          # apaga containers E volumes (bancos e logs)
#>
param(
    [Parameter(Position = 0)]
    [ValidateSet("subir", "verificar", "status", "logs", "reiniciar-servicebus", "parar", "zerar")]
    [string]$Acao = "verificar",

    [Parameter(Position = 1)]
    [ValidateSet("", "mssql", "db-init", "servicebus", "seq")]
    [string]$Servico = ""
)

$ErrorActionPreference = "Stop"
$raiz = Split-Path -Parent $PSScriptRoot
Set-Location $raiz

function Falhar([string]$mensagem) {
    Write-Host $mensagem -ForegroundColor Red
    exit 1
}

function Exigir-Docker {
    # No PowerShell 5.1, redirecionar stderr de comando nativo com "Stop" vira exceção
    $preferencia = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    docker version --format "{{.Server.Os}}" *> $null
    $codigo = $LASTEXITCODE
    $ErrorActionPreference = $preferencia
    if ($codigo -ne 0) {
        Falhar "Docker não está respondendo. Abra o Docker Desktop e espere 'Engine running' (ou rode .\scripts\setup-windows.ps1)."
    }
}

function Garantir-Env {
    if (-not (Test-Path ".env")) {
        Copy-Item ".env.example" ".env"
        Write-Host "Criei o .env a partir do .env.example. Revise a senha se quiser." -ForegroundColor Yellow
    }
}

function Carregar-Env {
    # Repassa MSSQL_SA_PASSWORD e MSSQL_PORT do .env para o smoke test
    Get-Content ".env" | Where-Object { $_ -match '^\s*(MSSQL_SA_PASSWORD|MSSQL_PORT)\s*=' } | ForEach-Object {
        $chave, $valor = $_ -split '=', 2
        Set-Item -Path ("Env:" + $chave.Trim()) -Value $valor.Trim()
    }
}

function Subir {
    Exigir-Docker
    Garantir-Env
    docker compose up -d
    if ($LASTEXITCODE -ne 0) { Falhar "docker compose up falhou. Veja a mensagem acima." }

    Write-Host "Aguardando o emulador do Service Bus (até 3 min)..." -ForegroundColor Cyan
    $pronto = $false
    for ($i = 0; $i -lt 36; $i++) {
        try {
            $resposta = Invoke-WebRequest -Uri "http://localhost:5300/health" -UseBasicParsing -TimeoutSec 3
            if ($resposta.StatusCode -eq 200) { $pronto = $true; break }
        } catch { }
        Write-Host "." -NoNewline
        Start-Sleep -Seconds 5
    }
    Write-Host ""
    if (-not $pronto) {
        docker compose logs --tail 40 servicebus
        Falhar "O emulador não respondeu em http://localhost:5300/health. Tente: .\scripts\ambiente.ps1 reiniciar-servicebus"
    }

    $codigo = docker inspect postrade-db-init --format "{{.State.ExitCode}}"
    if ($codigo -ne "0") {
        docker compose logs db-init
        Falhar "db-init terminou com código $codigo (os bancos não foram criados)."
    }

    $porta = "1433"
    $linhaPorta = Get-Content ".env" | Select-String '^\s*MSSQL_PORT\s*=\s*(\d+)' | Select-Object -First 1
    if ($linhaPorta) { $porta = $linhaPorta.Matches[0].Groups[1].Value }
    Write-Host "Ambiente no ar: SQL localhost,$porta | Service Bus localhost:5672 | Seq http://localhost:5341" -ForegroundColor Green
}

switch ($Acao) {
    "subir" { Subir }

    "verificar" {
        Subir
        Carregar-Env
        dotnet run --project "tools\Etapa0.SmokeTest"
        exit $LASTEXITCODE
    }

    "status" { Exigir-Docker; docker compose ps -a }

    "logs" {
        Exigir-Docker
        if ($Servico) { docker compose logs -f --tail 100 $Servico } else { docker compose logs -f --tail 50 }
    }

    "reiniciar-servicebus" {
        # Útil depois de editar deploy\servicebus\Config.json: o emulador só lê o arquivo ao iniciar
        Exigir-Docker
        docker compose restart servicebus
        Write-Host "Emulador reiniciado. Rode '.\scripts\ambiente.ps1 verificar' para conferir." -ForegroundColor Green
    }

    "parar" {
        Exigir-Docker
        docker compose down
        Write-Host "Containers parados. Os bancos continuam no volume mssql-data." -ForegroundColor Green
    }

    "zerar" {
        Exigir-Docker
        $confirmacao = Read-Host "Isso apaga os bancos PosTrade_* e os logs do Seq. Digite 'zerar' para confirmar"
        if ($confirmacao -ne "zerar") { Write-Host "Cancelado."; exit 0 }
        docker compose down -v
        Write-Host "Ambiente zerado. Suba de novo com '.\scripts\ambiente.ps1 verificar'." -ForegroundColor Green
    }
}
