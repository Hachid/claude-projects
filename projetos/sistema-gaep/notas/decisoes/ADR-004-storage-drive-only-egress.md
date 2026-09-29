# ADR-004 — Drive-only para binários + cache do consolidado (redução de egress)

**Data**: 2026-06-08
**Status**: Aceito
**Contexto da sessão**: PROGRESSO.md 2026-06-08

## Contexto

O Supabase free tem limite de **5 GB/mês de egress** (todo tráfego de saída: DB, Storage, Auth, API, Pooler). Em maio/2026 o projeto estourou **61,88 GB** e a org foi **restrita** → projeto **pausado** (app fora do ar). Causa raiz: fotos servidas por **URL pública do Supabase Storage** (renderizadas em `<img>` na tela/impressão e puxadas pelo PDF consolidado), bucket público e sem cache — a mesma foto (~KB) era re-baixada milhares de vezes.

Restrição inegociável: **projeto filantrópico, custo zero, sem cartão** (Google Cloud e R2/Vercel Blob foram descartados por exigirem cartão).

## Decisão

**O Supabase nunca mais serve um byte de binário.** Foto e PDF consolidado vivem só no **Google Drive** (via Apps Script Web App já existente, sem billing). O app lê binário apenas pelo proxy autenticado `/api/drive-file/{fileId}`, com cache. Ao Supabase sobra só JSON relacional pequeno — bem dentro dos 5 GB/mês.

Mecanismos:
1. **Cache no proxy** `/api/drive-file`: `private, max-age=2592000, immutable` + `ETag`. `private` (não CDN público) preserva login/LGPD dos dados de PM. fileId do Drive é imutável → cache agressivo é seguro.
2. **Cache do PDF consolidado no Drive**: chave **estável por conteúdo** (`consolidadoCacheKey`, sem timestamp) mapeada a um `drive_file_id` na tabela `consolidado_pdf_cache`. HIT pula a resolução de fotos + Playwright. **Fail-open**: qualquer erro/ausência de tabela/provider ≠ drive → gera normalmente (nunca quebra o consolidado).
3. **Migração** das fotos antigas (URLs Supabase → `/api/drive-file/{id}`) + **fechar o bucket** `gaep-fotos` (privado) — pós-restore.

## Alternativas consideradas

- **① Só terminar Drive + cache** (sem cachear consolidado): mais simples, mas mantém o Apps Script sendo puxado a cada geração do consolidado (cota diária frágil). Rejeitada por robustez.
- **③ Storage dedicado (Cloudflare R2 / Vercel Blob)**: CDN real, sem cota de Apps Script, atrás da mesma abstração `StorageProvider`. **Rejeitada**: exige cartão mesmo no plano grátis.

## Consequências

- ✅ Egress do Supabase tende a ~0; cota de Apps Script protegida pelos caches.
- ✅ Reaproveita a abstração `StorageProvider` e o proxy já existentes.
- ⚠️ Consolidado cacheado congela "consolidado por X em T" + hash/QR do primeiro gerador (aceitável p/ documento oficial verificável).
- ⚠️ PDFs órfãos acumulam no Drive quando o conteúdo muda (storage tem folga; poda é trabalho futuro).
- ⚠️ Migration `009` deve ser aplicada **antes** do redeploy, senão `putCached` sobe órfãos sem cache.
- 🔗 Depende do Apps Script Web App (ver Fase 3+4, 2026-05-26) — elo frágil, mitigado pelos caches.
