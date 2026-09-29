# ADR-001: Usar Baileys em vez de Evolution API

**Data**: 2026-05-06
**Status**: aceita

## Contexto
Precisamos de um conector com WhatsApp que funcione sem plataforma paga, com controle total do estado de sessão e baixa latência. Duas opções principais avaliadas:

- **Baileys** — biblioteca Node que fala WebSocket diretamente com o WhatsApp Web. Sem servidor intermediário.
- **Evolution API** — API HTTP em cima do Baileys, com painel próprio. Mais fácil de operar, mas adiciona uma camada e (em algumas distribuições) custo.

Restrições:
- Volume baixo inicialmente (centenas de msgs/dia).
- Eu domino TypeScript/Node.
- Quero poder customizar o handling de eventos sem proxiar JSON.

## Decisão
Usar **Baileys** diretamente, dentro do nosso próprio worker `ingest/`.

## Alternativas consideradas

- **Evolution API**
  - ✅ Setup em minutos, painel pronto.
  - ⚠️ Mais uma peça móvel para operar; abstração esconde detalhes que vou querer no router.
  - ⚠️ Mantida por terceiros — risco de quebrar com updates de Baileys.

- **API oficial WhatsApp Cloud (Meta)**
  - ✅ Suportada, sem risco de ban.
  - ❌ Exige conta Business verificada e templates aprovados; fricção alta para v1 pessoal.

## Consequências

- ✅ Controle total: posso plugar Redis Streams e filtros customizados sem proxy.
- ✅ Zero custo de plataforma; só infra.
- ⚠️ Risco de banimento se volume crescer — mitigar com rate limit por contato (1 msg/s).
- ⚠️ Atualizações de Baileys podem quebrar — pinear versão e revisar a cada minor.

## Referências

- https://github.com/WhiskeySockets/Baileys
- https://github.com/EvolutionAPI/evolution-api
