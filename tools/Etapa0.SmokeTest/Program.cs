// Verificação da Etapa 0: confirma que SQL Server e emulador do Service Bus estão prontos
// e exercita, com o SDK puro, os conceitos que o projeto usa depois.
//
//   dotnet run --project tools/Etapa0.SmokeTest
//
// Variáveis opcionais: MSSQL_SA_PASSWORD, MSSQL_PORT (mesmas do .env).

using Azure.Messaging.ServiceBus;
using Azure.Messaging.ServiceBus.Administration;
using Microsoft.Data.SqlClient;

const string ServiceBus =
    "Endpoint=sb://localhost;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;";
// Operações de gestão (ServiceBusAdministrationClient) usam a porta HTTP do emulador.
const string ServiceBusAdmin =
    "Endpoint=sb://localhost:5300;SharedAccessKeyName=RootManageSharedAccessKey;SharedAccessKey=SAS_KEY_VALUE;UseDevelopmentEmulator=true;";

var senhaSql = Environment.GetEnvironmentVariable("MSSQL_SA_PASSWORD") ?? "PosTrade#Lab2026";
var portaSql = Environment.GetEnvironmentVariable("MSSQL_PORT") ?? "1433";
var execucao = Guid.NewGuid().ToString("N")[..8];   // identifica as mensagens desta rodada
var falhas = 0;

Console.OutputEncoding = System.Text.Encoding.UTF8;   // acentos corretos no console do Windows
Console.WriteLine($"Etapa 0 - verificação do ambiente (rodada {execucao})\n");

async Task Passo(string nome, Func<Task<string>> acao, bool opcional = false)
{
    try
    {
        Console.WriteLine($"[OK]     {nome}: {await acao()}");
    }
    catch (Exception ex)
    {
        if (opcional) { Console.WriteLine($"[AVISO]  {nome}: {ex.Message}"); return; }
        falhas++;
        Console.WriteLine($"[FALHOU] {nome}: {ex.Message}");
    }
}

// 1. Emulador respondendo
await Passo("Emulador /health", async () =>
{
    using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
    var resposta = await http.GetAsync("http://localhost:5300/health");
    resposta.EnsureSuccessStatusCode();
    return $"HTTP {(int)resposta.StatusCode}";
});

// 2. SQL Server com os 4 bancos criados pelo db-init
await Passo("SQL Server e bancos dos serviços", async () =>
{
    var cs = $"Server=localhost,{portaSql};User Id=sa;Password={senhaSql};Encrypt=True;TrustServerCertificate=True;Connect Timeout=5";
    await using var conexao = new SqlConnection(cs);
    await conexao.OpenAsync();
    await using var comando = new SqlCommand(
        "SELECT name FROM sys.databases WHERE name LIKE 'PosTrade[_]%' ORDER BY name", conexao);
    var nomes = new List<string>();
    await using (var leitor = await comando.ExecuteReaderAsync())
        while (await leitor.ReadAsync()) nomes.Add(leitor.GetString(0));
    if (nomes.Count != 4)
        throw new InvalidOperationException($"esperava 4 bancos, encontrei {nomes.Count}: {string.Join(", ", nomes)}");
    return string.Join(", ", nomes);
});

await using var client = new ServiceBusClient(ServiceBus);

// Limpa sobras de rodadas anteriores
await Passo("Limpeza de mensagens antigas", async () =>
{
    var removidas = 0;
    foreach (var (topico, assinatura) in new[]
             {
                 ("execucao-recebida", "auditoria"), ("liquidacao-agendada", "auditoria"),
                 ("liquidacao-agendada", "vendas")
             })
    {
        await using var r = client.CreateReceiver(topico, assinatura);
        removidas += (await Receber(r, 0, TimeSpan.FromSeconds(4))).Count;
    }
    await using (var fila = client.CreateReceiver("etapa0-smoke"))
        removidas += (await Receber(fila, 0, TimeSpan.FromSeconds(4))).Count;
    removidas += await LimparSessoes("execucao-recebida", "alocacao");
    return $"{removidas} removidas";
});

