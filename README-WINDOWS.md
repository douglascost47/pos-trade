# Etapa 0 no Windows — passo a passo

Este guia leva um Windows 10/11 do zero até o ambiente da Etapa 0 rodando: SQL Server, emulador do Azure Service Bus e Seq em Docker, validados pelo smoke test. Os detalhes da topologia, das connection strings e dos limites do emulador estão no `README-ETAPA0.md`. Aqui ficam só o que muda no Windows e os problemas típicos dele.

Tempo estimado: 30 a 60 minutos, a maior parte esperando instalação e download de imagens (cerca de 3 GB).

## Visão geral

```text
Windows
 ├─ PowerShell ──► scripts\ambiente.ps1 ──► docker compose
 ├─ .NET 8 SDK ──► tools\Etapa0.SmokeTest (roda no Windows, fala com localhost)
 └─ Docker Desktop
     └─ WSL 2 (VM Linux leve)
         ├─ postrade-mssql        localhost:1433
         ├─ postrade-servicebus   localhost:5672 e :5300
         └─ postrade-seq          http://localhost:5341
```

Os containers rodam numa VM Linux do WSL 2, e o Docker Desktop publica as portas no `localhost` do Windows. Seu código .NET roda no Windows normalmente, no Visual Studio, Rider ou VS Code, e enxerga tudo por `localhost`.

## Passo 1 — Pré-requisitos

Abra o **PowerShell como administrador** só para este passo.

**1.1. WSL 2** (exige reinício):

```powershell
wsl --install
```

Se o WSL já existir, rode `wsl --update` e confira com `wsl --status` que a versão padrão é 2. Se aparecer erro de virtualização, ative "Intel VT-x" ou "AMD-V/SVM" na BIOS e o recurso "Plataforma de Máquina Virtual" no Windows.

**1.2. Docker Desktop, .NET 8 SDK e Git:**

```powershell
winget install --id Docker.DockerDesktop -e
winget install --id Microsoft.DotNet.SDK.8 -e
winget install --id Git.Git -e
```

Depois da instalação, faça logoff e login. Abra o Docker Desktop e, em **Settings → General**, deixe marcado **Use the WSL 2 based engine**. Espere aparecer **Engine running**.

> Licença: o Docker Desktop é gratuito para uso pessoal e para empresas pequenas. Em empresa grande, pode exigir assinatura. Para estudo na sua máquina pessoal, não há custo.

**1.3. Permitir scripts PowerShell** (no seu usuário, sem administrador):

```powershell
Set-ExecutionPolicy -Scope CurrentUser RemoteSigned
```

## Passo 2 — Pasta do projeto

Use uma pasta curta, **fora do OneDrive**. O OneDrive trava arquivos durante a sincronização e costuma quebrar `bin/obj` e montagens do Docker.

```powershell
mkdir C:\dev -Force
cd C:\dev
# extraia o zip aqui, ou clone o seu repositório:
# git clone https://github.com/<usuario>/postrade-lab.git
cd C:\dev\postrade-lab
```

**Se veio de um zip baixado da internet**, o Windows marca os arquivos como "baixados" e o `RemoteSigned` bloqueia os scripts. Desbloqueie uma vez:

```powershell
Get-ChildItem -Recurse | Unblock-File
```

Se for versionar, faça o primeiro commit **depois** de copiar o `.gitattributes`. Ele garante fim de linha LF nos arquivos que os containers Linux leem.

## Passo 3 — Diagnóstico da máquina

```powershell
.\scripts\setup-windows.ps1
```

O script não altera nada por padrão. Ele confere Windows, WSL, Docker Desktop (e se está em containers Linux), memória do Docker, .NET 8, Git, as portas 1433, 5672, 5300 e 5341 (inclusive faixas reservadas pelo Windows) e se há um SQL Server instalado ocupando a 1433.

Opções úteis:

```powershell
.\scripts\setup-windows.ps1 -Instalar                              # instala via winget o que faltar
.\scripts\setup-windows.ps1 -ConfigurarMemoriaWsl -MemoriaGB 6     # ajusta o .wslconfig (com backup)
```

**Memória:** o SQL Server sozinho pede cerca de 2 GB, e o conjunto precisa de pelo menos 4 GB. O WSL 2 usa por padrão até metade da RAM. Com 16 GB, isso já sobra. Com 8 GB, defina 5 ou 6 GB e feche o que não estiver usando. Depois de mudar o `.wslconfig`:

```powershell
wsl --shutdown
# reabra o Docker Desktop
```

Siga em frente quando o resumo terminar com **Pronto**.

## Passo 4 — Subir e verificar

```powershell
.\scripts\ambiente.ps1 verificar
```

O comando cria o `.env` a partir do `.env.example` (se não existir), sobe os containers, espera o emulador responder, confere se os bancos foram criados e roda o smoke test. Na primeira vez, o download das imagens leva alguns minutos. A saída final esperada é a lista de verificações com `[OK]` e a linha **Ambiente pronto para a Etapa 1**.

## Comandos do dia a dia

