# ADR-001: Login via JSON (não OAuth2 form-data)

**Data**: 2026-05-06
**Status**: aceita

## Contexto
FastAPI tem suporte nativo a `OAuth2PasswordRequestForm` (form-data). Porém o frontend usa `fetch` com `Content-Type: application/json`, e o backend em fase inicial não precisa de compatibilidade OAuth2 real.

## Decisão
`POST /auth/token` aceita JSON (`{ email, password }`) em vez de form-data.

## Alternativas consideradas
- **OAuth2 form-data**: compatível com ferramentas OAuth2, mas adiciona complexidade e não há client OAuth2 no projeto.

## Consequências
- ✅ Frontend mais simples (sem URLSearchParams)
- ✅ Testável diretamente com `curl -d '{"email":..}'`
- ⚠️ Não compatível com clientes OAuth2 padrão (aceito nesta fase)
