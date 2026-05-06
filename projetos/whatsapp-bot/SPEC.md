# WhatsApp Bot — SPEC

**Status**: 🟢 ativo
**Repo**: <preencher: ex. github.com/hachid/whatsapp-bot>
**Owner**: Hachid
**Última revisão**: 2026-05-06

## Problema
Atender mensagens de WhatsApp 24/7 com respostas automáticas inteligentes, encaminhando humanos só quando necessário, sem depender de plataformas pagas como Z-API ou Twilio em produção.

## Objetivo
Em 4 semanas, ter um bot rodando localmente em Docker que:
- Receba mensagens via WhatsApp (Baileys / Evolution API).
- Responda com LLM contextualizado por histórico do contato.
- Escale para humano (notifica via Telegram) quando detectar intenção de compra ou reclamação.

## Requisitos funcionais
- [ ] **RF-01**: Conectar a uma instância de WhatsApp via QR Code.
- [ ] **RF-02**: Persistir histórico de conversas em Postgres (últimas 30 mensagens por contato).
- [ ] **RF-03**: Roteador de intenção (LLM classifier) com 3 categorias: `auto`, `humano`, `ignorar`.
- [ ] **RF-04**: Modo `auto` responde via Claude Haiku 4.5 com prompt do contexto do contato.
- [ ] **RF-05**: Modo `humano` envia notificação no Telegram com link para a conversa.
- [ ] **RF-06**: Comando `/pausar` e `/retomar` por contato (admin via Telegram).

## Requisitos não-funcionais
- **Latência**: resposta em < 5s (p95).
- **Custo**: < R$ 50/mês de LLM (usar Haiku, cachear prompts comuns).
- **Privacidade/LGPD**: dados ficam no servidor próprio; sem envio para terceiros além do provedor LLM. Política de retenção: 90 dias.
- **Disponibilidade**: 99% (aceito downtime curto para reboot).

## Fora de escopo (v1)
- Envio de áudio/imagem.
- Multi-instância (várias contas de WhatsApp na mesma execução).
- Painel web administrativo (CLI + Telegram já bastam).

## Critérios de aceite
- Bot conectado, recebendo e respondendo em conta de teste.
- 10 mensagens reais respondidas com qualidade aceitável (revisão manual).
- Pausa/retomada por contato funcionando.
- Custo medido por 7 dias dentro do orçamento.
