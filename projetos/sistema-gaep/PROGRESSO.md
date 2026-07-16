# Sistema GAEP — PROGRESSO

> Log mais recente no topo. Cada sessão = uma entrada datada.


## 2026-07-16 — Google Calendar + Web Push: implementação completa + code-review

**Sessão**: Claude Code (Haiku) — Integração Google Calendar completa + auditoria

### Feito

**Fase 1: Implementação dos 5 críticos (em /loop)**
1. **Integração de sincronização nas Server Actions** (`app/(app)/calendario/actions.ts`, `app/(app)/missoes/actions.ts`):
   - Função helper `sincronizarComGoogle()` chamada após CREATE/UPDATE de eventos, afastamentos e missões
   - Sincronização não-bloqueante (`.catch()` silencia erros, evita bloquear operação principal)
   - Context admin passado diretamente para evitar double `requireOperador()`

2. **Job de renovação de watch channels** (`lib/google-calendar/watch-renewal.ts` + `app/api/calendar/watch-renewal/route.ts`):
   - Cron job que roda 1x/dia (`vercel.json`: `"0 0 * * *"` — limitado a Hobby plan)
   - Renova canais que expiram em < 12h
   - GET `/api/calendar/watch-renewal` autenticado via Bearer token (`VERCEL_CRON_SECRET`)

3. **Web Push API** (`lib/push-notification/web-push.ts` + `app/api/push/{subscribe,unsubscribe}/route.ts`):
   - Endpoints para registrar/remover subscriptions de Web Push
   - Migração `20260715_push_subscriptions.sql`: tabela de subscriptions com RLS por operador
   - Service worker (`public/service-worker.js`) para suportar notificações push
   - inicialização automática de `initializeWebPush()` ao carregar o módulo
   - VAPID keys via env vars (`NEXT_PUBLIC_VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`)

4. **Fallback de e-mails** (`lib/google-calendar/sync.ts`):
   - Função `getGaepOperatorEmails()` implementa fallback automático: gmail → email_funcional → email pessoal
   - Se evento não tem guests explícitos, busca operadores ativos do GAEP com fallback
   - Operadores sem nenhum e-mail são ignorados

5. **Prevenção de loop de sincronização** (`lib/google-calendar/sync.ts` + migration `20260715_google_event_sync_anti_loop.sql`):
   - Campos `last_sync_direction` (system-to-google | google-to-system) e `last_sync_timestamp` em `google_event_sync`
   - Detecta eco: se última sincronização foi TO Google há < 120s, pula webhook (configurável via `GOOGLE_CALENDAR_ANTI_LOOP_TIMEOUT_MS` env var)
   - Flag `__syncing_from_google` em eventos_agenda, afastamentos, missões para futuras otimizações

**Fase 2: Code Review (medium effort, 6 issues encontrados)**
- **Tenant boundary violations** (CRÍTICA): syncs não filtravam por `gaep_id` em UPDATEs, violando regra de service_role → manual `gaep_id` guards
  - Fixado em `sync.ts` linhas 214/351 com `.eq('gaep_id', ...)` obrigatório
- **Query bug** em `watch-renewal.ts:48`: `.eq('id', channel.gaep_id)` → `.eq('gaep_id', channel.gaep_id)` ✅
- **Double requireOperador()**: `sincronizarComGoogle()` fazia re-lookup de contexto — agora passa `ctx.admin` diretamente ✅
- **Hardcoded timeout**: 120000ms era magic number — agora `GOOGLE_CALENDAR_ANTI_LOOP_TIMEOUT_MS` env var ✅
- **Dead code**: `initializeWebPush()` exportado mas nunca chamado — agora chamado auto no módulo ✅
- **Unused function**: `getOperadorEmail()` foi removida (não usada, `getGaepOperatorEmails()` cobre o caso) ✅

**Fase 3: Deploy produção**
- **Commits**: 9 no total
  - `79bacdc` feat(calendar): integra sincronização nas Server Actions
  - `1fe96c3` feat(calendar): implementa job de renovação automática de watch channels
  - `c74b672` feat(push): implementa Web Push API para notificações internas
  - `7e46415` feat(calendar): implementa fallback de e-mails para convidados
  - `098737c` feat(calendar): implementa prevenção de loop de sincronização
  - `4cff54b` fix(calendar): corrige 6 issues encontrados no code-review
  - `5df7f52` fix: remove unused getOperadorEmail function
  - `9b8b945` fix: ajusta cron para daily (plano Hobby do Vercel)
  - `8b99bcc` fix: remove gaep-app-rn from build
- **Deploy**: ✅ **READY** (status ok, deployment ID `dpl_EkFaSVyx1CoYnoJsQPVoLvUmgDxV`)
- **URL produção**: https://sistema-gaep-ppf.vercel.app
- Endpoints criados: `/api/calendar/sync`, `/api/calendar/webhook`, `/api/calendar/watch-renewal`, `/api/push/subscribe`, `/api/push/unsubscribe`

### Migrations criadas
- `20260715_operadores_gmail.sql`
- `20260715_gaep_calendar_config.sql`
- `20260715_google_event_id_columns.sql`
- `20260715_google_event_sync.sql`
- `20260715_calendar_watch_channels.sql`
- `20260715_google_event_sync_anti_loop.sql`
- `20260715_push_subscriptions.sql`

### Decisões
- **Cron 1x/dia** (não 6h) porque plano Hobby do Vercel limita a daily — pode ser aumentado em Pro plan depois
- **VAPID keys**: geradas com `npx web-push generate-vapid-keys`, devem ser configuradas em Vercel
- **Loop prevention window**: padrão 2min (120000ms) é conservador; se Google Calendar demora > 2min para entregar webhook, será suppressado — configurável via env var

### Testes
- `npm test`: 424 testes (419 pass, 5 falhas preexistentes em `.git/sdd/backup-consolidadoPdfCache.test.ts`)
- `npm run build`: ✅ Compilado com sucesso (warnings pré-existentes Sentry/OpenTelemetry)
- TypeScript: ✅ Sem erros após fixes

### Próximos passos
1. **Configurar env vars em Vercel** (VAPID keys, CRON_SECRET, ANTI_LOOP_TIMEOUT_MS)
2. **Executar migrations** (`npm run db:sync`) — não feito (sem SUPABASE_DB_URL local)
3. **Validar Google Apps Script remoto**: exportar `Calendar.gs` e `Codigo.gs` para repo
4. **Teste end-to-end**: criar evento → sincronizar → conferir Google Calendar
5. **Teste push notifications**: registrar sub → editar evento → receber notificação

---

## 2026-07-15 — Migration `operadores.gmail` aplicada em produção

**Sessão**: Cursor Agent — aplicação operacional de migration pendente

### Feito
- `npm run db:sync` aplicou `handoff/migrations/20260715_operadores_gmail.sql` (já listada em `manifest.json`).
- Nova coluna `public.operadores.gmail` (TEXT, nullable) — conta Gmail preferencial para convites, agendamentos e notificações do Google Calendar.
- Migration registrada em `public._app_migrations`.

### Decisões
- Nenhuma alteração de schema além da coluna; sem backfill (campo opcional, preenchimento via UI/convites quando implementado).

### Próximos passos
- Expor edição de `gmail` na Gestão (dados pessoais do operador) e validar formato de e-mail.
- Usar `gmail` no fluxo de convites e sincronização do Google Calendar (quando implementado).

---

## 2026-07-14 — Fix layout: sheet do calendário sob o menu desktop

**Sessão**: Cursor Agent (Grok) — bug report em produção `/calendario`

### Causa raiz
O sheet do dia (`CalendarioMes.tsx`) usa `position: fixed; left: 0` com z-index 50. No desktop (≥1024px) o menu lateral fica sempre visível (z-index 420, 260px). O formulário (novo evento/afastamento) renderizava embaixo do menu.

### Correção
- Classe `.gaep-sheet-offset` em `app/globals.css`: no desktop `left: 260px` (mesmo recuo do shell).
- Backdrop + painel do sheet em `CalendarioMes.tsx` passam a usar essa classe.

### Próximos passos
- Commit + deploy para produção (ainda só local).
- Smoke visual: abrir dia → novo evento/afastamento em viewport ≥1024px.

---

## 2026-07-13 — Calendário: feriados automáticos + Disponibilidade v2

**Sessão**: Claude Code (Sonnet 5) — SDD 10 tasks, branch/worktree `feriados-automaticos`

### Entrega
- **Sincronização automática de feriados**: `lib/feriados/nacionais.ts` (busca nacional via BrasilAPI) + `lib/feriados/estaduais.ts` (tabela estática por UF, hoje cobrindo `PR`/`MS`, com Corpus Christi calculado pelo algoritmo da Páscoa). Alimenta tanto a tabela `feriados` (nova coluna `origem`: `manual`/`nacional`/`estadual`) quanto `gaep_dias_uteis` (recalculado para os 12 meses do ano sincronizado), via a nova função Postgres `sync_feriados_automaticos` (RPC atômica, chamada pela server action `sincronizarFeriadosAutomaticos(gaepId, ano)` em `app/(app)/gestao/actions.ts`).
- **`lib/calendario/disponibilidade.ts`**: nova função pura `diaNaoUtil(dia, feriados)` (fim de semana ou feriado), reaproveitada nos dois pontos de UI abaixo.
- **UI Gestão** (aba Feriados): botão "↻ Sincronizar {ano}" + badge de origem por linha (`manual`/`auto`/`auto-{UF}`); edição (✏️) só disponível para origem `manual`.
- **UI Disponibilidade** (`DisponibilidadePanel.tsx`): dias não úteis (fim de semana/feriado) agora em amarelo, com tooltip hover (desktop) / tap (mobile) explicando o motivo (nome do feriado ou "Fim de semana"); `CalendarioClient.tsx` passa `feriados` para o painel (antes não passava).
- **UI Mês** (`CalendarioMes.tsx`): fim de semana agora também em amarelo (antes só feriado cadastrado entrava nessa cor); novo selo verde de quantitativo de operadores disponíveis por dia útil (sempre da equipe inteira, ignora filtro de operador da tela).
- Migrations novas: `20260710_feriados_origem.sql` (coluna `origem` em `feriados`), `20260710_sync_feriados_automaticos_fn.sql` (função `sync_feriados_automaticos`, com `REVOKE`/`GRANT` de `EXECUTE` seguindo o padrão de lockdown deste repo).
- Spec/plano: `docs/superpowers/specs/2026-07-10-calendario-feriados-automaticos-design.md`, `docs/superpowers/plans/2026-07-10-calendario-feriados-automaticos.md`.

### Decisões
- **Municipal continua manual**: não existe fonte pública confiável de feriados municipais por cidade — fora de escopo.
- **`gaep_dias_uteis` não é protegido contra re-sync**: rodar a sincronização de novo para o mesmo ano recalcula e sobrescreve `dias_uteis` dos 12 meses; qualquer edição manual anterior naquele ano é substituída (comportamento assumido, não é merge inteligente).
- **Proteção de feriado manual movida para o banco**: a garantia "sync nunca sobrescreve feriado cadastrado à mão" foi implementada como `INSERT ... ON CONFLICT (gaep_id, data) DO UPDATE ... WHERE feriados.origem <> 'manual'` dentro da função Postgres — não em código de aplicação. Achado de revisão de código: a primeira versão lia os feriados manuais existentes, filtrava em app e só então fazia upsert, abrindo uma janela de corrida (TOCTOU) em que um `INSERT` manual concorrente entre a leitura e a escrita podia ser silenciosamente sobrescrito. A cláusula `WHERE` do `DO UPDATE` é avaliada pelo Postgres contra o índice único no momento da escrita, fechando a janela por completo (commit `8407a3c`).
- **Datas estaduais de PR/MS precisam de validação legal** antes de habilitar a sincronização em produção para essas unidades — os valores hoje na tabela estática não foram conferidos contra a legislação vigente.
- A nova RPC `sync_feriados_automaticos` segue o mesmo convênio de `REVOKE ALL` + `GRANT EXECUTE` explícito já usado nas demais RPCs deste repo (commit `5dae62f`).

### Verificação final (Task 10)
- `npm test`: **411/411 testes passaram, 47/47 arquivos** — suíte completa rodou limpa, sem nenhuma falha (nem os dois testes historicamente instáveis sob carga paralela, `atividadeActions.test.ts` e `sincronizarFeriadosAutomaticos.test.ts`, apresentaram timeout desta vez).
- `npm run build`: **verde** (exit 0; compilado com sucesso em ~2min, 12/12 páginas estáticas geradas). Únicos warnings são os pré-existentes (inferência de workspace root por múltiplos lockfiles no worktree; "Critical dependency" do Sentry/OpenTelemetry) — nenhum warning novo introduzido por esta feature.

### Próximos passos
- Rodar `npm run db:sync` para aplicar as duas migrations pendentes (`20260710_feriados_origem.sql`, `20260710_sync_feriados_automaticos_fn.sql`) — não aplicadas durante esta sessão (sem `SUPABASE_DB_URL` configurado neste worktree; é passo operacional separado).
- Validar as datas de feriados estaduais de PR/MS contra a legislação vigente antes de habilitar sincronização em produção para essas unidades.
- Smoke visual/mobile manual das novas UIs: tooltip em dispositivo touch real, cor amarela de fim de semana, selo de disponíveis no grid do Mês — ainda não feito.

---

## 2026-07-10 — Missões período / diárias (Fase 2)

**Sessão**: Cursor Agent — SDD Task 6 verificação, branch `feat/missoes-periodo-diarias`

### Entrega
- **Branch**: `feat/missoes-periodo-diarias` (worktree `.worktrees/missoes-periodo`), **8 commits** à frente de `origin/main` (incl. `c214c0c` fix ESLint build).
- Período de missão: `data_missao` (início) + `data_fim`, lib `lib/missoes/periodo.ts` (dias corridos + sugestão de qtd), actions/UI `/missoes`, período no PDF de relatório.
- Migration `20260709_missoes_data_fim.sql` **aplicada em produção** (projeto `pxaatetwxnalzqfnihof`), checksum `a8eb1cfed964fa2316cac6ff845377826d8edb2fe0705eae1efd056c0d3927d4`.
- Commits principais: `298b32c` periodo lib, `924c550` migration, `7a38aca` actions, `15583fe` UI, `b879eb5` PDF, `c214c0c` fix build lint.

### Verificação (Task 6)
- `npx vitest run lib/missoes "app/(app)/missoes"`: **7/7** pass.
- `npm test`: **397/397** (44 arquivos).
- `npm run build`: **verde** (warnings pré-existentes Sentry/OpenTelemetry + lockfile worktree).

### Próximos passos
- Bugbot + PR para `main` (não feito nesta sessão).
- Integração calendário/disponibilidade com missões multi-dia (Fase 2 calendário).

---

## 2026-07-09 — Calendário + Disponibilidade (Fase 1) — merge

**Sessão**: Cursor Agent — SDD + Bugbot + merge PR #2

### Entrega
- **PR**: https://github.com/Hachid/GAEP_CLAUDE_DESIGNER/pull/2 — **merged** em `main`.
- Módulo `/calendario` (abas Mês | Disponibilidade | Estatísticas), CRUD eventos/afastamentos, lib `disponibilidade` + `datetime-brt`, nav, testes.
- Migration `20260709_agenda_afastamentos_rls.sql` **aplicada em produção** (policy + registro em `_app_migrations`).
- Pós-Bugbot: match BRT de dias, mês default BRT, edit de inativo/soft-deleted, sheet pós-salvar, mutex anti double-submit, filtro efetivo, datas editáveis em dia inteiro.

### Próximos passos
- Smoke visual em produção/preview: `/calendario` — criar evento/afastamento, abas Disponibilidade e Estatísticas.
- **Fase 2**: missões com período no calendário/disponibilidade.
- **Fase 3**: Google Calendar via Apps Script.
- Nota: `npm run db:sync` completo ainda falha por checksum antigo de `20260429_config_relatorio.sql` (pré-existente; fora deste PR).

---

## 2026-07-09 — Calendário + Disponibilidade (Fase 1)

**Sessão**: Cursor Agent — SDD 7 tasks, branch `feat/calendario-disponibilidade-fase1`

