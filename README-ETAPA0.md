# Etapa 0 — Ambiente local

> **No Windows?** Siga primeiro o [README-WINDOWS.md](README-WINDOWS.md): ele cobre WSL 2, Docker Desktop, memória, portas e os scripts `setup-windows.ps1` e `ambiente.ps1`.

Sobe em Docker tudo o que o projeto precisa para começar: SQL Server 2022 (bancos dos serviços e backend do emulador), emulador do Azure Service Bus com a topologia do projeto já declarada, e Seq para logs.

```text
postrade-lab/
├─ docker-compose.yml
├─ .env.example                     # copie para .env
├─ .gitattributes                   # força LF nos arquivos lidos pelos containers
├─ deploy/
│  ├─ servicebus/Config.json        # tópicos, assinaturas e fila do emulador
│  └─ sql/01-create-databases.sql   # 1 banco por serviço
├─ scripts/
│  ├─ setup-windows.ps1             # Windows: diagnóstico e preparação da máquina
│  ├─ ambiente.ps1                  # Windows: subir, verificar, logs, parar, zerar
│  ├─ check-env.ps1                 # atalho para 'ambiente.ps1 verificar'
│  └─ check-env.sh                  # Linux / macOS / WSL
└─ tools/Etapa0.SmokeTest/          # console que valida o ambiente
```

## 1. Pré-requisitos

- **Docker Desktop** rodando. No Windows, com backend **WSL 2**.
- **Memória para o Docker: 4 GB ou mais.** O SQL Server sozinho pede cerca de 2 GB e cai sem aviso claro se faltar. No Windows, ajuste em `%UserProfile%\.wslconfig` (`[wsl2]` → `memory=6GB`) e reinicie com `wsl --shutdown`.
- **.NET 8 SDK** (`dotnet --list-sdks`).
- Portas livres: **1433** (SQL), **5672** e **5300** (Service Bus), **5341** (Seq). Se você já tem SQL Server instalado na máquina, mude `MSSQL_PORT` no `.env`.
- Mac com Apple Silicon: ative "Use Rosetta for x86/amd64 emulation" no Docker Desktop, porque a imagem do SQL Server é amd64.

## 2. Subir e verificar

```powershell
cp .env.example .env
./scripts/check-env.ps1          # Linux/macOS: ./scripts/check-env.sh
```

O script sobe os containers, espera o `/health` do emulador, confere se os bancos foram criados e roda o smoke test. A saída esperada:

```text
[OK]     Emulador /health: HTTP 200
[OK]     SQL Server e bancos dos serviços: PosTrade_Alocacao, PosTrade_Custos, PosTrade_Ingestao, PosTrade_Liquidacao
[OK]     Limpeza de mensagens antigas: 0 removidas
[OK]     Fila: envio e recebimento: 1 mensagem enviada e confirmada (complete)
[OK]     Fila: detecção de duplicidade do broker: 2 envios com o mesmo MessageId, 1 entrega
[OK]     Fila: retry até a DLQ: 3 entregas, depois DLQ com motivo 'MaxDeliveryCountExceeded'
[OK]     Tópico: fan-out e ordem por sessão: auditoria recebeu 4 cópias; alocação recebeu MASTER-1 na ordem 1,2,3
[OK]     Tópico: filtro de correlação: vendas recebeu 1 (Venda), auditoria recebeu 2
[OK]     API de gestão: listar tópicos: 6 tópicos: ...
Ambiente pronto para a Etapa 1.
```

Cada verificação é um conceito que cai na entrevista. Leia o `Program.cs` com calma: ele mostra, com o SDK puro, o que o MassTransit vai fazer por você depois.

## 3. Ordem de inicialização

```text
mssql (healthcheck com sqlcmd) ──► db-init (cria os 4 bancos e termina)
                                └► servicebus (usa o mesmo SQL como backend)
seq (independente)
```

Um único SQL Server atende o emulador e os serviços para economizar memória. O emulador cria bancos próprios lá dentro; os bancos `PosTrade_*` são só do projeto. Os dados dos serviços ficam no volume `mssql-data` e sobrevivem a `docker compose down`. Para zerar tudo: `docker compose down -v`.

## 4. Connection strings

| Uso | Valor |
| --- | --- |
| App rodando na sua máquina → Service Bus | `Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;` |
| App rodando na sua máquina → gestão (Administration Client) | mesma string com `sb://localhost:5300` |
| App em container na rede `postrade` → Service Bus | mesma string com `sb://sb-emulator` |
| App na sua máquina → SQL | `Server=localhost,1433;Database=PosTrade_Alocacao;User Id=sa;Password=<senha do .env>;TrustServerCertificate=True` |
| App em container → SQL | `Server=mssql,1433;...` |
| Logs (Serilog → Seq) | `http://localhost:5341` |

A chave `SAS_KEY_VALUE` é literal: o emulador aceita esse valor fixo. Guarde as strings em user-secrets (`dotnet user-secrets set "ConnectionStrings:ServiceBus" "..."`), não no `appsettings.json`.

