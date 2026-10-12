# Rádio de verdade, sem Bluetooth

Pedido do dono em 12/10/2026: *"comunicação via rádio, via outros meios,
não Bluetooth"*.

Os documentos anteriores (`comunicacao_sem_rede.md`,
`comunicacao_de_equipe_sem_rede.md`) tratavam Bluetooth como a opção de
curto alcance e LoRa como a de longo. Aqui o recorte é outro: **tirar o
Bluetooth do caminho inteiro**, inclusive do link entre o celular e o
rádio.

## 1. LoRa sem Bluetooth: USB-C ou WiFi do próprio nó

O jeito comum de ligar um nó Meshtastic ao celular é BLE. **Não é o
único**, e os outros dois servem melhor em campo:

| Ligação | Como funciona | Observação |
|---|---|---|
| **USB-C (OTG)** | cabo do nó ao celular; o app abre sozinho | **o celular ALIMENTA o nó** — tira o problema de bateria do rádio |
| **WiFi do nó** | o nó cria a própria rede e o celular entra nela | não é WiFi de internet: é o rádio sendo o ponto de acesso |
| BLE | o padrão | descartado aqui por decisão |

O USB-C é o mais robusto dos três para trilha: sem pareamento para cair,
sem bateria separada para acabar, e o cabo prende fisicamente o nó ao
celular — que é o que você quer em alguém correndo.

Alcance e custo não mudam: 2–8 km, até 20 km com visada, R$150–400 por nó.

## 2. Usar os rádios HT que a equipe JÁ TEM (AFSK/APRS)

Esta é a opção que ninguém lembra. O celular liga ao HT por **cabo de
áudio**, e os dados vão modulados em som — texto e posição GPS por cima
da mesma voz que já se usa.

- App de referência: **APRSdroid** (livre, open source, mapas offline, sem
  depender de internet nem de Google Maps)
- Custo: só o **cabo de interface** (~R$50–150). O rádio já existe.
- Entrega: posição, mensagem de texto e beacon automático

### A ressalva que decide, e é legal, não técnica

**APRS roda em faixa de radioamador** (144,390 MHz nas Américas), e no
Brasil operar nessa faixa **exige licença da ANATEL** (COER). Transmitir
dados em faixa licenciada sem habilitação é infração, não detalhe
burocrático.

Antes de comprar qualquer cabo, responda duas perguntas:

1. **Que rádios a equipe usa hoje?** PX (27 MHz, cidadão), FRS/PMR sem
   licença, ou equipamento licenciado?
2. **Alguém na equipe é radioamador licenciado?** Se sim, muda tudo — e
   essa pessoa é quem deve conduzir isto.

Se os rádios forem do tipo sem licença, transmitir dados por eles tende a
ser irregular, e o caminho honesto é o LoRa.

## 3. Por que LoRa é a recomendação apesar de custar mais

**915 MHz é faixa ISM, livre no Brasil**, sem licença, respeitado o limite
de potência. É a diferença entre uma solução que a equipe pode usar no dia
26/11 e uma que depende de habilitação de alguém.

Some a isso o que o LoRa entrega e o AFSK não: mesh de verdade (cada nó
repete a mensagem dos outros), confirmação de entrega, e a coordenada
chegando estruturada em vez de um pacote a decodificar.

## 4. Outras vias de rádio, e por que não recomendo

| Via | Alcance | Por que não |
|---|---|---|
| **WiFi Direct / Aware** | 50–200 m | é rádio e não é Bluetooth, mas o alcance é de quem já está junto |
| **DMR** (rádio digital) | 1–10 km | manda texto e GPS nativamente, mas é faixa licenciada e o aparelho custa mais que o nó LoRa |
| **NFC** | centímetros | já está no app, para pulseira — não é via de comunicação |
| **Dados por som (ultrassom)** | metros | existe, mas é frágil a ruído; numa trilha com vento e gente falando, não |
| **Satélite** | global | o SOS nativo do celular (Android 15+ / iPhone 14+) já cobre o caso extremo sem custo |
| **Sidelink / D2D** | — | celular falando direto com celular sem torre existe na norma 3GPP e **não está liberado** em aparelho de consumidor |

## Resumo

- **Sem Bluetooth, a resposta é LoRa por USB-C.** O cabo é mais confiável
  que pareamento e ainda alimenta o nó.
- **Aproveitar o HT existente é possível e barato**, mas esbarra em
  licença de radioamador. Confira o tipo de rádio e se há alguém
  habilitado antes de gastar R$1 com cabo.
- **915 MHz é livre; 144 MHz não é.** Essa frase é o resumo da decisão.
- O app já grava alarme com `sender_name` e coordenada — o formato que
  cabe no canal de 1–5 kbps do LoRa já existe, não precisa ser inventado.