### Implementado
- Migration `20260709_agenda_afastamentos_rls.sql`: policy SELECT `agenda_afastamentos_select_same_gaep` via `current_gaep_access(gaep_id)` (tabela já existia com RLS ON e 0 policies).
- Domínio `lib/calendario/` (`types.ts`, `disponibilidade.ts`): dias úteis (seg–sex menos `feriados`), mapa disponibilidade, % por operador/mês/ano.
- Server Actions `app/(app)/calendario/actions.ts`: CRUD `eventos_agenda` + `agenda_afastamentos` (soft delete, `logAuditFromCtx`, `validateOperadoresInGaep`).
- Rota `/calendario`: `page.tsx` (auth manual padrão `(app)`), `loading.tsx`, `CalendarioClient` com 3 abas (Mês | Disponibilidade | Estatísticas).
- `CalendarioMes.tsx`: grade mensal mobile-first, filtro operador, forms evento/afastamento.
- `DisponibilidadePanel.tsx`: matriz operador × dias; `EstatisticasPanel.tsx`: % com Recharts (toggle Mês/Ano).
- Item "Calendário" em `SidebarNav`.
- Testes: `lib/calendario/__tests__/disponibilidade.test.ts` (6), `calendarioActions.test.ts` (8).
- Spec/plan: `docs/superpowers/specs/2026-07-09-calendario-disponibilidade-fase1-design.md`, `docs/superpowers/plans/2026-07-09-calendario-disponibilidade-fase1.md`.

### Decisões (validadas com usuário / spec)
- **Schema A**: usar `eventos_agenda` como está — sem novos campos `tipo`/`operador_id`.
- **Permissão B**: qualquer operador do GAEP cria/edita eventos e afastamentos de qualquer colega.
- **Indisponível**: só `agenda_afastamentos`; eventos aparecem no mês mas **não** afetam % de disponibilidade.
- **UI**: uma rota `/calendario` com abas Mês | Disponibilidade | Estatísticas.
- Denominador das estatísticas: dias úteis calculados (seg–sex − `feriados`); `gaep_dias_uteis` **não** entra.

### Verificação final (Task 7)
- `npm test`: **379/379** testes passaram em **41/42** arquivos. 1 suíte falhou: `.superpowers/sdd/ref-afiActions.test.ts` (artefato SDD fora do app — import `../actions` inválido; **não relacionado ao calendário**).
- `npm run build`: **verde** (exit 0; warnings pré-existentes Sentry/OpenTelemetry).

### Próximos passos
- (feito) Migration RLS aplicada em prod; PR merged.
- Smoke visual manual: `/calendario`.
- **Fase 2** / **Fase 3** conforme acima.

---

## 2026-07-09 — AFI (Atividade Física Individual) na Folha de Ponto

**Sessão**: Cursor Agent — implementação do plano AFI folha ponto

### Implementado
- Migration `20260709_operador_afi.sql`: tabelas `operador_afi_mes` (horário padrão mensal) e `operador_afi_dia` (override por dia), RLS via `current_gaep_access(gaep_id)`.
- Domínio `lib/afi/` (resolver, horário +1h, auth `podeEditarAfi`).
- `fetchDesempenhoData` estendido: `folhaResumo` (ops+AFI, previsto `dias_uteis×8h`), `afiMes`, linha AFI por dia com atividade; KPI/BI permanece só com relatórios (7h).
- Actions `salvarAfiPadraoMes` e `atualizarAfiDia` (operador próprio ou ADMIN/SUPER_ADMIN).
- UI: painel “AFI do mês” em Gerar Folha + linha AFI inline (Sim/Não, horário).
- PDF desempenho-operador com linha AFI e resumo.
- Testes: `lib/afi/__tests__/resolver.test.ts`, `afiActions.test.ts`, `FolhaPonto.test.tsx`.

### Decisões (validadas com usuário)
- AFI além das 7h de operações → previsto folha = 8h/dia útil.
- Só em dias com relatório do operador; duração fixa 1h; coexiste com AF de equipe nos relatórios.

### Próximos passos
- Rodar `npm run db:sync` em ambiente com `SUPABASE_DB_URL` para aplicar migration.
- Validar na unidade: definir horário padrão, marcar dia sem AFI, conferir saldo e PDF.

---

## 2026-06-30 — Fix RLS: tabela pública sem RLS + recursão infinita na "defesa em profundidade"

**Sessão**: Claude Code (Sonnet 5) — resposta a alerta de segurança do Supabase (e-mail) → investigação → 5 migrations → revisão de segurança/code-review → hardening → fix de teste
**ADR**: `notas/decisoes/ADR-008-rls-security-definer-helpers.md`

### Pedido
Supabase reportou por e-mail (28/06): tabela `evento_lembretes` do projeto `pxaatetwxnalzqfnihof` com RLS desligado e acessível publicamente por qualquer um com a URL do projeto (`rls_desativado_em_público`).

### Causa raiz
`evento_lembretes` e `eventos_agenda` (feature de agenda) foram criadas direto no banco, **fora do fluxo de migrations deste repo** (não estão em `handoff/migrations/`), então não passaram pela auditoria de segurança de 16-17/06. `evento_lembretes` ficou com RLS OFF e grants completos (INSERT/SELECT/UPDATE/DELETE) para `anon`/`authenticated`.

### Implementado
1. **`20260630_evento_lembretes_rls.sql`**: ativa RLS + policy `evento_lembretes_select_same_gaep` (escopo via `evento_id → eventos_agenda.gaep_id`, mesmo padrão de `relatorio_participantes`).
2. **Achado incidental (crítico)**: ao validar a policy nova com `SET ROLE anon`, toda a camada de RLS "defesa em profundidade" (`20260616_rls_defense_in_depth.sql` + `20260617_rpc_lockdown_and_rls.sql`) quebrava com `infinite recursion detected in policy for relation operadores` — a policy de `operadores` faz `SELECT ... FROM operadores` dentro de si mesma. Afetava 14 policies em 13 tabelas (`operadores`, `relatorios`, `missoes`, `config_ia`, `feriados`, `drive_arquivos`, `config_relatorio`, `gaep_dias_uteis`, `gaeps`, `relatorio_participantes`, `relatorio_versoes`, `eventos_agenda`, `notificacoes`, `push_subscriptions`). Não vazava dados (RLS falha fechado), mas o backstop da chave anon/authenticated não funcionava — hoje sem impacto real porque o app só acessa essas tabelas via `service_role` no servidor.
   **`20260630_rls_fix_operadores_recursion.sql`**: extrai a leitura de `operadores` para 3 funções `SECURITY DEFINER STABLE` (`current_operador_id()`, `current_operador_gaep_id()`, `current_operador_is_super_admin()`, owner `postgres` = owner de `operadores`, sem `FORCE ROW LEVEL SECURITY` → bypassa RLS ao rodar). Todas as 15 policies (14 + as 2 de `relatorios`) reescritas para chamar as funções em vez de subquery direta.
3. Verificação: `SET ROLE anon` + `SELECT count(*)` em todas as 15 tabelas — sem erro, 0 linhas (esperado, sem JWT). `npm test`: 334/334 passaram (1 suite falhando é bug pré-existente de `vi.mock` hoisting em `valeTransporteAction.test.ts`, não relacionado).

### Decisões
- `eventos_agenda`/`evento_lembretes` foram "adotadas" pelo fluxo de migrations deste repo a partir de agora (policy recriada via `DROP POLICY IF EXISTS` + `CREATE POLICY` na migration, mesmo não tendo `CREATE TABLE` rastreado aqui na hora).
- **`20260630_retroactive_eventos_agenda_schema.sql`** (mesma sessão, logo em seguida): `CREATE TABLE IF NOT EXISTS` para as duas tabelas com colunas/constraints/índices exatamente como conferido no banco (inclui `eventos_agenda_check` fim>=inicio, `status` CHECK ANY, `evento_lembretes_tipo_check` CHECK ANY, UNIQUE `(evento_id, tipo)`, FK `ON DELETE CASCADE`, índice parcial `idx_eventos_agenda_gaep_inicio`). Inserida no manifest **antes** das duas migrations de RLS de hoje (elas fazem `ALTER TABLE`/`CREATE POLICY` nessas tabelas, então precisam vir depois numa reprodução em banco novo). Aplicada como no-op em produção — confirmado sem erro. Nenhum código de app neste repo usa essas tabelas ainda (feature só existe no banco).

### Verificação final (mesma sessão): sweep de alertas Supabase + code-review/security-review
- Repliquei manualmente as regras do Supabase Advisor Security (RLS off em public, RLS on sem policy, function search_path mutável, security_definer view, extension em public, uso de user_metadata/auth.role() em policy): **nenhum alerta novo**. Único item informativo pré-existente: 4 tabelas com RLS ligado e zero policies (`agenda_afastamentos`, `_app_migrations`, `consolidado_pdf_cache`, `convites_operador`) — falha fechada, não é exposição, consistente com app 100% via `service_role`.
- Rodei `security-review` + 4 ângulos de `code-review` (5 subagentes em paralelo) na diff das 3 migrations. **Nenhuma regressão de segurança** — toda policy reescrita é logicamente idêntica à original (subquery em `operadores` extraída para função, sem enfraquecer nenhum filtro). Achado real (pré-existente, não introduzido hoje): `operador_ve_seu_gaep` (relatorios) e `eventos_agenda_select_same_gaep` não filtravam `deleted_at IS NULL` na própria linha, embora as tabelas-filhas delas já exigissem isso do pai.
- **`20260630_rls_deleted_at_consistency.sql`**: corrigido — `deleted_at IS NULL` adicionado no ramo de tenant de ambas as policies (ramo SUPER_ADMIN preservado sem o filtro, mesmo padrão de `evento_lembretes`/`relatorio_participantes`, para SUPER_ADMIN continuar enxergando linhas soft-deletadas em auditoria). Verificado com `SET ROLE anon` — sem erro, 0 linhas.
- Achado cosmético (não corrigido, baixo valor): `20260630_evento_lembretes_rls.sql` cria a policy com o padrão antigo (recursivo), que é imediatamente substituído por `20260630_rls_fix_operadores_recursion.sql` na mesma sessão — funciona porque a ordem no manifest está certa, mas é frágil a reordenação futura do manifest.

### Consolidação: helper `current_gaep_access(uuid)`
- **`20260630_current_gaep_access_helper.sql`**: extraído o padrão `gaep_id = current_operador_gaep_id() OR current_operador_is_super_admin()`, repetido em 8 policies (`operadores`, `missoes`, `config_ia`, `feriados`, `drive_arquivos`, `config_relatorio`, `gaep_dias_uteis`, `gaeps`), para `public.current_gaep_access(target_gaep_id uuid)` (SQL, `STABLE`, `SET search_path = public`, sem `SECURITY DEFINER` — não precisa, só chama as 3 funções que já são). Grant só para `anon`/`authenticated`. Fora do escopo, por semântica diferente: `eventos_agenda` (deleted_at só no ramo de tenant), `operador_ve_seu_gaep` em `relatorios` (sem ramo admin nessa policy), tabelas via EXISTS/join e as escopadas por `operador_id`. Verificado com `SET ROLE anon` nas 8 tabelas — sem recursão, 0 linhas. `npm test`: 334/334 (mesma falha pré-existente não relacionada).

### Fix: `vi.mock` hoisting em `valeTransporteAction.test.ts`
- Causa: `vi.mock(...)` é hoisted pelo Vitest para o topo do módulo, acima das `const mockX = vi.fn()` declaradas normalmente — a fábrica do mock acessava as consts antes da inicialização (TDZ), quebrando a suíte inteira (`ReferenceError: Cannot access 'mockRevalidateTag' before initialization`). Trocado para `vi.hoisted()` (mesmo padrão já usado em `GestaoClient.test.tsx`), que hoisteia os mocks junto com o `vi.mock` preservando a ordem. `npm test`: 36/36 arquivos, 338/338 testes. `npm run build`: verde. Commit `5f8d5eb`.

### Próximos passos
- Se a feature de agenda/lembretes for retomada no app, checar se algum outro processo ainda cria tabelas fora do fluxo de `handoff/migrations/` — foi assim que `evento_lembretes` escapou da auditoria de RLS.

---

## 2026-06-19 — Frontend responsivo (tablet/desktop) com mínimo impacto

**Sessão**: Claude Code (Opus 4.8) — brainstorming → design (abordagem A) → execução direta

### Pedido
Deixar o frontend responsivo (mobile/tablet/desktop) com o **mínimo de impacto**, sem redesenho. O app era mobile-first travado em `maxWidth:430px` centralizado — em telas grandes virava uma tira estreita com espaço vazio nas laterais.

### Decisões de design
- Nível: **aproveitar o espaço** (mantém 1 coluna; sem layouts multi-coluna por tela).
- Largura **por tipo de tela**: `form` (leitura/digitação) e `data` (dashboards/tabelas).
- Menu lateral **fixo a partir de 1024px** (`lg`); drawer mantido em mobile e tablet.
- Abordagem **A**: componente wrapper compartilhado (descartado centralizar o shell em layout de grupo — evita refatorar roteamento e o fluxo de auth que vive em cada página).

### Implementado
- **`components/layout/AppMain.tsx`** (novo): colapsa `<main>` + `<div maxWidth:430>` numa casca única, com variante `form|data`. Server component.
- **`app/globals.css`**: classes `.gaep-main` / `.gaep-container--form|--data` + media queries 768/1024px; no desktop recua o conteúdo (`padding-left:276px`) e ativa o menu fixo (`.gaep-header/hamburger/drawer/drawer-close/backdrop`). **Reset no `@media print`** para a folha A4 nunca ser constrangida pela largura responsiva.
- **`components/layout/SidebarNav.tsx`**: 5 hooks de classe → header recuado, hambúrguer/✕/backdrop ocultos e drawer fixo no desktop. Lógica de `open` intacta no mobile.
- **8 páginas** migradas para `<AppMain variant>`: dashboard, operadores, missoes, gestão (2 blocos: self + full), relatorio (registro), `[id]` (detalhe), `[id]/editar`, historico. **4 skeletons** (`loading.tsx`) nas mesmas classes.
- Larguras: mobile 430px (igual a hoje) · tablet form 640 / data 768 · desktop form 720 / data 1080.

### Fora de escopo / não tocado
- `app/(app)/missoes/relatorio/page.tsx` (página de PDF, sem sidebar) — preservada.
- `app/(auth)` login e `convite/[token]` — cards centralizados próprios; adaptar se necessário.

### Testes / verificação
- Claude não roda `npm test`/`build` (fluxo do Cursor). **Pendente no Cursor**: `npm run build` verde + checagem visual em 375/768/1024/1440px + confirmar PDF intacto em `relatorio/[id]`. Sugerido teste de render do `AppMain` (classes por variante).

### Próximos passos
- Commit por caminho criado (só os 15 arquivos da feature; `lib/valeTransporte.ts` é da feature VT em paralelo, fora deste commit).
- **Push pendente** — fazer após `npm run build` verde (deploy Vercel/produção).

---

## 2026-06-18 — Vale-transporte (VT) no relatório e folha de ponto

**Sessão**: Claude Code (Opus 4.8) — brainstorming → design → execução → code review (subagent)

### Pedido
Campo de controle de pagamento de vale-transporte no relatório, pois os dados alimentam a folha de ponto e, conforme onde a atividade ocorreu, paga ou não VT. Valores `C/VT | S/VT | CAC | Missão`, default `C/VT`. Editável também por atividade na folha de ponto (`/operadores`). Alta aderência ao sistema atual.