## 5. Topologia declarada (`deploy/servicebus/Config.json`)

| Tópico | Assinaturas | Para que serve |
| --- | --- | --- |
| `execucao-recebida` | `alocacao` (sessions), `auditoria` | entrada; detecção de duplicidade ligada (janela de 5 min) |
| `execucao-cancelada` | `alocacao` (sessions), `liquidacao` | cancelamentos na mesma sessão da conta |
| `execucao-alocada` | `custos`, `liquidacao`, `posicao` | fan-out para 3 consumidores |
| `custos-calculados` | `liquidacao` | entrada da saga |
| `divergencia-conciliacao` | `operacao` | tratamento operacional |
| `liquidacao-agendada` | `auditoria`, `vendas` (filtro `lado = Venda`) | exemplo de filtro de correlação |

Mais a fila `etapa0-smoke` (MaxDeliveryCount 3), usada só pelo smoke test.

Todas as assinaturas têm `MaxDeliveryCount = 5`, lock de 1 minuto e dead-letter na expiração. Para mudar a topologia, edite o arquivo e rode `docker compose restart servicebus`: o emulador **não lê mudanças com ele rodando**.

## 6. Limites do emulador que afetam o projeto

| Limite | Impacto | Como contornar |
| --- | --- | --- |
| Entidades e mensagens **não persistem** após restart do container | mensagens em trânsito somem | normal para estudo; o `Config.json` recria a topologia |
| TTL máximo de mensagem: **1 hora** | agendar liquidação para D+2 em tempo real não funciona | use o relógio comprimido da Etapa 6 (1 dia útil = 1 minuto) |
| Até **10 conexões** simultâneas e 50 entidades | muitos serviços e réplicas ao mesmo tempo podem esbarrar no limite | um `ServiceBusClient` por processo (Singleton); poucas réplicas locais |
| Sem portal, métricas ou alertas | experimento de alerta da Etapa 5 não roda aqui | faça esse experimento num namespace real |
| Sem partições, sem WebSockets, só AMQP TCP | nenhum para este projeto | — |

### Atenção: MassTransit e o emulador

O emulador expõe a gestão de entidades numa porta diferente (5300) da porta de mensagens (5672). O **MassTransit 8** não tem suporte a essa configuração. No repositório do MassTransit, o mantenedor afirma que o suporte ao emulador existe na **versão 9**, que tem licença comercial.

Isso não afeta a Etapa 0, que usa o SDK direto. Para as etapas com MassTransit, escolha um caminho:

1. **Namespace Standard real no Azure** com MassTransit 8, como previsto no documento do projeto (custo baixo; apague ao terminar).
2. **MassTransit 9 com o emulador**, depois de conferir se os termos da licença cobrem uso pessoal e de estudo.
3. **Começar as etapas 3 a 5 com RabbitMQ local** (MassTransit 8, gratuito) e voltar ao Service Bus depois. Isso antecipa parte da Etapa 9.

O emulador continua útil o projeto inteiro para os pontos em que você usa o SDK diretamente: a ferramenta de redrive da Etapa 5, testes de sessions e de DLQ.

## 7. Problemas comuns

| Sintoma | Causa provável | Solução |
| --- | --- | --- |
| `postrade-mssql` reinicia ou sai com código 1 | senha fraca ou pouca memória | senha com maiúscula, minúscula, número e símbolo; 4 GB+ para o Docker |
| `postrade-servicebus` sai logo após subir | SQL ainda não aceitava conexões | aumente `SQL_WAIT_INTERVAL` no `.env` e rode `docker compose up -d servicebus` |
| Erro de porta 1433 em uso | SQL Server local instalado | `MSSQL_PORT=14333` no `.env` |
| Smoke test falha em "sessão" com timeout | assinatura sem `RequiresSession` ou topologia antiga | confira o `Config.json` e reinicie o emulador |
| Falha de login no SQL depois de trocar a senha | o volume guarda a senha antiga | `docker compose down -v` e suba de novo |
| `FileNotFoundException` do `Config.json` | caminho do volume errado | rode os comandos na raiz do repositório |

Logs do emulador: `docker compose logs -f servicebus`.

## Checklist da Etapa 0

- [ ] `docker compose ps` com `mssql`, `servicebus` e `seq` em execução e `db-init` encerrado com código 0
- [ ] Smoke test todo `[OK]`
- [ ] Seq abrindo em http://localhost:5341
- [ ] Connection strings nos user-secrets
- [ ] Decisão tomada sobre MassTransit e emulador (seção 6)
- [ ] Commit: "etapa 0: ambiente local"

Fontes: [Emulador — teste local](https://learn.microsoft.com/en-us/azure/service-bus-messaging/test-locally-with-service-bus-emulator) · [Emulador — limites](https://learn.microsoft.com/en-us/azure/service-bus-messaging/overview-emulator) · [Instalador e Config.json de exemplo](https://github.com/Azure/azure-service-bus-emulator-installer) · [MassTransit — discussão sobre o emulador](https://github.com/MassTransit/MassTransit/discussions/5684)
