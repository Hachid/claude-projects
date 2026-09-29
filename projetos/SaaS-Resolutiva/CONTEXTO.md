# SaaS Resolutiva — CONTEXTO

**Última revisão**: 2026-05-22

## Stack

### Backend (`backend/`)
- **Linguagem**: Python 3.x
- **Framework**: FastAPI
- **ORM**: SQLAlchemy + Alembic (migrations)
- **DB**: Supabase PostgreSQL (produção) | SQLite (testes)
- **Auth**: JWT via `python-jose[cryptography]` + `bcrypt` (direto, sem passlib)
- **WhatsApp**: Meta Cloud API — webhook inbound (HMAC-SHA256) + outbound (Graph API versão configurável)
- **IA/LLM**: OpenAI (GPT-4.1-mini por padrão)
- **Worker**: `message_worker.py` (BLPOP Redis) + `outbound_retry_worker.py`
- **E-mail**: Resend API (convite e recuperação de senha)
- **Testes**: pytest — 101 testes passando

### Frontend (`frontend/`)
- **Framework**: Next.js 15+ (App Router)
- **Linguagem**: TypeScript
- **Estilo**: Tailwind CSS v4 + tokens oklch Resolutiva (paleta #163B7A / #007BD4 / #35C7B9)
- **State**: React Context (`SessionProvider` em `features/session/`)
- **HTTP**: `ApiClient` em `lib/api/client.ts` — injeta Bearer + X-Tenant-ID automaticamente
- **Ícones**: lucide-react
- **Sem shadcn/ui** — HTML nativo + Tailwind

## Estrutura de pastas (relevante)

```
saas_automacao_base/
├── backend/
│   ├── app/
│   │   ├── api/routes/          ← auth, users, conversations, tenants, whatsapp_webhook, health, knowledge, password_reset
│   │   ├── core/                ← config.py, security.py, database.py, logging_utils.py
│   │   ├── models/              ← SQLAlchemy: Message (universal), ChannelIntegration, User (role), Contact, Conversation...
│   │   ├── schemas/             ← incoming_message.py (DTO), channel_constants.py, auth.py, user_management.py...
│   │   ├── services/
│   │   │   ├── channels/        ← whatsapp_payload_adapter.py (Meta payload → IncomingMessageDTO)
│   │   │   ├── channel_integration_service.py  ← resolve tenant por phone_number_id
│   │   │   ├── message_ingestion_service.py    ← ingesta universal (Contact + Conversation + Message)
│   │   │   ├── whatsapp_ingestion.py           ← thin wrapper (adapter → ingestion service)
│   │   │   ├── whatsapp_service.py             ← envio outbound (versão Graph API configurável)
│   │   │   ├── user_service.py, email_service.py, crm_read_service.py...
│   │   ├── providers/           ← base.py (protocolo), whatsapp_cloud.py (adapter)
│   │   ├── processors/          ← message_processor.py (IA → outbound)
│   │   └── workers/             ← message_worker.py, outbound_retry_worker.py
│   ├── alembic/versions/        ← 12 migrations em sequência até b2c3d4e5f6a7
│   └── tests/                   ← 101 testes
├── frontend/
│   ├── app/
│   │   ├── (auth)/              ← login, esqueci-senha, redefinir-senha
│   │   └── (dashboard)/         ← protegido por AuthGate: /, conversas, crm, equipe, ia, relatorios, configuracoes
│   ├── features/
│   │   ├── session/             ← SessionProvider, useSession, AuthGate, auth-service, use-permissions
│   │   ├── conversations/       ← inbox, chat 3 colunas, handoff, cockpit Gemini
│   │   ├── crm/                 ← kanban + lista + drawer premium + notas + funnel-stats
│   │   ├── equipe/              ← KPIs, grid IA, tabela humanos, drawer, ranking
│   │   ├── ai/                  ← mock-data.ts (endpoints não existem ainda)
│   │   └── settings/            ← users-permissions-section (RBAC real), resto mock
│   ├── components/layout/       ← sidebar dark grafite, header
│   └── lib/api/client.ts        ← ApiClient singleton
├── docs/
│   ├── deploy/                  ← producao-controlada, fase-12-2, fase-12-3-whatsapp-real
│   ├── integrations/            ← whatsapp_cloud_api.md (variáveis, roteamento, fallback)
│   └── architecture/            ← messages_universal.md (omnichannel, DTO, adapter)
└── deploy/hostinger/            ← nginx.conf, deploy.sh, docker-compose.prod.yml
```

## Ambientes

| Env | URL | Como subir |
|---|---|---|
| Backend local | `http://localhost:8000` | `cd backend && uvicorn app.main:app --reload` |
| Frontend local | `http://localhost:3000` | `cd frontend && npm run dev` |
| Produção | `https://actaresolve.com.br` | SSH + `deploy/hostinger/deploy.sh` |
| API docs | `http://localhost:8000/docs` | Swagger automático |

## Endpoints implementados no backend

### Auth
| Método | Path | Descrição |
|---|---|---|
| POST | `/auth/token` | Login JSON → JWT Bearer |
| GET | `/auth/me` | Usuário autenticado |
| POST | `/auth/forgot-password` | Solicita reset (sempre 200) |
| POST | `/auth/reset-password` | Define nova senha |

### Usuários (RBAC)
| Método | Path | Descrição |
|---|---|---|
| GET | `/users/` | Lista (scope por role) |
| POST | `/users/` | Criação com regras RBAC |
| GET | `/users/{id}` | Detalhe |
| PATCH | `/users/{id}` | Edição |
| PATCH | `/users/{id}/activate` | Ativa |
| PATCH | `/users/{id}/deactivate` | Desativa |
| GET | `/users/meta/roles` | Lista roles |
| GET | `/users/meta/permissions` | Matriz de permissões |

### Conversas / CRM
| Método | Path | Descrição |
|---|---|---|
| GET | `/conversations/inbox` | Inbox |
| GET | `/conversations/{id}/history` | Histórico |
| GET | `/conversations/{id}/crm` | Dados CRM |
| POST | `/conversations/{id}/handoff/in-progress` | Assume atendimento |
| POST | `/conversations/{id}/handoff/resume-ai` | Devolve para IA |
| POST | `/conversations/{id}/messages` | Envia mensagem humana |
| GET | `/conversations/crm` | Lista leads |
| PATCH | `/conversations/{id}/funnel-stage` | Muda estágio |
| PATCH | `/conversations/{id}/crm-data` | Valor, origem, produto |
| GET | `/conversations/{id}/notes` | Notas |
| POST | `/conversations/{id}/notes` | Cria nota |
| GET | `/conversations/crm/funnel-stats` | Stats do funil |

### Outros
| Método | Path | Descrição |
|---|---|---|
| GET | `/tenants/` | Lista tenants |
| GET | `/health` | API + DB + Redis status |
| GET | `/webhooks/whatsapp/` | Challenge da Meta |
| POST | `/webhooks/whatsapp/` | Mensagens inbound da Meta |

## Variáveis de ambiente (backend)

| Variável | Descrição |
|---|---|
| `DATABASE_URL` | PostgreSQL (Supabase em prod) |
| `REDIS_URL` | Redis URL |
| `SECRET_KEY` | JWT signing key (obrigatório em produção) |
| `OPENAI_API_KEY` | Chave OpenAI |
| `WHATSAPP_VERIFY_TOKEN` | Challenge Meta webhook |
| `WHATSAPP_ACCESS_TOKEN` | Bearer token Meta outbound |
| `WHATSAPP_PHONE_NUMBER_ID` | ID do número Meta |
| `META_APP_SECRET` | Segredo para HMAC (obrigatório em produção) |
| `META_GRAPH_API_VERSION` | Versão da API Meta (padrão: v18.0) |
| `DEFAULT_TENANT_ID` | Fallback de tenant no MVP (padrão: 1) |
| `ALLOW_DEFAULT_TENANT_FALLBACK` | Permite fallback se sem ChannelIntegration (padrão: true) |
| `CORS_ALLOWED_ORIGINS` | Origens CORS separadas por vírgula |
| `APP_ENV` | `development` ou `production` |
| `RESEND_API_KEY` | Chave Resend para e-mails |

## Convenções do projeto

- **Sem mocks inline em páginas** — mocks ficam em `features/<modulo>/mock-data.ts`
- **Sem shadcn/ui** — HTML nativo + Tailwind/tokens Resolutiva
- **Sem `X-Tenant-ID` hardcoded** — sempre via `apiClient.setTenantId()` no SessionProvider
- **`bcrypt` direto** — não usar `passlib`
- **Login JSON** — não form-data OAuth2
- **Strings em vez de Enum DB** para campos de canal (channel, provider, direction, message_type)
- **Sem IA dentro do webhook** — sempre via worker/fila
- **Persistir mensagem antes de enfileirar**

## Glossário do domínio
- **Tenant**: empresa cliente — `tenant_id` (int) + `schema_name`
- **ChannelIntegration**: mapeamento `phone_number_id → tenant_id + credenciais` por canal
- **IncomingMessageDTO**: DTO universal que qualquer canal (WhatsApp, Instagram, etc.) popula antes de ingestar
- **Handoff**: transferência IA→humano (`in-progress`) ou humano→IA (`resume-ai`)
- **Funil**: estágio do lead no kanban CRM (9 colunas)
- **SessionProvider**: carrega tenant via `GET /tenants/` + token via localStorage → alimenta ApiClient
- **AuthGate**: protege dashboard; redireciona para `/login` se `!isAuthenticated`
- **DEV_USER / DEV_TENANT**: fallback quando sem token e sem `AUTH_REQUIRED`

## Pessoas / Stakeholders
- **Hachid** — owner, desenvolvedor
