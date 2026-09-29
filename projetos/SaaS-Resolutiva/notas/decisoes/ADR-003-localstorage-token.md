# ADR-003: localStorage para persistência de token JWT (dev/MVP)

**Data**: 2026-05-06
**Status**: aceita (temporária — substituir em produção)

## Contexto
O token JWT precisa sobreviver a reloads do browser. As opções são localStorage, sessionStorage ou cookie httpOnly.

## Decisão
Usar `localStorage` com chave `resolutiva_access_token` para dev e MVP.

## Alternativas consideradas
- **Cookie httpOnly**: mais seguro contra XSS, mas requer backend configurar `Set-Cookie` com `httpOnly; Secure; SameSite`. Alvo de produção.
- **sessionStorage**: não sobrevive a nova aba — experiência ruim.
- **memória React**: não sobrevive a reload — força re-login toda vez.

## Consequências
- ✅ Zero infra adicional no backend
- ✅ Sessão persiste entre reloads e abas
- ⚠️ Vulnerável a XSS (aceito em dev/MVP; mitigado com CSP em produção)
- ⚠️ Migrar para cookie httpOnly antes de produção real

## Referências
- `frontend/features/session/auth-service.ts` — `saveToken`, `loadToken`, `clearToken`
