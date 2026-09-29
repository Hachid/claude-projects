# Iniciar ambiente de desenvolvimento

**Quando usar**: início de qualquer sessão de trabalho no SaaS-Resolutiva
**Última verificação**: 2026-05-12

## Backend

```powershell
cd C:\Projetos\saas_automacao_base\backend
.\.venv\Scripts\Activate.ps1
uvicorn app.main:app --reload
# API disponível em http://localhost:8000
# Docs em http://localhost:8000/docs
```

## Frontend

```powershell
cd C:\Projetos\saas_automacao_base\frontend
npm run dev
# App disponível em http://localhost:3000
```

## Testes backend

```powershell
cd C:\Projetos\saas_automacao_base\backend
pytest
# ou: pytest tests/test_auth.py -v
```

## Build frontend (verificar antes de PR)

```powershell
cd C:\Projetos\saas_automacao_base\frontend
npm run build   # deve completar 12/12 páginas sem erro
npm run lint    # deve retornar 0 erros
```

**Notas**:
- Backend e frontend precisam rodar simultaneamente para o frontend funcionar
- Sem `NEXT_PUBLIC_AUTH_REQUIRED=true`, AuthGate está em modo permissivo (dev)
- Tenant ID padrão: `1` (fallback em `features/session/dev-config.ts`)
