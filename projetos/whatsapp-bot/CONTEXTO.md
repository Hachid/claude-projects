# WhatsApp Bot — CONTEXTO

## Stack
- **Linguagem**: Node 20 (TypeScript)
- **Conector WhatsApp**: Baileys (`@whiskeysockets/baileys`)
- **LLM**: Claude Haiku 4.5 (via Anthropic API)
- **DB**: Postgres 16 (em Docker)
- **Cache/Fila**: Redis 7 (em Docker)
- **Notificações**: Telegram Bot API (`node-telegram-bot-api`)
- **Infra**: Docker Compose local; eventual deploy em VPS Hostinger

## Ambientes
| Env | URL / Host | Notas |
|---|---|---|
| local | `localhost:3000` | `docker compose up` na raiz do repo |
| staging | — | ainda não configurado |
| prod | VPS Hostinger (planejado) | Acesso via SSH chave `~/.ssh/hostinger_ed25519` |

## Credenciais (refs, NUNCA o valor)
- `ANTHROPIC_API_KEY` → `~/.env` (linha `ANTHROPIC_API_KEY=...`)
- `TELEGRAM_BOT_TOKEN` → 1Password://Pessoal/whatsapp-bot-telegram
- `POSTGRES_PASSWORD` → gerada via `openssl rand -hex 24`, salva em `1Password://Pessoal/whatsapp-bot-pg`
- `ADMIN_TELEGRAM_CHAT_ID` → `~/.env` (meu chat pessoal)

> O arquivo `.env.example` no repo lista as variáveis sem os valores.

## Glossário do domínio
- **Contato**: número de WhatsApp único (`@s.whatsapp.net`).
- **Sessão Baileys**: estado de autenticação persistido em `./auth_info_baileys/` (NUNCA commitar).
- **Intenção `auto`**: resposta gerada pelo bot.
- **Intenção `humano`**: caso que precisa de atendimento manual; bot fica em silêncio até admin retomar.
- **Intenção `ignorar`**: spam, grupos não monitorados, mensagens de status.

## Pessoas / Stakeholders
- **Hachid** — owner, único usuário admin via Telegram.
- *(adicionar quando virar projeto de cliente)*
