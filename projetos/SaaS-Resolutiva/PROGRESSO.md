# SaaS Resolutiva — PROGRESSO

> Log mais recente no topo. Cada sessão = uma entrada datada.

---

## 2026-05-22 — Fase 21 — Mensagem Universal (Prompt Whats 2)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Objetivo**: transformar o modelo Message de WhatsApp-only para omnichannel universal, sem quebrar nenhum fluxo existente.

**`backend/app/schemas/channel_constants.py`** — NOVO: constantes de canal:
- `CHANNEL_*`: whatsapp, instagram, tiktok, website, email, unknown
- `PROVIDER_*`: meta_cloud_api, meta_instagram_api, tiktok_business_api, actaresolve_widget, unknown
- `MSG_TYPE_*`: text, image, audio, video, document, sticker, location, interactive, template, unsupported
- `DIRECTION_*`: inbound, outbound
- `SENDER_*`: contact, ai, human, system
- Strings em vez de SQLAlchemy Enum para evitar DDL de ENUM no PostgreSQL

**`backend/app/models/message.py`** — 6 novos campos universais adicionados:
- `channel` String(50) nullable, server_default='whatsapp'
- `provider` String(50) nullable, server_default='meta_cloud_api'
- `external_contact_id` String(100) nullable (wa_id no WhatsApp)
- `external_conversation_id` String(255) nullable
- `message_type` String(50) nullable, server_default='text'
- `direction` String(20) nullable (inbound/outbound)
- Campos legados mantidos: `sender`, `external_message_id`, `raw_payload`
- Constraint `unique(tenant_id, external_message_id)` inalterada

**`backend/app/schemas/incoming_message.py`** — NOVO DTO universal:
- `IncomingMessageDTO` dataclass com todos os campos de canal + conteúdo + contexto
- Qualquer canal futuro converte seu payload para este DTO antes de ingestar

**`backend/app/services/channels/__init__.py`** — NOVO pacote

**`backend/app/services/channels/whatsapp_payload_adapter.py`** — NOVO adapter:
- `WhatsAppPayloadAdapter.extract_messages(payload, tenant_id, correlation_id)` → `list[IncomingMessageDTO]`
- Extrai: wa_id, wamid, profile.name, message.type, text.body
- Mapeia tipos Meta para constantes (text/image/audio/video/document/sticker/location/interactive/template/unsupported)
- Tipos não suportados: `text_content = "[mensagem_tipo]"` (compatível com anterior)
- Nunca perde `raw_payload`
- Retorna lista vazia se não houver mensagens inbound

**`backend/app/services/message_ingestion_service.py`** — NOVO serviço universal:
- `get_or_create_contact(db, tenant_id, whatsapp_id, name, phone_number)` — movido de `whatsapp_ingestion.py`
- `get_or_create_open_conversation(db, tenant_id, contact_id)` — movido de `whatsapp_ingestion.py`
- `MessageIngestionService.ingest(dto: IncomingMessageDTO)` — persiste Contact + Conversation + Message universal
- Deduplicação por `(tenant_id, external_message_id)` preservada
- Mensagem criada com `status=PENDING` e todos os campos universais preenchidos

**`backend/app/services/whatsapp_ingestion.py`** — reescrito como thin wrapper:
- `ingest_whatsapp_payload` agora: adapter → DTO → `MessageIngestionService.ingest`
- Assinatura e retorno idênticos (backward compat total com webhook e testes)
- Re-exporta `get_or_create_contact` e `get_or_create_open_conversation` para compat

**`backend/app/processors/message_processor.py`** — outbound com campos universais:
- `_create_ai_message` aceita `inbound_message` opcional para herdar channel/provider
- Mensagens outbound recebem: `channel`, `provider`, `direction="outbound"`, `message_type="text"`
- Fallback para "whatsapp" / "meta_cloud_api" quando inbound não tem campo preenchido

**`backend/alembic/versions/b2c3d4e5f6a7_add_universal_message_fields.py`** — NOVA migration:
- Adiciona os 6 novos campos com colunas nullable e server_defaults seguros
- Cria índices: `ix_messages_channel`, `ix_messages_direction`, `ix_messages_external_contact_id`
- Não altera constraint `unique(tenant_id, external_message_id)`
- Chained em `a1b2c3d4e5f6`

**`docs/architecture/messages_universal.md`** — NOVO:
- Por que a mensagem virou universal
- Campos universais e seus valores
- Fluxo WhatsApp → IncomingMessageDTO → MessageIngestionService
- Como futuros canais devem se integrar
- Garantia de compatibilidade com worker por message_id
- Débito técnico da constraint (Fase 3+)

### Validação

```
pytest -q → 101/101 ✅ (nenhum teste quebrado)
WhatsAppPayloadAdapter.extract_messages (text) → channel=whatsapp, message_type=text ✅
WhatsAppPayloadAdapter.extract_messages (image) → message_type=image, text_content=[mensagem_image] ✅
Imports todos OK: constants, DTO, adapter, ingestion service ✅
```

### Decisões técnicas

- **Strings em vez de Enum**: evita DDL ALTER TYPE no PostgreSQL que requer lock de tabela
- **`sender` não renomeado**: o campo legado cobre `sender_type`; sem duplicação
- **Constraint não alterada**: wamids são globalmente únicos; colisão multi-canal é Fase 3+
- **`ingest_whatsapp_payload` preservado**: webhook e testes não mudaram de assinatura
- **`get_or_create_*` re-exportados**: qualquer import externo continua funcionando

---

## 2026-05-22 — Fase 20 — Fundação Omnichannel (Prompt Whats 1)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Objetivo**: criar base omnichannel sem quebrar WhatsApp atual. Nenhum fluxo existente foi removido ou alterado de comportamento.

**`backend/app/models/channel_integration.py`** — NOVO modelo:
- Tabela `channel_integrations` com campos completos: `id`, `tenant_id`, `channel_type`, `provider`, `display_name`, `external_business_id`, `external_phone_number_id`, `external_account_id`, `access_token`, `app_secret`, `verify_token`, `webhook_secret`, `is_active`, `is_default`, `quality_status`, `metadata_json`, `created_at`, `updated_at`
- Aceita `channel_type`: whatsapp, instagram, tiktok, website
- Aceita `provider`: meta_cloud_api
- Credenciais isoladas em campos simples prontos para futura criptografia

**`backend/alembic/versions/a1b2c3d4e5f6_add_channel_integrations.py`** — NOVA migration:
- Cria tabela `channel_integrations` com todos os índices necessários
- FK para `tenants.id` condicional `if dialect_name != "sqlite"` (PostgreSQL-safe)
- Chained em `f3a4b5c6d7e8`

**`backend/app/services/channel_integration_service.py`** — NOVO serviço:
- `get_active_whatsapp_by_phone_number_id(phone_number_id)` — query por phone_number_id ativo
- `resolve_tenant_id_for_whatsapp(phone_number_id, correlation_id)` — retorna tenant_id ou None
  - Se integração encontrada → usa `integration.tenant_id`
  - Se não encontrada + `ALLOW_DEFAULT_TENANT_FALLBACK=true` → usa `DEFAULT_TENANT_ID` com warning
  - Se não encontrada + fallback desativado → retorna None com erro (mensagem descartada)
- `get_provider_config_for_tenant_channel(tenant_id, channel_type)` — busca integração ativa

**`backend/app/core/config.py`** — 2 novas variáveis:
- `META_GRAPH_API_VERSION: str = "v18.0"` — versão da Graph API configurável via env
- `ALLOW_DEFAULT_TENANT_FALLBACK: bool = True` — controla fallback para DEFAULT_TENANT_ID

**`backend/app/services/whatsapp_service.py`** — versão Graph API configurável:
- `BASE_URL` substituído por `GRAPH_BASE` + `_api_version()` (lê `settings.META_GRAPH_API_VERSION`)
- URL de envio: `https://graph.facebook.com/{META_GRAPH_API_VERSION}/{phone_number_id}/messages`
- Comportamento preservado; sem `META_GRAPH_API_VERSION` no env usa `v18.0`

**`backend/app/api/routes/whatsapp_webhook.py`** — roteamento omnichannel:
- `_resolve_tenant_id` recebe `db: Session | None = None` como parâmetro
- Se `phone_number_id` presente + `db` disponível → tenta `ChannelIntegrationService`
- Se integração encontrada → usa `integration.tenant_id` (sem tocar no resto do fluxo)
- Se não encontrada → cai no fallback legacy (WHATSAPP_PHONE_NUMBER_ID + DEFAULT_TENANT_ID)
- Warning de mismatch de phone_number_id preservado
- Chamada no POST: `_resolve_tenant_id(payload, correlation_id, db=db)`

