# Supabase clients (browser e server)

**Quando usar**: padrão para criar clientes Supabase no Next.js 15 (App Router) usando `@supabase/ssr`.
**Última verificação**: 2026-05-06

## Browser client (`lib/supabase/client.ts`)

```typescript
import { createBrowserClient } from '@supabase/ssr';

export function createClient() {
  return createBrowserClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
  );
}
```

## Server client (`lib/supabase/server.ts`)

```typescript
import { createServerClient } from '@supabase/ssr';
import { cookies } from 'next/headers';

export async function createClient() {
  const cookieStore = await cookies();
  return createServerClient(
    process.env.NEXT_PUBLIC_SUPABASE_URL!,
    process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY!,
    {
      cookies: {
        getAll() { return cookieStore.getAll(); },
        setAll(cookiesToSet) {
          try {
            cookiesToSet.forEach(({ name, value, options }) =>
              cookieStore.set(name, value, options),
            );
          } catch {
            // Server Component fallback — sem set permitido
          }
        },
      },
    },
  );
}
```

## Auth por matrícula (login)

```typescript
const supabase = createClient();
const { data, error } = await supabase.auth.signInWithPassword({
  email: `${matricula}@gaep.internal`,
  password: senha,
});
```

**Notas**:
- O Supabase exige formato de email — usamos `@gaep.internal` como domínio sintético.
- Senha padrão = matrícula no seed inicial; trocar no primeiro acesso.
- Sessão sem expiração: configurar **Session timeout = 0** no painel Supabase Auth.
