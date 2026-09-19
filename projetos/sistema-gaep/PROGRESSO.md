# Sistema GAEP — PROGRESSO

> Log mais recente no topo. Cada sessão = uma entrada datada. Sessões anteriores a 2026-08-06: `PROGRESSO-ARQUIVO.md` (histórico completo preservado, não deletado).

## 2026-09-18 — PDF: subtítulo do cabeçalho sobrepondo o corpo (consolidado GAEP-MOS)

**Sessão**: Usuário reportou, com prints, que o consolidado do GAEP-MOS saía com o subtítulo do cabeçalho ("Relatório de atividades GAEP-MOS") sobreposto ao corpo da página — visível colidindo com a primeira caixa de conteúdo ("Ocorrências: ..."). Tinha tentado ajustar a margem em Gestão › Relatório › Subtítulo sem nenhum efeito. Pedido explícito de `/brainstorming` pra entender a causa antes de mexer.

### Diagnóstico

O cabeçalho de todo PDF oficial (consolidado, relatório individual, efetivo) é o `headerTemplate`/`footerTemplate` nativo do Chromium via Playwright (`lib/pdf/pdfLetterheadTemplates.ts` + `lib/pdf/renderRelatorioPdfPlaywright.ts`), renderizado numa caixa cuja altura é `margin.top`/`margin.bottom`. Dois problemas empilhados:

1. `LETTERHEAD_MIN_MARGIN_MM.top = 34mm` foi calibrado (spec de 2026-08-08) para título institucional de **3 linhas**. O título do GAEP-MOS quebra em **4 linhas** porque a caixa do header no Chromium é mais estreita do que parece — não é a largura inteira da A4, é a página **menos as margens esquerda/direita** (confirmado empiricamente: gerei PDFs reais fixando `margin.top` em 34/40/50/60mm — 34mm sobrepõe, 40mm não). Uma primeira tentativa de correção, medindo a altura do header renderizado numa página normal na largura cheia da A4, subestimou a altura real por essa mesma razão e não resolveu nada até a largura ser corrigida.
2. Os campos de estilo de Título/Subtítulo em Gestão (fonte, cor, alinhamento, margens) **não têm efeito nenhum** no cabeçalho desde o redesenho de 2026-08-08 — `buildLetterheadHeaderTemplate` nunca lê `config.tituloEstilo`/`config.subtituloEstilo`, só usa CSS fixo no código. Por isso o ajuste do usuário não mudou nada: o campo que ele editou nunca foi lido pelo cabeçalho real.

### Fix

`lib/pdf/renderRelatorioPdfPlaywright.ts`: antes de gerar o PDF final, mede a altura real do header/footer numa página descartável do mesmo browser já aberto, na largura correta (`headerFooterContentWidthMm` = largura A4 − margens esquerda/direita), e usa `max(margem configurada, altura medida + 2mm de folga)` como margem efetiva. Cai pro comportamento de hoje se a medição falhar (mesma margem de antes, sem regressão). Sem mudança de rota nem de UI — corrige os 3 tipos de PDF de uma vez, e qualquer unidade futura com título longo.

### Testes e verificação

TDD nas funções puras novas (`parseMm`, `effectiveMarginMm`, `headerFooterContentWidthMm` — `lib/pdf/renderRelatorioPdfPlaywright.test.ts`). Regressão visual manual: script fora do repo (`tsx`) reproduzindo o título real do GAEP-MOS + a caixa "Ocorrências" via o pipeline real (`buildLetterheadHeaderTemplate` + `renderHtmlToPdfBuffer`), PDF renderizado com Chromium real (`channel: 'chrome'`) e inspecionado via screenshot — confirmei a sobreposição existente ANTES do fix de largura (mesmo com a medição de altura já implementada) e o layout limpo DEPOIS. `npx tsc --noEmit` limpo; `npm test` — 128 arquivos / 1108 testes passando (suíte inteira, incluindo mudanças de outras sessões em paralelo na mesma branch).

Commit `9a0755e`, só com os 3 arquivos do fix (não varreu outras mudanças não commitadas de outras sessões na mesma branch). Push e PR #41 (`feat/calendario-remarcar-cancelar` → `main`) abertos nesta sessão.

### Code review pós-fix

`/code-review` rodou sobre o diff da branch inteira (não só o fix de PDF — a branch já tinha 20+ commits de outra feature, remarcar/cancelar/reabrir evento de calendário, feitos por sessões em paralelo). **Nenhum achado nos arquivos do fix de PDF.** 15 achados fora do escopo desta sessão, não corrigidos — decisão de priorização deixada pro usuário:

- Cálculo de intervalo do participante (`lib/atividade/metricas.ts`) pega o dia errado em relatório multi-dia, inflando horas no dashboard e gerando falso conflito/omissão de AFI.
- Ao reabrir/cancelar/remarcar evento como SUPER_ADMIN, a sincronização com o Google usa o `gaepId` do operador em vez do `gaep_id` real do evento — risco de vazar o registro de sync pro GAEP errado.
- "Dia inteiro" no remarcar de evento não reseta os horários herdados do evento original.
- Rollback do remarcar deixa `evento_participantes` órfãos se falhar no meio, sem auditoria.
- Duplicações (helper de paginação, checagem de evento inativo, bloco de escopo+status) e limpezas menores (CSS morto, cores hardcoded, função nunca chamada).

### Pontos de atenção deixados

- Os campos de estilo de Título/Subtítulo em Gestão continuam na UI sem efeito real — não removidos nem sinalizados (decisão consciente, fora do escopo). Próxima sessão que mexer em cabeçalho de PDF: não gastar tempo debugando "por que salvar não funciona" nesses campos — o valor salva certo, só não é lido.
- **Duas sessões concorrentes na mesma branch** (`feat/calendario-remarcar-cancelar`) durante esta sessão: commits `edca08d` e `bc42b6d` apareceram localmente sem eu ter feito nada, exigindo `git push` de novo antes do PR pegar tudo. Mesma lição de processo já registrada em 2026-09-16/17 sobre duas sessões no mesmo diretório — aqui não houve troca de branch, só push assíncrono de outra sessão, mas vale o mesmo cuidado de conferir `git log origin/<branch>..HEAD` antes de abrir PR.
- Os 15 achados do code review (branch inteira) não foram triados nem corrigidos — ver `memory.md` para o resumo e decidir prioridade numa próxima sessão.

## 2026-08-20 — Dashboard: análise cross-GAEP para quem é lotado no SEGAEP

**Sessão**: Usuário reportou (com print da tela) que o filtro "Unidade na análise" do dashboard aparecia só para ele (SUPER_ADMIN). Pedido: todo usuário vinculado ao SEGAEP deve enxergar a dashboard dos outros GAEPs, para gerar relatórios. Tarefa curta e fechada — sem brainstorming, o requisito já vinha completo.

### Diagnóstico

O gate estava replicado em três pontos, todos comparando `perfil === 'SUPER_ADMIN'`:

1. `resolveAnaliseGaepIds` (`app/(app)/dashboard/gaepScope.ts`) — resolvia o escopo de GAEPs da análise.
2. `fetchRelatoriosParaConsolidadoPdf` (`app/(app)/dashboard/actions.ts`) — corpo do PDF consolidado.
3. `dashboard/page.tsx` — montagem de `listaGaepsAnalise`, que alimenta o select.

Um operador ou admin lotado no SEGAEP caía no ramo restrito dos três e ficava preso à própria unidade.

### Decisão de desenho (virou ADR-011)

A saída mais curta seria deixar o SEGAEP trocar a **unidade ativa** — o cookie `gaep-atuando` de `resolverGaepAtivo`. Recusado: a unidade ativa vale para toda Server Action (é lida dentro do próprio `requireOperador`), então isso daria **escrita** em GAEP alheio para resolver um problema de **leitura**.

Optamos por um gate separado, `podeAnalisarOutrosGaeps` (`lib/auth/analise-cross-gaep.ts`): `SUPER_ADMIN` **ou** unidade ativa com código `SEGAEP`. Só leitura analítica, nada além. Consequência assumida: o seletor de unidade da sidebar (`gaepsDisponiveis`) **continua exclusivo do SUPER_ADMIN** — mostrá-lo ao SEGAEP seria um controle inócuo, porque `resolverGaepAtivo` ignora o cookie para os demais perfis.

Custo: a consulta de permissão só roda quando o usuário pede escopo diferente do próprio. Reordenei `resolveAnaliseGaepIds` para retornar antes quando não há `analiseGaepId`, então o caminho normal (a esmagadora maioria dos acessos) não ganhou nenhuma query. A rota do PDF já tinha o código da unidade via `requireOperadorWithGaep` e o repassa no novo 5º parâmetro, economizando o SELECT.