**`backend/app/providers/`** — NOVO pacote:
- `base.py`: `BaseChannelProvider` como protocolo `@runtime_checkable` com `send_text_message`
- `whatsapp_cloud.py`: `WhatsAppCloudProvider` como adapter do `WhatsAppService` atual
  - Fase futura: receber `ChannelIntegration` e usar tokens específicos (multi-tenant real)

**`docs/integrations/whatsapp_cloud_api.md`** — NOVO:
- Tabela de variáveis de ambiente
- URL do webhook
- Como o tenant é resolvido por phone_number_id (prioridade de resolução)
- Como o fallback DEFAULT_TENANT_ID funciona
- Como cadastrar ChannelIntegration para o número inicial
- Como META_GRAPH_API_VERSION funciona
- Segurança e logs
- Canais futuros

### Validação

```
pytest -q → 101/101 ✅ (nenhum teste quebrado)
Imports: ChannelIntegration, ChannelIntegrationService, providers → OK ✅
WhatsAppCloudProvider isinstance BaseChannelProvider → True ✅
_resolve_tenant_id sem DB → comportamento legacy preservado ✅
META_GRAPH_API_VERSION default v18.0 → OK ✅
ALLOW_DEFAULT_TENANT_FALLBACK default True → OK ✅
```

### Decisões técnicas

- **Sem enum no DB para channel_type/provider**: VARCHAR(50) — mais flexível para novos canais/provedores sem nova migration
- **Protocolo `@runtime_checkable`**: permite `isinstance(provider, BaseChannelProvider)` em runtime
- **Fallback preservado**: `ALLOW_DEFAULT_TENANT_FALLBACK=True` por padrão — zero impacto no MVP
- **`db=None` em `_resolve_tenant_id`**: mantém compatibilidade com os 14 testes existentes do webhook (passam `db` via dependency injection, que já era presente)

### Próximo passo (Prompt Whats 2+)

- Cadastrar primeira ChannelIntegration via script ou endpoint admin
- Setar `ALLOW_DEFAULT_TENANT_FALLBACK=false` quando multi-tenant real estiver operacional
- Provider registry para roteamento dinâmico de outbound por canal

---

## 2026-05-21 — Deploy em Produção (actaresolve.com.br)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Infraestrutura completa de deploy na VPS Hostinger:**

- **Nginx** configurado como proxy reverso: `/api/*` → FastAPI:8000 | `/*` → Next.js:3000
- **HTTPS** ativo em `https://actaresolve.com.br` (certificado SSL já existia na VPS)
- **HTTP → HTTPS** redirect + redirect `www` → sem www
- **Certbot-ready**: bloco `.well-known/acme-challenge/` para renovação automática
- **Headers de segurança**: HSTS, X-Frame-Options, X-Content-Type-Options

**`deploy/hostinger/nginx.conf`** — NOVO: config completa com upstream blocks, SSL, redirect

**`deploy/hostinger/deploy.sh`** — atualizado (etapa 7): instala Nginx se necessário, copia conf, valida, recarrega; detecta automaticamente se cert SSL existe e usa config HTTP temporária se não

**`backend/alembic/env.py`** — correção crítica: `DATABASE_URL.replace("%", "%%")` para escapar `%40` (@ URL-encoded) do configparser do Alembic

**`backend/.env`** — atualizado com `SECRET_KEY` real gerada, `CORS_ALLOWED_ORIGINS=https://actaresolve.com.br,http://actaresolve.com.br`

**`frontend/.env.local`** — `NEXT_PUBLIC_API_BASE_URL=https://actaresolve.com.br/api`, `NEXT_PUBLIC_AUTH_REQUIRED=true`

**SSH configurado** — alias `actaresolve` em `~/.ssh/config` → deploy@2.24.96.166; chave id_ed25519 local autorizada; sudo NOPASSWD configurado na VPS

### Validação

```
https://actaresolve.com.br           → HTTP 200 (Next.js) ✅
https://actaresolve.com.br/api/health → {"ok":true, api+db+redis OK} ✅
Migrations Alembic no Supabase       → já em head ✅
```

### Configuração da VPS

- **IP**: 2.24.96.166 | **Domínio**: actaresolve.com.br
- **Repo**: `/home/deploy/actaresolve` (branch `fase-11-frontend-operacional`)
- **Env files**: `/home/deploy/actaresolve/deploy/hostinger/backend.env` e `frontend.env`
- **SECRET_KEY**: `617ee4c7519f9ae062b993f1d6ad25f20ae7f50196bd75c948b91ee988e67e5a`
- **Deploy sob demanda**: Claude conecta via SSH e executa `deploy.sh` automaticamente

---

## 2026-05-18 — Fase 16 — RBAC Completo: Usuários e Permissões

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Backend — RBAC completo:**

**`backend/alembic/versions/f3a4b5c6d7e8_add_user_role.py`** — NOVA migration:
- Adiciona coluna `role VARCHAR(20)` à tabela `users` com `server_default='vendedor'`
- Migra dados: `is_admin=true` → `role='admin'`; outros → `role='vendedor'`
- Cria índice `ix_users_role`

**`backend/app/models/user.py`** — campo `role: Mapped[str]` adicionado

**`backend/app/schemas/auth.py`** — `UserInToken` agora inclui campo `role: str`

**`backend/app/api/routes/auth.py`** — `role` incluído no JWT payload e em `_user_to_schema`

**`backend/app/api/deps.py`** — expandido com:
- `require_roles(*allowed_roles)` — dependency factory para RBAC
- `authorize_tenant_scope(user, tenant_id)` — bloqueia acesso cruzado entre tenants

**`backend/app/schemas/user_management.py`** — NOVO:
- `UserCreate`, `UserUpdate`, `UserResponse`, `RoleInfo`, `PermissionMatrix`
- Validações: role enum, senha mínima 8 chars

**`backend/app/services/user_service.py`** — NOVO:
- `list_users` — superadmin vê todos; admin vê só tenant próprio
- `create_user` — valida regras de criação de papéis
- `update_user` — validação de scope + regra anti-promoção-a-superadmin
- `set_active` — ativa/desativa com proteção contra auto-desativação

**`backend/app/api/routes/users.py`** — NOVO: 7 endpoints:
- `GET /users/` — lista com scope automático por role
- `POST /users/` — criação com regras de autorização
- `GET /users/{id}` — detalhe com scope check
- `PATCH /users/{id}` — edição (nome, role, status)
- `PATCH /users/{id}/activate` e `/deactivate`
- `GET /users/meta/roles` — lista roles com metadados
- `GET /users/meta/permissions` — matriz completa de permissões

**`backend/app/api/routes/password_reset.py`** — NOVO:
- `POST /auth/forgot-password` — sempre 200, não revela se e-mail existe
- `POST /auth/reset-password` — valida token em memória, atualiza senha
- Nota: envio de e-mail real requer SMTP configurado (TODO)

**`backend/app/main.py`** — registra `users_router` e `password_reset_router`

**`backend/tests/test_users_rbac.py`** — NOVO: 15 testes:
- Login retorna `role` no response
- Superadmin lista usuários de todos os tenants
- Admin lista apenas o próprio tenant
- Admin não acessa usuário de outro tenant (403)
- Vendedor recebe 403 em rotas de gestão
- Admin não pode criar superadmin (403)
- Criação válida de vendedor por admin
- Usuário inativo não autentica (403)
- Ativar/desativar funciona corretamente
- Roles e permissões endpoint retornam dados corretos
- Forgot-password sempre retorna 200
- Reset-password com token inválido retorna 400

---

**Frontend — RBAC e UI de usuários:**

**`frontend/features/session/types.ts`** — `SessionUserRole` expandido: `superadmin | admin | vendedor | manager | agent`

**`frontend/features/session/auth-service.ts`** — `AuthUser` agora inclui `role: string`

**`frontend/features/session/session-context.tsx`** — `mapAuthUser` usa `role` real do backend (antes derivava de `is_admin`)

**`frontend/features/session/use-permissions.ts`** — NOVO hook:
- `usePermissions()` → `{ role, can(), canAny(), isAdmin, isSuperAdmin, isVendedor }`
- Mapa de permissões por role para controle de UI

**`frontend/features/settings/services/users-service.ts`** — NOVO serviço:
- `usersService.list/get/create/update/activate/deactivate/getRoles/getPermissions`

**`frontend/features/settings/components/users-permissions-section.tsx`** — NOVO componente completo:
- Sub-tabs: "Lista de Usuários" e "Papéis e Permissões"
- Tabela de usuários com filtros (busca, role, status) integrada ao backend real
- Botões de ativar/desativar com feedback imediato
- Modal de criação com campos dinâmicos por role
- Modal de edição
- Drawer lateral "Visualizar permissões" com permissões agrupadas por módulo
- Acordeão de papéis com permissões expandíveis
- Acesso restrito: vendedor recebe tela de bloqueio

