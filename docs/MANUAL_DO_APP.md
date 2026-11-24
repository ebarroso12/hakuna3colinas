---
title: "Legendários Connect — Manual"
subtitle: "Aplicativo de coordenação dos Tops · versão 1.0.52"
date: "24 de novembro de 2026"
lang: pt-BR
---

# O que é este app

O **Legendários Connect** é o aplicativo de coordenação dos Tops. Ele serve
às **nove equipes** — ADM, Logística, Voz, Intercessão, Produção, Mídia,
Eventos, Segurança e Hakunas — e não só à equipe médica.

Ele faz quatro coisas:

1. **Emergência.** Qualquer pessoa aprovada aperta o botão e **todos** no Top
   recebem, com o nome de quem chamou e a posição no mapa.
2. **Comunicação.** Chat geral do Top, chat de cada equipe, e bloco de
   anotações pessoal de cada membro.
3. **Atendimento.** Ficha com dados de saúde, cor de triagem automática,
   registro de atendimento, sinais vitais e foto de ferida.
4. **Identificação.** Pulseira NFC e QR Code ligados à ficha da pessoa.

**O app funciona sem internet.** O que você escreve, registra ou aperta fica
guardado no celular e sobe sozinho quando o sinal voltar. Nada se perde por
falta de rede.

---

# Instalar

## No celular

Abra o navegador do celular e digite este endereço:

**github.com/ebarroso12/hakuna3colinas/releases/download/v1.0.52/legendarios1.0.52.apk**

Se o seu celular for antigo (comprado antes de 2019), use este em vez do de
cima:

**github.com/ebarroso12/hakuna3colinas/releases/download/v1.0.52/legendarios1.0.52-32bits.apk**

São uns 29 MB. Baixa sem precisar de login.

## Autorizar a instalação

O Android vai avisar que não instala aplicativo de fora da loja. É normal —
este app não está na Play Store.

1. Toque na notificação **Download concluído**
2. Aparece **"Por segurança, seu telefone não pode instalar apps
   desconhecidos desta fonte"** → toque em **Configurações**
3. Ligue a chave **Permitir desta fonte**
4. Volte e toque em **Instalar**
5. **Abrir**

## Permissões que o app pede

Aceite todas. Cada uma tem um motivo:

| Permissão | Para quê |
|---|---|
| **Notificação** | Receber o alarme de emergência com o app fechado |
| **Localização** | O mapa, a sua trilha, e o lugar do acidente no alarme |
| **Câmera** | Ler QR Code e tirar foto de ferida |
| **Bluetooth / Dispositivos por perto** | O rádio entre celulares, quando não há sinal |

Se você recusar a localização, o mapa e o rádio param de funcionar. Se
recusar a notificação, a emergência não chega com o app fechado.

## Atualizar depois

Quando sair versão nova, a tela inicial mostra uma faixa com o botão
**ATUALIZAR**. Toque e ele baixa sozinho. Instalar por cima **não apaga
nada** — seus dados continuam.

---

# Entrar pela primeira vez

Você entra com o **seu número dos Legendários**. Não é e-mail.

1. Abra o app e toque em **Primeiro acesso**
2. Digite **o seu número** e a **senha do Top** que o administrador anunciou
3. Toque em **CONTINUAR**
4. Preencha a sua ficha (explicada abaixo)
5. **Crie a sua senha pessoal** — mínimo 8 caracteres

Pronto. Daí em diante você entra só com **o seu número e a sua senha**.

> **A senha do Top não é a sua senha.** Ela é a mesma para todo mundo e serve
> só para se cadastrar. A sua senha é a que você acabou de criar, e é só sua.

## A ficha que você preenche

Ela existe para a equipe Hakuna te atender bem se algo acontecer. Preencha
com cuidado — **é o seu prontuário no evento**.

- **Nome completo** e **data de nascimento** (obrigatórios)
- **Família**, apelido, telefone, cidade
- **Tipo sanguíneo**, altura, peso
- **Comorbidades** — marque tudo que tiver. É isto que calcula a sua cor de
  triagem.