Renomeei a prop `isSuperAdmin` → `podeAnaliseCrossGaep` em `DashboardClient`/`FiltrosDash`: o nome antigo passou a mentir sobre o que o booleano controla.

### Testes e verificação

13 testes novos: `app/(app)/dashboard/__tests__/gaepScope.test.ts` (8) e `lib/auth/__tests__/analise-cross-gaep.test.ts` (5). Cobrem operador/admin de GAEP comum bloqueado mesmo pedindo `__ALL__`, SEGAEP liberado por lookup e por código já informado, SUPER_ADMIN inalterado, GAEP inexistente caindo na unidade ativa, e a asserção de que o caminho sem `analiseGaepId` não chama `from()`.

`npx tsc --noEmit` limpo; `npm run build` compila (só os avisos pré-existentes de OTEL/Sentry). Na suíte completa, `GestaoPage.test.tsx` e `testarPromptIA.test.ts` deram timeout — passam isolados, é a oscilação sob carga já documentada no CLAUDE.md, não regressão.

Commit `65a1b0d` direto na `main` (o repo deploya de lá), push feito. **Verificado em produção pelo usuário**: com conta do SEGAEP não-super-admin, "Unidade na análise" aparece com "Minha unidade (SEGAEP)" como padrão e lista os demais GAEPs.

### Pontos de atenção deixados

- O gate compara com o código literal `SEGAEP` (constante `SEGAEP_CODIGO`). Confirmado em `scripts/gaep-ids.json` que é exatamente esse o código no banco. Uma segunda unidade coordenadora exigiria flag em `gaeps`, não outro literal.
- Assimetria consciente: **Calendário › Disponibilidade** e **Gestão › Efetivo** continuam com a regra mais estrita (`SUPER_ADMIN` *atuando como* SEGAEP, decidida na própria `page.tsx`, com testes que asseguram a string exata da expressão). Não foram tocados — o pedido era do dashboard. Se um dia forem alinhados, migrar para `podeAnalisarOutrosGaeps` em vez de duplicar a comparação.

## 2026-08-18 (tarde) — QTS (Quadro de Trabalho Semanal) + Gestão › Afastamento (tipos configuráveis)

**Sessão**: Usuário reportou dois pedidos pendentes de sessões anteriores (o segundo já pedido ~3×): (1) botão "QTS" não aparecia no Calendário — não existia em lugar nenhum do código/specs, precisou de brainstorming em `AskUserQuestion` pra definir o escopo; (2) menu Gestão → Calendário (só um atalho duplicado para `/calendario`) devia virar Gestão → Afastamento, uma tela de CRUD (Admin/SuperAdmin) para tipos de afastamento.

### QTS — nova aba no Calendário

Lista dia-a-dia do mês: evento(s) do dia (se houver) + contagem e nomes dos operadores disponíveis naquele dia. Fim de semana/feriado com fundo âmbar (`#fef3c7`, mesmo tom já usado em `DisponibilidadePanel`/`CalendarioMes`). Implementado como aba nova (`QtsPanel.tsx`) ao lado de Mês/Disponibilidade/Estatísticas — reaproveita `contarDisponiveisPorDia` via uma função irmã nova, `disponiveisNoDia` (mesma regra, mas devolve a lista de operadores em vez de só a contagem, e sem o gate de dia útil — o QTS precisa dos nomes em todo dia, só destacado visualmente).

### Gestão › Afastamento — tipos de afastamento deixam de ser fixos em código

Até aqui, `TipoAfastamento` era uma união literal fixa (`FERIAS | LICENCA_MEDICA | ATESTADO | MISSAO_EXTERNA | FOLGA | OUTRO`) validada por um `CHECK` no Postgres. Virou uma tabela por GAEP (`tipos_afastamento`: `codigo`, `label`, `ativo`, soft delete), com CRUD em nova aba **Gestão → Afastamento** (substituiu o atalho antigo pro Calendário — não fazia sentido duas entradas de menu apontando pro mesmo lugar).

**Migration** `20260818_tipos_afastamento.sql` (`_app_migrations` id — próximo após 20260815): tabela + índice único `(gaep_id, codigo) WHERE deleted_at IS NULL` (permite recriar um código já excluído sem colidir) + RLS SELECT (`current_gaep_access`, mesmo padrão de `agenda_afastamentos`) + seed dos 6 códigos legados pra cada GAEP ativo (`ON CONFLICT DO NOTHING`, idempotente) + `DROP CONSTRAINT agenda_afastamentos_tipo_check` (remove o CHECK fixo). **Aplicada em produção nesta sessão** (`db:sync` segue bloqueado pelo checksum de abril — script avulso replicando o bookkeeping do `sync-db.js`, mesmo padrão das migrations de 08-13/08). Verificado direto no banco: 36 linhas (6 tipos × 6 GAEPs), RLS ligada, CHECK antigo removido (contagem 0).

**Compat. de tipo**: `TipoAfastamento` virou `string` (era união literal); `TIPOS_AFASTAMENTO`/`LABEL_TIPO_AFASTAMENTO` ficaram como `@deprecated` apontando pros novos `TIPOS_AFASTAMENTO_LEGADO`/`LABEL_TIPO_AFASTAMENTO_LEGADO` (usados só como seed/fallback). Nova função `labelTipoAfastamento(tipo, tiposDoGaep)` resolve o rótulo: procura na lista do GAEP (inclusive tipos já desativados — afastamento histórico não pode ficar sem nome) → cai pro label legado hardcoded → devolve o código bruto como último recurso.

**Validação server-side**: `criarAfastamento`/`atualizarAfastamento` (`app/(app)/calendario/actions.ts`) trocaram o `TIPOS_AFASTAMENTO.includes(...)` em memória por `tipoAfastamentoValido(admin, gaepId, tipo)` — SELECT em `tipos_afastamento` filtrado por `gaep_id` da sessão + `ativo = true`. Em `atualizarAfastamento`, só revalida se o tipo está **mudando** (`input.tipo !== row.tipo`) — permite corrigir outros campos (data, descrição) de um afastamento cujo tipo foi desativado depois, sem forçar troca.

**Formulário "Novo afastamento"** (`CalendarioMes.tsx`): dropdown de tipo agora vem de `tiposAfastamento` (prop, carregada em `calendario/page.tsx`), só tipos `ativo`. Edição de afastamento com tipo já desativado inclui esse tipo na lista marcado "(inativo)" — mesmo raciocínio já usado pra operador inativo (`opcoesOperador`).

### Testes e verificação

- `criarAfastamento rejeita tipo inválido`: reescrito — a validação agora bate no banco (`tipos_afastamento`), não é mais um `includes()` em memória; assertiva trocou de "admin nunca chamado" pra "chamado só com `tipos_afastamento`, nunca com `agenda_afastamentos`".
- `GestaoPage.test.tsx` (2 casos) e `testarPromptIA.test.ts`: falharam rodando junto com o lote completo (`STACK_TRACE_ERROR` na coleta), passaram 100% isolados — é a flakiness pré-existente já documentada no `CLAUDE.md`/`ARQUITETURA.md` (mocks de auth sob execução paralela), não regressão desta sessão.
- `npx tsc --noEmit`: limpo. `npx vitest run` (suíte completa): **742/742**. `npm run build`: verde (warnings pré-existentes de Sentry/OpenTelemetry, não relacionados).

### Code review (`/code-review high`) — 3 achados, todos corrigidos

1. **`lib/calendario/consolidado.ts` descartava em silêncio afastamento com tipo customizado**: `isTipoAfastamentoValido` ainda filtrava contra a lista legada de 6 tipos fixos — sobrevivência do padrão antigo depois que `TipoAfastamento` virou `string` livre em `page.tsx`, exatamente a armadilha de "atualizar todos os call sites" que o `CLAUDE.md` já documenta pra `config_ia`/`config_relatorio`. Um afastamento com tipo custom (ex.: "CURSO") sumia do painel consolidado cross-GAEP (SEGAEP), mostrando o operador como disponível quando na verdade estava afastado. Corrigido: função removida, filtro por `gaep_id` sem checagem de tipo. Teste `descarta afastamento com tipo inválido/desconhecido` reescrito pra `mantém afastamento com tipo customizado`.
2. **`adicionarGaep()` não semeava `tipos_afastamento` pro GAEP novo**: mesmo incidente do `config_ia` de 13/08 ("seed roda uma vez na migration, nada roda quando a unidade é criada depois") — GAEP criado depois desta feature ficaria com `tipos_afastamento` vazia, e "Novo afastamento" no Calendário renderizaria um `<select>` sem opções, com toda submissão falhando sem pista do motivo. Corrigido: `adicionarGaep()` agora semeia os 6 tipos legados logo após criar o GAEP (best-effort — falha no seed não desfaz o GAEP já criado, só loga; admin cadastra manualmente se precisar).
3. **Update otimista no formulário "Novo Tipo" usava o código bruto do form, não o normalizado pelo servidor**: `adicionarTipoAfastamento` normaliza o código (maiúsculas, sem acento, `_` no lugar de espaço) antes de gravar, mas o cliente atualizava a lista local com `form.codigo.trim().toUpperCase()` — badge divergente do valor real até o próximo refresh (acento/espaço/pontuação sobrando). Corrigido: a action passou a devolver `codigo` normalizado; o cliente usa esse valor no update otimista.