// 3. Fila simples: ida e volta
await Passo("Fila: envio e recebimento", async () =>
{
    await using var sender = client.CreateSender("etapa0-smoke");
    await using var receiver = client.CreateReceiver("etapa0-smoke");
    await sender.SendMessageAsync(new ServiceBusMessage($"ola-{execucao}") { MessageId = Guid.NewGuid().ToString() });
    var recebidas = await Receber(receiver, 1, TimeSpan.FromSeconds(15));
    if (recebidas.Count != 1 || recebidas[0].Body.ToString() != $"ola-{execucao}")
        throw new InvalidOperationException($"recebidas {recebidas.Count} mensagens");
    return "1 mensagem enviada e confirmada (complete)";
});

// 4. Duplicate detection: mesmo MessageId duas vezes dentro da janela de 5 min
await Passo("Fila: detecção de duplicidade do broker", async () =>
{
    await using var sender = client.CreateSender("etapa0-smoke");
    await using var receiver = client.CreateReceiver("etapa0-smoke");
    var id = $"exec-{execucao}";
    await sender.SendMessageAsync(new ServiceBusMessage("primeira") { MessageId = id });
    await sender.SendMessageAsync(new ServiceBusMessage("reenvio") { MessageId = id });
    var recebidas = await Receber(receiver, 1, TimeSpan.FromSeconds(15));
    if (recebidas.Count != 1)
        throw new InvalidOperationException($"esperava 1, recebi {recebidas.Count}");
    return "2 envios com o mesmo MessageId, 1 entrega";
});

// 5. Poison message: abandona até estourar MaxDeliveryCount (3) e lê da DLQ
await Passo("Fila: retry até a DLQ", async () =>
{
    await using var sender = client.CreateSender("etapa0-smoke");
    await using var receiver = client.CreateReceiver("etapa0-smoke");
    var id = $"poison-{execucao}";
    await sender.SendMessageAsync(new ServiceBusMessage("{\"quantidade\": -100}") { MessageId = id });

    var entregas = 0;
    var limite = DateTime.UtcNow.AddSeconds(30);
    while (DateTime.UtcNow < limite)
    {
        var msg = await receiver.ReceiveMessageAsync(TimeSpan.FromSeconds(3));
        if (msg is null) break;                    // não voltou: foi para a DLQ
        entregas++;
        await receiver.AbandonMessageAsync(msg);   // simula falha no processamento
    }

    await using var dlq = client.CreateReceiver("etapa0-smoke",
        new ServiceBusReceiverOptions { SubQueue = SubQueue.DeadLetter });
    var mortas = await Receber(dlq, 1, TimeSpan.FromSeconds(15));
    var morta = mortas.FirstOrDefault(m => m.MessageId == id)
        ?? throw new InvalidOperationException($"mensagem não encontrada na DLQ após {entregas} entregas");
    return $"{entregas} entregas, depois DLQ com motivo '{morta.DeadLetterReason}'";
});

// 6. Tópico com fan-out e sessions: ordem garantida por conta
await Passo("Tópico: fan-out e ordem por sessão", async () =>
{
    await using var sender = client.CreateSender("execucao-recebida");
    var envios = new[] { ("MASTER-1", 1), ("MASTER-2", 1), ("MASTER-1", 2), ("MASTER-1", 3) };
    foreach (var (conta, seq) in envios)
    {
        var msg = new ServiceBusMessage($"{{\"conta\":\"{conta}\",\"seq\":{seq}}}")
        {
            MessageId = $"{execucao}-{conta}-{seq}",
            SessionId = conta,                      // equivalente ao MessageGroupId do SQS FIFO
            ContentType = "application/json"
        };
        msg.ApplicationProperties["rodada"] = execucao;
        msg.ApplicationProperties["seq"] = seq;
        await sender.SendMessageAsync(msg);
    }

    await using var auditoria = client.CreateReceiver("execucao-recebida", "auditoria");
    var copiasAuditoria = (await Receber(auditoria, 4, TimeSpan.FromSeconds(15)))
        .Count(m => DaRodada(m));
    if (copiasAuditoria != 4)
        throw new InvalidOperationException($"auditoria recebeu {copiasAuditoria} de 4");

    var porConta = new Dictionary<string, List<int>>();
    for (var i = 0; i < 2; i++)
    {
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(15));
        await using var sessao = await client.AcceptNextSessionAsync("execucao-recebida", "alocacao",
            cancellationToken: cts.Token);
        var mensagens = await Receber(sessao, 1, TimeSpan.FromSeconds(10));
        porConta[sessao.SessionId] = mensagens
            .Where(m => DaRodada(m))
            .Select(m => Convert.ToInt32(m.ApplicationProperties["seq"]))
            .ToList();
    }

    if (!porConta.TryGetValue("MASTER-1", out var m1) || !m1.SequenceEqual(new[] { 1, 2, 3 }))
        throw new InvalidOperationException($"MASTER-1 fora de ordem: {string.Join(",", m1 ?? new())}");
    return "auditoria recebeu 4 cópias; alocação recebeu MASTER-1 na ordem 1,2,3";
});