**`frontend/app/(dashboard)/configuracoes/page.tsx`** — nova aba "Usuários e Permissões" integrada ao módulo existente

**`frontend/app/(auth)/login/page.tsx`** — link "Esqueci minha senha" adicionado

**`frontend/app/(auth)/esqueci-senha/page.tsx`** — NOVA página: formulário de solicitação de recuperação

**`frontend/app/(auth)/redefinir-senha/page.tsx`** — NOVA página: formulário de nova senha com validação + estados (loading, erro, sucesso, link inválido)

### Validação

```
pytest -q     → 101/101 ✅ (86 anteriores + 15 novos RBAC)
npm run build → 14/14 páginas ✅ (2 novas: /esqueci-senha, /redefinir-senha)
TypeScript: 0 erros ✅
```

### Decisões técnicas

- **Sem Supabase Auth**: projeto usa JWT próprio FastAPI; RBAC implementado sobre esta base
- **`role` como VARCHAR**: evita enum no DB para compatibilidade SQLite/PostgreSQL nos testes
- **Token reset em memória**: adequado para MVP; produção deve usar Redis com TTL de 15min
- **E-mail reset sem SMTP**: endpoint funcional, logs o token em `INFO`; requer configuração de e-mail
- **Admin não pode criar superadmin**: regra validada no backend, não depende do frontend

### Pendências

- [ ] SMTP para envio real de e-mails de recuperação (`SMTP_HOST`, `SMTP_PORT`, `SMTP_USER`, `SMTP_PASS`)
- [ ] Redis para armazenar tokens de reset com TTL
- [ ] Sidebar: ocultar menus por role (vendedor não vê Configurações > Usuários)
- [ ] Script `create_tenant_admin.py`: suportar `--role superadmin` para criar primeiro superadmin

---

## 2026-05-16 — Fase 19 — Módulo Equipe: Redesign completo (design Gemini)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Refatoração completa do módulo `/equipe` com visual premium baseado no protótipo Gemini:**

**`frontend/features/equipe/types.ts`** — NOVO: tipagens completas:
- `HumanMember`, `AIAgent`, `TeamKpis`, `NewHumanForm`, `NewAIForm`
- Unions: `MemberStatus`, `AIAgentStatus`, `TeamFilter`, `SortBy`, `DrawerTab`, `RankingTab`

**`frontend/features/equipe/mock-data.ts`** — NOVO: mock isolado conforme convenção do projeto:
- `MOCK_TEAM_KPIS` — 6 KPIs gerais (total equipe, ativos, conversas, conversão, TMR, handoffs)
- `MOCK_AI_AGENTS` — 4 agentes de IA (Qualificador, Vendas Sênior, Suporte, Recuperador)
- `MOCK_HUMAN_MEMBERS` — 5 operadores humanos com métricas individuais

**`frontend/app/(dashboard)/equipe/page.tsx`** — reescrito completo (era placeholder):
- **6 KPI cards** responsivos (1→2→3→6 colunas): Total Equipe, Ativos Agora (com dot animado), Em Atendimento, Taxa Conversão, TMR Médio, Handoffs Pendentes (ring vermelho)
- **Seção Impacto IA vs Humano**: donut SVG tri-segmentado (42% IA / 38% Humano / 20% Híbrido) + barras de conversão por tipo + insight gerencial
- **Alertas da Equipe**: 3 alertas com dots coloridos (crítico/atenção/oportunidade) + pulsação no badge
- **Filtros**: busca full-text, toggle tipo (Todos/Humanos/Agentes IA), selects de status/função/ordenação
- **Grid de Agentes IA**: cards com badge de status, métricas 2x2 (conversas, resolução, handoff, conversão), ações pausar/desativar
- **Tabela de Operadores Humanos**: colunas nome+email, função/time, status (pill colorido), conversas ativas (mini barra de carga com vermelho quando >12), TMR, conversão%, receita, botão detalhes
- **Distribuição de Carga**: barras horizontais por operador com cores por nível (vermelho/âmbar/verde/sky)
- **Ranking de Performance**: abas Humanos/Agentes IA com top-3 (receita + conversão)
- **Drawer de Detalhes** (slide-in direita, 480px): 4 abas — Perfil (cargo/time/status + permissões RBAC), KPIs Individuais (4 cards + SLA), Funil de Vendas (4 estágios com barras), Auditoria (timeline de ações)
- **Modal Adicionar Membro**: formulário com nome, email, cargo, time — adiciona localmente à lista
- **Modal Criar Agente IA**: formulário com nome, especialidade, descrição, autonomia — adiciona localmente à lista
- Filtros `useMemo` para busca, status, função e ordenação independentes por tipo (humano/AI)

### Compatibilidade com backend

Backend ainda não tem endpoint `/users` (RF-10 — backlog). A página:
- Usa mock isolado em `features/equipe/mock-data.ts` (convenção do projeto)
- Estrutura pronta para troca: `MOCK_HUMAN_MEMBERS` → `GET /users?tenant_id=X`
- Tipos em `features/equipe/types.ts` alinhados com o modelo `User` do backend (`id`, `email`, `full_name`, `is_active`, `is_admin`)

### Validação

```
npm run build → 12/12 páginas ✅ | TypeScript: 0 erros ✅
```

---

## 2026-05-16 — Fase 18B — CRM Etapa B: Backend + Frontend funcional

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Backend — novos endpoints e modelo:**

**`backend/app/models/lead_note.py`** — NOVO modelo:
- `LeadNote` com campos: `id`, `tenant_id`, `conversation_id`, `author`, `content`, `created_at`
- FK para `tenants.id` e `conversations.id`

**`backend/app/models/conversation.py`** — 3 novos campos:
- `estimated_value: Float` (nullable)
- `lead_source: String(50)` (nullable)
- `product_interest: String(100)` (nullable)

**`backend/alembic/versions/e2f3a4b5c6d7_add_lead_notes_and_crm_fields.py`** — NOVA migration:
- Chained em `1a2b3c4d5e6f`; adiciona 3 colunas em `conversations` e cria tabela `lead_notes`
- FK condicional `if dialect_name != "sqlite"` (padrão PostgreSQL-safe)

**`backend/app/schemas/conversation_crm.py`** — reescrito completo:
- Novos schemas: `FunnelStageUpdate`, `CrmDataUpdate`, `LeadNoteCreate`, `LeadNoteRead`
- Novos schemas: `FunnelStageStatItem`, `FunnelStatsResponse`
- `ConversationCRMListItem` atualizado com `estimated_value`, `lead_source`, `product_interest`
- Constantes: `VALID_FUNNEL_STAGES`, `FUNNEL_STAGE_LABELS`, `ORDERED_ACTIVE_STAGES`

**`backend/app/services/crm_read_service.py`** — ambos os métodos retornam os 3 novos campos comerciais

**`backend/app/api/routes/conversations.py`** — 5 novos endpoints:
- `PATCH /{id}/funnel-stage` — atualiza estágio, registra evento via `FunnelEventService`
- `PATCH /{id}/crm-data` — atualiza valor estimado, origem e produto de interesse
- `GET /{id}/notes` — lista notas da conversa
- `POST /{id}/notes` — cria nota com `author` = email do usuário autenticado
- `GET /crm/funnel-stats` — funil agregado com contagens e taxa de conversão por estágio

**`backend/tests/test_crm_write_routes.py`** — NOVO: 9 testes, todos passando (86/86 total)

---

**Frontend — integração funcional:**

**`frontend/features/conversations/types.ts`** — `ConversationCrmApiItem` recebe 3 novos campos: `estimated_value`, `lead_source`, `product_interest`

**`frontend/features/crm/types.ts`** — `CrmLeadUi` recebe `estimatedValue`, `leadSource`, `productInterest`; novos tipos exportados: `LeadNote`, `FunnelStageStatItem`, `FunnelStatsResponse`

**`frontend/features/crm/mappers.ts`** — `mapCrmApiItemToUi` mapeia os 3 novos campos

**`frontend/lib/api/client.ts`** — adicionado método `patch<T, B>` (estava ausente)

**`frontend/features/conversations/services/conversations-service.ts`** — 5 novas funções:
- `patchFunnelStage`, `patchCrmData`, `getLeadNotes`, `postLeadNote`, `getCrmFunnelStats`

**`frontend/features/crm/components/crm-lead-detail-panel.tsx`** — reescrito funcional:
- Select de estágio auto-salva via `patchFunnelStage` ao `onChange`
- Formulário comercial (valor, origem, produto) salva via `patchCrmData` com botão único
- Seção de notas: carrega via `getLeadNotes` no `useEffect`, adiciona via `postLeadNote`
- `useRef(prevConvId)` para resetar estado local quando um lead diferente é aberto
- Largura `w-[480px]` (antes `w-80`)

