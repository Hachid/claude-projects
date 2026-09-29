# SaaS Resolutiva — SPEC

**Status**: 🟢 ativo
**Repo**: local — `C:\Projetos\saas_automacao_base`
**Branch principal**: `main` | Branch atual: `fase-11-frontend-operacional`
**Owner**: Hachid
**Última revisão**: 2026-05-22

## Problema
Empresas perdem leads e demoram demais para responder clientes no WhatsApp. Atendimento humano 24/7 é caro e inconsistente. A Resolutiva resolve isso com IA + handoff inteligente em uma plataforma SaaS multitenancy.

## Objetivo
SaaS operacional multi-tenant onde cada empresa cliente tem:
- IA conversando autonomamente no WhatsApp (e futuramente outros canais)
- CRM com funil de vendas kanban
- Handoff humano quando necessário
- Painel operacional completo (dashboard, configurações, relatórios)

## Requisitos funcionais

### Concluídos
- [x] **RF-01**: Backend FastAPI multitenancy com JWT auth
- [x] **RF-02**: WhatsApp inbound/outbound via Meta webhook (HMAC-SHA256 validado)
- [x] **RF-03**: Worker de mensagens com retry e status tracking
- [x] **RF-04**: CRM com funil de vendas kanban e handoff IA ↔ humano
- [x] **RF-05**: Frontend operacional completo (14 telas) com design premium
- [x] **RF-06**: Autenticação real JWT + sessão persistida + recuperação de senha
- [x] **RF-10**: RBAC completo — roles superadmin/admin/vendedor; endpoints /users; Configurações > Usuários e Permissões

### Pendentes
- [ ] **RF-07**: Relatórios com gráficos reais (funil, conversão, volume)
- [ ] **RF-08**: Configurações PATCH reais (atendimento, notificações, WhatsApp)
- [ ] **RF-09**: Base de conhecimento (`GET/POST /knowledge/documents`) conectada ao frontend
- [ ] **RF-11**: Omnichannel real — Instagram, TikTok, website chat (Prompt Whats 3+)
- [ ] **RF-12**: Multi-tenant real por ChannelIntegration (sem DEFAULT_TENANT_ID)

## Requisitos não-funcionais
- **Auth**: JWT Bearer + localStorage (dev); cookie httpOnly (produção)
- **Multitenancy**: schema-based (schema_name por tenant no Postgres)
- **Omnichannel**: arquitetura preparada — ChannelIntegration + IncomingMessageDTO + providers
- **LGPD**: dados ficam no servidor próprio; retenção a definir
- **Disponibilidade**: 99% | Produção: actaresolve.com.br (VPS Hostinger)

## Fora de escopo (fase atual)
- MFA
- Relatórios analíticos avançados
- App mobile
- Instagram/TikTok/website chat (estrutura criada, integração real: Fase 3+)

## Critérios de aceite por fase (histórico resumido)

| Fase | Status | Resumo |
|---|---|---|
| 11 (Frontend operacional) | ✅ | 12 telas, JWT real, sidebar dark navy |
| 12.1 (Produção controlada) | ✅ | CORS configurável, SECRET_KEY, bootstrap script |
| 12.2 (Deploy scripts) | ✅ | Procfile, start scripts, docker-compose |
| 12.3 (WhatsApp real) | ✅ | HMAC-SHA256, 14 testes webhook |
| 13 (Docker VPS) | ✅ | Dockerfiles, docker-compose.prod.yml, deploy.sh |
| 14 (Correção audit_log migration) | ✅ | Tipos de FK corrigidos |
| 15 (Correção migration PostgreSQL) | ✅ | batch_alter_table removido |
| 16 (RBAC completo) | ✅ | 101 testes, /users endpoints, esqueci/redefinir senha |
| 17 (Cockpit conversas Gemini) | ✅ | Layout 3 colunas redesenhado |
| 18 (CRM redesign Gemini) | ✅ | Kanban + lista + drawer premium |
| 18B (CRM backend funcional) | ✅ | funnel-stage, crm-data, notes endpoints |
| 19 (Módulo Equipe redesign) | ✅ | 6 KPIs, drawer, ranking, distribuição |
| 20 (Fundação Omnichannel) | ✅ | ChannelIntegration, ChannelIntegrationService, providers |
| 21 (Mensagem Universal) | ✅ | IncomingMessageDTO, WhatsAppPayloadAdapter, MessageIngestionService |

## Próximas fases (Prompt Whats roadmap)

**Fase 22 — Prompt Whats 3**: (a definir pelo prompt)

**Débitos técnicos críticos:**
- Unique constraint de Message: `(tenant_id, external_message_id)` → avaliar `(tenant_id, channel, external_message_id)` quando Instagram vier
- `ALLOW_DEFAULT_TENANT_FALLBACK=false` em produção multi-tenant real
- Cookie httpOnly (substituir localStorage)
- Refresh token + expiração automática
- Redis para tokens de reset de senha (hoje em memória)
- Invitar usuário por e-mail (SMTP configurado com Resend)
