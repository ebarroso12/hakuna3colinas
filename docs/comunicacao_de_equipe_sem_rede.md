# Chat de equipe sem rede móvel e sem WiFi

Pedido do dono em 12/10/2026, depois do levantamento geral em
`comunicacao_sem_rede.md`. Aqui o recorte é outro e a conclusão muda.

## Por que equipe é um problema DIFERENTE do alarme

O alarme precisa atravessar a trilha inteira: quem se acidentou está a
quilômetros de quem vai socorrer. Por isso só LoRa serve, e por isso o
documento anterior descartou Bluetooth.

**Chat de equipe não tem essa exigência.** Equipe é um grupo pequeno que
trabalha junto — e "junto" é exatamente a condição em que BLE e WiFi
Direct funcionam. A pergunta deixa de ser "quantos quilômetros" e passa a
ser **onde cada equipe fica**.

### As 9 equipes não têm a mesma geometria

| Equipe | Onde fica | Rádio que serve |
|---|---|---|
| ADM | base | WiFi local / BLE |
| Produção | base | WiFi local / BLE |
| Mídia | base + saídas curtas | WiFi local / BLE |
| Eventos | base | WiFi local / BLE |
| Voz | base / palco | WiFi local / BLE |
| Intercessão | base | WiFi local / BLE |
| Logística | base + deslocamentos | WiFi local, LoRa fora |
| **Segurança** | **espalhada na trilha** | **LoRa** |
| **Hakunas** | **móveis, na trilha** | **LoRa** |

Seis das nove trabalham concentradas. Para elas, rede local resolve com
**todas** as funções do app — chat, foto, prontuário, anotação — e não só
texto curto.

As duas que estão espalhadas são justamente as de emergência. Elas
continuam dependendo de LoRa, pelos motivos do outro documento.

## "Sem WiFi" tem duas leituras, e elas levam a lugares opostos

1. **Sem internet** — rede local própria (roteador sem link) está liberada
2. **Sem rádio 2,4/5 GHz nenhum** — sobra só LoRa, e com ela sobra só texto

Este documento assume a leitura 1, que é a que o campo normalmente quer:
o problema não é WiFi, é não existir operadora no meio do mato. Se a
leitura for a 2, pule para `comunicacao_sem_rede.md`.

## Os três caminhos, do mais barato ao que resolve de verdade

### A. Fila que pula de celular em celular (R$0 de hardware)

Dois aparelhos perto trocam as filas pendentes por BLE ou WiFi Direct.
Quem chegar primeiro a um ponto com sinal sobe tudo.

- **Entrega:** o atendimento registrado às 9h não fica preso até as 18h
- **Não entrega:** conversa. Não é tempo real e não serve para coordenar
- **Bloqueio:** autoria. A RLS prende `sender_id = auth.uid()`, então o
  aparelho de B enviando a fila de A é **recusado**. Resolver exige Edge
  Function com `service_role` **e** payload assinado na origem — ver
  `comunicacao_sem_rede.md`

### B. Rede local no acampamento (R$150–400) ← melhor relação custo/efeito

Um roteador comum, **sem internet ligada**, ou um celular em modo
roteador. Cobre 50–150 m, mais com antena externa.

Com ele, seis das nove equipes ficam em rede o tempo todo no acampamento.
Mas há um porém que decide se vale a pena:

**O app conversa com o Supabase na nuvem, não com a rede local.** Um
roteador sem internet dá rede e não dá servidor — o chat continua sem para
onde enviar. Rede local só resolve junto com (C).

A exceção: se o acampamento tiver **qualquer** link (Starlink, um celular
com sinal fazendo tethering, internet da fazenda), então o roteador
sozinho já resolve tudo, porque o app volta a alcançar o Supabase. **Esse
é o cenário mais provável e o mais barato de testar** — vale medir antes
de comprar qualquer coisa.

### C. Servidor de campo (R$600–2.000)

Um mini-PC ou Raspberry Pi no acampamento rodando a pilha, com o app
apontando para ele quando está na rede local e para a nuvem quando há
internet.

- **Entrega:** o app INTEIRO funciona sem internet — chat das 9 equipes,
  foto de ferida, prontuário, mapa, alarme dentro do acampamento
- **Custo real não é o hardware, é o trabalho:** o app tem URL do Supabase
  fixa em `--dart-define`; precisaria descobrir servidor, alternar entre
  os dois, e **reconciliar** o que foi escrito em cada um. Reconciliação é
  onde isso fica caro
- A favor: `client_id` idempotente e hora do aparelho já existem, que é
  metade do problema de merge resolvido
- Contra: auth. Sessão emitida pelo servidor local não vale na nuvem e
  vice-versa. Esse é o nó

### O que eu NÃO recomendo

- **Bluetooth mesh como chat de equipe em movimento.** Numa trilha, 10–40 m.
  Quem está nesse raio conversa falando.
- **Começar pelo servidor de campo.** É o mais caro e o que depende de
  mais coisas darem certo. Se o acampamento tiver qualquer link, (B)
  entrega quase tudo por 5% do esforço.

## Ordem recomendada

1. **Medir o sinal no local do evento** antes de comprar qualquer coisa.
   Se há 3G/4G em algum ponto do acampamento, (B) resolve as seis equipes
   de base hoje, por R$150–400, sem uma linha de código.
2. **LoRa para segurança e hakunas**, que é o que o outro documento já
   recomendava e não muda aqui.
3. **(A) ou (C) só depois disso**, e os dois dependem de resolver
   autoria/auth — que é trabalho de servidor, não de rádio.

## O que vale registrar com honestidade

O obstáculo das soluções de software não é alcance de rádio: é que a
identidade do usuário está amarrada ao Supabase na nuvem
(`sender_id = auth.uid()`). Enquanto isso não tiver resposta, (A) e (C)
não saem do papel por mais BLE ou servidor que se coloque.

E há um fato de contexto que pesa mais que tudo isto: **hoje existe 1
conta no app inteiro** (conferido no banco em 12/10/2026, `profiles` = 1).
Comunicação offline entre equipes que ainda não têm conta nem vínculo
resolve um problema que o evento ainda não tem. A ordem que faz diferença
no dia 26/11 é: pessoas com conta → pessoas nas equipes → depois, rádio.
