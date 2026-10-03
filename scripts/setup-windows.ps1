#Requires -Version 5.1
<#
.SYNOPSIS
    Confere se o Windows está pronto para a Etapa 0 e, se pedido, instala ou configura o que falta.

.DESCRIPTION
    Verifica: versão do Windows, WSL 2, Docker Desktop, memória do Docker, .NET 8 SDK, Git,
    portas 1433/5672/5300/5341 (incluindo faixas reservadas pelo Hyper-V) e SQL Server local.
    Sem parâmetros, só diagnostica e não altera nada.

.PARAMETER Instalar
    Instala via winget o que estiver faltando (.NET 8 SDK, Git, Docker Desktop).

.PARAMETER ConfigurarMemoriaWsl
    Cria ou ajusta %UserProfile%\.wslconfig com a memória indicada (faz backup antes).

.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\scripts\setup-windows.ps1 -Instalar -ConfigurarMemoriaWsl -MemoriaGB 6
#>
param(
    [switch]$Instalar,
    [switch]$ConfigurarMemoriaWsl,
    [int]$MemoriaGB = 6
)

$ErrorActionPreference = "Continue"
$resultado = New-Object System.Collections.Generic.List[object]

function Registrar([string]$item, [string]$status, [string]$detalhe) {
    $resultado.Add([pscustomobject]@{ Item = $item; Status = $status; Detalhe = $detalhe })
    $cor = @{ OK = "Green"; AVISO = "Yellow"; FALTA = "Red" }[$status]
    Write-Host ("[{0,-5}] {1}: {2}" -f $status, $item, $detalhe) -ForegroundColor $cor
}

function Testar-Comando([string]$nome) { [bool](Get-Command $nome -ErrorAction SilentlyContinue) }

function Instalar-Winget([string]$id, [string]$nome) {
    if (-not $Instalar) { return $false }
    if (-not (Testar-Comando "winget")) {
        Write-Host "  winget não encontrado; instale '$nome' manualmente." -ForegroundColor Yellow
        return $false
    }
    Write-Host "  Instalando $nome via winget..." -ForegroundColor Cyan
    winget install --id $id --exact --accept-package-agreements --accept-source-agreements
    return ($LASTEXITCODE -eq 0)
}

Write-Host "`nEtapa 0 - diagnóstico do Windows`n" -ForegroundColor Cyan

# 1. Windows com suporte a WSL 2 (build 19041+)
$build = [int](Get-CimInstance Win32_OperatingSystem).BuildNumber
if ($build -ge 19041) { Registrar "Windows" "OK" "build $build" }
else { Registrar "Windows" "FALTA" "build $build; WSL 2 exige 19041 ou superior (Windows 10 2004+ ou Windows 11)" }

# 2. WSL 2
if (Testar-Comando "wsl") {
    wsl --status *> $null
    if ($LASTEXITCODE -eq 0) { Registrar "WSL" "OK" "instalado" }
    else { Registrar "WSL" "FALTA" "rode 'wsl --install' num PowerShell como administrador e reinicie" }
} else {
    Registrar "WSL" "FALTA" "rode 'wsl --install' num PowerShell como administrador e reinicie"
}

# 3. Docker Desktop instalado e rodando
if (-not (Testar-Comando "docker")) {
    if (Instalar-Winget "Docker.DockerDesktop" "Docker Desktop") {
        Registrar "Docker Desktop" "AVISO" "instalado agora; faça logoff/login, abra o Docker Desktop e rode este script de novo"
    } else {
        Registrar "Docker Desktop" "FALTA" "instale com: winget install Docker.DockerDesktop"
    }
} else {
    $os = docker version --format "{{.Server.Os}}" 2>$null
    if ($LASTEXITCODE -ne 0) {
        $exe = Join-Path $env:ProgramFiles "Docker\Docker\Docker Desktop.exe"
        if (Test-Path $exe) {
            Write-Host "  Docker Desktop parado; iniciando e aguardando até 2 min..." -ForegroundColor Cyan
            Start-Process $exe
            for ($i = 0; $i -lt 24; $i++) {
                Start-Sleep -Seconds 5
                $os = docker version --format "{{.Server.Os}}" 2>$null
                if ($LASTEXITCODE -eq 0) { break }
            }
        }
    }
    if ($os -eq "linux") { Registrar "Docker Desktop" "OK" "rodando com containers Linux" }
    elseif ($os -eq "windows") { Registrar "Docker Desktop" "FALTA" "está em modo Windows containers; clique com o botão direito no ícone e escolha 'Switch to Linux containers'" }
    else { Registrar "Docker Desktop" "FALTA" "não respondeu; abra o Docker Desktop e espere 'Engine running'" }

    # 4. Memória disponível para os containers
    $memBytes = docker info --format "{{.MemTotal}}" 2>$null
    if ($LASTEXITCODE -eq 0 -and $memBytes) {
        $memGB = [math]::Round([double]$memBytes / 1GB, 1)
        if ($memGB -ge 4) { Registrar "Memória do Docker" "OK" "$memGB GB" }
        else { Registrar "Memória do Docker" "FALTA" "$memGB GB; o SQL Server precisa de pelo menos 2 GB e o conjunto, de 4 GB. Use -ConfigurarMemoriaWsl" }
    }
}

