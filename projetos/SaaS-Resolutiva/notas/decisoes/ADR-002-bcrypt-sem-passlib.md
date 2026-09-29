# ADR-002: bcrypt direto sem passlib

**Data**: 2026-05-06
**Status**: aceita

## Contexto
`passlib` é a abordagem padrão para hashing de senhas em FastAPI, mas é incompatível com `bcrypt >= 4.0` neste ambiente (gera erros de import no Python 3.x instalado).

## Decisão
Usar `bcrypt` diretamente sem wrapper `passlib`.

## Alternativas consideradas
- **passlib + bcrypt**: padrão FastAPI, mas quebra com bcrypt ≥4.0 neste ambiente.
- **argon2**: mais seguro, mas adiciona dependência não necessária nesta fase.

## Consequências
- ✅ Sem erros de compatibilidade
- ✅ Zero overhead de wrapper
- ⚠️ Fora do padrão FastAPI docs (irrelevante para projeto próprio)