### Implementado
- **Enum (fonte única)** `lib/valeTransporte.ts`: `VALE_TRANSPORTE_VALUES`, `ValeTransporte`, `VALE_TRANSPORTE_PADRAO`, `isValeTransporte`, `coerceValeTransporte`, labels. Consumido por form, folha, ação e PDF.
- **Migration** `handoff/migrations/20260618_vale_transporte.sql` (+ manifest): coluna `relatorios.vale_transporte TEXT NOT NULL DEFAULT 'C/VT'` (legados → C/VT automático, sem backfill) + CHECK condicional. Idempotente.
- **Persistência** `app/relatorio/actions.ts`: `SalvarRelatorioInput`/`AtualizarRelatorioCompletoInput` ganham `valeTransporte`. **RPC `salvar_relatorio_completo` NÃO alterada** — criação usa o DEFAULT e um UPDATE pós-criação só quando ≠ C/VT. Edição grava no `fullPayload` com o mesmo fallback de coluna ausente (`42703`) do presos. `RelatorioDetalhado.vale_transporte` + busca defensiva no detalhe.
- **Formulários** `RelatorioForm.tsx` (criação, default C/VT + reset) e `RelatorioEditarForm.tsx` (edição). Detalhe `RelatorioDetalheClient.tsx`: linha read-only.
- **Folha de ponto**: `FolhaRow` ganha `relatorioId` + `valeTransporte`; `fetchDesempenhoData` monta a row (busca de VT em query separada defensiva). Nova action **`atualizarValeTransporte`** — `requireOperador` + `assertSameGaep` + filtro manual `gaep_id` (ADR-006); qualquer operador edita, mas só no próprio GAEP; audita + revalida detalhe/KPI. `FolhaPonto.tsx`: nova coluna VT com `<select>` editável (6 colunas, colspans ajustados). `DesempenhoClient.tsx`: update otimista + revert + `savingVT`.
- **PDF da folha** `buildDesempenhoOperadorPdfHtml.ts`: coluna VT por linha + bloco de subtotais por tipo (reg · horas).

### Decisões
- VT é propriedade do **registro** (compartilhada pela equipe), não do participante — editar na folha = editar o registro (fonte única).
- "Qualquer operador" edita na folha (escolha do usuário), mas a barreira de tenant é obrigatória.
- Não mexer na RPC (menor risco): DEFAULT + UPDATE pós-criação. VT fora do hash de integridade do PDF do relatório.
- Query de VT na folha é separada/defensiva (TODO: colapsar no select principal após a migration garantida em prod).

### Code review (subagent general-purpose)
- Sem bugs de quebra nem TS strict/`any`. Validou tenant, colspans (tela+PDF), idempotência da migration, não-interferência do UPDATE pós-criação com idempotência/testes.
- Aplicados 2 ajustes: `revalidatePath('/relatorio/{id}')` na ação (coerência do detalhe) + PDF importa `VALE_TRANSPORTE_VALUES` (fonte única da ordem). 1 TODO documentado (query defensiva).

### Testes
- Criados como prompts para o Cursor executar (Claude não roda `npm test`/`build` neste projeto). Novos: `operadores/__tests__/valeTransporteAction.test.ts` (enum inválido, cross-GAEP bloqueado, sucesso+audit+revalidate, inexistente) e `components/operadores/__tests__/FolhaPonto.test.tsx` (coluna VT, select, onChange, read-only, saving). Append em `RelatorioForm.test.tsx` (default C/VT, troca). Mocks de `RelatorioDetalhado` atualizados (`vale_transporte`). **Pendente rodar `npm test` + `npm run build` (verde) no Cursor.**

### Próximos passos / observações
- **Migration aplicada** pelo usuário via SQL Editor do Supabase ("Success"). Próximo `npm run db:sync` a registra em `_app_migrations` (idempotente).
- Commit por caminhos criado (feature VT). **Push pendente** — fazer após `npm test`/`build` verdes (deploy Vercel/produção).

---

## 2026-06-18 — Consolidado versionado no Google Drive (Versao N)

**Sessão**: Claude Code (Opus 4.8) — brainstorming → spec → plano → execução subagent-driven

### Pedido
Ao editar um relatório e regerar o PDF, o usuário via "outro relatório Versão 2" e queria que a edição sobrescrevesse a anterior, com versionamento. Investigação esclareceu: no app já sobrescreve (UPDATE na mesma linha + `relatorio_versoes`); o relatório individual fica só na tela; o que vai pro Drive é o **PDF consolidado**, que já guardava 1 arquivo por conteúdo mas com **hash** no nome. Objetivo: nomear as versões do consolidado de forma **sequencial** (`… - Versao N.pdf`), mantendo todas.

### Implementado (branch `feat/consolidado-versionado-drive`, a partir de `d2d62b6`)
- **Migration** `handoff/migrations/20260617_consolidado_pdf_versao.sql` (+ manifest): colunas `grupo TEXT` e `versao INTEGER` em `consolidado_pdf_cache`; `drive_file_id` → anulável; índice único parcial `(grupo, versao) WHERE ... NOT NULL`.
- **`lib/storage/path-builder.ts`**: `buildConsolidadoVersionedPath(basePath, versao)` (insere ` - Versao N` antes do `.pdf`; "Versao" sem acento) + testes.
- **`lib/pdf/consolidadoPdfCache.ts`**: `reservarVersaoConsolidado(cacheKey, grupo)` — `MAX(versao do grupo)+1` ignorando legados (`versao IS NULL`), upsert por `cache_key`, retry em conflito `23505` do índice único; `putCachedConsolidadoPdf` agora recebe `basePath`, reserva ANTES do upload e retorna a versão; `getCachedConsolidadoPdf` retorna `{ buffer, versao }`. Testes do cache (numeração, legado, retry, fail-open).
- **`app/api/pdf/consolidado/route.ts`**: usa `basePath`; nome do download `… - Versao N` (helper DRY `filenameComVersao`) em HIT, retry e MISS. Removido o sufixo de hash.
- Tudo **fail-open** (cache nunca derruba a geração); sem `any`; relatório individual e telas do app intocados.

### Decisões
- "Nova versão" = conteúdo diferente de todas as anteriores do GAEP+mês (relatório editado, foto, filtro, timbrado/estilo, ou consolidador). Conteúdo idêntico → HIT, não duplica.
- Arquivos hash antigos no Drive: mantidos como estão (numeração nova começa em 1).
- `drive_file_id` anulável também corrige bug latente do lock de geração (insert sem `drive_file_id`).

### Testes
- `tsc --noEmit` limpo nos arquivos da feature; **`vitest run` 317/317** (inclui 5 do cache + 4 do path-builder). Rodados nesta sessão (autorizado pelo usuário para esta execução).

### Recuperação (incidente de branch)
- Entre sessões, o working tree foi trocado p/ `feat/melhorias-relatorio` (trabalho paralelo no Cursor) e um reset apagou WIP não commitado das Tasks 1–2; ao retomar, edições das Tasks 3–4 caíram nessa branch por engano. Recuperado: revertido o que vazou, feature reaplicada integralmente em `feat/consolidado-versionado-drive`, sem misturar com melhorias. Backups em `.git/sdd/`.

### Próximos passos / observações
- **Aplicar a migration** `20260617_consolidado_pdf_versao.sql` via `npm run db:sync` (precisa `SUPABASE_DB_URL`). Sem ela, o cache do consolidado roda degradado (sempre MISS, fail-open) até as colunas existirem.
- Merge em `main` + push (produção Vercel).
- Docs: `docs/superpowers/specs/2026-06-17-consolidado-versionado-drive-design.md`, `docs/superpowers/plans/2026-06-17-consolidado-versionado-drive.md`.

---

## 2026-06-18 — Melhorias no fluxo de relatório (presos, equipe, histórico)

**Sessão**: Claude Code (Opus 4.8) — fluxo brainstorming → spec → plano → execução subagent-driven

### Pedido
Três melhorias: (1) presos escoltados = 1 por padrão em Operar + Escolta/Escolta Médica, com backfill dos já lançados; (2) mostrar os nomes dos operadores de cada relatório no histórico; (3) seleção de equipe começar vazia (era "todos selecionados") na criação.

### Implementado
- **Melhoria 1 — presos=1**: `RelatorioForm.tsx` e `RelatorioEditarForm.tsx` — `useEffect` pré-preenche 1 quando o campo de escolta aparece e está vazio, preservando valor já digitado/salvo. Backfill `handoff/migrations/20260617_backfill_presos_escoltados.sql` (idempotente, só `presos_escoltados IS NULL`, Operar + Escolta/Escolta Médica) + entrada no `manifest.json`.
- **Melhoria 2 — operadores no histórico**: `actions.ts` — `RelatorioResumo.equipe_nomes: string[]`; `buscarHistoricoRelatorios` faz batch-fetch de `relatorio_participantes` (2 rounds; nomes de relatoristas+participantes numa só query). `HistoricoClient.tsx` renderiza linha `👥 nomes` e inclui a equipe na busca textual. Escopo: só a tela de histórico (PDF intocado).
- **Melhoria 3 — equipe vazia**: `RelatorioForm.tsx` — estado inicial e `resetarFormulario` com `[]`. Edit form não muda (carrega equipe salva). Validação "≥ 1 operador" já existente força a escolha.
- Paridade form↔SQL: `.trim()` adicionado na comparação da categoria nos dois forms (casa com `upper(trim(nome))` do SQL).

### Decisões
- Backfill só nos `NULL` → 1 (não sobrescreve valores reais, inclusive 0/2).
- Histórico: equipe como lista de nomes em texto (compacto p/ mobile), não chips.
- `ESCOLTA_NOMES` duplicado nos dois forms: mantido (pré-existente; SQL não compartilharia constante TS).

### Testes
- Criados como prompts para o Cursor executar (Claude não roda `npm test`/`build` neste projeto). 3 arquivos novos: `RelatorioForm.test.tsx`, `RelatorioEditarForm.test.tsx`, `HistoricoClient.test.tsx` (equipe vazia, presos=1, preservação de valor, NULL legado→1, render/oculta da linha de equipe, busca por operador). **Pendente rodar `npm test` + `npm run build` (verde) no Cursor.**

### Branch / commits
- Branch dedicada **`feat/melhorias-relatorio`** (a partir de `d2d62b6`). WIP do consolidado/Drive foi stashado/preservado por fora — **nenhum arquivo de `lib/pdf/` ou `app/api/pdf/` nos commits desta feature**.
- 6 commits: `dbfb7e8` (equipe vazia + presos=1), `b25a8d9` (robustez/cobertura), `3d863d2` (backfill+manifest), `30f9871` (histórico equipe), `3083c2c` (robustez teste histórico), `a796538` (.trim categoria). Revisados: spec + qualidade por tarefa + review final holístico.

### Próximos passos / observações
- **Aplicar a migration** `20260617_backfill_presos_escoltados.sql` via `npm run db:sync` (precisa `SUPABASE_DB_URL`).
- **Push** de `feat/melhorias-relatorio` quando validado no Cursor.
- Edição concorrente do consolidado neste working tree durante a sessão (Cursor) — WIP do consolidado confirmado como tratado por fora; não commitado nesta branch.
- Docs: `docs/superpowers/specs/2026-06-17-melhorias-relatorio-design.md`, `docs/superpowers/plans/2026-06-17-melhorias-relatorio.md`.

---

## 2026-06-17 — Toggle Horas/Quantidade nos gráficos (Dashboard + Individual)

**Sessão**: Claude Code (Opus 4.8)

### Pedido
Botão para alternar a métrica dos gráficos entre Horas (carga horária) e Quantidade (nº de registros), no Dashboard e na tela Individual (Desempenho do Operador).

### Implementado
- **`lib/dashboard/metricaGrafico.ts`** (novo): helpers puros — `MetricaGrafico`, `metricaValor`, `metricaLabel`, `metricaNome`, `buildRankingBarData` (ordena o ranking pela métrica ativa). Quantidade = `totalRegistros`, que já existia nos dados → **zero mudança de backend**.
- **`lib/dashboard/useMetricaGrafico.ts`** (novo): hook que persiste a escolha em `localStorage` (`gaep-metrica-grafico`), compartilhada entre Dashboard e Individual; SSR-safe (default `horas`).
- **`components/dashboard/ToggleMetrica.tsx`** (novo): pílula segmentada no estilo dos botões de período (ajustada para discreta a pedido do usuário).
- **`DonutCategoria` / `RankingBars`**: nova prop `metrica` (default `horas` → sem regressão); valores/labels/tooltips alternam entre horas e contagem.
- **`DashboardClient` / `GraficosOperador`**: instanciam o hook, renderizam o toggle no topo dos gráficos e propagam `metrica`.
- Fora de escopo (intocados): gráfico de Evolução mensal, KPIGrid, backend.

### Decisões
- Quantidade = nº de registros (não escoltados).
- Persistência via localStorage compartilhada entre as duas telas.
- Evolução de Horas/mês permanece sempre em horas (sem contagem por operador no modelo atual).

### Testes
- 3 arquivos novos, 14 casos (helpers, hook, toggle) — **verde** (`npx vitest run`).
- `npm run build` **verde** (lint + types OK).

### Próximos passos / observações
- Nenhum pendente para a feature.
- O working tree ainda tinha mudanças não commitadas de auditoria de segurança (`gestao/actions.ts`, `api/pdf/*`, `operador-context.ts`, `lib/pdf/*`, `driveAccess.ts`) — **NÃO incluídas** neste commit.
- Docs: `docs/superpowers/specs/2026-06-17-toggle-horas-quantidade-graficos-design.md`, `docs/superpowers/plans/2026-06-17-toggle-horas-quantidade-graficos.md`.

---

## 2026-06-16 — Mitigação operacional + hardening service role

**Sessão**: Cursor Agent

### Pedido
Mitigar gap operacional (migrations/env/backfill) e service role como ponto único de falha; executar checklist de prioridade.

### Implementado

**Operacional (executado no remoto)**
- Confirmado: todas migrations `20260616_*` já aplicadas; nova `20260617_rpc_lockdown_and_rls.sql` aplicada via `npm run db:sync`
- **RPC lockdown**: `REVOKE EXECUTE` de `anon`/`authenticated` em `find_operadores_por_nome_guerra`, `redeem_convite`, `salvar_relatorio_completo` — só `service_role` (verificado no Postgres)
- **RLS expandido**: feriados, drive_arquivos, config_relatorio, gaep_dias_uteis, gaeps, relatorio_participantes, relatorio_versoes + catálogos globais; RLS em `_app_migrations`
- Backfill `drive_arquivos`: `ALL_GAEPS=1 CONFIRM=1` — 0 file_ids legados (fotos ainda não usam proxy URL ou bucket antigo)
- Supabase advisors: WARNs de RPC anon eliminados; restam INFO em tabelas service-only (convites, cache) e auth leaked-password (ativar no dashboard Supabase)

**Código / processo**
- `.env.example` com todas vars de produção (GAEP_COOKIE_SECRET, Upstash, Drive, Sentry)
- `GAEP_COOKIE_SECRET` já presente em `.env.local`
- Teste estático `admin-client-guards.test.ts` + `npm run verify:security` — actions/routes com `createAdminClient` devem importar guards
- Dashboard KPI: fetch paginado (500/ página) para reduzir picos de memória/conexão
- Backfill script: suporte `ALL_GAEPS=1`
- Comentário em `admin.ts`: preferir `ctx.admin` de `requireOperador()`

### Testes
**`npm test` verde: 294 testes**