# 5. .wslconfig (limite de memória da VM do WSL 2)
$wslconfig = Join-Path $env:UserProfile ".wslconfig"
if ($ConfigurarMemoriaWsl) {
    if (Test-Path $wslconfig) {
        Copy-Item $wslconfig "$wslconfig.bak-$(Get-Date -Format yyyyMMddHHmmss)"
        $linhas = @(Get-Content $wslconfig)   # @() garante array mesmo com uma linha só
    } else { $linhas = @() }

    if (-not ($linhas -match '^\s*\[wsl2\]')) { $linhas += "[wsl2]" }
    if ($linhas -match '^\s*memory\s*=') {
        $linhas = $linhas -replace '^\s*memory\s*=.*$', "memory=${MemoriaGB}GB"
    } else {
        $indice = [array]::FindIndex([string[]]$linhas, [Predicate[string]]{ param($l) $l -match '^\s*\[wsl2\]' })
        $antes = if ($indice -ge 0) { $linhas[0..$indice] } else { @() }
        $depois = if ($indice -lt $linhas.Count - 1) { $linhas[($indice + 1)..($linhas.Count - 1)] } else { @() }
        $linhas = @($antes) + "memory=${MemoriaGB}GB" + @($depois)
    }
    Set-Content -Path $wslconfig -Value $linhas -Encoding ASCII
    Registrar ".wslconfig" "AVISO" "memory=${MemoriaGB}GB gravado; rode 'wsl --shutdown' e reabra o Docker Desktop para aplicar"
} elseif (Test-Path $wslconfig) {
    $mem = (Select-String -Path $wslconfig -Pattern '^\s*memory\s*=\s*(.+)$').Matches | Select-Object -First 1
    $texto = if ($mem) { "memory=$($mem.Groups[1].Value.Trim())" } else { "sem limite de memória definido (WSL usa até 50% da RAM)" }
    Registrar ".wslconfig" "OK" $texto
}

# 6. .NET 8 SDK
$sdk8 = $false
if (Testar-Comando "dotnet") { $sdk8 = [bool](dotnet --list-sdks 2>$null | Select-String '^8\.') }
if ($sdk8) { Registrar ".NET 8 SDK" "OK" ((dotnet --list-sdks | Select-String '^8\.' | Select-Object -Last 1).ToString().Split(' ')[0]) }
elseif (Instalar-Winget "Microsoft.DotNet.SDK.8" ".NET 8 SDK") { Registrar ".NET 8 SDK" "AVISO" "instalado agora; abra um novo terminal" }
else { Registrar ".NET 8 SDK" "FALTA" "instale com: winget install Microsoft.DotNet.SDK.8" }

# 7. Git e fim de linha
if (Testar-Comando "git") {
    $autocrlf = git config --get core.autocrlf
    Registrar "Git" "OK" "core.autocrlf=$(if ($autocrlf) { $autocrlf } else { 'não definido' }); o .gitattributes do repositório força LF onde importa"
} elseif (Instalar-Winget "Git.Git" "Git") { Registrar "Git" "AVISO" "instalado agora; abra um novo terminal" }
else { Registrar "Git" "FALTA" "instale com: winget install Git.Git" }

# 8. Portas: em uso por outro processo ou reservadas pelo Hyper-V/WinNAT
$reservadas = @()
netsh interface ipv4 show excludedportrange protocol=tcp | ForEach-Object {
    if ($_ -match '^\s*(\d+)\s+(\d+)') { $reservadas += ,@([int]$matches[1], [int]$matches[2]) }
}
$portas = [ordered]@{ 1433 = "SQL Server"; 5672 = "Service Bus AMQP"; 5300 = "Service Bus gestão"; 5341 = "Seq" }
foreach ($porta in $portas.Keys) {
    $faixa = $reservadas | Where-Object { $porta -ge $_[0] -and $porta -le $_[1] } | Select-Object -First 1
    if ($faixa) {
        Registrar "Porta $porta ($($portas[$porta]))" "FALTA" "reservada pelo Windows na faixa $($faixa[0])-$($faixa[1]); veja 'Portas reservadas' no README-WINDOWS"
        continue
    }
    $conexao = Get-NetTCPConnection -LocalPort $porta -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $conexao) { Registrar "Porta $porta ($($portas[$porta]))" "OK" "livre"; continue }
    $processo = (Get-Process -Id $conexao.OwningProcess -ErrorAction SilentlyContinue).ProcessName
    if ($processo -match 'docker|wslrelay|vpnkit') {
        Registrar "Porta $porta ($($portas[$porta]))" "OK" "já publicada pelo Docker (ambiente no ar)"
    } else {
        Registrar "Porta $porta ($($portas[$porta]))" "FALTA" "em uso por '$processo' (PID $($conexao.OwningProcess))"
    }
}

# 9. SQL Server instalado no Windows disputando a 1433
$servicosSql = Get-Service -Name "MSSQL*" -ErrorAction SilentlyContinue | Where-Object Status -eq "Running"
if ($servicosSql) {
    Registrar "SQL Server local" "AVISO" "serviço '$($servicosSql[0].Name)' rodando; use MSSQL_PORT=14333 no .env ou pare o serviço"
}

# Resumo
$faltas = @($resultado | Where-Object Status -eq "FALTA").Count
$avisos = @($resultado | Where-Object Status -eq "AVISO").Count
Write-Host ""
if ($faltas -eq 0) {
    Write-Host "Pronto. Próximo passo: .\scripts\ambiente.ps1 verificar" -ForegroundColor Green
    if ($avisos -gt 0) { Write-Host "Revise os $avisos aviso(s) acima." -ForegroundColor Yellow }
    exit 0
} else {
    Write-Host "$faltas item(ns) precisam de ajuste antes de continuar." -ForegroundColor Red
    exit 1
}
