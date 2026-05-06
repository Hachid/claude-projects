# Conexão básica Baileys com QR + reconexão

**Quando usar**: esqueleto do `ingest/index.ts` para parear e manter sessão viva.
**Última verificação**: 2026-05-06

```typescript
import makeWASocket, {
  DisconnectReason,
  useMultiFileAuthState,
} from '@whiskeysockets/baileys';
import { Boom } from '@hapi/boom';
import qrcode from 'qrcode-terminal';

async function start() {
  const { state, saveCreds } = await useMultiFileAuthState('./auth_info_baileys');

  const sock = makeWASocket({
    auth: state,
    printQRInTerminal: false,
  });

  sock.ev.on('creds.update', saveCreds);

  sock.ev.on('connection.update', (u) => {
    const { connection, lastDisconnect, qr } = u;
    if (qr) qrcode.generate(qr, { small: true });
    if (connection === 'close') {
      const code = (lastDisconnect?.error as Boom)?.output?.statusCode;
      const shouldReconnect = code !== DisconnectReason.loggedOut;
      console.log('conexão fechada, reconectar?', shouldReconnect);
      if (shouldReconnect) start();
    }
  });

  sock.ev.on('messages.upsert', async ({ messages, type }) => {
    if (type !== 'notify') return;
    for (const m of messages) {
      if (m.key.fromMe) continue;
      // TODO: publicar no Redis Stream `incoming`
      console.log('IN', m.key.remoteJid, m.message?.conversation);
    }
  });
}

start().catch(console.error);
```

**Notas**:
- `useMultiFileAuthState` salva credenciais como JSON em pasta — backup é só copiar a pasta.
- Em prod, troque `console.log` por logger (pino) e o `printQRInTerminal` por envio do QR ao Telegram.
- Reconexão simples; produção precisa de back-off (1s, 2s, 5s, 15s, 60s).