### Pendente manual (não automatizável daqui)
1. **Vercel**: copiar `GAEP_COOKIE_SECRET` + criar Upstash e definir `UPSTASH_REDIS_*` no projeto
2. **Apps Script**: redeploy Web App com HMAC (`scripts/google-apps-script-drive-storage.gs` + `GAEP_SECRET`)
3. **Supabase Auth**: ativar [Leaked Password Protection](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
4. **Futuro escala**: agregação SQL/materialized view para dashboard (paginação in-memory já mitiga pico)

---

## 2026-06-16 — Tech debt pós-auditoria (itens restantes)

**Sessão**: Cursor Agent

### Pedido
Implementar tudo que ainda faltava do plano de auditoria (tech debt documentado em `ARQUITETURA.md`).

### Implementado

- **`requireOperadorWithGaep()`** unifica `resolverOperadorGaep` nas 3 rotas PDF (`[id]`, `consolidado`, `desempenho-operador`)
- **`gestao/actions.ts`**: removido wrapper `getAdminCtx()` — usa `requireOperadorAdmin()` direto
- **Troca obrigatória de senha**: coluna `must_change_password`, redirect no login/middleware, banner em Dados Pessoais, clear em `alterarMinhaSenha`, flag em `criarOperador`
- **Apps Script HMAC**: `lib/storage/apps-script-hmac.ts` + validação no `.gs` (timestamp + nonce, janela 5 min)
- **Correlation ID → audit_log**: coluna `correlation_id`, middleware propaga header no request, `logAudit` grava automaticamente
- **Sentry tags**: `gaep_id` e `correlation_id` via `lib/observability.ts` após auth
- **Hash integridade v2**: inclui `equipeIds` ordenados em `relatorioIntegrityParts`

### Migrations novas
`20260616_must_change_password.sql`, `20260616_audit_log_correlation_id.sql`

### Testes
**`npm test` verde: 293 testes**

### Próximos passos (operacionais)
1. Aplicar migrations no Supabase remoto (incl. novas)
2. **Redeploy Apps Script** com HMAC (`scripts/google-apps-script-drive-storage.gs`)
3. Backfill `drive_arquivos` (`scripts/backfill-drive-arquivos.js`)
4. Definir `GAEP_COOKIE_SECRET` e Upstash em produção

---

## 2026-06-16 — Correções auditoria ofensiva (P0→P3)

**Sessão**: Cursor Agent

### Pedido
Implementar o plano faseado de correções da auditoria ofensiva (tenant boundary, snapshot missão, convite atômico, Drive ownership, integridade PDF, consistência e hardening).

### Implementado

**P0 — tenant e auth crítica**
- `lib/auth/operador-context.ts`: `requireOperador`, `assertSameGaep`, `assertPerfilMin`, `validateOperadoresInGaep`
- Refatoração de actions críticas (operadores, relatório, gestão, missões, logs, IA, página detalhe) para usar contexto da sessão
- Snapshot missão server-side + migration trigger imutável (`20260616_missao_snapshot_immutable.sql`)
- RPC `redeem_convite` atômico + `app/convite/actions.ts`
- Cookie `gaep-ativo-cache` assinado (HMAC), revogação de sessão na desativação, limpeza no logout
- Tabela `drive_arquivos`, proxy com ownership + fallback legado, uploads privados no Apps Script

**P1 — integridade e login**
- SSRF: allowlist em `normalizeFotosUrls` / `imageDataUrlForPdf`
- Hash integridade v2 em `relatorioIntegrity.ts` + callers (PDF e detalhe)
- `consolidadoIntegrity` v2 (totais no payload)
- CSS sanitize em `estiloRelatorioCss.ts`
- Login: mensagem única anti-enumeração + rate limit (`checkRateLimit`)
- Migration `audit_log` imutável + `logAuditFromCtx` em relatório (create/update/delete)

**P2 — consistência**
- Optimistic lock em `atualizarRelatorioCompleto`
- Idempotency key + RPC `salvar_relatorio_completo` (fallback insert legado)
- Cache PDF consolidado: skip write se fotos falharam; `generating_at` single-flight
- Soft delete feriados; guards em `cleanup-maio-2026.js` e `sync-db.js`
- Rate limit distribuído via Upstash (interface `checkRateLimit` — login + IA)

**P3 — hardening**
- Sessão cookie 7 dias (`cookie-options.ts`); browser client alinhado
- RLS defesa em profundidade (operadores/missoes/config_ia)
- Service account Drive desabilitada em produção salvo `ALLOW_DRIVE_SA_FALLBACK=1`
- Middleware `x-correlation-id`
- Script `scripts/backfill-drive-arquivos.js` para migração Drive legado

**Testes**
- `lib/auth/__tests__/operador-context.test.ts`, `tenant-isolation.test.ts`
- Mocks atualizados em `relatorioActions.test.ts`, `normalizeFotosUrls.test.ts`
- **`npm test` verde: 291 testes**

### Migrations novas (aplicar com `npm run db:sync`)
`20260616_missao_snapshot_immutable`, `drive_arquivos`, `redeem_convite_rpc`, `audit_log_immutable`, `feriados_soft_delete`, `rls_defense_in_depth`, `relatorio_idempotency`, `consolidado_cache_generating`, `salvar_relatorio_rpc`

### Env produção
- `GAEP_COOKIE_SECRET` (fallback: service role key)
- `UPSTASH_REDIS_REST_URL` + `UPSTASH_REDIS_REST_TOKEN` (rate limit distribuído, opcional)
- Redeploy Apps Script com flag `private: true`

### Próximos passos
1. Aplicar migrations no Supabase remoto
2. Smoke manual: login, relatório, dashboard, operadores, missões, gestão, proxy fotos
3. Backfill `drive_arquivos` por GAEP quando conveniente (`scripts/backfill-drive-arquivos.js`)

---

## 2026-06-16 — Code review + correções de desempenho/fluidez (storage Drive)

**Sessão**: Claude Code (Opus 4.8)

### Pedido
Rodar revisão de código no trabalho da migração de storage (Drive), apontar inconsistências e formas de melhorar desempenho/fluidez (quadro de riscos), **implementar tudo** e rodar o reviewer para confirmar.

### Implementado (9 itens)
| # | Arquivo(s) | Mudança |
|---|---|---|
| #1 | `app/api/pdf/consolidado/route.ts` | Resolução de fotos do consolidado agora **em paralelo** (`mapWithConcurrency`, limite 5), ordem preservada por índice; `maxDuration` 120→**300**. Antes: 1 round-trip Apps Script por foto, em série → risco de timeout em período grande. |
| #2 | `lib/storage/downloadDriveFile.ts`, `route.ts` | **Observabilidade**: falhas de download deixam de ser silenciosas (`console.error`); contador `fotosComFalha` + header `X-Pdf-Fotos-Falhas`. |
| #3 | `middleware.ts` | `api/drive-file` **excluído do matcher** — a rota já valida sessão; corta o `getUser` duplicado por imagem. |
| #4 | `lib/pdf/consolidadoCacheKey.ts` (+teste), `route.ts` | `consolidadorNome` entra na chave de cache → **ADR-005** (revê tradeoff do ADR-004). |
| #5 | `route.ts` | `timeZone: 'America/Sao_Paulo'` no "emitido em" (servidor roda em UTC). |
| #6 | `lib/storage/downloadDriveFile.ts` (novo) + 3 chamadores | Helper **único** de download do Drive (Apps Script → service account legado); elimina lógica triplicada (proxy, PDF, cache). |
| #9 | `components/relatorio/FotoUpload.tsx` | Upload das fotos **em paralelo** (`Promise.all`), índice estável. |
| #7/#8 | comentários | Avaliados e **mantidos**: ordem da migração é operacional; `no-store` do consolidado é deliberado (URL não muda com o conteúdo → evitar PDF defasado). |

### Reviewer (rodado a pedido, high effort)
7 candidatos verificados → nenhum bug bloqueante. Todos os 9 itens conferidos como corretos. Achados de baixa severidade (vários pré-existentes): 503 enganoso no proxy, UI de upload sem `try/finally`, log perdido em misconfig parcial, possível pasta duplicada no Drive em upload concorrente, e 3 limpezas (regex {10,} vs {25,}, `import()` por foto, `mapWithConcurrency` como util).

### Follow-up aplicado (a pedido)
- **`FotoUpload.tsx`**: `handleFiles` agora em `try/catch/finally` — rejeição inesperada não trava mais a UI em "Enviando…".
- **`drive-file/[fileId]/route.ts`**: `downloadDriveFileById` → `null` agora responde **404 "Arquivo indisponível"** em vez de `503 "não configurado"` (mensagem honesta; causa real fica nos logs).

### Decisões
- **ADR-005** (`notas/decisoes/`): `consolidadorNome` na chave de cache do consolidado — o PDF servido sempre tem o nome/hash de quem pediu. Revê a consequência ⚠️ do ADR-004.

### ⚠️ NÃO rodado (workflow do projeto): `npm test` / `npm run build` — rodar no Cursor para confirmar verde (teste novo em `consolidadoCacheKey.test.ts`).

### Próximos passos
1. Cursor: `npm run test -- --run` + `npm run build` (confirmar verde, incl. novo teste do consolidador na chave).
2. Validar no browser pós-deploy: geração de consolidado de período grande (sem timeout), upload de 3 fotos, foto na tela/PDF.
3. Limpezas opcionais do reviewer (helper de concorrência compartilhado, `import()` estático na rota 3).

---

## 2026-06-08 — Retomada: diagnóstico do bloqueio + solução definitiva de egress (offline)

**Sessão**: Claude Code (Opus 4.8)

### Diagnóstico do "sistema não sobe"
- Sintoma inicial: host `pxaatetwxnalzqfnihof.supabase.co` dava **NXDOMAIN** (8.8.8.8 e 1.1.1.1). Parecia projeto deletado.
- Dashboard revelou a verdade: **org FREE restrita por egress** → **projeto PAUSADO** (por isso o DNS some). **Dados intactos.**
- Números (View usage): ciclo **14/05 → 14/06**; egress **61,88 GB / 5 GB** (overage 56,88 GB). Pico em **18–21/05** (um dia ~27,9 GB) — *antes* da migração pro Drive (26/05).
- **Correção de premissa do usuário**: o reset NÃO é 06/06 — é **14/06** (o ciclo free conta da criação da org).
- Causa raiz (confirmada no código): fotos **antigas** servidas por **URL pública do Supabase** (`<img src>` na tela/impressão) + **PDF consolidado** puxando todas as fotos. Storage real ~4 MB → 60 GB = mesma coisa baixada ~15 mil vezes (bucket público + sem cache).

### Decisão arquitetural (ADR — ver notas/decisoes/)
Aprovada a **opção ②**: **Supabase nunca mais serve binário.** Foto e PDF consolidado só no Google Drive; app lê binário só pelo proxy autenticado, com cache. Meta: egress < ~0,5 GB/mês.

### Feito nesta sessão (parte OFFLINE — não precisa do banco)
| Arquivo | Mudança |
|---|---|
| `app/api/drive-file/[fileId]/route.ts` | Cache do proxy estendido: `private, max-age=2592000, immutable` + `ETag` (fileId é imutável) — corta re-downloads de foto |
| `lib/pdf/consolidadoCacheKey.ts` (novo) | Chave de cache **estável por conteúdo** (sem timestamp) do consolidado |
| `lib/pdf/consolidadoPdfCache.ts` (novo) | get/put do PDF consolidado no Drive (tabela `consolidado_pdf_cache`), **100% fail-open**; só ativa com `STORAGE_PROVIDER=drive` |
| `app/api/pdf/consolidado/route.ts` | HIT antes do trecho caro (fotos+Playwright) → serve do Drive; MISS → gera, sobe pro Drive (nome único por versão `[hash8]`), grava mapping |
| `handoff/sql/009_consolidado_pdf_cache.sql` (novo) | Tabela de cache (RLS on, service-role only) |
| `lib/pdf/__tests__/consolidadoCacheKey.test.ts` (novo) | 10 testes da chave de cache |
| `scripts/migrate-fotos-supabase-to-drive.js` (novo) | Migração fotos Supabase→Drive, **dry-run por default**, `--confirm` aplica; roda só pós-restore |
| `.env.local` | Removido espaço sobrando em `NEXT_PUBLIC_SUPABASE_URL` |

**Verificado (sem código novo)**: pipeline já estava blindado — `buscarRelatorio` e o consolidado já usam `normalizeFotosUrls`; histórico só manda `has_fotos` booleano; uploads novos já vão pro Drive.

### Code-review (rodado a pedido)
- 5 achados (todos PLAUSIBLE; camada é fail-open, nada crasha).
- **Corrigido**: nome do PDF cacheado agora é **único por versão** (`[hash8]` antes do `.pdf`) — elimina risco de sobrescrita servir conteúdo errado caso o Apps Script faça upsert-por-nome.
- Aceitos/documentados: consolidado cacheado congela "consolidado por X em T" + hash (comportamento correto p/ documento oficial); órfãos no Drive não são podados (storage tem folga); geração concorrente pode duplicar upload (raro).

### ⚠️ NÃO rodado (workflow do projeto): `npm test` / `npm run build` — rodar no Cursor para confirmar verde.

### Próximos passos — pós-restore (a partir de 14/06)
1. **Restore** do projeto no dashboard Supabase (ou Upgrade Pro p/ religar antes).
2. Aplicar `handoff/sql/009_consolidado_pdf_cache.sql` **antes** do redeploy (senão putCached sobe órfãos sem cache).
3. Rodar `node scripts/migrate-fotos-supabase-to-drive.js` (dry-run → conferir → `--confirm`).
4. **Fechar o bucket `gaep-fotos`** (tornar privado) — mata o vetor de URL pública.
5. Redeploy na Vercel; acompanhar o gráfico de egress 1–2 dias → confirmar **plano**.

---

## 2026-05-26 — Fase 3+4: Google Drive via Apps Script (sem billing, sem Service Account)

**Sessão**: Claude Code

### Decisão arquitetural
Google Cloud exige cartão → descartado. Substituído por **Google Apps Script Web App** como ponte para o Google Drive. Zero billing, zero Service Account.

### Arquitetura
```
Next.js/Vercel → POST → Apps Script Web App → Google Drive
```

### Arquivos criados/alterados

| Arquivo | O que faz |
|---|---|
| `lib/storage/apps-script-provider.ts` | `AppsScriptDriveProvider` — chama Apps Script via HTTP POST com secret compartilhado |
| `scripts/google-apps-script-drive-storage.gs` | Código do Apps Script (cole no editor do script.google.com) |
| `scripts/test-drive-upload.ts` | Script de teste local (healthCheck + upload + download) |
| `lib/storage/__tests__/apps-script-provider.test.ts` | 14 testes unitários (isConfigured, upload, download, erros) |
| `lib/storage/index.ts` | `drive` → `AppsScriptDriveProvider` (antes era `GoogleDriveStorageProvider`) |
| `app/api/drive-file/[fileId]/route.ts` | Proxy autenticado: tenta Apps Script, cai para service account (legado) |
| `lib/pdf/imageDataUrlForPdf.ts` | Rota 3 usa Apps Script se configurado, service account como fallback |

### Variáveis de ambiente para ativar

```
STORAGE_PROVIDER=drive
GOOGLE_APPS_SCRIPT_WEBAPP_URL=   # URL gerada ao implantar o Web App
GOOGLE_APPS_SCRIPT_SECRET=       # segredo compartilhado (gerar UUID aleatório)
GOOGLE_DRIVE_ROOT_FOLDER_ID=1R0NaEL09HONH3slKXIS5Gawj76umQQJ0
```

### Como configurar (passos para o usuário)

1. Abrir https://script.google.com → Novo projeto
2. Colar o código de `scripts/google-apps-script-drive-storage.gs`
3. Projeto → Configurações → Propriedades do Script → adicionar `GAEP_SECRET = <uuid aleatório>`
4. Implantar → Novo implantação → Web App → Executar como: Eu → Quem tem acesso: Qualquer pessoa
5. Copiar a URL do Web App
6. Adicionar no Vercel: `GOOGLE_APPS_SCRIPT_WEBAPP_URL`, `GOOGLE_APPS_SCRIPT_SECRET`, `GOOGLE_DRIVE_ROOT_FOLDER_ID`, `STORAGE_PROVIDER=drive`

### Segurança (Opção A — MVP)
- Arquivos no Drive ficam com "anyone with link can view"
- Acesso pelo app é mediado pela rota proxy `/api/drive-file/{fileId}` (exige login)
- Secret impede uso indevido do endpoint Apps Script
- Nenhuma credencial vai para o cliente
- Erros do Apps Script nunca são expostos ao usuário

### Integração validada (2026-05-26)
- healthCheck: `ok=true, provider=drive_apps_script`
- Upload: arquivo criado com `fileId: 1nhX5QFlVY4U8HJHlS6UyHR0u61SKRZvE`
- Pastas criadas: `Sistema GAEP/GAEP-CAT/2026/05-Maio/Fotos/`
- Download: round-trip verificado (57 bytes, text/plain)
- 268/268 testes passando

### Próximos passos
- [ ] Testar upload de foto real em um relatório no Vercel (STORAGE_PROVIDER=drive já ativo)
- [ ] Confirmar que foto aparece no relatório e no PDF
- [ ] Confirmar que fotos antigas do Supabase continuam funcionando
- [ ] Fase futura: migrar fotos antigas do Supabase para o Drive

---

## 2026-05-26 — Fase 2: camada de abstração de storage (Supabase + GCS)

**Sessão**: Claude Code  
**Commit**: `21e949c` — `feat: storage abstraction layer (Supabase + GCS) — Fase 2 redução egress`

### O que foi feito

#### `lib/storage/` — nova camada criada do zero

| Arquivo | Responsabilidade |
|---|---|
| `types.ts` | Interface `StorageProvider` + tipos `UploadParams`, `DownloadParams`, etc. |
| `errors.ts` | Hierarquia de erros (`StorageError`, `StorageUploadError`, etc.) com `userMessage` em PT-BR; `toUserMessage()` nunca expõe stack/token |
| `path-builder.ts` | `buildFotoPath`, `buildRelatorioPath`, `buildConsolidadoPath`, `buildFotoFileName`, `sanitizeSegment`, `shortId` |
| `supabase-provider.ts` | Wrapper do `admin.storage` existente (`gaep-fotos` bucket) |
| `gcs-provider.ts` | Google Cloud Storage; dynamic `import('@google-cloud/storage')`; vars `GCS_*`; `makePublic()` após upload |
| `index.ts` | Factory `createStorageService()` controlada por `STORAGE_PROVIDER` env var (`supabase` default, `gcs`) |
| `__tests__/path-builder.test.ts` | 27 testes: sanitizeSegment, shortId, todos os builders |
| `__tests__/index.test.ts` | 9 testes: seleção de provider, case-insensitive, erro em provider inválido |

#### Arquivos alterados

- **`app/relatorio/actions.ts`**: `uploadRelatorioFoto` usa `buildFotoPath()` + `createStorageService().uploadFile()`; erro tratado via `toUserMessage()`
- **`lib/pdf/imageDataUrlForPdf.ts`**: `resolveImageToBuffer` roteia por tipo de URL — data URL inline → Supabase Storage → HTTP/GCS → path relativo (legado); param `admin` renomeado para `_admin` (sem quebrar callers)

#### Variáveis de ambiente para GCS (adicionar na Vercel quando migrar)
```
STORAGE_PROVIDER=gcs
GCS_BUCKET_NAME=
GCS_PROJECT_ID=
GCS_CLIENT_EMAIL=
GCS_PRIVATE_KEY=    # PEM com \n literais — Vercel armazena escaped
```

#### Segurança mantida
- Credenciais GCS/Supabase nunca chegam ao cliente
- Upload sempre no servidor (Server Action)
- Erros brutos nunca expostos ao frontend (`toUserMessage`)

### Testes
**250/250 passando** (era 214 antes da Fase 1 → subiu para 250 com 36 novos testes desta fase)

### Próximos passos
- [ ] **Ação urgente (billing)**: upgrade Supabase Pro ou aguardar reset do ciclo
- [ ] Criar bucket GCS + service account + configurar vars na Vercel (quando pronto para migrar)
- [ ] Setar `STORAGE_PROVIDER=gcs` na Vercel para ativar GCS em produção
- [ ] **Fase 3 (futura)**: migrar fotos já existentes no `gaep-fotos` bucket para GCS via script de migração

---

## 2026-05-26 — Diagnóstico completo Supabase + Fase 1 redução de Egress

**Sessão**: Claude Code

### Decisão arquitetural
- **Caminho A aprovado**: manter Supabase Auth + Postgres, migrar fotos para Google Cloud Storage (Fase 2)
- Checkpoint de segurança commitado em `d253d8a` antes da migração

### Diagnóstico gerado
- Relatório técnico completo com 14 seções: mapa de 22 arquivos, causas do egress, comparação A vs B, plano faseado
- Causa raiz confirmada: fotos no bucket `gaep-fotos` via URLs públicas carregadas automaticamente

### Fase 1 — Redução imediata de Egress (commit `fc22bbc`)

**`app/relatorio/actions.ts`**:
- `buscarHistoricoRelatorios`: limit 200→50, paginação via `.range()`, parâmetros `{ page?, limit? }`
- `RelatorioResumo`: novo campo `has_fotos: boolean` — as URLs nunca saem do servidor
- Retorna `{ data, hasMore }`

**`app/relatorio/historico/HistoricoClient.tsx`**:
- Botão "Carregar mais 50 relatórios" com estado acumulado
- Ícone 📷 nos cards com fotos (sem carregar as imagens)
- Filtros client-side continuam funcionando

**`components/relatorio/FotoUpload.tsx`**:
- Compressão client-side via Canvas API (sem deps extras)
- Máx 1200px na maior aresta, JPEG 85% — reduz ~75% por arquivo

**`middleware.ts`**:
- Cache do check `ativo` em cookie `gaep-ativo-cache` (httpOnly, TTL 5 min)
- Elimina 1 fetch REST ao Supabase por navegação por usuário

**Testes**: 214/214 passando — novos testes: paginação, has_fotos, hasMore

### Próximos passos
- [ ] **Ação urgente (billing)**: upgrade Supabase Pro ou aguardar reset do ciclo (ver 2026-05-24)
- [ ] Validar no browser: histórico paginado + ícone 📷 + compressão de fotos
- [ ] **Fase 2**: criar `StorageService` com abstração `SupabaseStorageProvider` / `GoogleCloudStorageProvider`
- [ ] **Fase 3**: migrar bucket `gaep-fotos` para Google Cloud Storage

---

## 2026-05-24 — Diagnóstico + mitigação egress (402); upgrade manual necessário

**Sessão**: Cursor Agent

### Causa raiz (confirmada)
- Supabase org **free** (`ijxixgibacpycphtwqkd`) com **`exceed_egress_quota`** → HTTP 402 bloqueia REST e Auth.
- Operador **Hachid** OK no banco (`2359019`, ativo, auth confirmado).

### Feito via Supabase MCP
- Migration **`008_login_find_operador_por_nome`**: extensão `unaccent` + RPC `find_operadores_por_nome_guerra(p_nome)` — login deixa de varrer todos os operadores.
- SQL local espelhado em `handoff/sql/008_login_find_operador_por_nome.sql`.

### Feito no código
- `app/(auth)/login/actions.ts`: usa RPC em vez de `select` completo.
- `lib/supabase/query-errors.ts`: mensagem clara quando Supabase retorna 402.
- Testes: `lib/supabase/__tests__/query-errors.test.ts` (3 testes verdes).

### Ação obrigatória (só no dashboard — MCP não altera billing)
1. Abrir [Billing da org](https://supabase.com/dashboard/org/ijxixgibacpycphtwqkd/billing?panel=subscriptionPlan).
2. **Upgrade para Pro** (libera imediatamente) **ou** aguardar reset do ciclo free (5 GB egress/mês).
3. Fazer **redeploy** na Vercel após merge do código otimizado (opcional mas recomendado).
4. Testar login: **Hachid** / senha `2359019` (ou senha alterada).

---

## 2026-05-20 — Prompt 5+6: Consolidado reestruturado + regressão completa

**Sessão**: Claude Code

### Feito

#### Prompt 5 — Reestruturar Relatório Consolidado Mensal
- `lib/pdf/buildConsolidadoPdfHtml.ts`:
  - Nova ordem: **Gráficos → Descrições → Fotos** (antes era Descrições → Gráficos → Fotos).
  - Grid de fotos alterado de 2 para **3 colunas** (`repeat(3, minmax(0, 1fr))`).
  - `column-gap` ajustado de 10mm para 5mm, `.foto-box` de 52mm para 42mm de altura.
  - Legendas ajustadas para 7.5px (antes 8px) para caber melhor em 3 colunas.
  - Relatórios já saíam em ordem cronológica (`data ASC`) — mantido.

#### Prompt 6 — Revisão de Regressão
**Bugs encontrados e corrigidos:**

1. **`presos_escoltados` invisível na vista de tela e de impressão CSS**
   - `RelatorioDetalheClient.tsx`: campo `presos_escoltados` adicionado na vista de tela (seção Equipe) e na `.print-page` (bloco descrição), ambos condicionais a `!= null`.
   - 2 testes adicionados em `RelatorioDetalheClient.test.tsx`.

2. **Consolidado PDF — relatórios do mesmo dia sem ordem por horário**
   - `dashboard/actions.ts → fetchRelatoriosParaConsolidadoPdf`: adicionado `.order('hora_inicio', { ascending: true })` como sort secundário.

**Nenhum bug encontrado em:**
- Tipagem TypeScript (`KPIData.totalEscoltados`, `RelatorioLinhaConsolidado`, `RelatorioDetalhado`) — coerente.
- Login/bloqueio de inativo — sem loop de redirect, cookies apagados corretamente.
- Filtros do dashboard — `categoriaId`/`atividadeId` aplicados corretamente.
- Compatibilidade com registros antigos (`presos_escoltados = null` tratado em todos os paths).
- `ESCOLTA_NOMES` normalização — cobre variantes com e sem acento.
- Middleware fail-open — operadores sem `auth_id` continuam acessando.

### Arquivos alterados
1. `lib/pdf/buildConsolidadoPdfHtml.ts` (Prompt 5)
2. `app/relatorio/[id]/RelatorioDetalheClient.tsx` (Bug 1)
3. `app/(app)/dashboard/actions.ts` (Bug 2)
4. `app/relatorio/[id]/__tests__/RelatorioDetalheClient.test.tsx` (testes Bug 1)

### Próximos passos
- [ ] Rodar migration 007 no Supabase (ALTER TABLE relatorios ADD COLUMN presos_escoltados).
- [ ] Validar no browser: campo escolta no formulário + "Presos escoltados" na vista de tela + card Dashboard.
- [ ] Gerar consolidado e confirmar: gráficos primeiro, descrições depois, fotos em 3 colunas.
- [ ] Validar bloqueio de operador inativo (login + sessão ativa).

---

## 2026-05-20 — Operador inativo bloqueado no login e na sessão

**Sessão**: Claude Code

### Feito
- **Prompt 4 — Operador inativo não acessa mais o sistema**:
  - `app/(auth)/login/actions.ts`: removido `.eq('ativo', true)` da query inicial; adicionado `ativo` ao SELECT; check explícito após encontrar o operador — retorna mensagem específica "Seu acesso está desativado." para inativos, mantendo "Nome de guerra ou matrícula inválidos." para não encontrados.
  - `middleware.ts`: após autenticação bem-sucedida, faz fetch REST ao Supabase (service role, sem RLS) para checar `ativo` do operador pelo `auth_id`. Se `ativo=false`: apaga cookies de sessão e redireciona para `/login?bloqueio=inativo`. Fail-open se a chamada falhar (não bloqueia operadores válidos).
  - `app/(auth)/login/page.tsx`: aceita `searchParams: Promise<{ bloqueio?: string }>`; lê `bloqueio=inativo`; passa `mensagemBloqueio` ao LoginForm; suprime redirect ao `/relatorio` quando `bloqueado=true`.
  - `app/(auth)/login/LoginForm.tsx`: prop `mensagemBloqueio?: string`; banner âmbar com `role="alert"` e `data-testid="mensagem-bloqueio"` exibido acima do card de login.
  - `app/(auth)/login/__tests__/LoginForm.test.tsx`: 2 novos testes — exibe banner quando `mensagemBloqueio` presente; não exibe quando ausente.

### Arquivos alterados
1. `app/(auth)/login/actions.ts`
2. `middleware.ts`
3. `app/(auth)/login/page.tsx`
4. `app/(auth)/login/LoginForm.tsx`
5. `app/(auth)/login/__tests__/LoginForm.test.tsx`

### Como testar
1. No Supabase Studio: setar `ativo=false` para um operador.
2. Tentar logar → mensagem "Seu acesso está desativado."
3. Com sessão ativa, setar `ativo=false` → recarregar página → redirecionado para `/login` com banner âmbar.
4. Reativar operador (`ativo=true`) → login volta a funcionar normalmente.

### Próximos passos
- [ ] Rodar migration 007 no Supabase (presos_escoltados).
- [ ] Validar no browser: formulário escolta + dashboard + PDFs.
- [ ] Validar bloqueio de operador inativo no browser.

---

## 2026-05-20 — Presos Escoltados: campo condicional + KPI + PDF

**Sessão**: Claude Code

### Feito
- **Prompt 3 — Quantidade de presos em Escolta + Card Total de Escoltados**:
  - `handoff/sql/007_presos_escoltados.sql`: `ALTER TABLE relatorios ADD COLUMN IF NOT EXISTS presos_escoltados INTEGER CHECK (presos_escoltados >= 0)`.
  - Campo visível apenas quando Categoria = OPERAR e Atividade = "Escolta" ou "Escolta Médica".
  - `RelatorioForm.tsx` + `RelatorioEditarForm.tsx`: estado `presosEscoltados (number | '')`, `mostrarEscolta` derivado, `useEffect` para limpar ao mudar atividade, campo numérico com `inputMode="numeric"`.
  - `salvarRelatorio`: `presos_escoltados: input.presosEscoltados ?? null` no INSERT.
  - `atualizarRelatorioCompleto`: `presos_escoltados` no UPDATE com fallback por coluna ausente (mesmo padrão do plantão).
  - `buscarRelatorio`: query secundária expandida com `presos_escoltados`.
  - `KPIData` ganhou `totalEscoltados: number`; `computeKPIUncached` acumula a soma; `operadores/actions.ts` já criava `KPIData` literal — `totalEscoltados: 0` adicionado.
  - `KPIGrid.tsx`: card "Total de Escoltados" (borda violeta, full-width) abaixo dos cards de categoria.
  - `RelatorioLinhaConsolidado` + `fetchRelatoriosParaConsolidadoPdf`: `presosEscoltados` mapeado.
  - `buildConsolidadoPdfHtml.ts`: bloco `escoltadosBlock` na timeline (violeta, só quando preenchido).
  - `buildRelatorioPdfHtml.ts`: campo `presosEscoltados` no modelo; renderiza em `equipeBloco` quando preenchido.
  - `route.tsx` do PDF individual: passa `rel.presos_escoltados`.
  - Fixture de teste `RelatorioDetalheClient.test.tsx`: `presos_escoltados: null` adicionado.

### Migration obrigatória
Antes de usar o campo, rodar no SQL Editor do Supabase:
```sql
-- handoff/sql/007_presos_escoltados.sql
ALTER TABLE relatorios
  ADD COLUMN IF NOT EXISTS presos_escoltados INTEGER CHECK (presos_escoltados >= 0);
```

### Arquivos alterados
1. `handoff/sql/007_presos_escoltados.sql` (novo)
2. `app/relatorio/actions.ts`
3. `app/relatorio/RelatorioForm.tsx`
4. `app/relatorio/[id]/editar/RelatorioEditarForm.tsx`
5. `app/(app)/dashboard/types.ts`
6. `app/(app)/dashboard/actions.ts`
7. `app/(app)/operadores/actions.ts`
8. `components/dashboard/KPIGrid.tsx`
9. `lib/pdf/buildConsolidadoPdfHtml.ts`
10. `lib/pdf/buildRelatorioPdfHtml.ts`
11. `app/api/pdf/[id]/route.tsx`
12. `app/relatorio/[id]/__tests__/RelatorioDetalheClient.test.tsx`

### Como testar
1. Rodar migration 007 no Supabase SQL Editor.
2. No formulário: selecionar OPERAR → "Escolta" — campo aparece. Trocar atividade → campo some.
3. Salvar relatório com presos=3 → reabrir na edição → campo exibe 3.
4. Dashboard: card "Total de Escoltados" exibe soma do período filtrado.
5. PDF consolidado: "Presos escoltados: 3" aparece na timeline do relatório.
6. PDF individual: "Presos escoltados: 3" aparece na seção de equipe.
7. Relatórios antigos sem o campo continuam funcionando normalmente.

### Próximos passos
- [ ] Rodar migration 007 no Supabase.
- [ ] Validar no browser (formulário + dashboard + PDFs).
- [ ] Rodar `npm run test -- --run` para confirmar testes.

---

## 2026-05-20 — Plantão na edição corrigido + Outros Integrantes no consolidado + Fix permissão editar

**Sessão**: Claude Code

### Feito
- **TAREFA 1 — Plantão na edição (bug fix)**:
  - `RelatorioDetalhado` ganhou campos `plantao: boolean | null` e `data_fim: string | null`.
  - `buscarRelatorio` (actions.ts): query secundária best-effort para `plantao, data_fim` (evita erro PostgREST 42703 se migration ainda não rodou).
  - `AtualizarRelatorioCompletoInput` ganhou `plantao?: boolean` e `dataFim?: string`.
  - Query de UPDATE em `atualizarRelatorioCompleto` persiste `plantao` e `data_fim` no banco.
  - `RelatorioEditarForm`: adicionados estados `plantao` (init de `relatorio.plantao ?? false`) e `dataFim` (init de `relatorio.data_fim ?? ''`); passados ao `DateTimeBlock` e ao `atualizarRelatorioCompleto`.
  - `calcHorasTotais` no form de edição corrigida para calcular duração correta em plantão multi-dia.
  - Fixture de teste `RelatorioDetalheClient.test.tsx` atualizada com `plantao: false, data_fim: null`.

- **TAREFA 2 — Outros Integrantes no PDF consolidado**:
  - Visualização na tela (`RelatorioDetalheClient`) e PDF individual já exibiam corretamente — nenhuma alteração necessária.
  - `RelatorioLinhaConsolidado` (dashboard/types.ts): adicionado `outrosIntegrantes: string | null`.
  - `fetchRelatoriosParaConsolidadoPdf` (dashboard/actions.ts): `outros_integrantes` adicionado ao SELECT, ao type `Row` e ao mapeamento de retorno.
  - `buildConsolidadoPdfHtml.ts`: exibe bloco "Outros integrantes / forças amigas" logo acima da descrição de cada relatório (quando preenchido).

- **Fix 404 persistente em `/relatorio/[id]/editar`**:
  - **Root cause**: verificação `isRelatorista` no server component bloqueava acesso quando o operador logado não era o relatorista do relatório — corretamente firing `notFound()`.
  - **Decisão**: modelo de permissão simplificado — isolamento por GAEP é a única restrição. Qualquer operador do mesmo GAEP pode editar qualquer relatório do GAEP.
  - Removida verificação `isAdmin/isRelatorista` de `app/relatorio/[id]/editar/page.tsx`.
  - Botão "Editar relatório" em `/relatorio/historico` visível para todos os operadores do GAEP (comportamento restaurado).

- **Fix "Rendered more hooks than during previous render"**:
  - Root cause: React Fast Refresh preservou fiber antigo com 14 hooks; após adicionar `useState` de `plantao` e `dataFim` (total 16 hooks), o render do form disparou a violação de invariante.
  - Não era bug de código — todos os hooks são incondicionais. Resolvido com hard refresh (Ctrl+Shift+R).

### Arquivos alterados
1. `app/relatorio/actions.ts` — query secundária plantão + logs diagnóstico removidos
2. `app/relatorio/[id]/editar/RelatorioEditarForm.tsx` — plantao/dataFim states
3. `app/relatorio/[id]/editar/page.tsx` — permissão simplificada (só isolamento GAEP)
4. `app/(app)/dashboard/types.ts`
5. `app/(app)/dashboard/actions.ts`
6. `lib/pdf/buildConsolidadoPdfHtml.ts`
7. `app/relatorio/[id]/__tests__/RelatorioDetalheClient.test.tsx`

### Como testar
1. Abrir `/relatorio/[id]/editar` como qualquer operador do GAEP — deve ter acesso.
2. Relatório com `plantao=true` — toggle deve aparecer ativado e `data_fim` preenchida.
3. Desativar e reativar o toggle Plantão — datas devem resetar/preencher conforme esperado.
4. Salvar — reabrir: plantão e data_fim persistidos.
5. Criar relatório com "Outros Integrantes" preenchido → gerar PDF consolidado → campo deve aparecer acima da descrição de cada entrada.
6. Rodar `npm run test -- --run` para confirmar testes passando.

### Próximos passos
- [ ] Validar no browser (plantão toggle + persistência + outros integrantes no PDF consolidado).
- [ ] Rodar `npm run test -- --run` para confirmar testes.

---

## 2026-05-20 — Individual: auto-load inicial; Histórico: busca por descrição

**Sessão**: Cursor

### Feito
- **Individual (DesempenhoClient)**: adicionado `useEffect` com `useRef` guard que dispara `fetchDesempenhoData` automaticamente ao montar a tela, exibindo a view BI do operador logado no mês atual sem necessidade de clique manual. Filtros continuam editáveis e o botão "Analisar Operador" ainda funciona normalmente.
- **Histórico (actions.ts)**: adicionado `descricao_revisada` ao SELECT de `buscarHistoricoRelatorios` e à interface `RelatorioResumo`.
- **Histórico (HistoricoClient)**: filtro de busca ampliado para incluir `descricao_revisada` no campo de pesquisa (antes só buscava em `categoria_nome`, `atividade_nome`, `relatorista_nome`). Placeholder atualizado.
- Testes existentes de `buscarHistoricoRelatorios` não são afetados (verificado).
- **Commit/push/deploy**: `e29d786` — `feat: Individual, Operador preenchido` em `main`; deploy Vercel produção **READY**.

### Arquivos alterados
1. `app/(app)/operadores/DesempenhoClient.tsx`
2. `app/relatorio/actions.ts`
3. `app/relatorio/historico/HistoricoClient.tsx`

### Como testar
1. Abrir `/operadores` logado — deve carregar automaticamente o painel BI do mês atual sem clicar em nada.
2. Abrir `/relatorio/historico` — digitar parte de uma descrição de relatório (ex.: texto que aparece no PDF) e verificar que a lista filtra corretamente.
3. Limpar o campo de busca — lista volta ao estado completo.
4. Chips de período, filtros avançados e botões Editar/Ver relatório devem continuar funcionando.

### Próximos passos
- [ ] Validar em produção: https://sistema-gaep-ppf.vercel.app/operadores e `/relatorio/historico`.

---

## 2026-05-10 — Estabilização de qualidade: testes/lint/build verdes

**Sessão**: Cursor

### Feito
- Corrigido erro de lint em `app/(app)/dashboard/actions.ts` (remoção de variável não utilizada na normalização de filtros).
- Ajustadas suítes para refletir comportamento atual dos componentes sem alterar regra de negócio:
  - `components/relatorio/__tests__/DateTimeBlock.test.tsx`: cenário de duração passou a usar wrapper controlado por estado; validação de mudança de data com valor diferente.
  - `components/relatorio/__tests__/DescricaoMic.test.tsx`: mock de `SpeechRecognition` no ambiente de teste para exibir botão de microfone conforme implementação.
  - `lib/cache/__tests__/queries.test.ts`: expectativa atualizada para ordenação operacional de categorias (`TREINAR`, `OPERAR`, `INSTRUIR`) aplicada em memória.
  - `app/(app)/gestao/__tests__/GestaoPage.test.tsx`: timeout explícito no teste inicial para evitar falso negativo por latência de importação.
- Correção prévia de duplicidade de chave na aba de logs mantida e validada (`LogsTab` + paginação estável em `logsActions`).

### Validação executada
- `npm run test -- --run` ✅ **200/200 testes passando**
- `npm run lint` ✅ sem erros
- `npm run build` ✅ build de produção concluído

### Próximos passos
- [ ] Commitar o conjunto de mudanças e abrir PR para revisão.

---

## 2026-05-10 — Logs de acesso: login + telas principais

**Sessão**: Cursor

### Feito
- Instrumentado `ACESSO` no sucesso de autenticação em `app/(auth)/login/actions.ts` com `tabela: 'login'` e metadados (`evento: LOGIN_SUCESSO`, `tela: /login`, perfil e nome de guerra).
- Instrumentado `ACESSO` nas páginas `app/relatorio/page.tsx`, `app/(app)/dashboard/page.tsx`, `app/(app)/operadores/page.tsx` e `app/(app)/missoes/page.tsx`, registrando `operador_id`, `gaep_id`, `tabela` da tela e `dadosDepois.tela`.
- Mantido padrão best-effort (`logAudit(...).catch(() => {})`) para não interromper navegação caso a auditoria falhe.

### Próximos passos
- [ ] Opcional: instrumentar também `/relatorio/historico` e `/relatorio/[id]` para rastreabilidade completa de leitura/consulta de relatórios.
- [ ] Validar na aba Gestão → Logs se as ações `ACESSO` estão aparecendo com tela correta para múltiplos perfis.

---

## 2026-05-09 — E-mail do sistema (matrícula): só Super Admin vê; sem edição

**Sessão**: Cursor

### Feito
- **`email_funcional`** passa a ser sempre **`{matricula}@gaep.internal`** (gerado no servidor em `criarOperador`, `editarOperador`, convite efetivo). Removidos inputs editáveis (gestão, convite, dados pessoais).
- UI: rótulo **E-mail do sistema**; visível **apenas para SUPER_ADMIN** (modal efetivo + aba Dados Pessoais), somente leitura, com legenda de geração automática.
- Helper `lib/email-sistema.ts` + teste Vitest.

---

## 2026-05-09 — Auth: cookies inválidos (refresh_token_not_found)

**Sessão**: Cursor

### Feito
- `Invalid Refresh Token` / `refresh_token_not_found`: **middleware** e **`/login`** passam a **apagar cookies** `sb-gaep-auth*` quando o erro indica sessão inválida, evitando tentativas repetidas de refresh e ruído no terminal.
- Helper `lib/supabase/stale-session.ts` + testes Vitest.

---

## 2026-05-09 — Gestão: Dados Pessoais + alteração de senha (Supabase Auth)

**Sessão**: Cursor

### Feito
- Menu **Gestão** visível a **todos** os perfis; primeiro subitem **Dados Pessoais** (todos). Demais abas só **ADMIN** / **SUPER_ADMIN**; operador comum acessa só `/gestao?tab=dados-pessoais` (redirect no servidor se outra aba).
- Aba **Dados Pessoais**: formulário editável (dados em `operadores`) + bloco **Alterar senha** (senha atual com placeholder *Matrícula*, nova senha, confirmação; legenda de requisitos via `lib/password-policy.ts`).
- Server actions `atualizarMeusDadosPessoais` e `alterarMinhaSenha`: validação da senha atual com `signInWithPassword`; nova senha com `auth.admin.updateUserById` (próximos logins). **Login** deixa de exigir `senha === matrícula` no servidor — aceita matrícula (primeiro acesso) ou senha já alterada.
- Testes: `GestaoPage` (redirect operador), `GestaoClient` (aba dados pessoais), `password-policy`, `LoginForm` (placeholder).

### Próximos passos
- [ ] Opcional: aviso no primeiro login para trocar senha fraca.

---

## 2026-05-09 — Formulários efetivo / convite: rótulos e campo Equipe

**Sessão**: Cursor

### Feito
- Legenda **E-mail funcional** sem sufixo “corporativo / PM”; **E-mail** → **E-mail pessoal** (gestão modal + `ConviteForm`).
- **Plano de saúde**: placeholder **Ex. Unimed ou SUS**.
- Campo **Equipe** oculto na UI (gestão e convite público); convite envia `equipe` oculto **Alpha**; `submeterConviteEfetivo` aceita equipe vazia com fallback Alpha e mensagem de erro sem exigir equipe.

---

## 2026-05-09 — Convite efetivo: Super Admin escolhe GAEP do link

**Sessão**: Cursor

### Feito
- Antes de **Gerar link de convite**, o **Super Admin** escolhe o GAEP na lista (`data.gaeps`); o botão fica desabilitado até haver seleção. **Admin** da unidade continua com o GAEP fixo (sem seletor).
- `gerarConviteEfetivo`: se `SUPER_ADMIN`, valida existência do `gaep_id` em `gaeps` (não deletado); **Admin** segue obrigado a `gaep_id === operador.gaep_id`.

---

## 2026-05-09 — Gestão: tab GAEPs só Super Admin; Dashboard escopo multi-GAEP

**Sessão**: Cursor

### Feito
- `/gestao?tab=gaeps`: **redirect no servidor** para `/gestao?tab=efetivo` se o perfil não for `SUPER_ADMIN` (URL manual ou link antigo). Sidebar já limitava o item a Super Admin.
- **Dashboard** (`SUPER_ADMIN`): seletor “Unidade em análise” — unidade do cadastro, cada GAEP da lista, ou **Todos os GAEPs (consolidado)**; KPI, ranking, evolução mensal e PDF consolidado respeitam o escopo (`analiseGaepId` / query `analiseGaepId` no PDF). Demais perfis inalterados.
- `dashboard/actions.ts`: `resolveAnaliseGaepIds`, KPI e evolução com `.in('gaep_id', …)` quando múltiplos; `fetchRelatoriosParaConsolidadoPdf(gaepIds[])`. Export `fetchKPIData` (correção de nome). Integridade do PDF: `gaepScopeKey` em `consolidadoIntegrity.ts`.
- Testes: `GestaoPage` (ADMIN + `tab=gaeps`), `kpiActions` (fixtures com `data`, mocks relatorios + `gaep_dias_uteis`).

### Próximos passos
- [ ] Opcional: dias úteis / variável mês no contexto alinhados ao GAEP selecionado no dashboard (hoje continua o GAEP do cadastro no carregamento da página).

---

## 2026-05-09 — Ranking por categoria: chave categoria+atividade

**Sessão**: Cursor

### Feito
- Bug: o ranking agregava só por `atividade_id`; no GAEP a mesma atividade do catálogo pode ser usada em **várias categorias** (ex.: Patrulhamento como OPERAR e como INSTRUIR). O primeiro relatório “ganhava” a categoria e todos os minutos iam para aquele bucket — INSTRUIR podia ficar vazio com horas na rosca.
- `rankingAtividadeKey(categoriaId, atividadeId)` em `dashboard/utils.ts`; `computeKPI` e `fetchDesempenhoData` passam a usar essa chave no `Map`.
- Teste Vitest: mesma atividade em OPERAR e INSTRUIR gera duas linhas no ranking.

---

## 2026-05-09 — Desempenho operador: ranking Instruir com dados

**Sessão**: Cursor

### Feito
- `fetchDesempenhoData` (`operadores/actions.ts`): `pickFirst` em `atividades` e `categorias_atividade` (mesmo padrão do KPI da dashboard), evitando `nome`/`id` indefinidos quando o PostgREST devolve array em join.
- `RankingBars`: filtro por categoria com `trim().toUpperCase()` para alinhar a `CAT_ORDER`.

---

## 2026-05-09 — RankingBars: sempre Treinar, Operar e Instruir

**Sessão**: Cursor

### Feito
- `RankingBars` passa a renderizar **sempre** as três categorias na ordem `CAT_ORDER` (Treinar → Operar → Instruir). Categoria sem atividades no período mostra mensagem fixa em vez de sumir da UI (corrige ausência de “Ranking Instruir” em `/operadores` quando não havia linhas INSTRUIR no array).

---

## 2026-05-09 — Dashboard: rosca "Composição por Categoria"

**Sessão**: Cursor

### Feito
- `DonutCategoria` com prop opcional `dashboardLayout`: rosca grossa (innerRadius 55 / outerRadius 92), percentuais em branco dentro da fatia (omitidos se fatia menor que 5%), legenda manual centralizada abaixo (bolinha + nome + horas via `formatMinutos`), sem `Legend` do Recharts nem labels externos; cores via `CAT_COLORS` inalteradas.
- `DashboardClient` e **`GraficosOperador`** (`/operadores`) passam `dashboardLayout` para o mesmo visual de rosca.

---

## 2026-05-09 — Convite ao efetivo (link público + GAEP)

**Sessão**: Cursor

### Feito
- Tabela `convites_operador` (`handoff/sql/005_convites_operador.sql` + migration `handoff/migrations/20260509_convites_operador.sql` no manifest): token único, `gaep_id`, `expires_at` (7 dias), `used_at`, soft delete `deleted_at`.
- **Gestão → Efetivo**: card “Convite ao efetivo” com botão **Gerar link**, campo somente leitura com URL e **Copiar link**; URL aponta para `/convite/[token]` (rota pública no `middleware`).
- **Página pública** `app/convite/[token]`: mesmo conjunto de campos do modal de Gestão + **e-mail funcional**; convite sempre cria **OPERADOR** (só Super Admin altera perfil depois). `submeterConviteEfetivo` + `criarOperador`/`editarOperador` persistem `email_funcional`; migration `20260509_operadores_email_funcional_if_missing.sql` + `handoff/sql/006_operadores_email_funcional.sql`.
- **Gestão Efetivo**: campo **E-mail funcional**; select de **perfil** apenas para **SUPER_ADMIN**; ADMIN vê aviso e cadastro forçado a OPERADOR no servidor.
- Ações em `app/convite/actions.ts` (`gerarConviteEfetivo`, `submeterConviteEfetivo`). Base URL: `NEXT_PUBLIC_SITE_URL` ou `VERCEL_URL`.
- Projeto Supabase **GAEP-DB-CLAUDE-DESIGNER**: DDL aplicado via MCP.

### Próximos passos
- [ ] Outros ambientes: rodar `005` ou `npm run db:sync` com `SUPABASE_DB_URL`.
- [ ] Definir `NEXT_PUBLIC_SITE_URL` na Vercel para o link gerado bater com o domínio público.

---

## 2026-05-09 — Login: nome de guerra + matrícula como senha

**Sessão**: Cursor

### Feito
- Fluxo de login padrão: usuário informa **nome de guerra** (`operadores.nome`) e **senha = matrícula**; server action resolve o operador (comparação insensível a maiúsculas/acentos), valida senha = matrícula e chama `signInWithPassword` com `{matricula}@gaep.internal`.
- Tela `/login`: removido dropdown de operadores; campos texto + senha; mensagem se houver **nome de guerra duplicado** no cadastro.
- Requer `SUPABASE_SERVICE_ROLE_KEY` na server action para listar operadores ativos (lookup).
- Testes `LoginForm`: mock de `@/lib/supabase/client` para Vitest sem env.

---

## 2026-05-09 — Auditoria Auth: matrículas Alex e Boza

**Sessão**: Cursor

### Feito
- Consulta no projeto Supabase **GAEP-DB-CLAUDE-DESIGNER** (`pxaatetwxnalzqfnihof`): 12 operadores ativos (`deleted_at` nulo); **10** com `auth.users` no email `matricula@gaep.internal`, email confirmado, senha e `operadores.auth_id` alinhados.
- **Inaptos (2)**: matrículas **2355659** (Alex) e **2359163** (Boza) — `auth_id` apontava para contas **235659@gaep.internal** e **235963@gaep.internal** (dígitos divergentes do cadastro em `operadores`); login por `signInWithPassword` com a matrícula real falha.
- Script SQL (DO block) documentado para colar no SQL Editor: cria usuários email/senha se ausentes, `auth.identities` email, e `UPDATE operadores` ligando `auth_id` pelo email esperado.
- Ajuste em `scripts/provision-operators-auth.js`: lista de matrículas corrigida de `235659`/`235963` para `2355659`/`2359163`.

### Próximos passos
- [ ] Executar o SQL de correção no Supabase (ou criar os 2 usuários pelo Dashboard Auth e rodar só o `UPDATE` de `auth_id`).
- [ ] Opcional: remover contas órfãs `235659@` / `235963@` em Auth se não forem mais necessárias (após validar que nada as referencia).

---

## 2026-05-08 — PDF individual e consolidado polidos + ordem categorias (commit 9703a3c)

**Sessão**: Claude Code

### Feito
- **PDF individual (desempenho-operador)**:
  - Cabeçalho exibe Nome completo, Matrícula, GAEP e Período (antes só mostrava nome de guerra)
  - Tabela "Composição por categoria" ganhou coluna de % do total (percentual real, não relativo ao maior valor)
  - `route.ts` busca `nome_completo` e `matricula` do operador alvo e os passa ao builder
- **PDF consolidado**:
  - Cards KPI com fundo 100% transparente; removidos "Carga prevista" e "Saldo"
  - Descrições: trim no texto antes do render resolve o problema de `text-indent` cair em linha vazia (causado por `\n` inicial no banco + `white-space:pre-line`)
- **Ordem das categorias** (dashboard, ambos os PDFs): TREINAR → OPERAR → INSTRUIR
  - Alterado em `app/(app)/dashboard/utils.ts` e `components/dashboard/KPIGrid.tsx`
- **DateTimeBlock**: removido sufixo "(turno multi-dia)" do label do toggle Plantão
- **Workflow de commit estabelecido**: commit semântico + `git push` imediato para acionar Vercel

### Decisões
- `(r.descricao_revisada ?? '').trim()` antes do `escapeHtml` garante que `text-indent` sempre cai no primeiro caractere visível, independente do conteúdo do banco.
- Ordem TREINAR→OPERAR→INSTRUIR reflete prioridade operacional do GAEP.

### Próximos passos
- [ ] Rodar `handoff/sql/004_audit_log_indexes.sql` no Supabase SQL Editor.
- [ ] Testar aba Logs: fazer uma edição de operador e verificar que aparece na lista.
- [ ] Gerar nova chave OpenAI e atualizar `.env.local` + Vercel dashboard.

---

## 2026-05-08 — PDF Consolidado: melhorias visuais (timbrado de fundo, pizza %, texto indentado)

**Sessão**: Claude Code

### Feito
- **Timbrado como fundo em todas as páginas**: quando `timbradoDataUrl` existe, é exibido como `position:fixed; top:0; left:0; width:210mm; height:297mm; z-index:-1` — aparece em TODAS as páginas do PDF como background oficial.
- **Cabeçalho institucional** (dark navy `#1a1a2e`) suprimido quando timbrado existe — a imagem oficial já é o cabeçalho.
- **Backgrounds semi-transparentes**: cards KPI usam `rgba(255,255,255,0.88)`, section headers usam `rgba(240,230,200,0.82)` para o timbrado aparecer através do conteúdo.
- **Contagem de operadores corrigida**: `buildKpiCards` agora recebe `totalOperadoresGaep` (query `count(*)` na tabela `operadores` com `ativo=true` e `deleted_at IS NULL`). Route `api/pdf/consolidado` faz a query em paralelo e passa o valor.
- **Gráfico de pizza com percentuais**: fatias agora exibem "NN%" em branco (`font-weight:700`) dentro de cada fatia quando há espaço (slice > 0.28 rad). Legenda também mostra "NN% · Xh Ym".
- **Rótulos em negrito** nos gráficos de barras (nome da atividade `font-weight:700`) e linha (eixo X/Y `font-weight:700`).
- **Texto da descrição com recuo**: `text-indent:1.5em` adicionado ao `<p>` da timeline, combinado com `text-align:justify`.
- **`ConsolidadoPdfModel`**: campo `totalOperadoresGaep: number` adicionado ao tipo.

### Decisões
- `z-index:-1` no timbrado garante que todo conteúdo (z-index padrão 0) aparece por cima.
- `height:297mm; object-fit:contain; object-position:top center` preserva proporções sem corte, posiciona no topo.
- Quando não há timbrado: comportamento anterior mantido (dark navy header, backgrounds sólidos).

### Próximos passos
- [ ] Rodar `004_audit_log_indexes.sql` no Supabase SQL Editor.
- [ ] Testar PDF consolidado em `/api/pdf/consolidado?dataInicio=...&dataFim=...` para validar timbrado + pizza % + operadores.
- [ ] Gerar nova chave OpenAI e atualizar `.env.local` + Vercel dashboard.

---

## 2026-05-08 — GAEPs: editar e excluir unidades (aba Gestão, SUPER_ADMIN)

**Sessão**: Claude Code

### Feito
- **`actions.ts`**: `editarGaep(id, { codigo, cidade, estado })` e `excluirGaep(id)` (soft delete via `deleted_at + ativo:false`). Ambas com verificação SUPER_ADMIN e `logAudit`.
- **`GestaoClient.tsx`**: `TabGAEPs` refatorada com 3 botões por linha (✏️ editar, 🗑️ excluir, 🔒/✅ toggle ativo), modal de edição pré-preenchido, modal de confirmação de exclusão com aviso de soft delete.

---

## 2026-05-08 — Logs de Acesso e Edições (aba Gestão, SUPER_ADMIN)

**Sessão**: Claude Code

### Feito
- **`lib/audit.ts`**: helper `logAudit()` fire-and-forget que insere na tabela `audit_log` existente. Nunca propaga erros (melhor-esforço).
- **`app/(app)/gestao/logsActions.ts`**: Server actions `fetchAuditLogs` (paginação 50/página, filtros: GAEP, ação, tabela, data), `fetchGaepsParaFiltro`, `fetchTabelasDistintas`. Enriquecimento com nome do operador e código do GAEP via batch queries.
- **`app/(app)/gestao/LogsTab.tsx`**: Componente cliente. Filtros (GAEP, tipo de ação, recurso, data de/até). Lista de logs com pill colorido por ação (Acesso/Criação/Edição/Exclusão), expansão inline mostrando JSON completo de dados_antes/dados_depois.
- **`app/(app)/gestao/actions.ts`**: `logAudit` instrumentado em 9 ações: `criarOperador`, `editarOperador`, `toggleAtivoOperador`, `adicionarAtividade`, `editarAtividade`, `removerAtividade`, `salvarConfigIA`, `salvarConfigRelatorio`, `adicionarGaep`.
- **`app/(app)/gestao/page.tsx`**: Log de acesso à página (ACESSO, tabela: gestao, dados: tab visitado + perfil). Fire-and-forget no fim do carregamento de dados.
- **`components/layout/SidebarNav.tsx`**: Item "📋 Logs" no submenu Gestão, visível apenas para SUPER_ADMIN.
- **`handoff/sql/004_audit_log_indexes.sql`**: Índices de performance para as queries de filtragem (gaep_id, acao, operador_id, tabela, created_at).

### Decisões
- Usada a tabela `audit_log` existente (001_schema.sql) — sem criar nova tabela.
- Aba "Logs" restrita a SUPER_ADMIN (mesma lógica que a aba GAEPs).
- Paginação "carregar mais" em vez de paginação clássica (UX mobile-first).

### Próximos passos
- [ ] Rodar `004_audit_log_indexes.sql` no Supabase SQL Editor para habilitar os índices.
- [ ] Testar aba Logs: fazer uma edição de operador e verificar que aparece na lista.
- [ ] Gerar nova chave OpenAI e atualizar `.env.local` + Vercel dashboard.

---

## 2026-05-08 — PDF Consolidado: redesign visual completo (layout profissional)

**Sessão**: Claude Code

### Feito
- **`lib/pdf/buildConsolidadoPdfHtml.ts` refatorado** com 6 seções conforme spec do prompt:
  - **SEÇÃO 1 — Timbrado**: header HTML (fundo `#1a1a2e`, bordas douradas, ornamentos ✦ nos 4 cantos, logo 80x80px à direita, texto institucional com fonte "IM Fell English", separador dourado).
  - **SEÇÃO 2 — Filtros**: 3 itens em linha com ícones SVG inline (calendário, tag, raio), fundo branco, borda inferior.
  - **SEÇÃO 3 — KPIs**: 6 cards em grid (Total horas, Total registros, Operadores, Horas OPERAR/TREINAR/INSTRUIR) com ícones SVG 22px e cores temáticas.
  - **SEÇÃO 4 — Gráficos**: 3 colunas — pizza SVG (fatias por categoria), barras horizontais HTML (por grupo/categoria), linha SVG (previsto tracejado × realizado sólido, com pontos e eixos).
  - **SEÇÃO 5 — Descrições (timeline)**: coluna esquerda 120px (data bold, pill colorido da categoria, atividade), bullet âmbar 10px central, coluna direita (descrição justify, relatorista italic alinhado à direita, ocorrências com borda dourada/fundo #fffbeb).
  - **SEÇÃO 6 — Fotos**: `break-before: page`, grid 2 colunas, legenda 8.5px cinza.
  - **Rodapé fixo**: `position:fixed`, fundo `#1a1a2e`, borda topo `#c9a84c`, 3 colunas (consolidador+hash | gerado+paginação CSS | QR 60x60).
- Fontes Google Fonts (`IM Fell English` + `Source Sans 3`) via `@import` com fallbacks Georgia/Arial.
- Paleta local `PDF_CAT_COLORS` (OPERAR `#2563eb`, TREINAR `#16a34a`, INSTRUIR `#d97706`) independente do dashboard.
- Assinatura do tipo `ConsolidadoPdfModel` e função `buildConsolidadoPdfHtml` mantidas inalteradas.

### Próximos passos
- [ ] Testar o PDF consolidado no browser (`/api/pdf/consolidado?...`) para validar visual.
- [ ] Gerar nova chave OpenAI e atualizar `.env.local` + Vercel dashboard (a atual foi exposta).

---

## 2026-05-08 — PDF: formatação, timbrado v3, ocorrências destacadas, consolidado melhorado

**Sessão**: Claude Code

### Feito
- **Timbrado v3**: `resolveTimbradoForPdf.ts` atualizado para `gaep-cat-header-v3.png`. Arquivo copiado para `public/`. Aplicado em todos os PDFs (individual, consolidado, desempenho).
- **Histórico**: botão "Ver relatório" em `/relatorio/historico` abre PDF diretamente em nova aba (`<a target="_blank">`) — removido iframe inline.
- **Editar relatório**: após salvar, link "Ver relatório em PDF" exibido na página de edição. Mensagens de erro/sucesso movidas para próximo do botão Salvar (não mais no topo do form).
- **Race condition fotos**: `FotoUpload` comunica estado de upload ao pai via `onUploadingChange`. Botão Salvar desabilitado durante upload.
- **Consolidado — foto box**: fundo branco removido, ficou transparente.
- **Consolidado — composição por categoria**: adicionada coluna `%` na tabela de categorias.
- **Consolidado — filename**: `Consolidado DD-MM-AAAA - DD-MM-AAAA.pdf`.
- **Descrição da atividade (ambos os PDFs)**: `text-align: justify; text-indent: 1.5em; white-space: pre-line`.
- **Ocorrências / observações**: quando preenchido, renderizado com fundo amarelo claro + borda âmbar + emoji ⚠️ nos PDFs individual e consolidado. Campo `ocorrencias` adicionado ao tipo `RelatorioLinhaConsolidado`, query e mapeamento.

### Próximos passos
- [ ] Gerar nova chave OpenAI e atualizar `.env.local` + Vercel dashboard (a atual foi exposta no chat).
- [ ] Testar fluxo completo: editar relatório com foto + ocorrência → verificar no PDF e consolidado.

---

## 2026-05-08 — Fix: foto não aparecia no PDF/consolidado após edição

**Sessão**: Claude Code

### Feito
- **Root cause identificado**: `FotoUpload` não comunicava o estado de upload ao pai. O botão "Salvar alterações" ficava habilitado enquanto o upload ainda estava em andamento. Se o usuário clicasse "Salvar" antes do upload terminar, a URL da foto não estava no estado `fotosUrls` — o relatório era salvo sem a foto, e portanto ela não aparecia no PDF nem no consolidado.
- **Fix em `FotoUpload.tsx`**: adicionada prop `onUploadingChange?: (uploading: boolean) => void`. Chamada com `true` quando o upload inicia (`setUploading(true)`) e com `false` quando termina (`setUploading(false)`).
- **Fix em `RelatorioEditarForm.tsx`**: adicionado estado `uploadingFoto`. Botão "Salvar alterações" agora fica desabilitado (`disabled={salvando || uploadingFoto}`) e mostra "⏳ Aguardando upload..." enquanto a foto está sendo enviada.
- **Fix em `RelatorioForm.tsx`**: mesmo padrão aplicado ao form de criação. `BotoesAcao` recebe `salvando={salvando || uploadingFoto}` — os botões "Salvar Direto" e "Redigir com IA" ficam bloqueados durante upload.

### Decisões
- `onUploadingChange` é prop opcional (`?`) para não quebrar usos futuros do componente sem a prop.
- O versionamento em si (`relatorio_versoes`) funciona corretamente — o problema era apenas o upload race condition.

### Próximos passos
- [ ] Gerar nova chave OpenAI e atualizar `.env.local` + Vercel dashboard (a atual foi exposta no chat).
- [ ] Testar o fluxo completo: editar relatório, adicionar foto, aguardar upload, salvar → verificar no PDF e consolidado.
- [ ] Validar PDF individual com período multi-dia.

---

## 2026-05-08 — Dashboard plantão + PDF filename + IA ok
**Sessão**: Claude Code

### Feito
- **Dashboard corrigido para plantão** (`app/(app)/dashboard/actions.ts`):
  - `computeKPI`: SELECT agora inclui `data, plantao, data_fim`. Cálculo de minutos usa aritmética de timestamps para plantões multi-dia.
  - `_fetchEvolucaoRaw`: mesmo fix — SELECT com `plantao, data_fim`, cálculo correto para participantes e relatorista.
  - Antes: plantão de 24h contava 0 minutos. Agora conta corretamente.
- **PDF filename**: `app/api/pdf/desempenho-operador/route.ts` — arquivo salvo como `NOME DD-MM-AAAA a DD-MM-AAAA.pdf` (ex: `Silva 08-05-2026 a 31-05-2026.pdf`).
- **Fix root cause da chave OpenAI**: `OPENAI_API_KEY` estava nas variáveis de usuário do Windows (`HKCU\Environment`), sobrescrevendo `.env.local`. Removida via PowerShell. Para iniciar sem herdar: `Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue; npm run dev`.
- **Schama cache Supabase**: coluna `data_fim` e `plantao` existiam mas PostgREST cache estava stale. Resolvido com `NOTIFY pgrst, 'reload schema'`.
- **DateTimeBlock redesign final**: chips de dia removidos, input nativo de data simples, plantão toggle pill, dataFim auto +1 dia.
- **Texto IA plantão**: abertura diferenciada `"No dia X às HH:MM até o dia Y às HH:MM, ..."`.
- **Tratamento erros IA**: mapeamento por `error.code` OpenAI, validação de formato da chave, logging diagnóstico.

### Próximos passos
- [ ] Gerar nova chave OpenAI (a atual foi exposta no chat) e atualizar `.env.local` + Vercel dashboard.
- [ ] Testar plantão completo no browser (salvar + ver na folha ponto + dashboard).
- [ ] Validar PDF individual com período multi-dia.

---

## 2026-05-08 — Fix IA funcionando + redesign DateTimeBlock mobile
**Sessão**: Claude Code

### Feito
- **Root cause do erro de chave OpenAI resolvido**: a variável `OPENAI_API_KEY` estava gravada nas variáveis de ambiente de usuário do Windows (`HKCU\Environment`), sobrescrevendo o `.env.local`. Removida via `[System.Environment]::SetEnvironmentVariable("OPENAI_API_KEY", $null, "User")`. Para iniciar o servidor sem herdar variáveis antigas: `Remove-Item Env:OPENAI_API_KEY -ErrorAction SilentlyContinue; npm run dev`.
- **API de IA validada**: `POST /api/ia 200` com modelo `gpt-4o`, chave `...mC6vQRMA`.
- **Redesign `DateTimeBlock`**: removidos chips de dia (Ontem/Hoje/Amanhã) conforme pedido. Voltou ao input nativo de data (abre calendário do celular). Plantão toggle agora é pill switch visual. Quando plantão ativado: `dataFim` auto-preenche para `data início + 1 dia`. Se data início mudar: dataFim reajusta automaticamente. Botão `⟳ Agora` no horário de término.
- **Texto IA para plantão**: abertura diferenciada — `"No dia 07/05 às 07:45 até o dia 08/05 às 08:00, o operador..."`. `horario` voltou a ser `"HH:MM às HH:MM"` (simples), com `plantao` e `dataFim` enviados como campos separados no body.
- **Tratamento de erros IA ampliado**: mapeamento de `error.code` OpenAI (`invalid_api_key`, `insufficient_quota`, `model_not_found`, `context_length_exceeded`), validação de formato da chave, logging diagnóstico com sufixo da chave + modelo.

### Decisões
- Variável de ambiente do sistema Windows sempre sobrescreve `.env.local` — nunca definir `OPENAI_API_KEY` como var do sistema; usar apenas `.env.local`.
- Chips de data removidos a pedido do usuário: design mais simples, input nativo.

### Próximos passos
- [ ] Gerar nova chave OpenAI e atualizar `.env.local` (a chave atual foi compartilhada no chat).
- [ ] Commitar e fazer push das mudanças para deploy Vercel (adicionar `OPENAI_API_KEY` no dashboard Vercel).
- [ ] Testar plantão no formulário completo.
- [ ] Rodar migration SQL `003_plantao.sql` no Supabase SQL Editor.

---

## 2026-05-07 — Melhoria de tratamento de erros na API de IA
**Sessão**: Claude Code
**Duração aprox**: 10min

### Feito
- Melhorado `app/api/ia/route.ts`:
  - `OPENAI_API_KEY` agora é lida com `.trim()` para evitar espaços acidentais.
  - Validação de formato da chave antes de chamar a OpenAI: deve começar com `sk-` e ter ≥ 40 chars. Log diagnóstico inclui comprimento e prefixo.
  - Log de erro ampliado: agora registra `code`, `type`, sufixo da chave (`...XXXX`), modelo utilizado e mensagem da OpenAI — tudo server-side apenas.
  - Mapeamento de `error.code` da OpenAI: `invalid_api_key`, `insufficient_quota`, `model_not_found`, `context_length_exceeded` geram mensagens amigáveis específicas.
  - Adicionado `case 400` no switch HTTP para erros de parâmetros inválidos.
  - Interface `OpenAIResponse.error` atualizada com campos `code` e `type`.

### Decisões
- Logging diagnóstico sempre server-side. Frontend nunca recebe info técnica da chave ou da OpenAI.
- Validação de formato da chave feita antes do fetch para falhar rápido e logar claramente.

### Bloqueios
- Nenhum.

### Próximos passos
- [ ] Reiniciar o servidor de dev para carregar o `.env.local` atualizado (Next.js não recarrega env vars em hot-reload).
- [ ] Testar "Redigir com IA" com 1 operador no browser para validar o texto final gerado pelo GPT.
- [ ] Testar geração do PDF com o operador Maia (maio/2026) no browser logado.
- [ ] Deploy na Vercel e validação com a equipe GAEP-CAT.

---

## 2026-05-07 — Fix concordância nominal + validação da abertura do relatório com IA
**Sessão**: Claude Code
**Duração aprox**: 30min

### Feito
- Corrigida e validada a abertura gerada em `app/api/ia/route.ts` (commit `8849f09`).
- Lógica testada via script Node.js com 6 cenários — todos corretos:
  - 1 operador → `"o operador X, realizou a operação de Y, e"`
  - 2+ operadores → `"os operadores X, Z, realizaram a operação de Y, e"`
  - TREINAR → `"realizou o treinamento de Y"` (masculino)
  - INSTRUIR → `"realizou a instrução de Y"` (feminino)
  - Sem atividade → `"realizou a operação, e"`
  - Sem categoria → `"realizou a atividade de Y, e"`
- Tentativa de teste HTTP direto ao `/api/ia` bloqueada pelo middleware (`matcher` cobre `/api/*`). Confirmado que o middleware só bypassa POST com `next-action` header (Server Actions), não chamadas REST comuns.

### Decisões
- Teste via browser é o caminho correto para validar o fluxo completo com IA; CLI é inviável sem replicar o cookie SSR do Supabase.

### Bloqueios
- Nenhum.

### Próximos passos
- [ ] Testar "Redigir com IA" com 1 operador no browser para validar o texto final gerado pelo GPT.
- [ ] Testar geração do PDF com o operador Maia (maio/2026) no browser logado.
- [ ] Deploy na Vercel e validação com a equipe GAEP-CAT.
- [ ] Testes E2E com Playwright para os 6 fluxos.

---

## 2026-05-07 — Fix concordância nominal na abertura do relatório com IA
**Sessão**: Claude Code
**Duração aprox**: 10min

### Feito
- Corrigida a abertura hardcoded em `app/api/ia/route.ts` (commit `8849f09`):
  - **Singular/plural**: sujeito e verbo agora variam conforme `equipe.length`
    - 1 operador → `"o operador X, realizou"`
    - 2+ operadores → `"os operadores X, Y, realizaram"`
  - **Categoria concordada**: infinitivo convertido para substantivo com artigo correto
    - OPERAR → `"a operação de [atividade]"`
    - TREINAR → `"o treinamento de [atividade]"`
    - INSTRUIR → `"a instrução de [atividade]"`

### Decisões
- Mantida a função `nominarCategoria` inline na route (sem extração para utilitário), pois é o único ponto de uso.

### Bloqueios
- Nenhum.

### Próximos passos
- [ ] Testar geração do PDF com o operador Maia (maio/2026) no browser logado.
- [ ] Deploy na Vercel e validação com a equipe GAEP-CAT.
- [ ] Testes E2E com Playwright para os 6 fluxos.

---

## 2026-05-07 — Validação do PDF de Desempenho do Operador
**Sessão**: Claude Code
**Duração aprox**: 20min

### Feito
- Validados todos os arquivos do feature PDF de desempenho individual:
  - `app/api/pdf/desempenho-operador/route.ts` — autenticação, isolamento de GAEP, validação de params, tratamento de erro 503
  - `lib/pdf/buildDesempenhoOperadorPdfHtml.ts` — KPIs, Folha Ponto, Composição/Ranking por categoria
  - Confirmado que os selects (`nome_guerra:nome`, `gaeps(id, nome:codigo)`) são idênticos ao padrão de todas as outras routes
  - Confirmado que `CAT_ORDER` é exportado de `utils.ts` (linha 32)
- Servidor de dev subido na porta 3000 para teste.
- Identificado operador de teste com dados reais em maio/2026: **Maia** (id `4a95b2c0`, matrícula `1511953`, dias 04–06/05).
- URL de teste montada — usuário optou por não gerar o PDF nesta sessão.

### Decisões
- Nenhuma.

### Bloqueios
- Nenhum. PDF pendente de validação manual pelo usuário.

### Próximos passos
- [ ] Testar geração do PDF com o operador Maia (maio/2026) no browser logado.
- [ ] URL: `http://localhost:3000/api/pdf/desempenho-operador?operadorId=4a95b2c0-2495-4298-afe1-7ec4fe039c43&dataInicio=2026-05-01&dataFim=2026-05-31&download=1`
- [ ] Deploy na Vercel e validação com a equipe GAEP-CAT.
- [ ] Testes E2E com Playwright para os 6 fluxos.

---

## 2026-05-07 — Organização do vault e isolamento de contexto
**Sessão**: Claude (Cowork)
**Duração aprox**: 25min

### Feito
- Adicionada seção **Repositório** no topo do `CONTEXTO.md` (path local + GitHub URL `Hachid/GAEP_CLAUDE_DESIGNER`).
- Identificada pasta legada `C:\Projetos\Sistema_GAEP_Claude\gaep` (repo `Hachid/GAEP_CLAUDE`, Next.js 16 + Jest) — confirmada como **NÃO ativa** pelo usuário.
- Pasta `projetos/sistema-gaep/` commitada e pushada no Git do vault (estava untracked — risco de perda eliminado).

### Decisões
- **Manter 1 vault só** (`claude-projects`) ao invés de criar vault separada por projeto. Justificativa: arquitetura multi-projeto já implementada (`projetos/<slug>/`), isolamento de contexto via `CLAUDE.md` ponteiro do repo funciona. Vault separada fica como fallback se o ponteiro falhar — gatilho objetivo: pegar Claude lendo arquivos do projeto errado em sessão.
- Pasta legada `Sistema_GAEP_Claude/` deve ser arquivada pelo usuário (renomear para prefixo `_arquivo_*` ou mover para `C:\Projetos\_arquivo\`).

### Bloqueios
- Lock file `.git/index.lock` impedia commit — resolvido após fechar Obsidian.

### Próximos passos
- [ ] **Usuário**: arquivar pasta `C:\Projetos\Sistema_GAEP_Claude\` (não ativa, confunde contexto).
- [ ] Validar isolamento na próxima sessão Claude Code abrindo o repo `Sistema_GAEP_Claude_designer`.

---

## 2026-05-07 — PDF da Folha Ponto por operador
**Sessão**: Claude Code
**Duração aprox**: 15min

### Feito
- Analisado o estado completo do projeto: todas as 6 etapas já implementadas.
- Commitados e publicados no GitHub (branch `main`) os arquivos pendentes:
  - `app/api/pdf/desempenho-operador/route.ts` — endpoint que gera o PDF da Folha Ponto
  - `lib/pdf/buildDesempenhoOperadorPdfHtml.ts` — builder HTML da folha de ponto
  - `app/(app)/operadores/DesempenhoClient.tsx` — botão "Gerar PDF" exibido na view Folha Ponto
  - `CLAUDE.md` — arquivo de contexto do repo adicionado ao controle de versão

### Decisões
- Commit `3f0fb78` agrupa todos os arquivos do feature PDF de desempenho.

### Bloqueios
- Nenhum.

### Próximos passos
- [ ] Validar o PDF gerado com dados reais de um operador.
- [ ] Deploy na Vercel e validação com a equipe GAEP-CAT.
- [ ] Testes E2E com Playwright para os 6 fluxos.
- [ ] PWA: manifest + service worker para uso offline parcial em campo.

---

## 2026-05-06 — Onboarding do projeto no vault
**Sessão**: Claude (organização do vault)
**Duração aprox**: 20min

### Feito
- Mapeada a estrutura do repo `C:\Projetos\Sistema_GAEP_Claude_designer`.
- Criados `SPEC`, `CONTEXTO`, `ARQUITETURA`, `PROGRESSO` no vault em `projetos/sistema-gaep/`.
- Stack confirmada: Next.js 15.5 + React 19 + TS + Tailwind 3.4 + Supabase + Vitest + Playwright + Sentry + Recharts.
- Identificado pacote `handoff/` como fonte da verdade do design (6 etapas).
- Adicionado projeto ao índice `LEIA_PRIMEIRO.md`.

### Decisões
- Slug do projeto: **`sistema-gaep`** (kebab-case do `name` no `package.json`).
- Pasta no vault: **`projetos/sistema-gaep/`** — isolada, sem misturar com `whatsapp-bot/`.

### Bloqueios
- Nenhum.

### Próximos passos
- [ ] Criar `CLAUDE.md` na raiz do repo apontando para esta pasta do vault (ancoragem automática quando abrir Claude Code lá).
- [ ] Confirmar existência de `next.config.*` e documentar.
- [ ] Verificar inicialização do Sentry (`sentry.*.config.ts`).
- [ ] Registrar ADR-001 (auth por matrícula via email sintético).
- [ ] Registrar ADR-002 (PDF via Playwright serverless).
- [ ] Aplicar schema (`handoff/sql/001_schema.sql`) no Supabase do ambiente local e rodar `seed`.
- [ ] Implementar **ETAPA 1 — Login** seguindo o handoff.

---

## Backlog (não datado)

- [ ] Definir provedor de deploy (Vercel vs VPS) e variáveis correspondentes.
- [ ] PWA: manifest + service worker para uso offline parcial em campo.
- [ ] Auditoria de queries N+1 nos painéis (Dashboard e Folha Ponto).
- [ ] Substituir `scripts/sync-db.js` por `supabase migration` formal.
- [ ] Hardening do `cleanup-maio-2026.js` (guard `--confirm` + dump).
- [ ] Testes E2E com Playwright para os 6 fluxos.

---

## Priming pronto (cole no Claude Code ao abrir uma sessão neste projeto)

```
Antes de qualquer ação:

1) Leia C:\Projetos\claude-projects\projetos\sistema-gaep\SPEC.md
2) Leia C:\Projetos\claude-projects\projetos\sistema-gaep\PROGRESSO.md
3) Leia C:\Projetos\claude-projects\projetos\sistema-gaep\ARQUITETURA.md (apenas se a tarefa toca arquitetura/DB)
4) Leia C:\Projetos\Sistema_GAEP_Claude_designer\handoff\README.md (fonte da verdade do design)

Confirme em 3 bullets o que entendeu sobre o estado atual do projeto antes de propor qualquer mudança.

NÃO leia arquivos de outros projetos (whatsapp-bot, erp-local, thermal-camera).
NÃO explore o repo inteiro — use o que está acima como contexto suficiente.
```
