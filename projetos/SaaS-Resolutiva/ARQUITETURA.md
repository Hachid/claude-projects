# SaaS Resolutiva — ARQUITETURA

**Última revisão**: 2026-05-22

## Visão de alto nível

```
WhatsApp (Meta Cloud API)
  │
  ├─ webhook POST /api/webhooks/whatsapp/
  │    ├─ HMAC-SHA256 validado (raw body)
  │    ├─ ChannelIntegrationService → resolve tenant_id por phone_number_id
  │    ├─ WhatsAppPayloadAdapter → IncomingMessageDTO
  │    └─ MessageIngestionService → Contact + Conversation + Message (universal)
  │
  ├─ Worker (BLPOP message_processing_queue)
  │    └─ MessageProcessor → IA (OpenAI) → outbound → WhatsAppService
  │
Browser (Next.js 15)
  └─ JWT + X-Tenant-ID → FastAPI Backend → Postgres (Supabase) + Redis (VPS)
```

## Módulos do Backend

### Core
- **`app/core/config.py`** — `Settings` (pydantic-settings): SECRET_KEY, CORS, META_GRAPH_API_VERSION, ALLOW_DEFAULT_TENANT_FALLBACK, etc.
- **`app/core/security.py`** — verify_password, hash, create_access_token, decode_access_token
- **`app/core/database.py`** — SessionLocal, Base, get_db
- **`app/core/logging_utils.py`** — `build_log_message(event, **ctx)` → log estruturado

### API Routes
- **`auth.py`** — `POST /auth/token` (login JSON→JWT), `GET /auth/me`
- **`users.py`** — 7 endpoints CRUD de usuários + ativar/desativar + roles/permissions
- **`password_reset.py`** — `POST /auth/forgot-password`, `POST /auth/reset-password`
- **`conversations.py`** — inbox, history, crm, handoff, messages, funnel-stage, crm-data, notes, funnel-stats
- **`tenants.py`** — CRUD tenants
- **`whatsapp_webhook.py`** — GET (challenge), POST (ingestão + status outbound)
- **`health.py`** — GET /health (API + DB + Redis)
- **`knowledge.py`**, **`contacts.py`**, **`operations.py`**

### Models (SQLAlchemy)
| Model | Tabela | Notas |
|---|---|---|
| `Tenant` | tenants | schema_name único |
| `User` | users | role (superadmin/admin/vendedor) |
| `Contact` | contacts | whatsapp_id único por tenant |
| `Conversation` | conversations | owner_type, ai_paused, lead_temperature |
| `Message` | messages | **universal**: channel, provider, direction, message_type, external_contact_id |
| `ChannelIntegration` | channel_integrations | omnichannel: phone_number_id → tenant_id |
| `LeadNote` | lead_notes | notas por conversa |
| `FunnelEvent` | funnel_events | histórico de estágios |
| `ConversationContextSnapshot` | conversation_context_snapshots | snapshot IA |
| `AIConfig` | ai_configs | prompts por tenant |
| `KnowledgeDocument/Chunk` | knowledge_* | RAG |

### Services
- **`channel_integration_service.py`** — resolve tenant_id por phone_number_id via ChannelIntegration
- **`message_ingestion_service.py`** — ingesta universal (Contact + Conversation + Message)
- **`channels/whatsapp_payload_adapter.py`** — Meta payload → IncomingMessageDTO
- **`whatsapp_service.py`** — envio outbound via Graph API (versão configurável via META_GRAPH_API_VERSION)
- **`whatsapp_ingestion.py`** — thin wrapper: adapter → ingestion service
- **`crm_read_service.py`** — leitura CRM com campos comerciais
- **`user_service.py`** — CRUD usuários com RBAC
- **`email_service.py`** — envio via Resend API

### Providers (omnichannel)
- **`providers/base.py`** — `BaseChannelProvider` (protocolo @runtime_checkable)
- **`providers/whatsapp_cloud.py`** — `WhatsAppCloudProvider` (adapter de WhatsAppService)

### Schemas universais
- **`schemas/channel_constants.py`** — CHANNEL_*, PROVIDER_*, MSG_TYPE_*, DIRECTION_*, SENDER_*
- **`schemas/incoming_message.py`** — `IncomingMessageDTO` (dataclass universal)

### Workers
- **`workers/message_worker.py`** — BLPOP em `message_processing_queue`; processa por `message_id`
- **`workers/outbound_retry_worker.py`** — retry de mensagens outbound com falha
- **`processors/message_processor.py`** — orquestra IA → outbound; cria mensagem AI com campos universais

## Fluxo de mensagem WhatsApp (inbound completo)

