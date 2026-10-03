#!/usr/bin/env bash
# Sobe o ambiente da Etapa 0, espera tudo ficar pronto e roda o smoke test.
# Uso (na raiz do repositório):  ./scripts/check-env.sh
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ ! -f .env ]]; then
  cp .env.example .env
  echo "Criei o .env a partir do .env.example. Revise a senha se quiser."
fi

docker compose up -d

echo "Aguardando o emulador do Service Bus (até 3 min)..."
for _ in $(seq 1 36); do
  if curl -fsS -m 3 http://localhost:5300/health >/dev/null 2>&1; then PRONTO=1; break; fi
  sleep 5
done
if [[ -z "${PRONTO:-}" ]]; then
  docker compose logs --tail 40 servicebus
  echo "Emulador não respondeu em /health. Veja os logs acima." >&2
  exit 1
fi

EXIT=$(docker inspect postrade-db-init --format '{{.State.ExitCode}}')
if [[ "$EXIT" != "0" ]]; then
  docker compose logs db-init
  echo "db-init terminou com código $EXIT" >&2
  exit 1
fi

set -a; source <(grep -E '^(MSSQL_SA_PASSWORD|MSSQL_PORT)=' .env); set +a
dotnet run --project tools/Etapa0.SmokeTest
