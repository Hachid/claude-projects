# docker-compose base (Postgres + Redis)

**Quando usar**: ponto de partida do `docker-compose.yml` do projeto.
**Última verificação**: 2026-05-06

```yaml
services:
  db:
    image: postgres:16-alpine
    restart: unless-stopped
    environment:
      POSTGRES_USER: bot
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
      POSTGRES_DB: whatsapp_bot
    volumes:
      - pgdata:/var/lib/postgresql/data
    ports:
      - "5432:5432"

  redis:
    image: redis:7-alpine
    restart: unless-stopped
    ports:
      - "6379:6379"

  app:
    build: .
    restart: unless-stopped
    env_file: .env
    depends_on: [db, redis]
    volumes:
      - ./auth_info_baileys:/app/auth_info_baileys
    ports:
      - "3000:3000"

volumes:
  pgdata:
```

**Notas**:
- `auth_info_baileys` precisa ser volume bind (persistir fora do container) ou perde sessão a cada rebuild.
- `POSTGRES_PASSWORD` vem do `.env` — nunca hardcode.
- Para dev rápido sem build da imagem `app`, use `command: npm run dev` e bind do código fonte.