```
1. Meta POST → /api/webhooks/whatsapp/
2. HMAC-SHA256 validado (raw body)
3. ChannelIntegrationService.resolve_tenant_id_for_whatsapp(phone_number_id)
   ├─ Se ChannelIntegration ativa → usa integration.tenant_id
   └─ Fallback (ALLOW_DEFAULT_TENANT_FALLBACK=true) → DEFAULT_TENANT_ID
4. WhatsAppPayloadAdapter.extract_messages(payload, tenant_id) → [IncomingMessageDTO]
5. MessageIngestionService.ingest(dto)
   ├─ Deduplicação por (tenant_id, external_message_id)
   ├─ get_or_create_contact(whatsapp_id=dto.external_contact_id)
   ├─ get_or_create_open_conversation(contact_id)
   └─ Message(channel, provider, direction=inbound, message_type, status=PENDING)
6. Message.status = QUEUED → enqueue_message_processing(message_id)
7. Worker BLPOP → MessageProcessor.process(message_id)
   ├─ Carrega IA config, contexto, histórico
   ├─ Executa OpenAI
   ├─ _create_ai_message(channel/provider herdados, direction=outbound)
   └─ WhatsAppService.send_text_message(to, text)
```

## Fluxo de autenticação

```
1. /login → POST /auth/token → JWT (7 dias)
2. saveToken(localStorage) + apiClient.setAccessToken(token)
3. apiClient.setTenantId(tenant.id) via GET /tenants/
4. router.replace('/') → AuthGate permite → dashboard carrega
5. Reload: loadToken() → GET /auth/me → restaura sessão
6. Token inválido: clearToken() → redirect /login (AUTH_REQUIRED=true)
```

## RBAC

| Role | Pode criar | Pode ver | Pode editar |
|---|---|---|---|
| superadmin | admin, vendedor | todos os tenants | tudo |
| admin | vendedor (não superadmin) | próprio tenant | usuários do tenant |
| vendedor | — | próprias conversas | — |

## Infra de produção (actaresolve.com.br)

- **VPS Hostinger**: 2.24.96.166 | usuário: deploy
- **Nginx**: proxy reverso `/api/*` → FastAPI:8000 | `/*` → Next.js:3000
- **HTTPS**: certificado SSL ativo
- **Banco**: Supabase PostgreSQL (Alembic migrations em head)
- **Redis**: rodando na VPS (fila de mensagens)
- **Deploy**: via SSH + `deploy/hostinger/deploy.sh`

## Migrations Alembic (em ordem)

| Revision | Descrição |
|---|---|
| 9668532fc93e | create_base_schema |
| 1a2b3c4d5e6f | add_conversation_ownership_and_crm_fields |
| ea12b7c4f901 | add_sales_state_fields_to_conversations |
| c41e9d2a7f10 | add_followup_schedule_and_decision_log |
| f18a4b3c9d20 | add_funnel_events_table |
| 6b7e9f2d1a10 | add_conversation_context_snapshots |
| b9b38a5135f9 | add_knowledge_base_tables |
| d32fc8e95834 | add_outbound_status_and_attempts |
| e2f3a4b5c6d7 | add_lead_notes_and_crm_fields |
| f3a4b5c6d7e8 | add_user_role |
| a1b2c3d4e5f6 | add_channel_integrations |
| b2c3d4e5f6a7 | add_universal_message_fields |

## Decisões arquiteturais (ADRs)

- **ADR-001**: JWT em JSON (não form-data OAuth2)
- **ADR-002**: `bcrypt` direto sem `passlib` (incompatibilidade bcrypt ≥4.0)
- **ADR-003**: `SessionProvider` sem NextAuth
- **ADR-004**: `localStorage` para token (dev/MVP); cookie httpOnly → produção
- **ADR-005**: Mock isolado em `mock-data.ts` (nunca inline na página)
- **ADR-006**: Strings em vez de SQLAlchemy Enum para campos de canal (evita DDL de ENUM no PostgreSQL)
- **ADR-007**: `ChannelIntegration` como tabela de roteamento (phone_number_id → tenant_id), com fallback `DEFAULT_TENANT_ID` enquanto multi-tenant real não está ativo

## Tech debt

### Backend
- [ ] `ALLOW_DEFAULT_TENANT_FALLBACK=false` quando ChannelIntegration estiver cadastrada
- [ ] Unique constraint de Message: avaliar incluir `channel` quando Instagram for integrado
- [ ] Redis para tokens de reset de senha (hoje em memória — TTL 15min)
- [ ] Janela de validade de webhook (timestamp ±5 min anti-replay)
- [ ] `GET /ai-config` + `PATCH /ai-config`
- [ ] `PATCH /settings/attendance` + `PATCH /settings/notifications`
- [ ] `GET /whatsapp/status`
- [ ] `GET /auth/me` retornar `schema_name`
- [ ] `POST /conversations/{id}/close`

### Frontend
- [ ] Polling ou WebSocket para conversas em tempo real
- [ ] Badge de não-lidas no inbox
- [ ] Cookie httpOnly (substituir localStorage)
- [ ] Refresh token + expiração automática
- [ ] Sidebar: ocultar menus por role
- [ ] Tela `/relatorios` com gráficos reais
