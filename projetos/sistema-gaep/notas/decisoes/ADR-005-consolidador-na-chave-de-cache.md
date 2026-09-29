# ADR-005 — `consolidadorNome` na chave de cache do consolidado

**Data**: 2026-06-16
**Status**: Aceito
**Contexto da sessão**: PROGRESSO.md 2026-06-16
**Revisa**: ADR-004 (consequência ⚠️ "consolidado cacheado congela 'consolidado por X em T' + hash/QR do primeiro gerador")

## Contexto

O ADR-004 introduziu o cache do PDF consolidado com chave **estável por conteúdo** (`consolidadoCacheKey`), e aceitou como tradeoff que o PDF cacheado "congela o consolidador X e o hash/QR do primeiro gerador".

Numa revisão de código (ver PROGRESSO 2026-06-16) ficou claro o custo desse tradeoff: como a chave **não** incluía quem consolida, o operador **B** que pedisse o mesmo período/escopo recebia o PDF cacheado gerado pelo operador **A** — com o **nome de A no rodapé** e o **hash/QR de autenticidade calculado para A**. Num documento oficial verificável (com QR de autenticidade), exibir um consolidador e um hash que não correspondem a quem efetivamente emitiu é uma **divergência de auditoria**, não apenas cosmética.

## Decisão

Incluir `consolidadorNome` na `consolidadoCacheKey` (campo `cn` no payload do hash).

Consequência direta: passa a existir **uma entrada de cache por consolidador** (por versão de conteúdo). O PDF servido — seja HIT ou MISS — sempre carrega o nome e o hash/QR de **quem pediu**. As demais dimensões da chave (conteúdo dos relatórios + fotos, KPI, evolução, período, filtros, config/timbrado) permanecem inalteradas.

O timestamp de emissão continua **fora** da chave: para o mesmo consolidador + mesmo conteúdo, o "emitido em" segue congelado na 1ª geração (comportamento correto — reusar o documento idêntico, não regerar por causa do relógio).

## Alternativas consideradas

- **Manter o tradeoff do ADR-004 e só documentar** (não mexer na chave): zero custo de cache extra, mas mantém a divergência de auditoria num documento oficial. Rejeitada — o ganho de hit-rate não justifica servir nome/hash de outra pessoa.
- **Remover consolidador e hash do PDF cacheado** (tornar o documento "anônimo"): quebra o requisito de rastreabilidade/autenticidade do sistema. Rejeitada.

## Consequências

- ✅ O rodapé e o hash/QR do consolidado sempre correspondem a quem emitiu — auditoria consistente.
- ✅ Egress permanece protegido: o cache continua existindo e funcionando (fail-open intacto).
- ⚠️ Hit-rate levemente menor e mais uploads ao Drive (uma entrada por consolidador). Aceitável: numa unidade pequena, poucos operadores geram o consolidado.
- 🔗 Revisa o item ⚠️ de "Consequências" do ADR-004 referente ao congelamento do consolidador.

## Mudanças de apoio na mesma sessão (não-arquiteturais)

Implementadas junto, detalhadas no PROGRESSO 2026-06-16: resolução de fotos do consolidado em paralelo (concorrência limitada) + `maxDuration` 300; observabilidade de falhas de foto (log + header `X-Pdf-Fotos-Falhas`); helper único `downloadDriveFileById` (Apps Script → service account) eliminando lógica triplicada; `/api/drive-file` fora do matcher do middleware (corta `getUser` duplicado por imagem); fuso `America/Sao_Paulo` no "emitido em"; upload de fotos em paralelo com `try/finally`.
