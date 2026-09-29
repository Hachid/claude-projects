# LEIA PRIMEIRO — Vault `claude-projects`

> Índice geral do vault. **Sempre** comece por aqui ao iniciar uma sessão com Claude Code.

## Para que serve este vault

Este vault é a **memória externa** dos meus projetos. Ele existe para:

1. **Economizar tokens** no Claude Code — em vez de explicar contexto toda vez, aponto o Claude para um arquivo do vault.
2. **Melhorar contexto** — decisões, arquitetura, glossário e estado de progresso ficam versionados em markdown.
3. **Integrar com GitHub** — cada projeto do vault espelha (ou referencia) um repo Git; commits, issues e PRs aparecem no `PROGRESSO.md`.
4. **Histórico de decisões** — toda decisão técnica relevante (`ADR`-like) entra em `notas/decisoes/` do projeto correspondente.

---

## Estrutura

```
claude-projects/
├── LEIA_PRIMEIRO.md     ← este arquivo (índice geral)
├── TEMPLATES.md         ← molde para iniciar novo projeto
├── WORKFLOW.md          ← processo padrão (sessão de trabalho com Claude)
│
├── _sistema/            ← prompts, configs, MCPs, snippets globais
├── aprendizado/         ← estudos, cursos, papers, anotações de leitura
├── clientes/            ← um folder por cliente (NDA-safe)
├── pessoal/             ← anotações pessoais (saúde, finanças, ideias)
└── projetos/            ← um folder por projeto técnico
    ├── SaaS-Resolutiva/
    ├── sistema-gaep/
    ├── erp-local/
    └── thermal-camera/
```

## Anatomia de um projeto

Cada pasta dentro de `projetos/` (ou `clientes/<nome>/projetos/`) segue:

```
<nome-do-projeto>/
├── SPEC.md          ← o quê e por quê (escopo, requisitos, fora-de-escopo)
├── CONTEXTO.md      ← stack, ambiente, credenciais (refs), glossário
├── ARQUITETURA.md   ← desenho do sistema, módulos, fluxos, dependências
├── PROGRESSO.md     ← log datado: o que foi feito, próximos passos, bloqueios
├── notas/           ← brainstorms, ADRs, pesquisa, dúvidas
│   └── decisoes/    ← uma nota por decisão técnica relevante
└── snippets/        ← trechos de código reutilizáveis e comandos úteis
```

> **Regra-de-ouro**: SPEC e ARQUITETURA mudam pouco; PROGRESSO é editado quase toda sessão; CONTEXTO é atualizado quando o ambiente muda.

---

## Como usar com Claude Code

No início de cada sessão, abra o terminal **na raiz do repo do projeto** e diga ao Claude algo como:

```
Leia C:\Projetos\claude-projects\projetos\whatsapp-bot\SPEC.md
e C:\Projetos\claude-projects\projetos\whatsapp-bot\PROGRESSO.md
antes de qualquer coisa. Depois siga o WORKFLOW.md do vault.
```

Isso carrega ~2 arquivos pequenos (centenas de tokens) em vez de fazer o Claude redescobrir tudo.

Ao final da sessão, peça:

```
Atualize PROGRESSO.md com o que fizemos hoje e quaisquer decisões relevantes.
Se houver decisão arquitetural, crie uma nota em notas/decisoes/.
```

---

## Índice de projetos ativos

| Projeto | Pasta | Status | Última atualização |
|---|---|---|---|
| Sistema GAEP | [`projetos/sistema-gaep/`](projetos/sistema-gaep/SPEC.md) | 🟢 ativo | 2026-05-06 |
| SaaS Resolutiva | [`projetos/SaaS-Resolutiva/`](projetos/SaaS-Resolutiva/SPEC.md) | 🟢 ativo | 2026-05-12 |
| ERP Local | `projetos/erp-local/` (criar) | ⚪ planejado | — |
| Thermal Camera | `projetos/thermal-camera/` (criar) | ⚪ planejado | — |

> **Isolamento de contexto** entre projetos: ao abrir uma sessão Claude Code, **carregue apenas os arquivos do projeto em questão** (use o "Priming pronto" no `PROGRESSO.md` daquele projeto). Não cruze contextos — uma sessão = um projeto.

> Atualize esta tabela sempre que abrir/arquivar um projeto.

---

## Convenções

- **Idioma**: português para notas pessoais, inglês para código e termos técnicos.
- **Datas**: `YYYY-MM-DD` em PROGRESSO e nomes de notas.
- **Links internos**: use `[[wikilinks]]` do Obsidian para referências cruzadas.
- **Tags úteis**: `#decisao`, `#bloqueio`, `#ideia`, `#bug`, `#refatorar`, `#cliente/<nome>`.
- **Confidencial**: nunca colar segredos. Use `<env:VAR_NAME>` como placeholder e referenciar `~/.env` ou `1Password://...`.

---

## Próximos passos sugeridos

- [ ] Inicializar `git` na raiz do vault e fazer push para GitHub privado.
- [ ] Adicionar `.gitignore` para `.obsidian/workspace.json` e segredos.
- [ ] Configurar plugin **Git** do Obsidian para auto-commit diário.
- [ ] Criar pastas dos projetos restantes (erp-local, thermal-camera) usando o `TEMPLATES.md`.