- **Alergias** e **medicamentos de uso contínuo** — escreva mesmo que pareça
  pouco importante
- **Cirurgias**, restrições físicas, plano de saúde
- **Contato de emergência** — nome e telefone de quem avisar

## Se não tiver a senha do Top

Toque em **"Não tem a senha do Top? Pedir código ao administrador"**. Você
manda o seu número e o número do Top, e o administrador te passa um código.
Esse código funciona como senha — **troque a senha depois de entrar**, no
menu da tela inicial.

## Já tem conta

Na tela de entrada, digite **o seu número** e **a sua senha**. Pronto.

Esqueceu a senha? Peça ao administrador — ele gera um código novo para você.

---

# A tela inicial

Mostra a lista de **Tops** (os eventos). Toque no Top para entrar.

No alto, à direita:

- **Três pontinhos** → trocar senha, sair, ver a versão instalada
- **Faixa com ATUALIZAR** → aparece quando há versão nova

A lista de Tops **funciona sem internet** — ela fica guardada no celular.

---

# Dentro do Top

## O que todo mundo tem

### O botão EMERGÊNCIA

Vermelho, grande, impossível de errar.

Ao apertar, **todos os aprovados do Top recebem** — com o seu nome e a sua
posição. Quem estiver com o app aberto ouve o alarme e vê uma faixa
vermelha; quem estiver com o app fechado recebe uma notificação.

**Aperte sem medo de errar.** É melhor um alarme à toa que um acidente em
silêncio.

Quando você recebe um alarme, a faixa mostra **quem chamou** e o botão para
ver **o lugar no mapa**. A coordenada aparece em texto e pode ser copiada —
para ditar no rádio quando não houver mapa.

> Alarme que chegou pelo rádio entre celulares aparece marcado como **não
> confirmado**. O rádio não tem como provar quem mandou. Quando o mesmo
> alarme chega pelo servidor, ele se confirma sozinho.

### Compartilhar a minha posição

Liga o envio da sua posição a cada 15 metros caminhados. Alimenta o mapa, a
sua trilha e o cálculo de "quem está mais perto" numa emergência.

**Ligue no começo do dia.** Sem isso, numa emergência ninguém sabe quem está
por perto de você.

### O chat geral

Todo mundo aprovado do Top participa. É o canal de recado para todos.

### Chats das equipes

Aparecem as **nove equipes**, sempre. Você entra nas que você é membro
liberado. Nas outras, ao toque, o app explica o que falta:

- **Você não está nesta equipe** → pedir inclusão ao administrador
- **Está, mas falta liberar** → pedir liberação ao coordenador
- **Bloqueado** → falar com o coordenador

A coordenação da equipe pode marcar uma mensagem como **alerta**, que
aparece destacada para todos da equipe.

### Bloco de anotações

Cada membro tem o **seu** bloco, por equipe. Ninguém escreve no bloco de
outro. Serve para anotar o que você precisa lembrar no turno.

> **Não escreva sintoma, pressão nem conduta aqui.** Isso vai no
> atendimento. Escrito na anotação, fica fora da triagem e invisível para
> quem vai atender.

### A fila (ícone de nuvem)

Mostra o que você escreveu e ainda não subiu para o servidor, por falta de
sinal. Sobe sozinho quando a rede voltar.

Se algo aparecer com aviso vermelho, foi **recusado** pelo servidor — avise
o administrador. Nada é apagado sem você saber.

---

# Sem sinal de internet

## O que funciona offline

- Ver a lista de Tops e de participantes
- Abrir e preencher ficha de participante
- Registrar atendimento, sinais vitais, foto de ferida
- Escrever no chat e nas anotações
- Apertar EMERGÊNCIA
- Ler pulseira NFC e QR Code

Tudo isso fica no celular e sobe quando houver sinal.

## O que NÃO funciona offline

- Ver a posição das outras pessoas no mapa (é tempo real, não existe sem
  rede)
- A lista de perfis de usuários
- O histórico de atendimento que está no servidor (o que **você** registrou
  aparece sempre)