### Validação

```
pytest -q     → 86/86 ✅
npm run build → 12/12 páginas ✅ | TypeScript: 0 erros ✅
```

### Pendências restantes (CRM)

- [ ] Botões "Marcar como Ganho/Perdido" — endpoints existem via `patchFunnelStage`, apenas habilitar os botões
- [ ] Funil SVG cônico visual (atualmente: barras horizontais)
- [ ] `POST /conversations/{id}/close` para "Finalizar Chamado" (em `/conversas`)

---

## 2026-05-16 — Fase 18 — CRM Redesign (design Gemini)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Redesign completo do módulo `/crm` com visual premium inspirado no protótipo Gemini:**

**`features/crm/types.ts`** — tipos ampliados:
- `CrmKpiData`: adicionados `active` (leads fora de won/lost) e `stale` (leads parados)
- Novos tipos exportados: `CrmOwnerFilter`, `CrmTempFilter`, `CrmViewMode`

**`features/crm/mappers.ts`** — `computeKpis` atualizado:
- Calcula `active` = total excluindo won/lost
- Calcula `stale` = leads com `isStale === true`

**`features/crm/components/crm-kpi-cards.tsx`** — redesign completo:
- 6 cards com `border-[3px]` colorida no topo (amber, green, red)
- Ícones: UserCheck, Flame, Users, FileText, TrendingUp, AlertTriangle
- Valores em `text-[#163B7A]` com variações de cor por severidade
- Grid 6 colunas responsivo (2→3→6)

**`features/crm/components/crm-filters.tsx`** — filtros expandidos:
- `select` de Temperatura (Quente/Morno/Frio) com props `tempFilter`
- `select` de Responsável (IA/Humano) com props `ownerFilter`
- Chips de filtro rápido redesenhados como pills coloridos (rounded-full, cor por tipo)