Suíte completa revalidada após as correções: **742/742**, `tsc --noEmit` limpo, `npm run build` verde.

### 2ª rodada de `/code-review high` (pedida pelo usuário, achando que a feature já tinha sido desenhada antes) — 1 bug real + 2 limpezas

Antes de rodar de novo, investiguei se havia implementação anterior perdida (usuário relatou "já tínhamos desenhado e implementado isso e foi perdido"): `git log --all` (todas as branches + `-S"tipos_afastamento"`/`-S"QTS"` no conteúdo dos commits), `git stash list`, `git worktree list`, specs/planos em `docs/superpowers/`, e o próprio `PROGRESSO.md`. **Nenhum vestígio de código** — o único commit relacionado (`3606899`, 16/08) foi puramente cosmético: renomeou o rótulo do atalho de "Afastamentos" pra "Calendário" porque o item sempre apontou pra `/calendario` (nunca existiu tela de CRUD de tipos). Conclusão: o que foi "perdido" foi uma conversa de design de uma sessão anterior que passou por `/clear` — nunca virou spec/plano salvo em disco, só ficou no contexto da conversa. Coerente com o próprio usuário ter respondido "já brainstormamos isso, mas vamos novamente" quando perguntei o que era o QTS no início desta sessão.

Achados do 2º review:
1. **Bug real — conversão evento→afastamento podia enviar tipo inativo**: `FormAfastamento` chuta `tipo: 'FERIAS' | 'OUTRO'` a partir do título do evento (regex `/f[ée]rias/i`), mas esse valor nunca era revalidado contra `opcoesTipo` (tipos ativos do GAEP) antes do submit — ao contrário do que já acontecia pro operador (`operadorEfetivo`). Se o admin desativasse 'OUTRO' em Gestão › Afastamento (uso normal da própria feature nova) e alguém convertesse um evento sem "férias" no título, a submissão falhava com "Tipo de afastamento inválido" sem pista visual. Corrigido com o mesmo padrão de `operadorEfetivo`: novo `tipoEfetivo` que cai pro primeiro tipo ativo se o valor atual não estiver em `opcoesTipo`. Teste de regressão novo: `converter evento em afastamento não envia tipo inativo/inexistente do GAEP` (`CalendarioMes.test.tsx`).
2. **Limpeza — `TIPOS_AFASTAMENTO`/`LABEL_TIPO_AFASTAMENTO` `@deprecated` sem consumidor**: os aliases "pra compat" que criei na 1ª rodada não tinham nenhum import real fora de `.worktrees/` (só um comentário mencionando o nome antigo). Removidos — ficaram só `TIPOS_AFASTAMENTO_LEGADO`/`LABEL_TIPO_AFASTAMENTO_LEGADO`.
3. **Limpeza — regex de acentos duplicada**: `normalizarCodigoTipoAfastamento` (`gestao/actions.ts`) tinha uma cópia literal do `UNICODE_COMBINING_MARKS` que já existia em `lib/calendario/disponibilidade.ts`. Exportado de lá, importado em vez de duplicado.

Suíte revalidada de novo após esta rodada: **743/743** (nova + as 742 antigas), `tsc --noEmit` limpo, `npm run build` verde.

### Apontamentos técnicos pra próximas sessões

1. **`tipos_afastamento` é o 3º caso do padrão "tabela configurável por GAEP com CRUD em Gestão"** — mesmo molde de `feriados`/`tipos_missao`: RLS SELECT via `current_gaep_access`, mutação só por `service_role` com `requireOperadorAdmin` + `assertSameGaep`/`assertInputGaepScope`, soft delete. Se aparecer um 4º caso (ex.: categorias de evento), reaproveitar esse molde em vez de reinventar.
2. **Código normalizado, não livre**: `normalizarCodigoTipoAfastamento` em `gestao/actions.ts` (maiúsculas, sem acento, `_` no lugar de espaço) — evita códigos incompatíveis por capitalização/acentuação entre GAEPs, mesmo raciocínio de nunca deixar o usuário digitar um identificador técnico sem sanitizar.
3. **QTS não é paginado nem filtrado por operador** — lista todo mundo disponível em toda linha do mês inteiro. Para GAEPs com efetivo grande, pode valer revisar performance/UX depois (a lista de nomes por dia pode ficar longa); não houve pedido explícito de filtro nesta sessão.


## 2026-08-18 — Designação de Chefe em Eventos + Notificação com Destaque

**Sessão**: Usuário pediu "coloque outra caixinha para definir o Chefe" na tela de disponibilidade do evento, destacado em âmbar. Chefe responsável pela missão, recebe push com `👮 Chefe: {nome}` na 1ª linha.

### Feature: Chefe de Evento (UI + Backend)

**Design escolhido**: radio "Chefe" **na própria linha** de cada operador em "Disponibilidade no período" — em vez de panel separado. Evita duplicar a lista de 100+ líneas, reutiliza o markup existente.

**Invariantes (integrados ao form)**:
- Um único chefe por evento (radio group singleton)
- Marcar chefe **auto-inclui** o operador na notificação (nunca fica responsável fora do aviso)
- Desmarcar da notificação quem é chefe **limpa** o chefe (mesmo motivo)
- Trocar o período ou "Limpar seleção" também limpa o chefe (período muda, disponibilidade pode mudar, logo responsável pode ficar inválido)

**Visual**: tarja âmbar (`#fbbf24` border-left + fundo `#fffbeb`) + badge "Chefe" em maiúsculas (0.68rem, peso 800). Destaca a linha selecionada; não usa emoji na UI.

**Backend (`resolverNotificacaoEvento` refatorado)**:
- Devolve `nomePorId: Record<string, string>` além de `operadorIds`/`emails`
- Nova função `resolverNomeChefe(chefeId, notificacao)` — só resolve nome de id que **sobreviveu à validação de gaep_id/ativo**
- Chefe de outro GAEP, inativo, ou fora da lista nunca vira nome (nunca vaza tenant-crossing, nunca varia `undefined` no push de id forjado)

**Push de notificação**: corpo passa de `"Sala 2 · 2026-07-10"` pra `"👮 Chefe: Bruno Costa\nSala 2 · 2026-07-10"` quando há chefe — destaca a informação que muda o que o operador precisa fazer.

### Rebase na refatoração de notificação (origin/main PR #21)

