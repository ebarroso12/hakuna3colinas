# Transmissão simultânea (texto e voz) sem rede

Pedido do dono em 12/10/2026. "Simultânea" aqui é **broadcast**: um fala,
todos recebem ao mesmo tempo — o comportamento de rádio PTT.

Pesquisado, não lembrado. Fontes no fim.

## Texto: resolvido, e é exatamente o que o LoRa faz

Mesh LoRa é broadcast por natureza: cada nó repete o que ouviu. Uma
mensagem sai e chega a toda a malha, sem servidor no meio.

- Alcance: 2–8 km; 10–20 km com visada
- Entrega a todos: sim, é o modo padrão
- Custo: R$150–400 por nó
- O app já grava alarme com nome e coordenada — o formato que cabe no
  canal já existe

**Para texto e posição, simultâneo e sem rede, está resolvido.**

## Voz: a física não deixa, e os números são estes

Voz precisa de banda. Banda custa alcance. Não há como ter os dois.

### LoRa com Codec2 — existe, mas não é conversa

O Meshtastic tem módulo de áudio com Codec2. Os números reais:

| | |
|---|---|
| Bitrates do Codec2 | 700 a 3200 bps |
| Mínimo para voz **confiável** | **2,4 kbps** |
| Implementação atual ("Voice Burst") | clipe de **1 segundo**, ~88 bytes |
| Intervalo imposto entre envios | **30 segundos** |

Lê-se: **recado de um segundo, com meio minuto de espera até o próximo.**
A 450 bps, cada segundo gravado enche dois pacotes — a transmissão não
acompanha a fala.

Isso não é push-to-talk. É correio de voz muito curto, e chamar de "voz
por LoRa" sem dizer isso engana quem vai comprar.

### Apps de walkie-talkie offline — PTT de verdade, alcance curto

Existem vários, funcionam hoje, e são grátis ou quase: **Mobile Talkie**,
**DirectTalk**, **Slide2Talk**, **Walkie Talkie Offline**. Operam por
Bluetooth, WiFi Direct, hotspot ou LAN, **sem conta e sem servidor**.

- Voz em tempo real: **sim**
- Broadcast para o grupo / canais: **sim**
- Alcance: **Bluetooth ~50 m; WiFi Direct / LAN 100–200 m**

São boas de verdade — para quem está junto.

### Rádio HT — e é aqui que a conta fecha

| Via | Voz ao vivo | Broadcast | Alcance | Custo |
|---|---|---|---|---|
| **Rádio HT** | ✅ | ✅ | **1–5 km** | **já têm** |
| App PTT offline | ✅ | ✅ | 50–200 m | ~R$0 |
| LoRa + Codec2 | ❌ clipe de 1 s | ✅ | 2–20 km | R$150–400/nó |
| PTT por celular (BiPTT) | ✅ | ✅ | **precisa de sinal** | plano |

**Para voz simultânea a quilômetros, sem rede, o rádio HT que a equipe já
tem é insuperável.** Nenhuma tecnologia de celular chega perto, e não é
questão de app melhor: é banda contra alcance.

## A combinação que eu recomendo

Não existe uma tecnologia só. Existe divisão de trabalho:

| O quê | Por onde | Observação |
|---|---|---|
| **Voz na trilha** | rádio HT | já têm, nada a comprar |
| **Voz no acampamento** | app PTT offline por WiFi Direct | grátis, testável hoje |
| **Alarme com GPS e nome** | LoRa | chega a km, estruturado |
| **Chat, prontuário, foto, triagem** | o app | já grava offline e sobe depois |

O erro a evitar é tentar substituir o rádio por app. O rádio resolve voz
melhor que qualquer celular sem sinal; o app resolve **registro**, que
nenhum rádio faz. Voz some no ar — atendimento, triagem e auditoria
precisam ficar gravados.

## O que testar primeiro, de graça

1. Instalar um app de PTT offline em dois celulares e medir o alcance
   real no terreno do evento. Dez minutos, custo zero.
2. Medir o sinal de operadora no acampamento. Se houver em algum ponto,
   muda a conta inteira (ver `comunicacao_de_equipe_sem_rede.md`).
3. Só depois comprar rádio novo.

## Fontes

- Meshtastic, configuração do módulo de áudio:
  https://meshtastic.org/docs/configuration/module/audio/
- Voice Burst (Codec2 700B, 1 s, 88 bytes, limite de 30 s):
  https://github.com/meshtastic/Meshtastic-Android/issues/4998
- Discussão de PTT no Meshtastic:
  https://meshtastic.discourse.group/t/ptt-voice-transmission/356
- Apps de PTT offline (Bluetooth / WiFi Direct / LAN), exemplos:
  Mobile Talkie, DirectTalk, Slide2Talk, Walkie Talkie Offline
