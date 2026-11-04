# Challenge 2026 — DevOps & Cloud (Sprints 3 e 4)

**Time CCGL** · Turma **2TDSPW** · Região Azure: **chilecentral**

**Veti** é a API REST de uma clínica veterinária (Spring Boot / Java 21). O repositório publicado que junta o código e os scripts Azure CLI na `main` é [challenge-2026-java-spint1](https://github.com/Challenge-2025-Equipe-07/challenge-2026-java-spint1). Este repositório repete os mesmos scripts, o DDL, o diagrama e o Newman.

**Opção 2 — PaaS, sem container no deploy.** O JAR roda no Azure App Service e o banco é o Azure Database for PostgreSQL Flexible Server. ACR e ACI não fazem parte desta entrega. `Dockerfile` e `docker-compose.yml`, dentro da pasta da API, servem só para um PostgreSQL local de desenvolvimento.

A pipeline avaliada é a desse repositório, [`azure-pipelines.yml`](https://github.com/Challenge-2025-Equipe-07/challenge-2026-java-spint1/blob/main/azure-pipelines.yml). Ela está registrada no Azure DevOps como `veti-api`, dispara na `main`, roda `./mvnw test` e publica o JAR em `app-ccgl-rm564113`. O [`azure-pipelines.yml`](azure-pipelines.yml) da raiz deste repositório de scripts não é essa esteira.

---

## Integrantes

| RM | Nome | Turma |
|---|---|---|
| 564113 | Camilo Micheletto da Silva | 2TDSPW |
| 564968 | Carlos André Silva | 2TDSPW |
| 562700 | Guilherme Ribeiro da Costa | 2TDSPW |
| 566376 | Laura Lopes Cruz | 2TDSPW |

---

## 1. O que auditar, com a API já no ar

Não é preciso recriar a Azure para ver a entrega funcionando.

| O quê | Onde |
|---|---|
| API | https://app-ccgl-rm564113.azurewebsites.net/veti |
| Health (API + PostgreSQL + Google OAuth) | https://app-ccgl-rm564113.azurewebsites.net/health |
| Swagger | https://app-ccgl-rm564113.azurewebsites.net/veti/swagger-ui.html |
| Projeto Azure DevOps (Scrum) | https://dev.azure.com/RM566376/CCGL |
| Pipeline `veti-api` | https://dev.azure.com/RM566376/CCGL/_build?definitionId=1 |

A raiz do site (`/`) responde 404 de propósito: não há página HTML. O health check da plataforma é `GET /health`.

```bash
git clone https://github.com/Challenge-2025-Equipe-07/challenge-2026-java-spint1.git
cd challenge-2026-java-spint1
chmod +x azure_*.sh tests/run_newman.sh

curl -sS https://app-ccgl-rm564113.azurewebsites.net/health
./mvnw test
./tests/run_newman.sh
./azure_test_infra.sh
```

`./tests/run_newman.sh` exige Node.js (`npx`). Os casos batem na API publicada: `GET /tutores`, login JWT, criar tutor, alterar tutor e criar pet. Outro host: `BASE_URL=https://app-ccgl-rm564113.azurewebsites.net/veti ./tests/run_newman.sh`.

A coleção mais longa está em `api-tests/veti.postman_collection.json` no mesmo repositório, com health, bloqueio sem token e o CRUD de consulta.

---

## 2. O que a solução faz

Na nuvem a API persiste cadastros reais e expõe CRUD HTTP autenticado.

- **CRUD** de inclusão, alteração, exclusão e consulta em tabelas relacionadas. O fluxo de homologação usa `tb_tutor` e `tb_pet` (o pet aponta para o tutor).
- Persistência no PostgreSQL Flexible Server, com TLS.
- Autenticação JWT (`POST /veti/auth/login` devolve o token em texto).
- `GET /health` sem autenticação: processo, PostgreSQL e, com Google configurado, o provedor OAuth.
- Log JSON no stdout com `traceId`, `spanId` e `correlationId` (níveis INFO, WARN e ERROR).
- Tracing e métricas por OpenTelemetry na API e pelo agente Java do Application Insights no App Service.
- Testes unitários AAA em `challenge-2026-java-spint1` (`./mvnw test`) e Newman na pasta `tests/`.

Hibernate cria as tabelas em minúsculas (`tb_tutor`, `tb_pet`). `"TB_TUTOR"` entre aspas não existe. No App Service, `DDL_AUTO=update` aplica o mesmo modelo. O DDL comentado está em [`script_bd.sql`](script_bd.sql).

---

## 3. Benefícios para o negócio

A clínica deixa de depender do notebook de quem desenvolveu a API. Tutores, pets e a agenda ficam num banco gerenciado, com backup e TLS a cargo do PostgreSQL Flexible Server. O veterinário entra com JWT (ou Google, quando configurado) e o cadastro fica disponível por HTTPS. Senha do banco, segredo do JWT e a connection string do Application Insights não vão para o Git: o script de create grava App Settings, e a pipeline só regrava a variável que estiver preenchida no Azure DevOps. Health check, log com id de correlação e tracing mostram se a API, o banco ou o login Google caíram.

O plano de laboratório é App Service **B1** Linux e PostgreSQL Burstable `Standard_B1ms`.

---

## 4. Arquitetura

![Arquitetura Opção PaaS — DevOps, usuário, IDE, GitHub, Azure Pipelines, App Service, PostgreSQL, Key Vault e Application Insights](arquitetura-cicd.svg)

Personas no diagrama: DevOps Engineer e usuário final.

1. Push para o GitHub (`git push` na branch `main` do repositório da API)
2. Disparo do trigger de CI
3. Compilação e testes (`./mvnw test` e `./mvnw package`)
4. Publicação do artefato JAR
5. Disparo do CD, autenticado pela service connection ARM `azure-rm-challenge`
6. Deploy no App Service `app-ccgl-rm564113`, com health check em `/health`

Em runtime o usuário chama a API por HTTPS, a Web App grava no PostgreSQL por JDBC com TLS, lê os segredos pelos App Settings e envia telemetria ao Application Insights. O Key Vault guarda JDBC, usuário, senha, JWT e a connection string. Em runtime a Web App usa a cópia que está nos App Settings.

| Recurso | Nome | Função |
|---|---|---|
| Resource Group | `rg-challenge-devops` | Agrupa e apaga tudo de uma vez |
| PostgreSQL Flexible Server | `pg-ccgl-rm564113` | PaaS Burstable `Standard_B1ms` |
| Database | `db-challenge` | Banco da Veti |
| Key Vault | `kv-ccgl-rm564113` | Segredos do setup |
| App Service Plan | `plan-ccgl-rm564113` | Hospedagem B1 Linux |
| Web App | `app-ccgl-rm564113` | Runtime Java 21 + JAR |
| Log Analytics | `law-ccgl-rm564113` | Logs de HTTP, console e métricas. Se `chilecentral` recusar o workspace, o script cria em `eastus2` |
| Application Insights | `appi-ccgl-rm564113` | Tracing e métricas do agente Java |

Admin do Postgres: usuário `ccgl`. Host: `pg-ccgl-rm564113.postgres.database.azure.com`, porta `5432`.

---

## 5. Pré-requisitos

- Conta Azure com permissão na assinatura, e [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli) (`az login`)
- Java 21 (`/usr/libexec/java_home -v 21` no macOS, ou `JAVA_HOME` apontando para um JDK 21)
- `git`, `curl`, `python3`
- Node.js, só para o Newman
- Senha do admin Postgres, se for recriar a infra: `export PG_ADMIN_PASSWORD='...'`

Para só auditar a API publicada, bastam `curl`, Java 21 e Node.js. O `az login` entra em `./azure_test_infra.sh` e no `SELECT`.

---

## 6. How-to

### 6.1 Conferir a infra que já existe

```bash
./azure_test_infra.sh
```

Confere Web App `Running`, PostgreSQL `Ready`, Application Insights, o agente Java e `GET /health` com status `UP`.

Logs da app:

```bash
az webapp log tail -g rg-challenge-devops -n app-ccgl-rm564113
```

### 6.2 Recriar infra, build e deploy

```bash
export PG_ADMIN_PASSWORD='SuaSenhaForte!123'
./azure_create_infra.sh
```

O script faz login, registra os providers, e cria ou reaproveita Resource Group, PostgreSQL, `db-challenge`, firewall, Key Vault, plano B1, Web App, Log Analytics, Application Insights, diagnostic settings e App Settings (`DB_URL`, `DB_USER`, `DB_PASSWORD`, JWT, `APPLICATIONINSIGHTS_CONNECTION_STRING`, `ApplicationInsightsAgent_EXTENSION_VERSION=~3`).

Se `challenge-2026-java-spint1/` já for um clone, o script atualiza a `main`. Se a pasta ainda não existir, ele clona https://github.com/Challenge-2025-Equipe-07/challenge-2026-java-spint1. Em seguida roda `./mvnw clean package -DskipTests` e `az webapp deploy --type jar`. Os testes AAA ficam na pipeline (`./mvnw test`), não neste package. No fim, o health check da plataforma aponta para `GET /health`.

O Flexible Server pode levar vários minutos até `Ready`. O script espera esse estado antes de seguir. Rodar o create de novo reaproveita o que já existe.

### 6.3 CRUD na nuvem

`GET` de tutores é público. `POST`, `PUT` e `DELETE` exigem JWT.

```bash
./azure_test_crud.sh
```

O script cria e altera tutores, pets, veterinários e consultas, apaga um registro e termina com `SELECT` no Postgres. Esse `SELECT` sai desta máquina só se a porta 5432 do Flexible Server estiver liberada para o IP atual. Se estourar tempo, use o Beekeeper no passo seguinte: o CRUD HTTP já terá gravado.

### 6.4 SELECT no banco

```bash
az postgres flexible-server execute \
  --name pg-ccgl-rm564113 \
  --admin-user ccgl \
  --admin-password "$PG_ADMIN_PASSWORD" \
  --database-name db-challenge \
  --querytext 'SELECT * FROM tb_tutor LIMIT 10; SELECT * FROM tb_pet LIMIT 10;'
```

Beekeeper Studio, importando a URI `postgres://...` impressa no final do `azure_create_infra.sh` (a URI, não a URL JDBC). Em SSL, escolha **Trust the server**.

| Campo | Valor |
|---|---|
| Connection type | PostgreSQL |
| Host | `pg-ccgl-rm564113.postgres.database.azure.com` |
| Port | `5432` |
| User | `ccgl` |
| Default database | `db-challenge` |
| SSL | Enable SSL → **Trust the server** |

Consulta: `SELECT * FROM tb_tutor;` e `SELECT * FROM tb_pet;`.

### 6.5 Pipeline

Projeto: https://dev.azure.com/RM566376/CCGL  
Pipeline: `veti-api` (YAML em `challenge-2026-java-spint1/azure-pipelines.yml`).

- Trigger em push e pull request na `main`. O CD só roda na `main`, com o CI verde.
- CI: Java 21, `./mvnw test`, pacote e artefato `drop`.
- CD: service connection ARM `azure-rm-challenge`, App Settings e `az webapp deploy --type jar` em `app-ccgl-rm564113`.
- O job usa o pool self-hosted `Default` (agente `veti-agent`). Para uma execução nova, esse agente precisa estar online. A última execução verde e os logs ficam no histórico da pipeline para auditoria.

Variável vazia de banco, JWT ou Application Insights não apaga o App Setting que o create já gravou.

### 6.6 Limpeza

```bash
./azure_delete_infra.sh
```

Apaga o Resource Group (Web App, plano, PostgreSQL, Application Insights, Log Analytics) e faz purge do Key Vault. Sem o purge, o nome `kv-ccgl-rm564113` fica preso em soft-delete. A exclusão do grupo é assíncrona.

---

## 7. Scripts e código

| Arquivo | Função |
|---|---|
| `azure_create_infra.sh` | Cria a PaaS. Se o `mvnw` estiver na mesma pasta, compila esse repositório. Senão, clona a API, gera o JAR e faz o deploy |
| `azure_test_infra.sh` | Web App, PostgreSQL, Application Insights e `GET /health` com status `UP` |
| `azure_test_crud.sh` | CRUD HTTP e SELECT de conferência |
| `azure_delete_infra.sh` | Resource Group e purge do Key Vault |
| `azure-pipelines.yml` | Rascunho local. A pipeline do Azure DevOps é a do repositório da API |
| `tests/run_newman.sh` | Newman contra a API publicada |
| `script_bd.sql` | DDL PostgreSQL |
| `arquitetura-cicd.svg` | Diagrama da arquitetura e do CI/CD |

O código, os mesmos scripts e a pipeline `veti-api` estão na `main` de https://github.com/Challenge-2025-Equipe-07/challenge-2026-java-spint1.

```bash
git clone https://github.com/Challenge-2025-Equipe-07/challenge-2026-java-spint1.git
cd challenge-2026-java-spint1
./mvnw test
```