- Apagar usuário ou participante — exige internet, de propósito

## O rádio entre celulares

Quando **não há internet nenhuma**, o app consegue falar com outros celulares
por perto, direto, sem rede.

**Como ligar:** entre no chat de uma equipe e toque no **botão da malha**.
Faça isso em todos os celulares que precisam se falar.

**O que passa pelo rádio:** mensagens do chat de equipe e o alarme de
emergência.

**Três limites que você precisa saber:**

1. **O app tem de estar aberto, na tela, nos dois celulares.** Com o celular
   no bolso e a tela apagada, o Android congela o rádio e ele para.
2. **O alcance é de 10 a 150 metros** no mato. Corpo e vegetação absorvem o
   sinal. Não serve para a trilha inteira.
3. **Não há confirmação de entrega.** O app mostra para quantos aparelhos
   ele *falou*, nunca quantos *ouviram*.

Vem desligado de propósito: ligado, ele consome bateria de verdade — e
bateria em campo é recurso de segurança.

---

# Para a equipe Hakuna

Só quem está liberado como Hakuna naquele Top acessa esta parte. O
administrador libera.

## A lista de participantes

Mostra todos com a **cor de triagem** ao lado. Busca por nome, número ou
família — e funciona sem acento ("joao" acha "JOÃO").

O botão **Novo** cadastra alguém na hora, mesmo sem internet.

## As cores da triagem

Calculadas automaticamente a partir da **idade** e do **número de
comorbidades**:

| Idade | 0 comorbidades | 1 comorbidade | 2 ou mais |
|---|---|---|---|
| **até 25** | azul | verde | vermelho |
| **26 a 40** | verde | amarelo | vermelho |
| **41 ou mais** | amarelo | vermelho | vermelho |

A cor **sobe para vermelho** automaticamente quando a última aferição mostra
SpO₂ abaixo de 90, pressão sistólica acima de 180 ou diastólica acima de 110.

A cor nunca desce sozinha.

## Atendimento

Na ficha da pessoa → **Atendimento**. Registre procedimento, sinais vitais e
feridas. Pode tirar foto.

O atendimento fica **aberto** até alguém encerrar. Encerrar é outro toque, na
mesma tela.

## Sinais vitais

Tela própria, para aferir sem abrir atendimento. Alimenta a triagem do mesmo
jeito.

## Prontuário

Histórico de atendimentos da pessoa. O que **você** registrou aparece sempre,
com ou sem internet.

## Chat clínico

Canal separado, só de quem é Hakuna liberado. É onde se fala de paciente.

---

# Pulseira NFC e QR Code

## Ler

**LER TAG** está na barra de baixo, em qualquer lugar da lista de
participantes — é a ação mais usada em campo.

Encoste o celular na pulseira. O app abre a ficha da pessoa.

Se não identificar, ele mostra o código da pulseira e o tipo — assim você sabe
se a pulseira é de outro sistema ou está em branco, em vez de ficar batendo o
celular nela.

**QR Code** funciona igual, pela câmera, e **não precisa de internet** — o
leitor está dentro do app.

## Emitir

Só o administrador emite pulseira. Na ficha da pessoa → emitir. A pulseira e
o QR Code carregam **o mesmo código**: revogar um revoga o outro.

---

# Para o administrador

Menu **Administração** na tela inicial.

- **Pedidos de acesso** — liberar quem pediu entrada e passar o código
- **Usuários** — papéis, dados de triagem
- **Tops** — criar e editar evento

Dentro do Top, no menu de três pontinhos:

- **Painel do Top** — contagens do evento (precisa de internet)
- **Equipes do Top** — montar as nove equipes, dar cargo, liberar, bloquear
- **Pulseiras NFC** — emitir e revogar
- **Quem vê o mapa** — liberar ou bloquear pessoa por pessoa
- **Importar planilha** — CSV ou XLSX com a lista de participantes

## Quem pode o quê