// 7. Filtro de correlação: assinatura 'vendas' só recebe lado = Venda
await Passo("Tópico: filtro de correlação", async () =>
{
    await using var sender = client.CreateSender("liquidacao-agendada");
    foreach (var lado in new[] { "Compra", "Venda" })
    {
        var msg = new ServiceBusMessage($"{{\"lado\":\"{lado}\"}}") { MessageId = $"{execucao}-{lado}" };
        msg.ApplicationProperties["lado"] = lado;
        msg.ApplicationProperties["rodada"] = execucao;
        await sender.SendMessageAsync(msg);
    }

    await using var vendas = client.CreateReceiver("liquidacao-agendada", "vendas");
    await using var auditoria = client.CreateReceiver("liquidacao-agendada", "auditoria");
    var deVendas = (await Receber(vendas, 1, TimeSpan.FromSeconds(15)))
        .Where(m => DaRodada(m)).ToList();
    var deAuditoria = (await Receber(auditoria, 2, TimeSpan.FromSeconds(15)))
        .Count(m => DaRodada(m));

    if (deVendas.Count != 1 || !Equals(deVendas[0].ApplicationProperties["lado"], "Venda") || deAuditoria != 2)
        throw new InvalidOperationException($"vendas={deVendas.Count}, auditoria={deAuditoria}");
    return "vendas recebeu 1 (Venda), auditoria recebeu 2";
});

// 8. API de gestão (porta 5300). Opcional: só confirma que o client de administração conecta.
await Passo("API de gestão: listar tópicos", async () =>
{
    var admin = new ServiceBusAdministrationClient(ServiceBusAdmin);
    var nomes = new List<string>();
    await foreach (var topico in admin.GetTopicsAsync()) nomes.Add(topico.Name);
    return $"{nomes.Count} tópicos: {string.Join(", ", nomes)}";
}, opcional: true);

Console.WriteLine(falhas == 0
    ? "\nAmbiente pronto para a Etapa 1."
    : $"\n{falhas} verificação(ões) falharam. Veja a seção de problemas comuns no README-ETAPA0.md.");
return falhas == 0 ? 0 : 1;

// Recebe até não chegar mais nada, confirmando cada mensagem.
// Para depois de ter ao menos 'esperado' mensagens e um lote vazio, ou no timeout.
static async Task<List<ServiceBusReceivedMessage>> Receber(ServiceBusReceiver receiver, int esperado, TimeSpan timeout)
{
    var todas = new List<ServiceBusReceivedMessage>();
    var limite = DateTime.UtcNow + timeout;
    while (DateTime.UtcNow < limite)
    {
        var lote = await receiver.ReceiveMessagesAsync(maxMessages: 20, maxWaitTime: TimeSpan.FromSeconds(2));
        foreach (var msg in lote)
        {
            todas.Add(msg);
            await receiver.CompleteMessageAsync(msg);
        }
        if (lote.Count == 0 && todas.Count >= esperado) break;
    }
    return todas;
}

bool DaRodada(ServiceBusReceivedMessage m) =>
    m.ApplicationProperties.TryGetValue("rodada", out var valor) && Equals(valor, execucao);

async Task<int> LimparSessoes(string topico, string assinatura)
{
    var removidas = 0;
    while (true)
    {
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(4));
            await using var sessao = await client.AcceptNextSessionAsync(topico, assinatura, cancellationToken: cts.Token);
            removidas += (await Receber(sessao, 0, TimeSpan.FromSeconds(4))).Count;
        }
        catch (Exception ex) when (ex is OperationCanceledException
                                       or ServiceBusException { Reason: ServiceBusFailureReason.ServiceTimeout })
        {
            return removidas;   // nenhuma sessão pendente
        }
    }
}
