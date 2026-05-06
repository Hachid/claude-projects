# WORKFLOW — Sessão de trabalho com Claude Code

> Processo padrão. O objetivo é **mínimo de tokens, máximo de contexto**. Faça sempre os 4 passos.

---

## 1. Abrir sessão (priming)

Abra o terminal na raiz do repo do projeto. Primeiro turno com Claude Code:

```
Antes de qualquer ação:

1) Leia C:\Projetos\claude-projects\projetos\<projeto>\SPEC.md
2) Leia C:\Projetos\claude-projects\projetos\<projeto>\PROGRESSO.md
3) Se for tarefa arquitetural, leia também ARQUITETURA.md
4) Confirme em 3 bullets o que entendeu sobre o estado atual do projeto.
```

Isso custa ~500–1500 tokens em vez dos 5–20k que o Claude gastaria explorando o repo cego.

> Dica: salve esse bloco como snippet do terminal ou como alias (`claude-prime`).

---

## 2. Definir o objetivo da sessão (curto!)

```
Objetivo desta sessão: <uma frase>.
Critério de pronto: <uma frase>.
Restrições: <stack, prazo, "não tocar em X">.
```

Se a tarefa for grande, peça primeiro um **plano**:

```
Antes de codar, gere um plano em 5–10 passos. Vou aprovar antes de você começar.
```

---

## 3. Trabalhar em ciclos curtos

Para cada ciclo:

1. Claude propõe diff/comando.
2. Você revisa.
3. Aplica e roda.
4. Reporta resultado em uma linha (`✅ ok` / `❌ erro: <mensagem>`).

Se algo não-óbvio for decidido (ex: "vou usar Postgres em vez de SQLite"), peça:

```
Adicione uma ADR em notas/decisoes/ explicando essa escolha.
```

---

## 4. Encerrar sessão (consolidação)

Antes de sair, sempre:

```
Atualize C:\Projetos\claude-projects\projetos\<projeto>\PROGRESSO.md:
- adicione uma entrada datada de hoje (<YYYY-MM-DD>)
- liste o que foi feito, decisões, bloqueios e próximos passos
- mantenha o log mais recente no topo

Se houve mudança de arquitetura, atualize ARQUITETURA.md e/ou crie uma ADR.

Faça commit no repo do projeto com mensagem descritiva e dê push.
```

---

## Integração com GitHub

Sugestão de fluxo:

- O **vault** (`claude-projects/`) é um repo privado próprio com auto-commit (plugin Git do Obsidian, intervalo de 30min).
- Cada **projeto** tem seu próprio repo. `PROGRESSO.md` referencia issues/PRs por número (`#42`).
- Em cada PR, copie o bloco "Decisões" da entrada do PROGRESSO no descritivo — assim o histórico fica nos dois lugares.

Pedido típico ao Claude:

```
Crie a issue no GitHub correspondente ao próximo passo do PROGRESSO,
com label apropriado. Use `gh issue create`.
```

---

## Gatilhos rápidos (cole e use)

**Resumir estado**:
```
Resuma em 5 bullets o estado atual do projeto a partir do PROGRESSO.md.
```

**Detectar dívida técnica**:
```
Liste em ARQUITETURA.md as áreas marcadas como "TODO" ou "tech debt"
e proponha priorização.
```

**Refresh do CONTEXTO**:
```
Releia o repo. Compare com CONTEXTO.md. Liste o que mudou (versões,
dependências novas, variáveis de ambiente novas). Sugira um diff.
```

---

## Anti-padrões a evitar

- ❌ Pedir ao Claude para "ler o repo inteiro" — caro e quase sempre desnecessário.
- ❌ Deixar PROGRESSO desatualizado por mais de 2 sessões — o vault perde valor.
- ❌ Misturar mais de um projeto na mesma sessão — confunde contexto, gasta tokens.
- ❌ Colar segredos em qualquer arquivo do vault.
