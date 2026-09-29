# ADR-008 — Funções `SECURITY DEFINER` como padrão obrigatório para identidade em RLS

**Data**: 2026-06-30
**Status**: Aceito
**Contexto da sessão**: PROGRESSO.md 2026-06-30
**Revisa**: ADR-006 (Tenant boundary: service role + `operador-context` + RLS defesa)

## Contexto

O Supabase enviou um alerta de segurança (`rls_desativado_em_público`) reportando que a tabela `evento_lembretes` do projeto `pxaatetwxnalzqfnihof` estava com RLS desligado e acessível publicamente por qualquer cliente com a URL do projeto. Investigando, ficou claro que `evento_lembretes` e `eventos_agenda` (feature de agenda/lembretes) haviam sido criadas diretamente no banco, fora do fluxo de migrations deste repo (`handoff/migrations/` + `manifest.json`), e por isso escaparam da auditoria de segurança P0→P3 de 2026-06-16/17.

Ao corrigir e validar a nova policy com `SET ROLE anon`, foi descoberta uma falha muito mais ampla: **todas** as policies de RLS "defesa em profundidade" criadas em `20260616_rls_defense_in_depth.sql` e `20260617_rpc_lockdown_and_rls.sql` resolviam a identidade do operador logado com uma subquery direta em `public.operadores` — inclusive a própria policy definida **em** `operadores`. Isso faz a policy de `operadores` reavaliar a si mesma indefinidamente: qualquer `SELECT` nas 15 tabelas afetadas (`operadores`, `relatorios`, `missoes`, `config_ia`, `feriados`, `drive_arquivos`, `config_relatorio`, `gaep_dias_uteis`, `gaeps`, `relatorio_participantes`, `relatorio_versoes`, `eventos_agenda`, `evento_lembretes`, `notificacoes`, `push_subscriptions`) pela chave `anon`/`authenticated` falhava com `infinite recursion detected in policy for relation operadores`.

Isso **não vazava dados** — RLS falha fechado, não aberto — e **não afetava produção**, já que o app usa `service_role` exclusivamente no servidor (que ignora RLS por completo; ver ADR-006). Mas neutralizava por completo o backstop pensado para o caso de a chave `anon`/`authenticated` (pública, embutida no bundle do browser via `NEXT_PUBLIC_SUPABASE_ANON_KEY`) ser usada diretamente contra o PostgREST.

## Decisão

Nenhuma policy de RLS neste projeto deve resolver a identidade do operador via subquery inline em `public.operadores`. Em vez disso, usar funções `SECURITY DEFINER STABLE` com `search_path` fixo:

- `public.current_operador_id()` — `id` do operador logado.
- `public.current_operador_gaep_id()` — `gaep_id` do operador logado.
- `public.current_operador_is_super_admin()` — `true` se `perfil = 'SUPER_ADMIN'`.
- `public.current_gaep_access(target_gaep_id uuid)` — açúcar sintático para o padrão comum `target_gaep_id = current_operador_gaep_id() OR current_operador_is_super_admin()`, usado em 8 das 15 policies.

Essas funções rodam como o *owner* de `public.operadores` (`postgres`, sem `FORCE ROW LEVEL SECURITY`), então leem a tabela sem reavaliar a própria policy — quebra a recursão. Todas mantêm `WHERE auth_id = auth.uid() AND deleted_at IS NULL` (e `perfil = 'SUPER_ADMIN'` na terceira), preservando exatamente a semântica das subqueries que substituíram — verificado policy por policy contra as definições anteriores, sem nenhuma condição enfraquecida.

Grants: `REVOKE ALL ... FROM PUBLIC` + `GRANT EXECUTE ... TO anon, authenticated` explícito em cada função — nunca deixar `PUBLIC` com `EXECUTE`.

Tabelas cuja policy precisa de lógica adicional além do padrão simples (ex.: `deleted_at IS NULL` só no ramo de tenant, não no de `SUPER_ADMIN` — caso de `eventos_agenda`) **não** devem usar `current_gaep_access()`, pois isso aplicaria a condição extra incorretamente também ao ramo admin.

Migrations desta sessão, nesta ordem no manifest: `20260630_retroactive_eventos_agenda_schema.sql` (schema retroativo de `eventos_agenda`/`evento_lembretes`, nunca antes versionado), `20260630_evento_lembretes_rls.sql` (RLS inicial, ainda com o padrão antigo), `20260630_rls_fix_operadores_recursion.sql` (introduz as 3 funções base e reescreve as 15 policies), `20260630_rls_deleted_at_consistency.sql` (alinha `deleted_at IS NULL` entre `relatorios`/`eventos_agenda` e suas tabelas-filhas), `20260630_current_gaep_access_helper.sql` (consolida o padrão repetido em 8 policies).

## Alternativas consideradas

- **Marcar as funções auxiliares como `STABLE` sem `SECURITY DEFINER`** (rodando com o privilégio do caller): não resolve a recursão, porque o caller (`anon`/`authenticated`) ainda estaria sujeito à RLS de `operadores` ao executar a função. Rejeitada.
- **Desabilitar RLS nas tabelas afetadas** (confiar só na camada primária de `service_role` + `operador-context`): abre mão do backstop de defesa em profundidade que a auditoria P0→P3 (fase P3) explicitamente introduziu. Rejeitada — o objetivo da fase P3 era justamente ter uma segunda camada caso a primária falhe.
- **Manter as 15 subqueries inline e só corrigir a recursão em `operadores` com uma exceção pontual**: mais frágil — qualquer nova tabela criada no futuro copiando o padrão antigo reintroduziria o bug (foi exatamente assim que ele se espalhou por 15 tabelas na primeira vez). Rejeitada em favor de um padrão único e centralizado.

## Consequências

- ✅ A camada de defesa em profundidade volta a funcionar para as 15 tabelas — verificado com `SET ROLE anon` em todas, sem erro, 0 linhas (esperado sem JWT).
- ✅ Padrão centralizado: qualquer ajuste futuro na lógica de identidade/tenant muda em 1 lugar (as funções), não em N policies — reduz o risco de drift que causou este incidente.
- ✅ `relatorios`/`eventos_agenda` ficaram mais restritivas que antes (`deleted_at IS NULL` agora exigido no ramo de tenant, onde antes não era) — endurecimento, não regressão.
- ⚠️ `evento_lembretes` e `eventos_agenda` continuam sem `CREATE TABLE` originalmente commitado neste repo antes de 2026-06-30 — a migration retroativa documenta o estado atual, mas não há histórico de como o schema evoluiu antes disso.
- 🔗 Reforça ADR-006 (RLS como camada secundária, nunca primária) — nada nesta correção muda o fato de que `service_role` + `operador-context` continuam sendo a autorização real.

## Mudanças de apoio na mesma sessão (não-arquiteturais)

Sweep manual replicando as regras do Supabase Advisor Security (RLS desligado, RLS sem policy, `search_path` mutável, view `security_definer`, extensão em `public`, uso de `user_metadata`/`auth.role()` em policy) — nenhum alerta novo além do já corrigido. Revisão de segurança + code-review em 5 subagentes paralelos na diff das migrations — nenhuma regressão confirmada. Corrigido também um bug pré-existente e não relacionado de `vi.mock` hoisting em `app/(app)/operadores/__tests__/valeTransporteAction.test.ts` (trocado para `vi.hoisted()`, mesmo padrão de `GestaoClient.test.tsx`).