**`features/crm/components/crm-lead-card.tsx`** — cards mais ricos:
- Badge IA/Humano com ícone Bot/User e cor brand (#35C7B9/#007BD4)
- Badge temperatura como pill colorido (amber/blue/slate)
- Layout rounded-xl com sombra sutil
- Highlight âmbar para `needsHuman`

**`features/crm/components/crm-pipeline-column.tsx`** — headers dark:
- Headers sólidos dark por estágio (slate-700, blue-700, purple-700, etc.)
- Body com cor de fundo suave correspondente ao estágio
- rounded-xl consistente

**`features/crm/components/crm-lead-list.tsx`** — NOVO componente:
- Tabela inteligente: Lead/Telefone | Estágio | Temperatura | Responsável | Última Atividade | Ações
- Badges coloridos para estágio e temperatura
- Badge IA/Humano com ícone
- Link "Conversa" em cada linha
- Linha clicável abre o detail panel

**`features/crm/components/crm-lead-detail-panel.tsx`** — drawer muito mais rico:
- Largura: `w-80` → `w-[480px]`
- Header: badges de temperatura + IA/Humano, nome, telefone, última atividade
- Quick Actions: "Abrir Conversa" (verde) + "Pausar IA"/"Retomar IA" (toggle real via handoff endpoints)
- Handoff: `postHandoffInProgress` / `postHandoffResumeAi` com loading state
- Seção AI Intelligence: gradiente azul sutil, resumo da conversa, grid intent/sentiment/tom
- Seção Next Action: card âmbar com `nextRecommendedAction`
- Seção Dados Comerciais: grade 2x2 com estágio, temperatura, responsável, status IA
- Seção Notas: placeholder "em breve" com disabled inputs
- Footer: botões "Ganho"/"Perdido" desabilitados (em breve)
- Prop `onReload` para refresh após ação de handoff

**`app/(dashboard)/crm/page.tsx`** — integração completa:
- Mini Funil de Distribuição: barras de progresso horizontais com % por estágio (dados reais)
- Tabs: "Pipeline Kanban" / "Lista de Leads" com `viewMode` state
- Filtros: `ownerFilter` + `tempFilter` + `filter` (quick chips) + `search` — todos aplicados em `filteredLeads`
- `clearFilters()` central para resetar tudo
- Skeleton redesenhado com `rounded-xl` dark headers
- Passa `onReload` para o detail panel

### Validação

```
npm run build → 12/12 páginas ✅ | TypeScript: 0 erros ✅
```

### Pendências criadas (Etapa B)

- [ ] Backend: `PATCH /conversations/{id}/funnel-stage` (editar estágio no drawer)
- [ ] Backend: `GET /crm/funnel-stats` para funil SVG cônico com taxas de conversão reais
- [ ] Backend: Notas por lead (endpoint + modelo)
- [ ] Backend: Campos comerciais (valor estimado, empresa, origem, produto de interesse)

---

## 2026-05-16 — Fase 17 — Cockpit de Conversas (design Gemini)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Redesign completo do módulo `/conversas` com visual Gemini:**

**`features/conversations/utils.ts`** — adicionado helper `getInitials(name, phone)`:
- Gera iniciais de 2 letras a partir do nome ou últimos 2 dígitos do telefone

**`features/conversations/components/conversation-filters.tsx`** — novo design:
- Tipo `ConversationFilterValue` simplificado: `'all' | 'ia' | 'humano'`
- Tabs tipo pill: Todas / IA (verde #35C7B9) / Humano (azul #007BD4)
- Search bar com borda branca e ring azul

**`features/conversations/components/conversation-list-item.tsx`** — card redesenhado:
- Avatar com iniciais + ícone Bot/User como badge overlay
- Borda esquerda colorida: azul tech (selecionado), âmbar (humano), transparente (padrão)
- Dot verde `#35C7B9` para conversas com IA ativa
- Card `bg-white/50 rounded-xl` com sombra suave

**`features/conversations/components/conversation-list.tsx`** — atualizado:
- Skeleton com `rounded-xl` e `h-[68px]` para match com cards
- `<ul>` com `gap-1.5` entre items
- Empty state com `AlertCircle` icon

**`features/conversations/components/message-bubble.tsx`** — redesign completo:
- Avatar para cada sender: iniciais do cliente / Bot icon (IA) / User icon (operador)
- Bubbles: branco (cliente) / `#163B7A` gradiente (IA) / `#007BD4` (operador)
- Tag "Resolutiva AI" / "Operador" no footer da bubble
- Animação `animate-fadeIn` ao aparecer

**`features/conversations/components/human-reply-box.tsx`** — refatorado:
- Removidas as ações de handoff (movidas para o chat header)
- Adicionados ícones Paperclip + Smile no campo de input
- Botão Send estilizado `#007BD4` hover `#163B7A`
- Indicador de tempo médio de resposta da IA no rodapé
- Input com `Enter` para enviar (sem Ctrl+Enter)

**`features/conversations/components/conversation-chat.tsx`** — melhorias:
- Header rico: avatar de iniciais + status dot animado + label IA/Humano
- Toggle IA/Humano movido para o header (antes estava no reply box)
  - "IA Ativa (Pausar)" chama `postHandoffInProgress`
  - "Devolver para IA" chama `postHandoffResumeAi`
- Separador de data "Hoje, DD/MM/AAAA" entre mensagens
- Passa `contactInitials` para cada `MessageBubble`
- Botão MoreVertical no header

**`features/conversations/components/conversation-context-panel.tsx`** — redesign total:
- **Perfil do Lead**: avatar grande + nome + badge de ownership + botões Phone/Mail/Calendar
- **Co-Piloto Resolutiva**: sentimento previsto + intenção detectada + sugestão de próximo passo com ícone Sparkles
- **Ficha Cadastral**: estágio do funil, temperatura (com badge colorido), tom, atendimento
- **Resumo**: exibe `conversationSummary` ou `contextSummary` quando disponível
- **Linha do Tempo**: eventos dinâmicos (handoff, estágio)
- **Botão "Finalizar Chamado"** fixo no rodapé (pendente endpoint backend)
- Layout `flex-col h-full`: seções roláveis + footer fixo

**`app/(dashboard)/conversas/page.tsx`** — colunas redimensionáveis:
- `leftWidth` (default 300px) / `rightWidth` (default 340px) com drag handles
- Divisoras azuis `#007BD4` ao arraste, cinza no estado normal
- Coluna 1: `bg-[#F0F4F8]` (Azul Gelo Suave) com footer de contagem
- Coluna 3: `bg-[#E6ECF2]` (Azul Metálico Premium)
- Filtro atualizado: `'all' | 'ia' | 'humano'`

### Validação

```
npm run build → 12/12 páginas ✅ | TypeScript: 0 erros ✅
Dev server: http://localhost:3001/conversas ✅
```

### Pendências criadas

- [ ] Backend: `POST /conversations/{id}/close` para o botão "Finalizar Chamado"
- [ ] Polling ou WebSocket para atualização em tempo real da lista de conversas

---

## 2026-05-16 — Fase 16 — Novo Layout Sidebar + Dashboard (design Gemini)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**`frontend/features/settings/brand-config.ts`** — hook `useBrandConfig()` criado:
- Persiste `logoUrl`, `brandName`, `brandTagline` em `localStorage` (key `actaresolve:brand`)
- `logoUrl = ''` → usa SVG padrão; `logoUrl = '<url>'` → exibe `<img>` com a imagem configurada
- Será consumido pelo submenu de Aparência em Configurações (futuro)

**`frontend/components/layout/sidebar.tsx`** — redesign completo:
- Fundo dark grafite `#1F2937` (antes: CSS var `--sidebar` claro)
- Logo SVG vetorial `ActaLogoIcon` como fallback; imagem configurável via `useBrandConfig().config.logoUrl`
- Sidebar expandida: logo + nome + tagline (ou imagem externa)
- Sidebar colapsada: ícone SVG em gradiente `#163B7A → #35C7B9`
- Nav items: `rounded-xl`, ativo = `bg-[#007BD4]` (Azul Tech)
- Botão **Sair** com `useSession().logout()` (antes: botão não existia)
- Link **Configurações** movido para footer (antes: estava no nav principal)
- Botão Pin/Unpin preservado

**`frontend/app/(dashboard)/page.tsx`** — dashboard rico:
- 4 KPI cards com mini sparklines (barras SVG inline)
- Alertas Operacionais com timeline (dots coloridos por severidade)
- Funil de Vendas visual (4 estágios com barras de progresso hover)
- Banner IA Performance (gradiente dark + anel animado)
- Valores marcados `—` prontos para conectar ao backend

**`frontend/app/globals.css`** — adicionado:
- `@keyframes spin-slow` + `.animate-spin-slow` (para o anel giratório do banner IA)

### Validação

```
npm run build → 12/12 páginas ✅ | TypeScript: 0 erros ✅
```

### Decisões

- **`logoUrl` em localStorage**: solução MVP; quando o backend tiver endpoint `/settings/appearance`, migrar para API + `useEffect` de bootstrap
- **Sem `next/image`**: logo externa pode ser qualquer URL — `<img>` é mais flexível que `Image` do Next para URLs dinâmicas não pre-configuradas
- **Dashboard com `—`**: valores reais virão do `GET /crm/leads` e `GET /conversations` (backlog existente)

### Próximos passos

- [ ] Submenu **Configurações > Aparência** com campos `logoUrl`, `brandName`, `brandTagline` usando `useBrandConfig().update()`
- [ ] Conectar KPIs reais ao Dashboard
- [ ] Testar visualmente no browser (dev server)

---

## 2026-05-14 — Fase 15 — Correção de Migration PostgreSQL (1a2b3c4d5e6f)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Problema

Migration `1a2b3c4d5e6f_add_conversation_ownership_and_crm_fields.py` usava:

```python
with op.batch_alter_table("conversations", schema=None, recreate="always") as batch_op:
```

No PostgreSQL 16, isso tenta dropar a PK `conversations_pkey` e recriar a tabela, o que falha com:

```
psycopg2.errors.DependentObjectsStillExist: cannot drop constraint conversations_pkey
on table conversations because other objects depend on it
```

Dependentes identificados: `messages_conversation_id_fkey`, `conversation_decision_logs_conversation_id_fkey`, `followup_schedules_conversation_id_fkey`, `funnel_events_conversation_id_fkey`, `conversation_context_snapshots_conversation_id_fkey`.

Problema adicional: no `downgrade`, os `batch_op.drop_column` estavam indentados dentro do `if dialect_name != "sqlite"`, fazendo-os ser ignorados em SQLite.

### Corrigido

**`backend/alembic/versions/1a2b3c4d5e6f_add_conversation_ownership_and_crm_fields.py`**

**upgrade()**: Removido `batch_alter_table(..., recreate="always")`. Substituído por operações diretas PostgreSQL-safe:
- `op.add_column("conversations", ...)` — para cada uma das 5 colunas novas
- `op.create_foreign_key(...)` — condicional `if dialect_name != "sqlite"` preservado
- `op.create_index(...)` e `op.create_table("conversation_assignments", ...)` — inalterados

**downgrade()**: Removido `batch_alter_table`. Substituído por:
- `op.drop_constraint(...)` — condicional `if dialect_name != "sqlite"`
- `op.drop_column("conversations", ...)` — agora fora do `if`, executado em todos os dialetos

### Validação

```
Sintaxe Python: OK ✅
Carregamento do módulo: OK (revision, upgrade, downgrade verificados) ✅
pytest -q → 77/77 ✅
recreate="always": removido, nenhuma ocorrência restante ✅
```

### Como reaplicar na VPS com banco limpo

1. Garantir que o banco PostgreSQL está vazio (ou `alembic downgrade base` se já houve tentativa parcial)
2. `alembic upgrade head` — aplicará todas as migrations em sequência sem erro de FK dependente

---

## 2026-05-14 — Fase 14 — Correção de Tipo AuditLog (migration inicial)

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Problema

Migration inicial (`9668532fc93e_create_base_schema.py`) criava `audit_logs.tenant_id` e `audit_logs.user_id` como `sa.String(length=36)`, mas `tenants.id` e `users.id` são `sa.Integer()`. PostgreSQL 16 rejeita a FK com tipo incompatível:

```
foreign key constraint "audit_logs_tenant_id_fkey" cannot be implemented
DETAIL: Key columns "tenant_id" and "id" are of incompatible types: character varying and integer.
```

### Corrigido

**`backend/app/models/audit_log.py`**
- `tenant_id`: `Column(String(36), ForeignKey("tenants.id"), ...)` → `Column(Integer, ForeignKey("tenants.id"), ...)`
- `user_id`: `Column(String(36), ForeignKey("users.id"), ...)` → `Column(Integer, ForeignKey("users.id"), ...)`
- Import ajustado: `Column, Integer, String, ...` (removido import não-usado de `datetime, timezone`)
- `id` (PK UUID): mantido como `String(36)` — correto, não referencia nada

**`backend/alembic/versions/9668532fc93e_create_base_schema.py`**
- `audit_logs.tenant_id`: `sa.String(length=36)` → `sa.Integer()`
- `audit_logs.user_id`: `sa.String(length=36)` → `sa.Integer()`
- Nenhuma outra migration toca `audit_logs`, sem cascata de correções necessária

### Validação

```
python -c "from app.models.audit_log import AuditLog; ..."
→ tenant_id: INTEGER | user_id: INTEGER | id: VARCHAR(36) ✅

pytest -q → 77/77 ✅
```

### Decisão

Correção feita diretamente na migration base (não criada nova migration), pois o banco de produção na VPS ainda não foi provisionado com dados reais — a migration ainda não foi aplicada com sucesso em nenhum ambiente persistente.

---

## 2026-05-14 — Fase 13 — Deploy Docker Hostinger VPS + Rebranding ActaResolve

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Diagnóstico pré-fase

| Item | Estado antes |
|---|---|
| Dockerfiles | ❌ Não existiam |
| docker-compose produção | ❌ Não existia (apenas alembic/docker-compose.yml de dev) |
| Scripts deploy VPS | ❌ Não existiam |
| Nome do produto | "SaaS Resolutiva" / "Resolutiva" em vários arquivos |
| `next.config.ts` standalone | ❌ Sem `output: 'standalone'` |

### Criado

**`backend/Dockerfile`**
- FROM python:3.11-slim
- Instala gcc e libpq-dev para psycopg2-binary
- pip install sem cache a partir de requirements.txt
- CMD padrão: `bash start_api.sh` (worker sobrescreve via compose)

**`backend/.dockerignore`**
- Exclui __pycache__, .env, *.db, tests/, private_*, alembic/docker-compose.yml

**`frontend/Dockerfile`** (multi-stage)
- Stage deps: node:20-alpine, npm ci
- Stage builder: aceita NEXT_PUBLIC_* como build ARGs (embutidos em build time)
- Stage runner: node:20-alpine, usuário não-root nextjs, copia standalone + static + public
- CMD: `node server.js`

**`frontend/.dockerignore`**
- Exclui .next, node_modules, .env*, .git

**`frontend/next.config.ts`**
- Adicionado `output: 'standalone'` (necessário para o Docker standalone)

**`deploy/hostinger/docker-compose.prod.yml`**
- name: actaresolve
- Serviços: postgres (16-alpine), redis (7-alpine), api, worker, frontend
- Rede interna `actaresolve_net` — postgres e redis sem portas públicas
- api e frontend: `127.0.0.1:8000:8000` e `127.0.0.1:3000:3000`
- api e worker usam mesma imagem `actaresolve_backend:latest` (build único)
- Healthchecks: postgres (pg_isready), redis (redis-cli ping), api (/health)
- restart: unless-stopped em todos os serviços
- Volumes persistentes: postgres_data, redis_data

**`deploy/hostinger/backend.env.example`**
- APP_NAME=ActaResolve
- DATABASE_URL com hostname `postgres` (serviço Docker interno)
- REDIS_URL com hostname `redis` (serviço Docker interno)
- POSTGRES_PASSWORD separado (usado pela interpolação yaml do compose)
- Todas as variáveis existentes documentadas

**`deploy/hostinger/frontend.env.example`**
- NEXT_PUBLIC_API_BASE_URL, NEXT_PUBLIC_AUTH_REQUIRED=true
- NEXT_PUBLIC_TENANT_ID documentado como dev-fallback

**`deploy/hostinger/deploy.sh`**
- set -euo pipefail
- Verifica backend.env e frontend.env antes de prosseguir
- git fetch + pull na branch atual
- Sourcia env files antes do build (exporta vars para build args e interpolação yaml)
- docker compose build → up -d
- Loop de espera para postgres ficar pronto (pg_isready)
- `docker compose run --rm --no-deps api alembic upgrade head`
- Status final dos containers

### Rebranding ActaResolve

**Arquivos de exemplo:**
- `backend/.env.example`: APP_NAME, DATABASE_URL, CORS_ALLOWED_ORIGINS → ActaResolve/actaresolve

**Frontend UI (texto visível ao usuário):**
- `frontend/app/layout.tsx`: title → "ActaResolve — Automação Inteligente"
- `frontend/app/globals.css`: comentário de tema
- `frontend/components/layout/sidebar.tsx`: logo text
- `frontend/app/(auth)/login/page.tsx`: título da página de login

**Frontend configuração/mocks:**
- `frontend/features/session/auth-service.ts`: TOKEN_KEY localStorage
- `frontend/features/session/dev-config.ts`: email, nome e schema_name de dev
- `frontend/features/settings/mock-data.ts`: displayName WhatsApp, emails de equipe
- `frontend/features/ai/mock-data.ts`: nome do assistente
- `frontend/features/ai/components/ai-personality-section.tsx`: preview de resposta

### Validações

```
pytest -q        → 77/77 ✅
npm run build    → 12/12 páginas ✅ | TypeScript: 0 erros ✅
docker compose config → syntax valid ✅
```

### Decisões

- **Redis com volume**: redis_data persistente para não perder fila em reboot da VPS
- **Worker sem healthcheck**: processo background, difícil de healthcheckar sem endpoint HTTP
- **worker usa imagem pré-buildada** (`actaresolve_backend:latest`) para não recompilar — `image:` tag compartilhada com api; compose builda a api e reutiliza a imagem no worker
- **NEXT_PUBLIC_* como build args**: variáveis embutidas em build time — mudança exige rebuild
- **deploy.sh cria container temporário para migrations** (`run --rm --no-deps`): não interrompe a api em execução

### Pendências para a VPS (ação manual após push)

1. Instalar Docker Engine + Docker Compose no Ubuntu 24.04 (já instalados segundo o prompt)
2. Clonar repositório na VPS
3. Copiar `backend.env.example` → `backend.env` e preencher todas as variáveis reais
4. Copiar `frontend.env.example` → `frontend.env` e preencher `NEXT_PUBLIC_API_BASE_URL`
5. Executar `bash deploy/hostinger/deploy.sh`
6. Configurar Nginx no host (fora do Docker) para proxy reverso para 127.0.0.1:8000 e 127.0.0.1:3000
7. Configurar SSL com Certbot
8. Criar primeiro tenant/admin: `docker compose exec api python -m scripts.create_tenant_admin ...`

### Próximos passos (Fase 13+)

- Nginx conf + Certbot (bloqueados intencionalmente para validar compose primeiro)
- GitHub Actions para CI/CD automatizado
- Tabela `whatsapp_integrations` (multi-tenant real)
- Remoção de `DEFAULT_TENANT_ID`

---

## 2026-05-12 — Fase 12.3 — WhatsApp Cloud API Real + Segurança do Webhook

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Diagnóstico pré-fase

| Item | Estado antes da 12.3 |
|---|---|
| Validação HMAC do webhook | ❌ Ausente — endpoint aceitava qualquer POST |
| Leitura do corpo bruto | ❌ Usava `request.json()` (reserializado, inutilizável para HMAC) |
| Roteamento por phone_number_id | ❌ `DEFAULT_TENANT_ID` fixo sem extração do payload |
| Testes do webhook | ❌ Nenhum teste existia para o endpoint WhatsApp |
| DEFAULT_TENANT_ID no .env.example | ❌ Variável não documentada |

### Implementado

**`backend/app/api/routes/whatsapp_webhook.py`** — reescrito com:
- `_verify_meta_signature(raw_body, header, app_secret)` — HMAC-SHA256 com `hmac.compare_digest`
- `await request.body()` → corpo bruto preservado antes de parse
- `json.loads(raw_body)` após validação (nunca `request.json()`)
- Rejeição 401 se assinatura ausente, 403 se inválida
- Em dev sem `META_APP_SECRET`: aceita com warning em log
- Em produção sem `META_APP_SECRET`: HTTP 500 (misconfiguration explícita)
- `_extract_phone_number_id()` — lê `metadata.phone_number_id` do payload
- `_resolve_tenant_id()` — compara com `WHATSAPP_PHONE_NUMBER_ID`, usa `DEFAULT_TENANT_ID` como resultado (MVP 1 tenant); log explícito de match ou mismatch
- Correção: `_process_outbound_statuses` agora usa `logger.exception()` (antes chamava `build_log_message` sem logar)

**`backend/tests/test_whatsapp_webhook.py`** — 14 testes criados:
- GET: token válido, token inválido, mode inválido, token não configurado
- POST assinatura: ausente (401), inválida (403), body adulterado (403), válida (200)
- POST sem META_APP_SECRET: dev aceita, produção rejeita
- POST enqueue: mensagem persistida chama `enqueue_message_processing` uma vez
- POST status-only: não enfileira
- Roteamento: phone_number_id match, mismatch (fallback), ausente (fallback)
- Deduplicação: mesmo wamid enviado duas vezes → segunda não persistida

**`backend/.env.example`** — adicionado `DEFAULT_TENANT_ID` com explicação de débito técnico

**`docs/deploy/fase-12-3-whatsapp-real.md`** — criado com:
- Explicação da validação HMAC e comportamento por cenário
- Roteamento por phone_number_id e débito técnico multi-tenant
- Pré-requisitos no painel Meta
- Variáveis de ambiente necessárias
- Passo a passo para configurar webhook no painel Meta
- Como verificar o GET de challenge
- Como acompanhar logs API, worker, Redis, banco e painel
- Diagnóstico de falhas comuns (assinatura inválida, verify token, outbound, painel)
- Checklist de prontidão antes de expor webhook
- Checklist de validação ponta a ponta
- Tabela de riscos e o que depende de ação manual

### Decisões de projeto

- `DEFAULT_TENANT_ID` mantido como fallback explícito no MVP — documentado como débito técnico (Fase 13+)
- Mismatch de phone_number_id não rejeita no MVP — log de warning + fallback, para não quebrar em configurações parciais
- Produção sem `META_APP_SECRET` → 500 explícito, não silêncio
- Corpo bruto (`request.body()`) lido antes de qualquer parse — crítico para HMAC correto

### Próximos passos
- [ ] Provisionar VPS ou Railway com PostgreSQL + Redis
- [ ] Configurar HTTPS e domínio em produção
- [ ] Configurar credenciais WhatsApp no painel Meta (webhook URL, verify token, subscrição `messages`)
- [ ] Executar primeiro teste ponta a ponta real (mensagem → ingestão → worker → IA → outbound)
- [ ] **FASE 13**: Multi-tenant real — tabela `whatsapp_integrations`, remoção de `DEFAULT_TENANT_ID`

---

## 2026-05-12 — Fase 12.2 — Deploy em Produção Controlada + Preparação WhatsApp Real

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Diagnóstico de prontidão herdado da 12.1

Todos os itens da 12.1 validados. Vault não registra provedor de hospedagem específico — SPEC menciona "MVP local → VPS". Documentação estruturada de forma portátil.

### Criado

**`backend/start_api.sh`**
- Script de start padronizado da API
- Suporta `PORT` e `WEB_WORKERS` via env
- Uso: `./start_api.sh` | referenciado no `Procfile` e nos exemplos systemd

**`backend/start_worker.sh`**
- Script de start padronizado do worker
- Emite log de contexto (APP_ENV, REDIS_URL) antes de iniciar

**`backend/Procfile`**
- Declaração de processos para Railway, Render, Heroku e similares
- `web: bash start_api.sh` | `worker: bash start_worker.sh`

**`docs/deploy/fase-12-2-execucao-deploy.md`**
- Análise de alternativas de hospedagem (VPS, Railway, Render, Fly.io) com recomendações
- Plano completo Caminho 1 — VPS genérico: instalar deps, PostgreSQL, Redis, migrations, bootstrap, systemd API, systemd worker, Next.js, Caddy SSL
- Plano alternativo Caminho 2 — Railway (piloto rápido)
- Checklist completo de secrets e variáveis (backend + frontend) com `NEXT_PUBLIC_AUTH_REQUIRED=true` explicitado
- Checklist de validação pós-deploy (backend, frontend, webhook)
- Seção objetiva de preparação para FASE 12.3: o que está pronto, o que falta fazer no painel Meta, o que a 12.3 validará
- Tabela de riscos antes do go-live

### Alterado

**`docs/deploy/producao-controlada.md`**
- Adicionada referência para `fase-12-2-execucao-deploy.md`

### Pendências identificadas (a resolver antes do go-live)

- Validação HMAC do webhook Meta com `META_APP_SECRET` (não implementada — alta severidade)
- Backup do PostgreSQL não configurado
- Provedor de hospedagem não decidido — ação do owner

### Próximos passos
- [ ] Provisionar VPS ou Railway com PostgreSQL + Redis
- [ ] Executar plano de deploy do `fase-12-2-execucao-deploy.md`
- [ ] Configurar credenciais WhatsApp no painel Meta (pré-FASE 12.3)
- [ ] **FASE 12.3**: Conexão WhatsApp Cloud API real + teste ponta a ponta

---

## 2026-05-12 — Fase 12.1 — Preparação para Produção Controlada

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Diagnóstico de prontidão (pré-fase)

| Item | Status antes | Ação |
|---|---|---|
| DATABASE_URL (PostgreSQL) | ✅ Config via env, alembic lê settings | — |
| REDIS_URL | ✅ Via settings, sem hardcode | — |
| API e worker separados | ✅ Processos independentes | Documentar |
| Healthcheck (DB + Redis + API) | ✅ Completo em `/health` | — |
| CORS | ❌ Hardcoded localhost | Corrigido |
| SECRET_KEY em produção | ⚠️ Fallback sem validação | Corrigido |
| Bootstrap tenant/admin | ❌ Não existia | Criado |
| backend/.env.example | ⚠️ Incompleto (6 vars) | Atualizado |
| Documentação de deploy | ❌ Não existia | Criada |

### Corrigido

**`backend/app/core/config.py`**
- Adicionado `CORS_ALLOWED_ORIGINS: str` — lista separada por vírgula, default `localhost:3000`
- Adicionado `@property cors_origins` — parseia string → `list[str]`
- Adicionado `@model_validator` — levanta `ValueError` se `APP_ENV=production` e `SECRET_KEY` ainda for o valor padrão dev

**`backend/app/main.py`**
- CORS usa `settings.cors_origins` em vez de lista hardcoded

**`backend/.env.example`**
- Reescrito com todas as 18+ variáveis documentadas: `DATABASE_URL`, `REDIS_URL`, `SECRET_KEY`, `CORS_ALLOWED_ORIGINS`, `ACCESS_TOKEN_EXPIRE_MINUTES`, `OPENAI_*`, `WHATSAPP_*`, `META_APP_SECRET`, worker settings

### Criado

**`backend/scripts/create_tenant_admin.py`**
- Bootstrap idempotente de tenant + admin para produção
- Aceita parâmetros via CLI (`--tenant-name`, `--schema-name`, `--admin-email`, `--admin-password`) ou variáveis de ambiente (`BOOTSTRAP_*`)
- Não contém senha hardcoded
- Valida: parâmetros obrigatórios, senha mínima de 8 chars
- Retorna mensagens claras em caso de duplicidade (idempotente)
- Comando: `cd backend && python -m scripts.create_tenant_admin --tenant-name "..." --admin-email "..." --admin-password "..."`

**`docs/deploy/producao-controlada.md`**
- Arquitetura de produção (API + Worker + Frontend + Nginx + PostgreSQL + Redis)
- Dependências externas (PostgreSQL 14+, Redis 6+, OpenAI)
- Variáveis de ambiente documentadas
- Ordem de deploy (10 passos)
- Comandos para: migrations, bootstrap, API (uvicorn + systemd), worker (Python + systemd), frontend (Next.js build)
- Validação: healthcheck, login, comunicação frontend → backend
- Checklist completo antes da FASE 12.2
- Pendências de decisão (hosting, SSL, domínio, backup, monitoramento)

### Resultado

```
pytest        → 61/61 ✅
config.py     → settings carregam OK, cors_origins=['http://localhost:3000', ...] ✅
main.py       → import OK ✅
SECRET_KEY    → validação em production mode ativa ✅
CORS          → configurável via CORS_ALLOWED_ORIGINS ✅
```

**Credenciais dev** (inalteradas): `admin@teste.com` / `admin123` / tenant_id=1

### Próximos passos
- [ ] Provisionar VPS ou ambiente de produção (decisão pendente)
- [ ] Executar `alembic upgrade head` em PostgreSQL real
- [ ] Executar `scripts/create_tenant_admin.py` no ambiente de produção
- [ ] **FASE 12.2**: WhatsApp Cloud API real e teste ponta a ponta

---

## 2026-05-12 — Fase 11.9 — Estabilização da Integração Real Frontend ↔ Backend

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Diagnóstico

**Causa raiz do "Failed to fetch"**: banco SQLite não tinha as colunas da migração `1a2b3c4d5e6f` (`owner_type`, `owner_user_id`, `ai_paused`, `lead_temperature`, `conversation_summary` + tabela `conversation_assignments`). A migração falhava com `CircularDependencyError` no Alembic 1.18.4 — bug conhecido com `batch_alter_table` + `server_default`.

**Stack validada (nenhum problema encontrado):**
- CORS `http://localhost:3000` ✅
- `GET /conversations/inbox` e `GET /conversations/crm` — apenas `X-Tenant-ID`, sem Bearer obrigatório ✅
- JWT Bearer injetado por `apiClient.setAccessToken()` quando presente ✅
- `AuthGate` bloqueia children enquanto `isLoading=true` — sem race condition ✅
- Error messages já traduzidas em `client.ts` ✅

### Corrigido

**Backend:**
- Schema SQLite recriado via `Base.metadata.drop_all + create_all` (14 tabelas)
- Alembic estampado em `head` (`1a2b3c4d5e6f`)
- Tenant de teste inserido: `id=1, name="Tenant Teste"`
- Usuário admin inserido: `admin@teste.com` / `admin123`
- Dependências instaladas: `pip install -r requirements.txt` (`python-jose`, `bcrypt`)

**Frontend:**
- `frontend/.env.local` criado a partir de `.env.local.example`
- `ConversationList` — prop `totalCount` distingue inbox vazio de filtro-sem-resultado
- `CrmPage` — estado filtrado-vazio separado de CRM vazio (EmptyCrmState vs mensagem + "Limpar filtros")

### Resultado

```
POST /auth/token → JWT ✅
GET  /auth/me   → usuário real ✅
GET  /conversations/inbox → 200, items=[] ✅
GET  /conversations/crm   → 200, items=[] ✅
npm run build → 12/12 ✅ | TypeScript: 0 erros ✅
pytest        → 61/61 ✅
```

**Credenciais dev:** `admin@teste.com` / `admin123` / tenant_id=1

### Próximos passos
- [ ] Popular banco com dados de teste (contatos + conversas) para testar UI com dados reais
- [ ] Conectar KPIs reais no Dashboard
- [ ] Criar endpoint `PATCH /conversations/{id}/funnel-stage`
- [ ] Tela `/relatorios` com gráficos reais (RF-07)

---

## 2026-05-12 — Auditoria de Integração Frontend ↔ Backend

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Auditado
- `lib/api/client.ts`, `features/session/`, `features/conversations/`, `features/crm/`
- Todos os endpoints do frontend cruzados com `backend/app/api/routes/conversations.py`
- CORS, deps.py, schemas, tipos e mappers

### Resultado da auditoria
- **Endpoints**: todos corretos — `/conversations/inbox`, `/{id}/history`, `/{id}/crm`, `/conversations/crm`, handoff, messages
- **Auth**: `X-Tenant-ID` e `Bearer` injetados pelo `apiClient`; `AuthGate` previne race condition
- **CORS**: configurado para `localhost:3000` ✅
- **Tipos**: frontend ↔ backend compatíveis; mapper faz `funnel_stage ?? 'new'`

### Corrigido

1. **`frontend/.env.local.example`** — criado com `NEXT_PUBLIC_API_BASE_URL`, `NEXT_PUBLIC_TENANT_ID`, `NEXT_PUBLIC_AUTH_REQUIRED` documentados; devs precisam copiar para `.env.local`

2. **`lib/api/client.ts` — mensagens de erro traduzidas**:
   - "Failed to fetch" → "Servidor indisponível (url). Verifique se o backend está em execução."
   - HTTP 400/401/403/404/422/5xx → mensagens em português
   - Centralizado nas funções `resolveNetworkErrorMessage` e `resolveHttpErrorMessage`

3. **`features/session/auth-service.ts`** — `API_BASE` agora faz `.replace(/\/+$/, '')` (consistência com `client.ts`); comentário documenta que é fetch direto por ser pré-sessão (sem tenant header)

**Build**: 12/12 ✅ | TypeScript: 0 erros ✅

### Próximos passos
- [ ] Criar `.env.local` local com `NEXT_PUBLIC_TENANT_ID=<id real do tenant no banco>`
- [ ] Subir backend + frontend e testar fluxo real: login → conversas → CRM
- [ ] Conectar KPIs reais no Dashboard

---

## 2026-05-12 — Fase 11.4 — Refatoração Frontend Operacional

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito

**Design System (globals.css)**
- Paleta oficial Resolutiva aplicada: Azul Profundo #163B7A, Azul Tech #0078D4, Ciano #00A8CC, Verde IA #35C759
- Background mudado de branco puro → Cinza Cloud #F5F7FA (workspace feel)
- Bordas → Cinza Interface #D9E1EA
- `--radius` reduzido 0.625rem → 0.5rem (mais enterprise)
- Sidebar dark navy enterprise: `--sidebar` = oklch(0.235 0.095 258) ≈ #163B7A

**Sidebar**
- Fundo dark navy (antes: branco) — estilo Linear/Vercel
- Logo "R" corrigido para `bg-action` (Azul Tech) — visível sobre fundo dark
- Nav items com `rounded-md`, sem shadow, active usa `bg-sidebar-primary` (Azul Tech)
- Texto dos itens inativos levemente opaco (`/80`) para criar hierarquia
- Altura do logo alinhada com header: h-11

**Layout Global**
- Header: h-14 → h-11, border mais definida
- PageSurface: p-6/gap-4 → p-4 lg:p-5 / gap-3, heading text-2xl → text-lg

**Dashboard**
- Substituído layout placeholder por central operacional real:
  - KPI strip compacto (4 métricas)
  - Funil operacional com os 9 estágios oficiais (barra de progresso)
  - IA Status (respondidas, handoffs, avg. resposta)
  - Alertas operacionais (follow-ups vencidos, aguardando humano, sem resposta >24h)
  - Quick nav para módulos principais

**Conversas (Cockpit)**
- Painel esquerdo: w-80 → w-72 (mais espaço para chat)
- Painel direito: "Contexto" → "Inteligência" com painel rico:
  - Funil progress bar visual (estágios oficiais)
  - Sinais IA: buy signal, handoff, risco como chips de estado
  - Próxima ação destacada com ícone Zap
  - Temperatura ao lado do estágio do funil
- List item: mais compacto (2 linhas vs 4), dot de status inline com nome

**CRM**
- Header compactado (py-4 → py-2.5), botões menores (h-8 → h-7)
- Padding do pipeline reduzido (px-6 → px-4)

**IA**
- Removido max-w-3xl constraint (mais densidade)
- Header compactado, ícone usa `bg-action/10 text-action`
- Disclaimer reduzido

**Build**: 12/12 páginas ✅ | TypeScript: 0 erros ✅

### Próximos passos
- [ ] Conectar KPIs reais no Dashboard (GET /crm/leads, GET /conversations)
- [ ] Refinamento dos kanban cards do CRM (temperatura, sinais)
- [ ] Tela Relatórios com gráficos reais (RF-07)
- [ ] Ajuste de fontes e typography scale (Inter ou Geist)

---

## 2026-05-12 — Sincronização vault Obsidian

**Sessão**: Claude Code (organização)
**Duração aprox**: 15min

### Feito
- Renomeado `whatsapp-bot` → `SaaS-Resolutiva` no vault
- Reescritos SPEC, CONTEXTO, ARQUITETURA e PROGRESSO com estado real do projeto
- Criado `CLAUDE.md` no repo para priming rápido de sessões futuras

### Próximos passos
- [ ] Decidir próxima fase (Fase 12): relatórios reais, endpoints faltantes, ou infra de produção

---

## 2026-05-06 — Fase 11.8 — Integração Login Real no Frontend ✅

**Sessão**: Claude Code
**Branch**: `fase-11-frontend-operacional`

### Feito
- `features/session/auth-service.ts` — funções puras: `loginRequest`, `fetchCurrentUser`, `saveToken`, `loadToken`, `clearToken`
- `lib/api/client.ts` — `setAccessToken()` + injeção `Authorization: Bearer` automática
- `session-context.tsx` — bootstrap com localStorage → `GET /auth/me`; `login()` no contexto; fallback dev preservado
- `auth-gate.tsx` — proteção ativa: redireciona para `/login` quando `!isAuthenticated && !isLoading`
- `app/(auth)/login/page.tsx` — formulário real com estado de loading e erro
- `app/(dashboard)/layout.tsx` — envolvido com `<AuthGate>`
- Build: 12/12 páginas ✅ | lint: 0 erros, 0 warnings

### Decisões
- `localStorage` para dev/MVP (sem infra adicional); cookie httpOnly é o alvo de produção — ver ADR-004
- Fallback dev preservado: sem `NEXT_PUBLIC_AUTH_REQUIRED`, `AuthGate` não bloqueia

---

## 2026-05-06 — Fase 11.7 — Autenticação Real no Backend ✅

### Feito
- `app/core/security.py` — verify/hash password, create/decode JWT
- `app/schemas/auth.py` — `TokenRequest`, `TokenResponse`, `UserInToken`
- `app/api/routes/auth.py` — `POST /auth/token`, `GET /auth/me`, `get_current_user`
- `requirements.txt` — `python-jose[cryptography]` + `bcrypt`
- 61/61 testes passando

### Decisões
- `bcrypt` direto sem `passlib` (incompatibilidade bcrypt ≥4.0) — ver ADR-002
- Login JSON, não form-data OAuth2 — ver ADR-001

---

## 2026-05-06 — Fase 11.6 — Sessão e Tenant Dinâmico ✅

### Feito
- `features/session/` — `SessionProvider`, `useSession()`, `AuthGate`, `dev-config.ts`
- `lib/api/client.ts` — removido `X-Tenant-ID` hardcoded; `setTenantId()` dinâmico
- `header.tsx` — exibe tenant name e iniciais do usuário via `useSession()`
- `app/(auth)/login/` — route group sem AppShell + página visual

---

## 2026-05-06 — Fases 11.1 a 11.5 — Frontend Operacional ✅

**11.1 — Foundation Visual**
- Tema oklch Resolutiva, sidebar collapsível hover/pin, header, app-shell, 11 rotas

**11.2 — Conversas Operacional**
- Layout 3 colunas (lista | chat | contexto/IA/CRM), hooks reais, handoff, mensagem humana

**11.3 — CRM com Funil Kanban**
- Kanban 9 colunas, 6 KPIs computados client-side, painel slide-in de detalhe do lead

**11.4 — Central de IA**
- 5 tabs (Personalidade, Regras, Base de Conhecimento, Handoff, Segurança); mock isolado

**11.5 — Configurações Operacionais**
- 7 seções; `GET /tenants/` real para nome da empresa + mock isolado para o resto

---

## Backlog (não datado)

### Backend — endpoints faltantes
- [ ] `GET /ai-config` + `PATCH /ai-config`
- [ ] `GET /knowledge/documents` + `POST`
- [ ] `GET /users?tenant_id=X` (equipe por tenant)
- [ ] `PATCH /settings/attendance` + `PATCH /settings/notifications`
- [ ] `GET /whatsapp/status`
- [x] `PATCH /conversations/{id}/funnel-stage` — concluído Fase 18B
- [ ] `GET /auth/me` retornar `schema_name`

### Frontend
- [ ] Tela `/relatorios` com gráficos reais
- [ ] Polling ou WebSocket para conversas em tempo real
- [ ] Deep link `/conversas?id=X` (pré-selecionar do CRM)
- [ ] Badge de não-lidas no inbox

### Produção
- [ ] Cookie httpOnly (substituir localStorage)
- [ ] Refresh token + expiração automática
- [ ] Recuperação de senha / convite de usuário
- [ ] RBAC completo (além de `is_admin`)
- [ ] MFA
- [ ] Deploy VPS + infra (nginx/caddy, SSL, systemd)
