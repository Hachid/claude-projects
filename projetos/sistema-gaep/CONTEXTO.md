# Sistema GAEP — CONTEXTO

## Repositório

- **Path local**: `C:\Projetos\Sistema_GAEP_Claude_designer`
- **GitHub**: https://github.com/Hachid/GAEP_CLAUDE_DESIGNER
- **Branch padrão**: `main`
- **Slug do projeto** (vault): `sistema-gaep`

> **Atenção**: existe uma pasta legada em `C:\Projetos\Sistema_GAEP_Claude\gaep` (repo `Hachid/GAEP_CLAUDE`, Next.js 16 + Jest). **Não é o projeto ativo**. Não cruzar contexto. A ser arquivada.

## Stack

- **Framework**: Next.js 15.5 (App Router)
- **Linguagem**: TypeScript 5
- **UI**: React 19 + Tailwind CSS 3.4 + design tokens em `handoff/tokens/design-tokens.ts`
- **Backend-as-a-Service**: Supabase (`@supabase/ssr ^0.5`, `@supabase/supabase-js ^2.49`)
  - Auth (matrícula como email interno `{matricula}@gaep.internal`)
  - Postgres (schema em `handoff/sql/001_schema.sql`)
  - Storage (fotos de relatório, até 3 por registro)
- **Gráficos**: Recharts 3.8
- **Geração server-side de imagens/PDF**: `playwright-core` + `@sparticuz/chromium` + `sharp`
- **QR Code**: `qrcode` 1.5
- **Observabilidade**: Sentry (`@sentry/nextjs`, `@sentry/react`)
- **Testes**: Vitest 3 + Testing Library (jest-dom, react, user-event) + jsdom
- **Lint**: ESLint 9 com `eslint-config-next`
- **Cliente Postgres direto** (devDep): `pg` 8.20 — usado em `scripts/sync-db.js` e `scripts/cleanup-maio-2026.js`

## Scripts (`package.json`)

| Script | Comando | Quando usar |
|---|---|---|
| `dev` | `node scripts/sync-db.js --auto && next dev` | Desenvolvimento — sincroniza DB antes de subir |
| `build` | `next build` | Build de produção |
| `start` | `next start` | Servir build |
| `lint` | `next lint` | Lint do projeto |
| `test` | `vitest` | Rodar testes |
| `test:ui` | `vitest --ui` | Vitest com interface |
| `db:sync` | `node scripts/sync-db.js` | Sincronizar schema sem subir o dev |
| `db:cleanup-maio-2026` | `node scripts/cleanup-maio-2026.js` | Cleanup pontual; ⚠️ verificar antes de rodar |

## Ambientes

| Env | URL / Host | Notas |
|---|---|---|
| local | `http://localhost:3000` | `npm run dev`; usa `.env.local` na raiz |
| staging | — | a definir |
| prod | — | a definir (Vercel? VPS?) |

## Credenciais (refs, NUNCA o valor)

> Arquivo real: `C:\Projetos\Sistema_GAEP_Claude_designer\.env.local` (NÃO commitar).

- `NEXT_PUBLIC_SUPABASE_URL` → `.env.local`
- `NEXT_PUBLIC_SUPABASE_ANON_KEY` → `.env.local`
- `SUPABASE_SERVICE_ROLE_KEY` → `.env.local` (usado em scripts e rotas server-only)
- `DATABASE_URL` → `.env.local` (string Postgres usada por `scripts/sync-db.js`)
- `OPENAI_API_KEY` (ou equivalente do `Config IA`) → `.env.local`
- `SENTRY_DSN` / `SENTRY_AUTH_TOKEN` → `.env.local`

## Estrutura relevante do repo

```
Sistema_GAEP_Claude_designer/
├── app/                       # App Router (page.tsx, rotas (auth)/(app))
├── lib/
│   └── supabase/client.ts    # Cliente Supabase
├── handoff/                   # 🎯 fonte da verdade do design e plano
│   ├── README.md              # Pacote de handoff completo
│   ├── Plano de Execução.html
│   ├── design/                # Protótipo HTML + JSX de referência
│   ├── tokens/design-tokens.ts
│   └── prompts/cursor.md
├── scripts/                   # sync-db.js, cleanup-maio-2026.js
├── public/                    # gaep-logo.png
├── tailwind.config.ts
├── vitest.config.ts / vitest.setup.ts
├── eslint.config.mjs
└── .env.local                 # ❌ não commitar
```

## Glossário do domínio

- **GAEP**: Grupo de Apoio à Execução Penal (unidade da PM).
- **GAEP-CAT**: unidade-piloto, Catanduvas/PR.
- **Operador**: policial militar usuário do sistema (matrícula como ID).
- **Relatório / Operação**: registro de uma atividade executada pela equipe num turno.
- **Categoria de atividade**: macro-grupo (OPERAR, TREINAR, INSTRUIR…).
- **Atividade**: item específico dentro de uma categoria.
- **FolhaPonto**: tabela de horas trabalhadas por operador no período.
- **Missão (Diária)**: deslocamento/serviço com pagamento de diária.
- **Snapshot de valor**: valor de diária congelado no momento do registro — alterações futuras não retroagem.
- **Soft delete**: marcação `deleted_at = now()` em vez de DELETE físico.
- **Perfis**: OPERADOR · SUPERVISOR · ADMIN · SUPER_ADMIN · AUDITOR.

## Pessoas / Stakeholders

- **Hachid** — owner técnico, dev principal.
- **Equipe GAEP-CAT** — usuários piloto e validadores funcionais.
- *(adicionar contatos específicos quando confirmados)*