O repositório avançou enquanto esta sessão rodava (PR #21: `coletarDisponiveisDoPeriodo` → `resolverNotificacaoEvento`, validação de IDs em vez de cálculo de disponibilidade). Opções:
1. ❌ Merge manual (2 arquitetures convivendo) — confuso
2. ❌ Desfazer e refazer (retrabalho) — lento
3. ✅ **Rebase em cima da remote** — limpo, alinhado

Executado: `git reset --hard origin/main` (backup de worktree criado), backup do componente `SelecionarChefePanel.tsx` pro scratchpad, rebase local com adaptação à nova arquitetura (`resolverNotificacaoEvento` + `notificarOperadorIds: string[]`). Feature refatorada em ~120 min de rebase + ajuste de testes.

### Testes

- UI: `DisponibilidadeEventoLista.test.tsx` — 11 novos tests (seleção, tarja, radio, integração com notificação). Novo helper `renderLista()` que pré-popula as props comuns.
- Backend: `notificarDisponiveis.test.ts` — 5 novos tests (`nomePorId` em sucesso, `resolverNomeChefe` com 3 cenários, push com chefe destacado, push sem chefe). 
- Server Action: `calendarioActions.test.ts` — 3 novos tests (chefe válido passa `chefeNome` ao push; chefe de outro GAEP não vira nome; module mock com `importOriginal` pra funções puras não serem mockadas).
- Suíte completa: **82/82 testes** de calendário passando; `tsc --noEmit` limpo.

### Otimizações de tokens nos arquivos de contexto

1. **PROGRESSO.md**: consolidado histórico anterior (2026-08-08 / 2026-08-07) em versões mais concisas, removendo detalhes pré-históricos; nova entrada minimalmistas (o que era feito, decisões, apontamentos)
2. **CLAUDE.md**: atualizado estado atual (2026-08-18) com designação de Chefe; seção de "Regras de trabalho" compactada (removidas cópias de instruções já no ARQUITETURA.md)
3. **ARQUITETURA.md**: sem mudanças arquiteturais maiores — feature cabe no escopo de "Servidor Actions" existente; menção adicionada em "3. Estrutura de pastas" (calendario → disponibilidade)

### Apontamentos técnicos pra próximas sessões

1. **Escolha: UI-level chefe, não persistido** — decisão deliberada. O chefe é **transitório no contexto da criação/edição**, não é atributo do evento. Se virar persistido depois, seria uma migration + coluna + RLS. Por enquanto: só notificação imediata.

2. **Armadilha de `nomePorId` e GAEP scope** — `resolverNotificacaoEvento` já filtra por `gaep_id` e ativo; `resolverNomeChefe` só resolve de `nomePorId` (já validado). Impossível vazar nome de outro tenant. Testar em isolation: um `chefeId` de produção não decifra nome em staging.

3. **Push com emoji** — `👮` escolhido (polícia = responsável/chefe); fácil trocar (`👔 Chefe:`, `💼 Responsável:`, etc.) em uma linha. Sem emoji na badge da UI (âmbar + texto é destaque suficiente).

4. **Merge limpo com rebase** — quando a remote muda enquanto você trabalha (common em time), rebase preserva história limpa. Aqui: `main` chegou em `279e500` enquanto este branch rodava em `9bc9250` (commit local da feature 1ª versão). Reset para a remote, rebase local em 1 commit novo com adaptação arquitetural.

### Commit e Push

- `de762cb`: feat(calendario): designação de Chefe (82/82 testes) 
- `1ff380b`: fix(calendario): emoji chefe 👑→👮

---

## 2026-08-13 — Dois bugs em produção às vésperas do rollout: IA quebrada em 4 GAEPs + fragilidade do upload de foto

**Sessão**: O sistema começa a ser usado por todos os GAEPs na semana que vem (40 operadores, 6 relatoristas diários). Um relatorista do **GAEP-MOS** mandou print com dois erros na mesma tela: "Não foi possível enviar a foto no momento" (já tinha acontecido e sido corrigido em 06/08) e "Configuração de IA não encontrada. Contate o administrador" (inédito). Investigação via `systematic-debugging`.

### Bug 1 — IA: causa raiz determinística, afetava 4 das 6 unidades

`config_ia` só tinha linha para **GAEP-CAT e GAEP-PV**. Faltava em **GAEP-BRA, GAEP-CG, GAEP-MOS e SEGAEP** — o seed (`handoff/sql/002_seed.sql:57`) insere config para um único GAEP e nada cria a linha quando uma unidade nova é cadastrada. `app/api/ia/route.ts` fazia `.single()` e devolvia 404 fechado.

**Por que ninguém tinha visto**: a tela de Gestão mentia. `app/(app)/gestao/page.tsx` tinha um default hardcoded (em 3 lugares) que preenchia o formulário mesmo sem linha no banco, então o admin via a IA como "configurada". Pior: `testarPromptIA` recebe os valores do formulário e **nunca lê `config_ia`** — o admin clicava "Testar prompt", funcionava, e concluía que estava tudo certo, enquanto todo relatorista da unidade tomava 404. A prova disso ficou no banco: o prompt do GAEP-PV (salvo em 09/08) é **exatamente** o default hardcoded da UI — alguém abriu a tela, viu preenchido e salvou.

**Correção**: `lib/ia/config.ts` como fonte única do default (elimina as 3 cópias); `/api/ia` passa a `maybeSingle()` + fallback para o padrão (unidade sem config funciona, com `console.warn` para o admin cadastrar), e distingue erro de leitura (502) de ausência de linha. Não foi preciso semear as 4 linhas faltantes — o fallback resolve, e semear reintroduziria a duplicação.

### Chave OpenAI por GAEP (pedido do usuário na sessão)

Para controlar custo por unidade: `OPENAI_API_KEY_{CODIGO}` (ex.: `OPENAI_API_KEY_GAEP_MOS`), com fallback na `OPENAI_API_KEY` global. Decisão: **variável de ambiente na Vercel**, não coluna criptografada em `config_ia` — a Vercel já criptografa, a chave nunca toca banco nem navegador, e evita migration + AES-GCM + mascaramento na UI. Detalhe deliberado: chave dedicada **malformada não cai no fallback global** — cair mascararia erro de digitação e jogaria o custo daquela unidade na conta compartilhada, o oposto do objetivo.

### Bug 2 — Foto: NÃO era o bug de 06/08; era fragilidade estrutural

O fix de 06/08 (`d8adc80`, `doPost` duplicado no Apps Script) era falha total e permanente. Testei a ponte de verdade: `healthCheck` OK; **3 uploads paralelos** (padrão real do `FotoUpload.tsx`) 3/3 OK em 5,9–7,2s; **6 uploads simultâneos** (6 relatoristas) 6/6 OK em 4,6–7,3s. Ou seja: **foi transitório**. O problema real é que o sistema não tinha como sobreviver a — nem sequer diagnosticar — um blip:

1. **Motivo do erro descartado**: `apps-script-provider.ts` fazia `throw new StorageUploadError()` **sem argumento**, jogando fora o `data.error` do Apps Script. O log do Vercel só dizia "Storage upload failed" — o erro era, por construção, não-diagnosticável.
2. **Zero retry** em qualquer camada, com 4,5–7,3s de latência por foto.
3. **Zero timeout** no `fetch` — chamada pendurada travava a Server Action.
4. **Colisão de nome → sobrescrita silenciosa**: `buildFotoPath` aceita `reportId` para desambiguar, mas `uploadRelatorioFoto` **não passava**. O Apps Script (`handleUploadFile`) manda pro lixo qualquer arquivo homônimo antes de criar o novo — dois relatórios do mesmo GAEP/dia/categoria/atividade e o segundo destruía a foto do primeiro, que virava link morto no PDF já emitido. Consultei produção: **0 casos até agora, mas já havia 10 grupos com a chave repetida** — só não estourou porque apenas 27% dos relatórios têm foto (59 de 221).
5. **Foto perdida no erro**: o cliente descartava o `File` já comprimido, obrigando o relatorista a reabrir a galeria.

**Correções**: retry (3 tentativas, backoff exponencial + jitter) só em falhas transitórias — `Missing required fields` é determinística e não repete; timeout de 30s por tentativa; motivo real preservado na mensagem interna (`userMessage` continua sem vazar detalhe); `downloadFile` passou a lançar `StorageDownloadError` em vez de erro de upload. No cliente, arquivos que falharam ficam guardados e há botão **"↻ Tentar novamente"**, sem reabrir a galeria.

### Nome da foto no Drive (formato definido pelo usuário)

Novo: `GAEP-CAT - 13.08.2026.1 - OPERAR - APOIO A UNIDADE - 01.jpg` (código do GAEP na frente, sequência do dia após a data). A foto sobe **antes de o relatório existir**, então a sequência é alocada no 1º upload e reusada pelas outras fotos via `rascunhoId` (UUID gerado por montagem do `FotoUpload`; o `key={fotoUploadKey}` do `RelatorioForm` já força remontagem após salvar, então cada relatório ganha id novo).

**Migration `20260813_relatorio_sequencias.sql`** (tabela append-only + RPC `alocar_sequencia_relatorio`): alocação atômica via constraint única + retry no `unique_violation`, mesmo padrão anti-TOCTOU de `20260807_sync_feriados_automaticos_fn.sql` — `max(seq)+1` no app teria a mesma janela de corrida. RLS habilitada sem policies (default-deny, só service role), como `pdf_validacoes`. Sem soft delete de propósito: apagar permitiria realocar um número e recriar a colisão.

`db:sync` segue bloqueado (checksum de `20260429_config_relatorio.sql`, pendência de abril). Aplicada manualmente com **migration + bookkeeping na mesma transação** (ou as duas coisas ou nenhuma) — registrada em `_app_migrations` **id 60**. Verificada em produção: rascunho novo → 1; mesmo rascunho reusa 1; outro rascunho → 2; **6 alocações concorrentes → [3,7,6,4,8,5], todas distintas**.

### Entrega e verificação

- `npx tsc --noEmit` limpo; `npm run build` verde; `npm test` **601/602**.
- A falha isolada é **flakiness pré-existente**, não regressão: provei rodando o mesmo lote de 5 arquivos na árvore limpa (`git stash`) 3× — a run 2 falhou 3 testes **sem nenhuma mudança minha**. Os arquivos passam isolados. É timeout de 15s sob carga paralela, atingindo aleatoriamente testes que dependem de mocks de auth. **Vale investigar à parte** — mascara regressão real.
- Chave OpenAI validada ponta a ponta (HTTP 200, gpt-4o, texto correto com o prompt padrão).

### Chave OpenAI gerenciável pelo super admin (2ª parte da sessão)

O usuário criou as 5 chaves na OpenAI (SEGAEP, GAEP-PV, GAEP-MOS, GAEP-CG, GAEP-CAT — **GAEP-BRA não tem, e está correto**: 0 operadores e 0 relatórios, cai na global) e perguntou se dava para cadastrar direto em Gestão em vez de env var na Vercel, restrito a ele como super admin. Decisão: **fazer as duas coisas** — env var cadastrada agora (não bloqueia o lançamento) e a tela como camada de precedência maior, para ele rotacionar sozinho sem redeploy.

Implementado: `lib/ia/keyCrypto.ts` (AES-256-GCM, chave-mestra em `CONFIG_IA_ENC_KEY`, **`gaep_id` como AAD** — linha copiada para outra unidade não decifra), migration `20260813_config_ia_openai_key.sql` (**`_app_migrations` id 61**), actions `salvarChaveOpenAI`/`removerChaveOpenAI` com gate `requireSuperAdmin`, e seção na aba Config IA visível só para SUPER_ADMIN.

Decisões de segurança: a chave **nunca volta ao navegador** depois de salva (a tela lê `openai_key_mask`, nunca `openai_key_enc`; não há botão "revelar" — rotacionar na OpenAI leva segundos, então a comodidade não paga a superfície de vazamento); audit log grava **só a máscara**; sem `CONFIG_IA_ENC_KEY` a action **recusa gravar** em vez de cair para texto puro; e chave gravada que não decifra devolve **503** em vez de cair na global — cair mascararia o problema e jogaria o custo na conta compartilhada.

Atenção aplicada de propósito: `config_ia` tem a mesma armadilha de `config_relatorio` do PR #15 (PostgREST só devolve colunas nomeadas). Mapeei os 2 call sites antes de escrever a coluna e criei `lib/ia/__tests__/configIaSelectSites.test.ts`, que além de exigir `openai_key_enc` em `/api/ia` **proíbe** `openai_key_enc` no SELECT da Gestão.

Verificado contra o banco real (GAEP-BRA, chave falsa, limpo depois): texto puro não aparece no banco; decifra com o gaep certo; **recusa decifrar com outro gaep_id**; máscara correta.

### Pendências

1. **Definir `CONFIG_IA_ENC_KEY` na Vercel** (gerada nesta sessão, está no `.env.local`) e **cadastrar `OPENAI_API_KEY_*` por GAEP** — ambas só valem a partir do próximo deploy. Depois disso, as chaves podem migrar para a tela.
2. **Flakiness da suíte** (acima) — investigar isolamento de mocks entre arquivos.
3. **Prompt por unidade**: as 4 unidades sem `config_ia` usam o padrão. Personalizar via Gestão › IA quando quiserem.
4. Nada foi commitado — mudanças estão na árvore de trabalho, `main` limpa até então.


## 2026-08-08 — Cabeçalho oficial do PDF (brasões PPF+GAEP) + correção de paginação — PR #15

**Sessão**: Usuário reportou 3 bugs visuais no PDF de Relatório (com screenshots): brasão sobrepondo o título, autenticação/rodapé sobrepondo ocorrências, fotos sobrepondo o brasão na página 2+. Perguntou se valia abandonar o papel timbrado e criar um modelo próprio do sistema.

### Causa raiz

Margem simulada via CSS `padding` + `position:fixed` (cabeçalho/rodapé "grudados" no topo/base da página via `position:fixed`, conteúdo com `padding-top`/`padding-bottom` do tamanho do cabeçalho/rodapé pra não invadir aquele espaço). Esse hack só reserva espaço corretamente na primeira e na última página do PDF — em qualquer página do meio, o navegador (Playwright/Chromium) não sabe que precisa repetir aquele padding, e o conteúdo flui por cima.

### Solução (brainstorming → spec → plano → `subagent-driven-development`)

Trocar pro mecanismo nativo do Playwright: `page.pdf({ margin, displayHeaderFooter: true, headerTemplate, footerTemplate })` — o Chromium desenha cabeçalho/rodapé de forma independente em cada página, dentro da margem real (não simulada). Layout novo: brasão da PPF (esquerda) + título/subtítulo (centro) + brasão do GAEP (direita), configuráveis por unidade — substitui o "Timbrado" antigo (uma imagem de fundo A4 inteira, hardcoded pro GAEP-CAT em alguns pontos).

**Documentos**: `docs/superpowers/specs/2026-08-08-pdf-relatorio-cabecalho-oficial-design.md` (spec) → `docs/superpowers/plans/2026-08-08-pdf-relatorio-cabecalho-oficial.md` (plano, 12 tasks).

### Execução — `subagent-driven-development`, 12 tasks + 1 review final de branch inteira

Cada task: subagent implementador dedicado + review de spec/qualidade independente antes de avançar. Duas rodadas de fix em tasks individuais:
- **Task 4** (`contentDispositionFilename.ts`, nome do arquivo acentuado no download): reviewer achou 2 gaps de RFC 5987 (`filename*=` não escapava `'()* `corretamente; `filename="..."` não escapava aspas literais) — plan-mandated (código idêntico ao do plano), escalado ao usuário, aprovado pra corrigir. Fixed + 3 testes novos.
- **Task 7** (`salvarBrasaoBase64`/`removerBrasao`, server actions de upload dos brasões): reviewer achou que a action confiava no `gaepId` vindo do cliente sem checar contra a sessão (`assertSameGaep`) — herdado do timbrado antigo, não regressão desta task, mas viola a regra do próprio projeto ("IDs vindos do formulário só preenchem UX — autorização vem da sessão"). Corrigido usando o helper já existente no codebase.

**Migration** (`handoff/migrations/20260808_config_relatorio_brasoes.sql`, colunas `brasao_ppf_url`/`brasao_gaep_url` em `config_relatorio`): `npm run db:sync` estava bloqueado por um checksum divergente **pré-existente e não relacionado** numa migration de abril (`20260429_config_relatorio.sql`) — o `sync-db.js` para no primeiro mismatch que encontra, então ninguém consegue rodar `db:sync` até isso ser investigado à parte. Migration desta sessão foi aplicada manualmente (script avulso replicando a bookkeeping exata do `sync-db.js` — mesmo checksum, mesma tabela `_app_migrations`) e **verificada de forma independente direto no banco** (colunas existem, checksum bate byte a byte com o arquivo commitado). Foi definida uma política daqui pra frente: se um subagent topar com esse mesmo bloqueio de `db:sync`, deve perguntar antes de aplicar DDL manualmente, não decidir sozinho.

**Task 12** (limpeza final + `npm run build`): achou de brinde um código morto (`compressToA4Jpeg`, órfão desde a Task 8) que estava quebrando o build de produção por regra do ESLint — `tsc --noEmit` sozinho não pega isso. Corrigido no mesmo commit.

### Review final de branch inteira — achou o bug mais sério da sessão

Depois das 12 tasks aprovadas individualmente (0 findings bloqueantes sobreviventes), rodei uma review adicional olhando o diff inteiro de uma vez — exatamente pra pegar o que review task-por-task não consegue ver. Achou **2 bugs Críticos**, ambos falhas de "encanamento" de dado, invisíveis a qualquer review de arquivo isolado:

1. **Nenhum dos 4 arquivos que consultam `config_relatorio`** (`app/api/pdf/[id]/route.tsx`, `app/api/pdf/consolidado/route.ts`, `app/relatorio/[id]/page.tsx`, `app/(app)/gestao/page.tsx` — 8 pontos contando os fallbacks) **buscava as colunas novas no `SELECT`**. Resultado: mesmo com a migration aplicada e tudo implementado certo, o Supabase nunca devolvia `brasao_ppf_url`/`brasao_gaep_url`, e nenhum PDF em produção mostraria brasão nenhum, pra nenhum GAEP — a feature inteira do plano ficaria inatingível apesar de "tudo passar".
2. `app/(app)/gestao/page.tsx` **hardcodava `null`** nesses dois campos em 3 pontos, em vez de ler o dado real — a própria tela de administração dos brasões perderia o que foi configurado a cada reload.

Verifiquei os dois achados manualmente (grep direto) antes de aceitar como reais. Corrigidos numa fix wave única + teste de regressão novo (`lib/pdf/configRelatorioSelectSites.test.ts`, lê os arquivos-fonte reais do disco e garante que os 4 pontos de SELECT continuem com as colunas dos brasões). Durante a re-review da fix wave, apareceu uma **recorrência do mesmo padrão** em `app/(app)/missoes/relatorio/page.tsx` (fora do escopo original do plano) — corrigida também, de forma cirúrgica (sem forçar o mesmo refactor da Gestão, porque esse arquivo tem defaults diferentes).

### Entrega

- 19 commits (2 de doc + 17 de implementação) — `df762e6`..`1d0634b` na branch `fix/build-audit-2026-08-05`.
- `tsc --noEmit` limpo (projeto inteiro), `npm test` 452/452 (as 2 suítes que falham na coleta por `SUPABASE_URL` ausente no Vitest são pré-existentes, confirmado com `git diff` que nenhum arquivo por trás delas foi tocado — ver sessão 2026-08-07 sobre esse gap), `npm run build` verde.
- PDFs reais gerados via Chromium (Relatório 3 páginas, Consolidado 3 páginas/14 relatórios/9 fotos) e inspecionados visualmente em cada task — confirmado sem sobreposição em nenhuma página.
- **Descoberta no meio do processo**: o PR #5 (que este branch carregava aberto desde 06-08) já tinha sido mergeado em `main` por fora desta sessão — informação no `CLAUDE.md` estava desatualizada. Verificado que `main` já contém todo o histórico anterior deste branch antes de decidir como prosseguir (`git merge-base --is-ancestor`), então o PR novo ficou com diff limpo, só o trabalho desta sessão.
- **PR #15 aberto contra `main`**: https://github.com/Hachid/Sistema_GAEP/pull/15.

### Merge do PR #15 — conflito real com o trabalho dos PRs #7-#14

`main` tinha avançado bem mais do que o esperado enquanto esta sessão rodava (PRs #7 a #14 mergeados por fora — convite ao efetivo, drill-down de PDF, correção de race condition em feriados, 2 hotfixes de produção). `gh pr merge` falhou (merge commit não podia ser criado automaticamente). Merge local (`git merge origin/main`) achou 6 arquivos com mudança sobreposta; 2 conflitos de texto reais (`CLAUDE.md`, `handoff/migrations/manifest.json` — resolvidos combinando as duas versões) e 4 arquivos que o Git auto-mergeou **sem marcar conflito** (`GestaoClient.tsx`, `actions.ts`, `page.tsx` da Gestão, seus testes).

**Não confiei no auto-merge silencioso** — rodei `tsc --noEmit` depois de resolver os conflitos de texto e achou 3 erros num terceiro ponto de construção de `ConfigRelatorioUIData` em `gestao/page.tsx` (o branch `gestaoModo: 'view-only'` usado pelo acesso de leitura do AUDITOR, que **chegou em `main` depois que este branch divergiu** — nunca existiu na história deste branch, então a correção do bug Crítico #2 desta sessão nunca tinha visto esse terceiro site pra corrigir). O merge automático do Git preservou os dois lados sem conflito porque estavam em regiões diferentes do arquivo, mas o resultado era logicamente incompatível: meu lado removeu os imports de `DEFAULT_TITULO_RELATORIO_INSTITUCIONAL`/`DEFAULT_PRINT_MARGINS_MM` (não precisava mais deles após rotear por `configRelatorioFromRow`), e o lado de `main` ainda os referenciava num literal hand-rolled. Corrigido substituindo esse terceiro literal por `configRelatorioFromRow(null)` também (confirmado campo-a-campo idêntico ao hand-rolled antes de trocar).

Verificação pós-merge: `tsc` limpo, **521/521 testes** (subiu de 452 porque `main` trouxe bastante teste novo), `npm run build` verde, Vercel preview do merge commit com build `SUCCESS` antes de mergear de fato. **PR #15 mergeado em `main`** (commit de merge `80eeccd`): https://github.com/Hachid/Sistema_GAEP/pull/15.

**Lição**: merge automático sem conflito marcado não é garantia de correção — só significa que o Git conseguiu combinar as linhas sem ambiguidade textual. Quando dois branches fazem refactor divergente no mesmo arquivo (aqui: um lado remove um import que o outro lado, chegado depois, ainda usa), o resultado pode compilar quebrado sem nenhum `<<<<<<<` pra avisar. Sempre rodar `tsc`/testes depois de QUALQUER merge, mesmo "limpo".

### Brasões confirmados em produção

Usuário confirmou visualmente que os brasões (PPF + GAEP) aparecem corretamente no PDF de Relatório gerado em produção, após o merge — fecha o item mais importante da lista de próximos passos (era exatamente o passo que teria pego o bug crítico #1 mais cedo, se tivesse sido feito antes da review final).

### Próximos passos

- `20260429_config_relatorio.sql` — checksum divergente pré-existente que bloqueia `npm run db:sync` pra qualquer um rodando o manifesto do início. Não investigado nesta sessão (fora de escopo), mas foi o motivo de precisar aplicar a migration desta sessão manualmente.

---

## 2026-08-07 — Recuperação pós-restart: 2 implementações retomadas em paralelo (worktrees) + 2 PRs abertos

**Sessão**: Notebook reiniciou com 2 features em andamento, cada uma num git worktree isolado. Nada foi perdido (os dois worktrees estavam com `git status` limpo — todo o progresso já commitado localmente), mas nenhuma das branches tinha sido enviada pro `origin` ainda.

### Diagnóstico
- `.claude/worktrees/convite-efetivo-provisionamento` (branch `feat/convite-efetivo-provisionamento`): Tasks 1-3 do plano já feitas (migration, `resolverPerfilOperador`, `gerarConviteEfetivo`).
- `.claude/worktrees/feat+efetivo-gaeps-pdf` (branch renomeada para `feat/efetivo-gaeps-drilldown-pdf`, era `worktree-feat+efetivo-gaeps-pdf`): Tasks 1-4 já feitas (listagem, Server Action, `EfetivoRoster`, acordeão + botão PDF). Tinha um lock de sessão órfão (`claude session ... pid 19280`, morto no reboot) — inofensivo.

### Execução
Dois subagentes despachados em paralelo (`superpowers:dispatching-parallel-agents`), um por worktree, cada um seguindo `superpowers:executing-plans` a partir da próxima task pendente:
- **Convite ao efetivo**: completou Tasks 4-6. Investigou uma falha de teste que parecia regressão (`Perfil inválido.` vs `Acesso negado.`) — confirmou que era flake de concorrência (duas suítes `vitest run` rodando ao mesmo tempo em worktrees diferentes, disputando cache de transform), não bug real. Achou e corrigiu de brinde um bug no próprio plano: um teste com `getByText` que nunca poderia bater com o JSX proposto (texto quebrado entre elementos `<strong>`).
- **Drill-down + PDF**: completou Tasks 5-7 (`buildEfetivoPdfHtml.ts`, rota `GET /api/pdf/efetivo`, acesso `view-only` do AUDITOR).

### Achado de infra (não é bug de nenhuma das duas features)
`calendarioActions.test.ts` e `missaoPeriodoActions.test.ts` falham na coleta (`Error: supabaseUrl is required.`) sempre que rodados isolados — **reproduz até no checkout principal** (`fix/build-audit-2026-08-05`, com `.env.local` real presente), então não é causado por nenhum dos dois branches. Causa: `lib/google-calendar/sync.ts` cria o client Supabase real no import (side-effect eager), sem mock nesses dois arquivos de teste, e o Vitest deste projeto (`vitest.config.ts`/`vitest.setup.ts`) não carrega `.env.local` em modo teste (diferente do `next build`, que carrega normalmente). Na suíte completa isso não derruba a contagem de testes individuais (425/425, depois 443/443 e 458/458 nos worktrees) porque a falha é só de coleta das 2 suítes — mas é um gap real que vale corrigir um dia (mock de `@/lib/google-calendar/sync` nesses 2 arquivos, ou factory ao invés de `createClient` top-level).

### Entrega
- **PR #5 mergeado em `main`** (commit de merge `1939a7d`, 2026-08-07) — build de produção corrigido, `main` builda de novo.
- **PR #8 mergeado em `main`** (commit de merge `cd2b47e`, 2026-08-07, merge feito manualmente pelo usuário direto no GitHub) — [convite ao efetivo com provisionamento direto](https://github.com/Hachid/Sistema_GAEP/pull/8). Nasceu como PR #6 contra `fix/build-audit-2026-08-05`; ao tentar retargetar pra `main` depois do merge do #5, apareceu um PR #8 já existente pra mesma branch (título genérico, corpo vazio) — **não era automação**: o usuário tinha clicado em "Create pull request" direto no GitHub antes de eu preencher o #8 com título/corpo. Resolvido preenchendo #8 e fechando #6 como duplicado; o usuário mergeou #8 pouco depois.
- **PR #7** — [drill-down de efetivo por GAEP + PDF do efetivo](https://github.com/Hachid/Sistema_GAEP/pull/7) (`feat/efetivo-gaeps-drilldown-pdf` → `main`, retargetado sem problema). Ainda aberto, não mergeado.
- Copiado `.env.local` pro worktree `feat/efetivo-gaeps-drilldown-pdf` (não tinha nenhum) — sem ele `npm run build` falhava na etapa "Collecting page data" de `/api/calendar/watch-renewal`.

### PR #7 mergeado (com incidente) + PR #4 fechado como duplicado

- **PR #7 mergeado em `main`** (commit de merge `d96778b`). Precisou de merge manual de `origin/main` no worktree — 2 conflitos reais em `GestaoClient.tsx` (spec doc era add/add trivial; o código era mais sério: o card "Convite ao efetivo" do PR #8 tinha sido escrito contra o `TabEfetivo` monolítico pré-refactor, mas esta branch já tinha extraído `EfetivoRoster` de `TabEfetivo` — git colocou o card novo dentro de `EfetivoRoster`, que não tinha `gaepCodigo`/`gaepsConvite` disponíveis). Fix: `EfetivoRoster` ganhou props opcionais `showConvite`/`gaepCodigo`/`gaepsConvite` (default off) e passou a hospedar o card (preserva `ops`/`setOps` local, então "adiciona operador na lista após convite" continua funcionando sem hack de remount); `TabEfetivo` virou wrapper fino. O acordeão da aba GAEPs (outro call site de `EfetivoRoster`) não passa `showConvite` — card fica escondido lá.
- **Incidente durante a resolução, vale registrar como lição**: depois de resolver o conflito de código, rodei `git add` só uma vez logo após tirar os marcadores (`sed`) — os ajustes estruturais seguintes (Edit tool) ficaram só na working tree. `tsc`/`vitest`/`next build` locais leem a working tree direto, então todos passaram verdes; mas o `git commit --no-edit` só pegou o que estava *staged* (a versão ainda quebrada). Isso só apareceu no build da Vercel do PR (que clona o commit de verdade) — `Cannot find name 'precisaEscolherGaepConvite'`, o erro que eu já tinha corrigido localmente. **Lição**: depois de qualquer edição pós-`git add` durante resolução de conflito, `git add` de novo antes de commitar — ou usar `git status`/`git diff --cached` pra conferir que staged == working tree antes do commit. Corrigido com um commit novo (`f0562ac`), verificado no build da Vercel antes de mergear de fato.
- **PR #4 fechado sem merge** — era uma **implementação duplicada**: `main` já tinha "feriados automáticos" (mesma ideia — sync BrasilAPI + estaduais, coluna `origem`, RPC) implementado de forma totalmente independente pelo Cursor em `e545eb9` (14/07) + follow-ups, sem nenhum commit em comum com a branch `feat/calendario-feriados-automaticos` (a sessão SDD documentada abaixo, em 2026-07-13). Resolver os 9 conflitos (incluindo migrations e módulos novos `lib/feriados/*`) pra substituir uma implementação já em produção por uma reimplementação paralela foi julgado risco alto pra ganho incerto — decisão do usuário.
- **Achado não resolvido, digno de investigação separada**: a versão do Cursor em `main` pode não ter a proteção contra race condition (TOCTOU) que a branch fechada tinha — `ON CONFLICT (gaep_id, data) DO UPDATE ... WHERE feriados.origem <> 'manual'` avaliado atomicamente pelo Postgres. Não confirmei se a versão em produção tem equivalente. Comentário deixado no PR #4 fechado.
- Worktree órfão limpo: `.git/worktrees/feriados-automaticos` apontava pra `C:/Projetos/Sistema_GAEP_Claude_designer/...`, diretório que não existe mais no disco — unlock + prune. Criado worktree temporário novo (`.claude/worktrees/calendario-feriados-automaticos`) só pra investigar o merge; removido do git depois (`git worktree remove`), mas a pasta física ficou presa no disco por permissão do Windows (arquivo em uso) — puramente cosmético, sem trabalho dentro, pode apagar manualmente quando não estiver em uso.

### Race condition investigada e corrigida — PR #9

Investigação confirmou o achado: a versão de feriados automáticos do Cursor em `main` (`e545eb9`) **tinha mesmo** a race condition TOCTOU — `sincronizarFeriadosAutomaticos` lia os feriados existentes, decidia em código de app se sobrescrevia (checando `origem === 'manual'` contra um snapshot já lido), e só então escrevia. Confirmado com o código real (`app/(app)/gestao/actions.ts:819-910` em `main` antes do fix).

**Antes de escrever a correção, verifiquei duas pré-condições direto no banco de produção** (via `SUPABASE_DB_URL`, `pg` client): a constraint `UNIQUE(gaep_id, data)` (`feriados_gaep_id_data_key`) existe de fato — pré-requisito pro `ON CONFLICT` funcionar; e a função `sync_feriados_automaticos` (que a branch fechada tinha testado mas nunca chegou a aplicar) não existia no banco ainda.

- **Fix**: `handoff/migrations/20260807_sync_feriados_automaticos_fn.sql` — função Postgres `sync_feriados_automaticos` com `INSERT ... ON CONFLICT (gaep_id, data) DO UPDATE ... WHERE origem <> 'manual'`, avaliada atomicamente no momento da escrita. `sincronizarFeriadosAutomaticos` reescrita pra chamar `admin.rpc(...)` em vez do loop select+filtro+upsert; mantém uma leitura prévia só informativa (estimar "quantos são novos" pro toast, sem decidir mais o que sobrescrever).
- **Achado extra durante o port**: a migration original (portada da branch fechada) revogava `EXECUTE` de `anon, authenticated` nomeadamente — mas `CREATE FUNCTION` concede `EXECUTE` a `PUBLIC` por padrão, e toda role é membro implícito de `PUBLIC`, então aquele `REVOKE` **não fechava nada de fato**. Confirmado consultando `information_schema.routine_privileges` em produção depois do primeiro apply: `PUBLIC` ainda tinha `EXECUTE`. Corrigido pra `REVOKE ALL ... FROM PUBLIC`, o padrão já usado pela maioria das outras RPCs deste repo (`redeem_convite`, `current_gaep_access`, etc. — só uma migration antiga, `20260617_rpc_lockdown_and_rls.sql`, usa o padrão fraco por nomeação de role).
- **Migration já aplicada em produção** nesta sessão (`npm run db:sync`), grants conferidos depois (só `postgres` + `service_role`).
- Teste novo: `app/(app)/gestao/__tests__/sincronizarFeriadosAutomaticos.test.ts` (5 testes) — não existia cobertura pra essa função em `main` antes.
- Verificação: 481/481 testes, `tsc` limpo, `npm run build` verde.
- **PR #9 mergeado em `main`** (commit de merge `d258b64c`): https://github.com/Hachid/Sistema_GAEP/pull/9 (`fix/feriados-race-condition` → `main`).

### Auditoria das outras 3 RPCs com o mesmo padrão fraco de REVOKE — sem risco real

`20260617_rpc_lockdown_and_rls.sql` usa `REVOKE EXECUTE ... FROM anon, authenticated` (o mesmo padrão fraco corrigido acima) pra `find_operadores_por_nome_guerra`, `redeem_convite` e `salvar_relatorio_completo`. Consultei os grants reais em produção (`information_schema.routine_privileges`), não só o histórico de migrations: **as três estão seguras** — só `postgres` + `service_role`, sem `PUBLIC`/`anon`/`authenticated`. `REVOKE`/`GRANT` não são cumulativos-perigosos (revogar de role nomeada nunca concede nada), então o revoke fraco dessa migration foi redundante-mas-inofensivo pras três, porque cada uma já tinha sido travada corretamente (`REVOKE ALL ... FROM PUBLIC`) em outro lugar antes dela rodar:
- `redeem_convite` → `20260616_redeem_convite_rpc.sql`
- `salvar_relatorio_completo` → `20260616_salvar_relatorio_rpc.sql`
- `find_operadores_por_nome_guerra` → `handoff/sql/008_login_find_operador_por_nome.sql`

**Achado à parte** (não é falha de segurança, é falha de processo): esse último arquivo define a função **fora do sistema de migrations rastreado** (`handoff/migrations/` + `manifest.json`) — é um SQL solto em `handoff/sql/`, numeração antiga (`008_`), de antes da adoção do fluxo de migrations datadas (o diretório inteiro `handoff/sql/001-009` é o bootstrap original do schema, documentado em `handoff/README.md` — não é uma violação de convenção, é anterior a ela). Confirmado também: exatamente 1 overload de cada uma das 3 funções (sem versão esquecida com assinatura diferente e grants soltos).

### PR #10 mergeado — traz find_operadores_por_nome_guerra pro sistema de migrations

A pedido do usuário, formalizei o achado acima: nova migration `20260807_find_operadores_por_nome_guerra_fn.sql` (idempotente — `CREATE OR REPLACE` + `REVOKE`/`GRANT` idênticos ao arquivo legado), aplicada em produção (`npm run db:sync`), grants confirmados inalterados antes/depois (`postgres` + `service_role`, 1 overload) e chamada de teste confirmando que a função segue funcionando. `handoff/sql/008_...` ganhou nota apontando pra migration nova como fonte de verdade. **Mergeado em `main`** (commit de merge `c590081c`): https://github.com/Hachid/Sistema_GAEP/pull/10.

### Limpeza final da sessão

- **9 branches remotas** conferidas com o usuário (screenshot do GitHub): 8 já mergeadas (esperado, `delete_branch_on_merge: false`) + `feat/calendario-feriados-automaticos` (a branch do PR #4, fechado sem merge — trabalho rejeitado, não esquecido). Apagada do `origin` a pedido do usuário.
- Pasta órfã `C:/Projetos/Sistema_GAEP_Claude_designer/...` já não existia mais no disco (deve ter sido liberada quando o processo que travava o Windows fechou) — nada a fazer.
- **`NEXT_PUBLIC_SITE_URL` configurada na Vercel** (`https://sistema-gaep-ppf.vercel.app`, o alias estável de produção — projeto não tem domínio customizado, confirmei via `vercel domains ls`/`vercel alias ls`). Antes de mexer, confirmei que o fallback automático (`VERCEL_PROJECT_PRODUCTION_URL`, injetado pela própria Vercel) já deveria estar gerando links corretos — essa var é reforço, não estava quebrando nada. Só vale a partir do próximo deploy (mesmo comportamento observado com `GOOGLE_APPS_SCRIPT_SECRET` em 06/08).

### PR #11 mergeado — gap de teste do Vitest corrigido, suíte 100% verde

`calendarioActions.test.ts`/`missaoPeriodoActions.test.ts` importavam (transitivamente) `lib/google-calendar/sync.ts`, que cria um client Supabase real **no import** (não via factory) — sem mock, quebrava sob Vitest com `supabaseUrl is required.` (este projeto não carrega `.env.local` em modo teste). Fix: `vi.mock('@/lib/google-calendar/sync', ...)` com mocks vazios nos 2 arquivos — seguro porque a sincronização é best-effort por design (`sincronizarComGoogle()` em `actions.ts` embrulha tudo num `try/catch` que só loga erro, nunca propaga). **Suíte completa agora 100% verde: 58/58 arquivos, 493/493 testes** (era a última falha pré-existente conhecida do projeto). PR mergeado em `main` (commit de merge `c42da653`): https://github.com/Hachid/Sistema_GAEP/pull/11.

**Padrão que se repetiu 3x nesta sessão**, vale registrar: todo `git worktree add` novo carece de `.env.local` (é gitignored, não vem no checkout) — sempre que criar um worktree novo, copiar `.env.local` do checkout principal *antes* de rodar `npm run build` (o `next build` carrega `.env.local` de verdade, ao contrário do Vitest, e falha em "Collecting page data" sem ele — não é bug de código, é setup do worktree).

### Próximos passos

Nenhum pendente desta sessão. Lista de auditoria/melhorias de baixa prioridade pra retomar quando fizer sentido, sem urgência:
- `20260617_rpc_lockdown_and_rls.sql` usa o mesmo padrão fraco de REVOKE que causou o gap corrigido no PR #9 — auditado em 07/08, as 3 RPCs afetadas (`find_operadores_por_nome_guerra`, `redeem_convite`, `salvar_relatorio_completo`) estão seguras na prática (cada uma tinha um `REVOKE ALL FROM PUBLIC` correto em outra migration). Nenhuma ação necessária, só documentado.

---

## 2026-08-06 — Ponte Apps Script (Drive) quebrada: 4 bugs empilhados, corrigidos e verificados em produção

**Sessão**: Debugging do "Não foi possível enviar a foto no momento" no `/relatorio` — upload de fotos/relatórios parado.

### Causa raiz (4 bugs empilhados, do mais externo ao mais interno)

1. **Deployment do Apps Script com "Who has access: Only myself"** — bloqueava toda chamada servidor-a-servidor (Vercel → Apps Script) com HTTP 401, porque o request não carrega sessão Google. A segurança real do endpoint é o secret + HMAC anti-replay (`lib/storage/apps-script-hmac.ts`), não o controle de acesso do Google — corrigido para "Anyone".
2. **`HtmlService.MimeType.JSON` inexistente** no script (deveria ser `ContentService.MimeType.JSON`) — `TypeError: Cannot read properties of undefined (reading 'JSON')`, mesmo depois de corrigir o acesso.
3. **Dois arquivos com `doPost` próprio no mesmo projeto Apps Script** (`Calendar.gs` e `Codigo.gs`) — Apps Script concatena todos os `.gs` num único escopo global; um `doPost` sobrescreve o outro silenciosamente conforme ordem de carregamento. O de `Calendar` (só entende ações `calendar.*`) vencia o de `Codigo` (ações de storage: `healthCheck`/`uploadFile`/`downloadFile`/`deleteFile`/`getFileInfo`) — upload de fotos ficava inacessível mesmo com código correto em `Codigo.gs`, sem nenhuma mudança do lado do Vercel. **Provável causa do "parou do nada"** relatado pelo usuário: o `doPost` duplicado deve ter entrado durante o desenvolvimento do sync de Calendário (meados de julho).
4. **Nome de Script Property divergente** — o código lê uma property do Apps Script pra validar o secret; passou por três nomes diferentes até bater (`GAEP_APPS_SCRIPT_SECRET` → `GAEP_SECRET` → nome final `GOOGLE_APPS_SCRIPT_SECRET`, escolhido por ser o mesmo nome já usado na env var da Vercel/`.env.local` — um nome só, em todo lugar).
5. **Bônus, não-bug**: mesmo com a ponte 100% saudável, produção continuou falhando até um `vercel --prod` novo — mudança de env var no dashboard da Vercel não se propaga pra deployments já no ar.

### Fix

- Os dois arquivos do Apps Script foram fundidos num **único `doPost`** que despacha por tipo de ação (`calendar.*` → esquema `payload.hmac` de `lib/google-calendar/sync.ts`; storage → esquema `gaep_signature` de `lib/storage/apps-script-hmac.ts`). Fonte da verdade: `docs/calendar.gs.md` (cole no arquivo "Calendar" do projeto Apps Script). `docs/codigo.gs.md` virou nota de depreciação.
- `docs/GOOGLE_APPS_SCRIPT_DEPLOY_VISUAL.md` corrigido (recomendava "Only myself" por engano).
- Deploy de produção forçado via `vercel --prod` a partir da branch `fix/build-audit-2026-08-05` (não `main`, que segue com o build quebrado até o PR #5 ser mergeado).

**Delivery: 5 commits** (`d8adc80`, `9a5a620`, `04fafb8`, `f101288`, `ca7203a`) na branch `fix/build-audit-2026-08-05` (mesma do PR #5, ainda aberto).

**Verificação**: `node scripts/test-apps-script-health.js` → `{"ok":true,"provider":"drive_apps_script",...}`. Upload real testado via diagnóstico (arquivo criado e removido do Drive). Upload de foto **confirmado funcionando pelo usuário em produção** após o `vercel --prod`.

### Próximos passos
1. Mergear PR #5 (`fix/build-audit-2026-08-05`) em `main` — build de produção segue quebrado em `main` até lá.
2. Sincronizar `.env.local` com o secret real da Vercel (`GOOGLE_APPS_SCRIPT_SECRET`), pra `test-apps-script-health.js` não voltar a acusar falso-negativo.
3. Confirmar no projeto Apps Script real que o arquivo "Codigo" foi de fato removido (ficou pendente confirmar com o usuário).

---
## Backlog (não datado)

- [ ] Definir provedor de deploy (Vercel vs VPS) e variáveis correspondentes.
- [ ] PWA: manifest + service worker para uso offline parcial em campo.
- [ ] Auditoria de queries N+1 nos painéis (Dashboard e Folha Ponto).
- [ ] Substituir `scripts/sync-db.js` por `supabase migration` formal.
- [ ] Hardening do `cleanup-maio-2026.js` (guard `--confirm` + dump).
- [ ] Testes E2E com Playwright para os 6 fluxos.

---
