# Comunicação sem 3G, sem rede móvel e sem WiFi

Pedido do dono em 11/10/2026: *"Comunicação que não depende nem do 3G nem
de rede móvel nem de WiFi"*.

Este documento é levantamento, não implementação. Nada disso está no app.

## A conta que decide tudo

Não existe escolha de software aqui — existe escolha de **física**. O que
limita é alcance, e alcance custa dinheiro ou não existe.

| Via | Alcance real no mato | Hardware extra | Banda | Serve para |
|---|---|---|---|---|
| **BLE** entre celulares | 10–40 m | nenhum | ~10 kB/s | passar dado quando duas pessoas se cruzam |
| **WiFi Direct** | 50–150 m | nenhum | MB/s | o mesmo, com mais banda |
| **LoRa** (Meshtastic) | 2–8 km; 10–20 km com visada | R$150–400 por nó | **~1–5 kbps** | alarme e coordenada, em segundos |
| **Satélite** (SOS do celular) | global | nenhum (Android 15+ / iPhone 14+) | só SOS | pedir socorro, sem dado do app |
| **Satélite** (inReach/Zoleo) | global | ~R$2.000 + assinatura | texto curto | ponto fixo de comando |
| **Rádio HT** | 1–5 km | já têm | voz | o que eles já usam hoje |

**2,4 GHz (Bluetooth e WiFi) é absorvido por corpo humano e vegetação.**
Os 100 m de catálogo do BLE são em campo aberto, sem gente no caminho. Numa
trilha fechada, com o celular no bolso, conte com 10–40 m. É por isso que
BLE **não substitui** o alarme: ele cobre o grupo que já está junto, e
quem está junto se ouve grito.

**LoRa troca banda por alcance, e a troca é brutal:** 1–5 kbps. Dá para
texto curto e coordenada. **Não dá** para foto de ferida, prontuário nem
sincronizar a fila. Quem promete isso em LoRa está errado.

## O que o app JÁ tem a favor, e é mais do que parece

A parte difícil de rede mesh é **duplicata**: a mesma mensagem chega por
dois caminhos e o destino grava duas vezes. Num alarme, dois registros do
mesmo acidente mandam duas equipes para o mesmo lugar.

Isso já está resolvido aqui, por acidente felizardo da arquitetura
offline:

- `outbox` com `client_id` único por linha, gerado no aparelho
- envio por `upsert(onConflict: 'client_id', ignoreDuplicates: true)`
- hora do evento vinda do APARELHO (`created_at`, `occurred_at`), não de
  `now()` no Postgres — então um evento que viaja 6 h numa mochila chega
  com a hora em que aconteceu
- quarentena: entrada recusada não trava as de trás

Ou seja: **a fila é idempotente e carrega a hora correta.** Transportá-la
por qualquer meio físico não corrompe nada.

## O bloqueio real, e ele não é de rádio

A RLS prende a autoria ao autenticado: `sender_id = auth.uid()`,
`lida_por = auth.uid()`, `actor_id = auth.uid()`
(`fila_offline_chat_e_auditoria.sql:93-94`).

Consequência: **se o aparelho de B transportar a fila de A e enviar com a
sessão de B, o Postgres RECUSA.** Vai para quarentena e não sobe.

Isso não é hipótese — é a pendência "Troca de usuário no mesmo aparelho"
já registrada no `CLAUDE.md`, com outro nome. Qualquer plano de relay
entre aparelhos bate nela primeiro.

Para destravar, o caminho é uma Edge Function com `service_role` que
aceite "enviado por B em nome de A". E aí aparece o problema de verdade:
**o servidor precisa de prova de que A realmente escreveu aquilo**, senão
qualquer um injeta atendimento e alarme no nome de qualquer pessoa. Prova
exige assinar o payload no aparelho de A com uma chave que só A tem.

Em dado clínico, isso não é detalhe. É o item mais caro deste documento e
não deve ser improvisado.

## Caminho recomendado, em duas fases

### Fase 1 — transporte por mochila (custo zero de hardware)

Quando dois aparelhos se aproximam, trocam as filas pendentes por
BLE/WiFi Direct. Quem chegar primeiro a um ponto com sinal sobe tudo.

- Pacotes: `nearby_connections` (Android, API do Google, funciona 100%
  offline), `flutter_p2p_connection` (WiFi Direct + BLE),
  `flutter_nearby_connections` (Android + iOS)
- Permissões novas no manifest: `BLUETOOTH_SCAN`, `BLUETOOTH_ADVERTISE`,
  `BLUETOOTH_CONNECT`, `NEARBY_WIFI_DEVICES`
- **Não é tempo real.** Não serve para alarme. Serve para o atendimento
  registrado às 9h não ficar preso no aparelho até as 18h.
- Depende de resolver a autoria (acima). Sem isso, não comece.

### Fase 2 — LoRa para o alarme (hardware)

Um nó Meshtastic por equipe (9 nós) mais 1–2 repetidores em ponto alto.
O nó conversa com o celular por Bluetooth, então o app pode falar com ele.

- **Banda 915 MHz** (AU915/BR). Não comprar 868 MHz, que é Europa.
- Custo: Heltec V3 ~US$20–30; LILYGO T-Beam ~US$40–50 (tem GPS próprio);
  repetidor solar RAK WisMesh ~US$129
- O que cabe no canal: "EMERGÊNCIA — Edson — lat,lng". Exatamente o que a
  v1.0.39 já põe em `top_alerts` (`sender_name`, `latitude`, `longitude`).
- O que NÃO cabe: foto, prontuário, chat de equipe, sincronizar fila
- Repetidor em ponto alto vale mais que nó melhor na mão de cada um:
  alcance em LoRa é geometria, não potência

### O que NÃO recomendo

- **Depender de BLE para alarme.** 10–40 m no mato. Quem está nesse raio
  já viu o acidente.
- **Comprar satélite por pessoa.** R$2.000 × 200 não se paga, e o SOS
  nativo do celular já cobre o caso extremo sem custo.
- **Aposentar o rádio HT.** Voz humana resolve ambiguidade que texto não
  resolve, e eles já sabem usar. O LoRa complementa o rádio; não o
  substitui.

## Resumo honesto

- Sem hardware novo, não há como fazer alarme chegar longe. Isso é física.
- Com ~R$1.500–4.000 em nós LoRa, o alarme passa a funcionar de verdade na
  trilha — e o app já grava o dado no formato que cabe no canal.
- A Fase 1 é software, aproveita a fila que já existe, e o obstáculo dela
  é **autoria/RLS**, não rádio.
- O que já existe e continua valendo enquanto nada disso for feito: o
  rádio HT, e o alarme pelo app para quem tiver sinal.