| Ação | Senderista | Hakuna liberado | Coordenador da equipe | Admin | Admin master |
|---|---|---|---|---|---|
| Criar e editar ficha, inclusive família | não | **sim** | não | **sim** | sim |
| Pôr alguém na equipe | não | não | **sim, na dele** | **sim** | sim |
| Liberar, bloquear e remover membro | não | não | **sim, na dele** | **sim** | sim |
| Dar cargo de coordenador | não | não | não | **sim** | sim |
| Emitir pulseira | não | não | não | **sim** | sim |
| Liberar Hakuna no Top | não | não | não | **sim** | sim |
| Definir quem vê o mapa | não | não | não | **sim** | sim |
| Apagar ficha ou usuário | não | não | não | não | **só ele** |
| Promover alguém a admin | não | não | não | não | **só ele** |
| Mudar regras de triagem | não | não | não | não | **só ele** |
| Gerar a senha do Top e abrir o cadastro | não | não | não | não | **só ele** |

As **nove equipes** e os **três cargos** são fixos — não é possível criar
outros pelo app.

---

# Para o administrador master

## Abrir um Top para a equipe

1. Menu do Top → editar
2. Preencha **Número do Top**, **Local / pista** e **Diretor responsável**
3. **Salvar**
4. Botão **Gerar senha do Top**

A senha aparece **uma única vez** — anote na hora. Gerar outra invalida a
anterior.

Anuncie ao grupo assim:

> Baixe o app, toque em **Primeiro acesso**, digite o **seu número dos
> Legendários** e a senha do Top **XXXXXXXX**. Preencha sua ficha e crie a
> sua senha. Depois você entra só com o seu número e a sua senha.

## Fechar depois do evento

Na mesma tela há o interruptor **Cadastro ABERTO / FECHADO**. Feche quando a
equipe toda já estiver dentro.

**Por que fechar:** a senha do Top é compartilhada e continua circulando no
WhatsApp para sempre. Fechar é o que tira o valor dela — sem precisar gerar
senha nova.

## Antes do evento começar

- **Libere os Hakunas no Top.** Sem isso eles não registram atendimento.
- **Monte as equipes** e dê os cargos de coordenação.
- **Suba o emblema e as fotos** do Top, se quiser.

---

# Quando algo dá errado

| O que aparece | O que é | O que fazer |
|---|---|---|
| "Número ou senha do Top incorretos" | O número está errado, ou a senha do Top mudou | Confira o número; peça a senha atual |
| "Este número já tem conta" | Você já se cadastrou antes | Entre com número e **a sua** senha |
| "O cadastro deste Top está FECHADO" | O administrador fechou | Peça para ele reabrir |
| "Erro ao carregar perfil" | O servidor não respondeu | Toque em **Tentar de novo**. Não é a sua senha. |
| Tela de espera "Conectando ao servidor…" | Sem sinal | Espere 8 segundos; se já foi aprovado neste celular, o app entra com o que está guardado |
| O rádio não acha ninguém | Permissão ou Bluetooth desligado | Ligue o Bluetooth; confira as permissões de localização e dispositivos por perto; mantenha o app aberto |
| Mensagem no chat não aparece no outro celular | Sem sinal e sem rádio | Ligue o botão da malha nos dois, com os apps abertos |

**Nada que você escreveu se perde** por erro de rede. Fica na fila (ícone de
nuvem) e sobe depois.

---

# O que o app NÃO faz

Dito com clareza, para ninguém contar com o que não existe:

- **Não funciona em iPhone** por enquanto.
- **Não tem rádio de longa distância.** O rádio entre celulares vai de 10 a
  150 metros. Para a trilha inteira seria preciso equipamento próprio.
- **O rádio exige o app aberto**, na tela, nos dois celulares.
- **Não envia foto nem prontuário pelo rádio** — só texto curto e o alarme.
- **Não confirma entrega** de mensagem pelo rádio.
- **Não substitui o rádio HT da organização.** O app ajuda; ele não é o plano
  de comunicação do evento.

---

*Legendários Connect · versão 1.0.52 · 24 de novembro de 2026*