| Comando | O que faz |
| --- | --- |
| `.\scripts\ambiente.ps1 verificar` | sobe, espera ficar pronto e roda o smoke test |
| `.\scripts\ambiente.ps1 subir` | só sobe e espera ficar pronto |
| `.\scripts\ambiente.ps1 status` | lista os containers e o estado de cada um |
| `.\scripts\ambiente.ps1 logs servicebus` | acompanha os logs de um serviço (`mssql`, `db-init`, `servicebus`, `seq`) |
| `.\scripts\ambiente.ps1 reiniciar-servicebus` | reinicia o emulador depois de editar o `Config.json` |
| `.\scripts\ambiente.ps1 parar` | para tudo e mantém os bancos |
| `.\scripts\ambiente.ps1 zerar` | apaga containers e volumes (pede confirmação) |

O emulador não guarda mensagens nem entidades entre reinícios. Isso é esperado: a topologia volta pelo `Config.json`.

## Ferramentas no Windows

- **IDE:** Visual Studio 2022, Rider ou VS Code com C# Dev Kit. No Visual Studio, os segredos ficam em **botão direito no projeto → Manage User Secrets**. Na linha de comando, `dotnet user-secrets set "ConnectionStrings:ServiceBus" "<connection string>"`.
- **SQL:** SQL Server Management Studio (`winget install Microsoft.SQLServerManagementStudio`) ou a extensão **SQL Server (mssql)** do VS Code. Conecte em `localhost,1433` com o usuário `sa` e a senha do `.env`, marcando **Trust server certificate**.
- **Service Bus:** o Service Bus Explorer open source não funciona com o emulador. Para inspecionar mensagens, use o smoke test como base ou a ferramenta de redrive da Etapa 5, ambos com o SDK.
- **Logs:** Seq em http://localhost:5341.
- **Terminal:** o Windows Terminal com PowerShell 7 (`winget install Microsoft.PowerShell`) é mais confortável, mas todos os scripts também rodam no Windows PowerShell 5.1 que vem com o sistema.

## Problemas comuns no Windows

| Sintoma | Causa | Solução |
| --- | --- | --- |
| "cannot be loaded because running scripts is disabled" | política de execução | `Set-ExecutionPolicy -Scope CurrentUser RemoteSigned` |
| "is not digitally signed" | arquivos vindos de zip baixado | `Get-ChildItem -Recurse \| Unblock-File` na pasta do projeto |
| "ports are not available ... access a socket in a way forbidden" | porta dentro de uma faixa reservada pelo Hyper-V/WinNAT | veja a seção a seguir |
| Erro na porta 1433 | SQL Server instalado no Windows | `MSSQL_PORT=14333` no `.env`, ou pare o serviço em `services.msc` |
| `postrade-mssql` reinicia em loop | pouca memória no WSL 2 ou senha fraca | ajuste o `.wslconfig` (Passo 3) e use uma senha forte no `.env` |
| "Docker Desktop is starting" para sempre | WSL travado | `wsl --shutdown`, feche e reabra o Docker Desktop; se persistir, `wsl --update` |
| "/bin/bash^M: bad interpreter" ou JSON inválido no container | arquivos convertidos para CRLF pelo Git | confira o `.gitattributes` e rode `git add --renormalize .` |
| Acentos estranhos no terminal | console em outra página de código | o smoke test já força UTF-8; no PowerShell 5.1 use o Windows Terminal ou `chcp 65001` |
| Containers sem internet ou download de imagens falhando | VPN corporativa ou proxy | desconecte a VPN para baixar as imagens ou configure o proxy em **Settings → Resources → Proxies** |
| Tudo muito lento | antivírus varrendo as pastas | exclua `C:\dev` e as pastas do Docker da varredura em tempo real, se a política permitir |

### Portas reservadas pelo Windows

O Hyper-V e o WinNAT reservam faixas de portas de forma dinâmica, e às vezes elas incluem 5300 ou 5672. O `setup-windows.ps1` detecta isso. Para ver as faixas:

```powershell
netsh interface ipv4 show excludedportrange protocol=tcp
```

Solução rápida, num PowerShell como **administrador**:

```powershell
net stop winnat
docker compose up -d     # na pasta do projeto: o Docker pega as portas enquanto o WinNAT está parado
net start winnat
```

Se o problema voltar com frequência, uma solução comum é reservar as portas manualmente, também como administrador e com o WinNAT parado. Teste depois de reiniciar o Windows; se o Docker não conseguir publicar a porta, remova a reserva com `netsh int ipv4 delete excludedportrange protocol=tcp startport=<porta> numberofports=1`.

```powershell
net stop winnat
netsh int ipv4 add excludedportrange protocol=tcp startport=5300 numberofports=1
netsh int ipv4 add excludedportrange protocol=tcp startport=5672 numberofports=1
net start winnat
```

A reserva manual impede que o Windows sorteie essas portas para a faixa dinâmica do Hyper-V.

## Checklist da Etapa 0 no Windows

- [ ] `.\scripts\setup-windows.ps1` termina com **Pronto**
- [ ] `.\scripts\ambiente.ps1 verificar` com todas as verificações `[OK]`
- [ ] SSMS ou VS Code conectando em `localhost,1433` e mostrando os bancos `PosTrade_*`
- [ ] Seq abrindo em http://localhost:5341
- [ ] Connection strings nos user-secrets
- [ ] Projeto fora do OneDrive e `.gitattributes` no primeiro commit
