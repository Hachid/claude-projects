# Sistema GAEP — SPEC

**Status**: 🟢 ativo
**Repo local**: `C:\Projetos\Sistema_GAEP_Claude_designer`
**Repo remoto**: <preencher: github.com/...>
**Owner**: Hachid
**Cliente / Unidade piloto**: GAEP-CAT — Catanduvas/PR
**Última revisão**: 2026-05-06

## Problema
A unidade GAEP-CAT (Polícia Militar) precisa de um sistema mobile-first para que operadores registrem atividades, gestores acompanhem efetivo e desempenho, e a corporação tenha rastreabilidade auditável de horas, missões e diárias — substituindo planilhas e formulários manuais.

## Objetivo
Entregar um app web mobile-first (PWA-ready) que cobre 6 fluxos completos (Login, Relatório, Painel BI, Desempenho Individual, Missões, Gestão) com **fidelidade pixel-perfect** ao protótipo de design aprovado, rodando em Next.js 15 + Supabase, e implantar a v1 na unidade piloto GAEP-CAT.

## Requisitos funcionais

- [ ] **RF-01 — Login**: autenticação por matrícula (`{matricula}@gaep.internal` no Supabase Auth), sessão sem expiração configurada no Supabase, redirect para `/relatorio`.
- [ ] **RF-02 — Relatório de Operação**: registrar data/horários, categoria/atividade dependentes, equipe (chips toggler com TODOS), até 3 fotos no Storage, descrição com microfone (Web Speech API) e revisão por IA.
- [ ] **RF-03 — Painel BI**: KPIs grandes + cards por categoria, donut, ranking de barras horizontais, evolução mensal multi-linhas (Recharts) com filtros 3m/6m/12m/total.
- [ ] **RF-04 — Desempenho Individual**: seleção de operador, KPIs (missões + carga horária), gráficos por categoria, **FolhaPonto** com múltiplas atividades por dia e total geral.
- [ ] **RF-05 — Missões (Diárias)**: cadastro com snapshot de valor unitário, ranking consolidado em accordion editável, soft delete por missão.
- [ ] **RF-06 — Gestão**: tabs por perfil (Efetivo, Atividades, Feriados, Config IA, Diárias; +GAEPs para SUPER_ADMIN), CRUD com soft delete e perfis com tags coloridas.

## Requisitos não-funcionais

- **Mobile-first**: viewport alvo 375–430px; touch targets ≥ 44px.
- **Acessibilidade**: contraste mínimo AA com a paleta dos design tokens.
- **Auditoria**: nunca DELETE físico — sempre `deleted_at`.
- **Histórico financeiro**: alterações em valor de diárias **não retroagem** (snapshot em `valor_unitario_snapshot`).
- **Observabilidade**: Sentry no frontend e backend (já em dependências).
- **Geração de PDF/imagens**: server-side via `playwright-core` + `@sparticuz/chromium` + `sharp` (folha-ponto, relatórios exportados).
- **Privacidade**: dados de servidores municipais; respeitar LGPD; sem envio para terceiros além de Supabase + provedor de IA do `Config IA`.

## Fora de escopo (v1)

- Apps nativos (iOS/Android) — só web/PWA.
- Multi-tenant transparente (SUPER_ADMIN gerencia GAEPs, mas onboarding de novos GAEPs ainda manual).
- Integração com sistemas externos da PM (somente exportação CSV/PDF).
- Notificações push.

## Critérios de aceite

- 6 etapas implementadas e com fidelidade visual ao protótipo `handoff/design/GAEP Prototype.html`.
- Schema Supabase aplicado a partir de `handoff/sql/001_schema.sql` + seed (`002_seed.sql`).
- Login funcional com 1 operador admin de teste.
- 1 relatório real registrado com IA + foto + descrição salvos.
- Folha-Ponto exportável (PDF) bate com somatório esperado.
- Vitest verde nas suítes existentes; sem `any` no código novo.
- Deploy em ambiente acessível à equipe da GAEP-CAT para validação.
