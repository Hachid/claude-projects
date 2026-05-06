# WhatsApp Bot — PROGRESSO

> Log mais recente no topo. Cada sessão = uma entrada datada.

---

## 2026-05-06 — Setup inicial e estrutura no vault
**Sessão**: Claude (organização do vault)
**Duração aprox**: 30min

### Feito
- Criada estrutura do projeto no vault (`SPEC`, `CONTEXTO`, `ARQUITETURA`, `PROGRESSO`).
- Definido escopo da v1: Baileys + Haiku + Telegram para escalada.
- Diagrama de arquitetura inicial em Mermaid.

### Decisões
- **Baileys** em vez de Evolution API — ver [[notas/decisoes/ADR-001-baileys-vs-evolution]].
- **Claude Haiku 4.5** para classificador e resposta — barato + rápido o suficiente.

### Bloqueios
- Nenhum no momento.

### Próximos passos
- [ ] Criar repo `whatsapp-bot` no GitHub (privado).
- [ ] Subir esqueleto: `docker-compose.yml` com Postgres + Redis.
- [ ] Implementar módulo `ingest/` com pareamento por QR Code.
- [ ] Salvar primeira mensagem recebida no Postgres (sem responder ainda).

---

## Backlog (não datado)

- [ ] Painel web admin simples (Next.js?) — depois da v1.
- [ ] Suporte a áudio (transcrição via Whisper local).
- [ ] Multi-tenant (várias instâncias por usuário).
- [ ] Deploy em VPS com `systemd` + `caddy` para webhook health.
- [ ] Integração com CRM (qual?) para registrar leads identificados como `humano`.
