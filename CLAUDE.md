# Legendario Connect

App de coordenação dos eventos ("Tops") dos Legendários — **das 9 equipes,
não só da médica.** Rastreamento de posição, chat por equipe, triagem por
cor, sinais vitais, atendimento e NFC.

## As três dimensões de quem é quem — não confundir

Este arquivo já descreveu o app como "da equipe médica (Hakunas)", e isso
levou a uma leitura errada do produto inteiro. Corrigido em 11/10/2026.
São **três** coisas separadas no banco:

| Dimensão | Enum | Valores | O que é |
|---|---|---|---|
| Papel no sistema | `user_role` | `admin`, `hakuna`, `senderista` | O que a pessoa pode fazer no app |
| Equipe no Top | `team_key` | 9 valores (abaixo) | Em qual equipe ela trabalha |
| Posição na equipe | `team_role` | `coordenador`, `subcoordenador`, `membro` | A hierarquia dentro da equipe |

**`hakuna` NÃO é uma equipe** — é um papel, de quem atende clinicamente.
Uma pessoa pode ser `hakuna` e estar na equipe `logistica`.

As 10 chaves de `team_key`: `adm`, `logistica`, `voz`, `intercessao`,
`producao`, `midia`, `eventos`, `seguranca`, **`hakunas`**, `geral`.

São **9 equipes** mais o canal `geral`, que não é equipe — é o que todo
participante aprovado do Top enxerga. Daí `TeamKeyUi.equipes` devolver 9.
Ver `lib/models/team.dart`, que tem rótulo, ícone e cor de cada uma.

`hakunas` entrou em 11/10/2026. **A equipe de salvamento faltava no enum**,
e por isso não tinha chat nem bloco de anotações como as outras — só o chat
clínico, em `top_hakuna_messages`, numa tabela separada. Hakuna é equipe
**e** papel: a equipe é onde a pessoa trabalha, o papel (`user_role`) é o
que ela pode fazer.

### As 9 equipes têm de APARECER, não só existir

O dono abriu o app em 11/10/2026 e não achou as 9. Os dois lados do mesmo
problema, os dois corrigidos:

1. **`TeamChatsScreen` listava só as equipes em que a pessoa já era membro
   liberado.** `top_team_members` nasce vazia, então esse era o estado de
   **todo mundo** num Top recém-montado — e também do admin, que a RLS
   libera em todas (`is_admin() or is_team_member(...)`). A tela estava
   fechando porta que o banco deixa aberta, o inverso da regra do projeto.
   Hoje ela mostra **sempre as 9** e marca o estado de cada uma. Equipe
   fechada não abre o chat (a RLS esvaziaria) — ao toque, explica.

   Os três estados de "fechada" têm soluções diferentes e por isso são
   textos diferentes: **não está na equipe** (pedir inclusão), **está e
   falta liberar** (`released = false`, pedir liberação) e **bloqueado**.
   O segundo é o pior de esconder: `is_team_member` exige `released`, e
   quem cai nele fica sem chat e sem anotações sem saber o que pedir. Daí
   `fetchMyTeams(..., somenteAtivas: false)` existir.

   Travado por `test/widgets/as_nove_equipes_aparecem_test.dart`, que
   monta a tela no pior caso (ninguém logado: zero vínculos e perfil que
   nem carrega) e exige as 9 na árvore. Ele precisa de superfície alta —
   o `ListView` constrói só o visível e a primeira versão falhou em
   "Mídia" por isso, não por defeito da tela.

   **O ADMIN VÊ E ACESSA AS 9**, incluindo mandar mensagem como alerta.
   Decisão do dono em 11/10/2026, nestas palavras: "como administrador
   devo ver e ter acesso a todas as equipes". Garantido no banco por
   `supabase/admin_ve_todas_as_equipes.sql` — **aditivo de propósito**:
   `team_messages` não está no repositório, então não há como reescrever
   as policies dela sem apagar regra que não se sabe que existe. Policies
   do mesmo comando são OR entre si, então somar `is_admin()` amplia e não
   tira nada de ninguém.

   **O vínculo manda sobre o papel, e a ordem importa.** Admin bloqueado
   numa equipe aparece como BLOQUEADO, não como "acesso de admin": o
   bloqueio é decisão explícita de alguém sobre aquela pessoa naquela
   equipe, e ignorá-lo seria a tela desfazendo pela leitura o que um admin
   fez pela escrita.

   A regra toda mora em `lib/models/acesso_as_equipes.dart`, fora da tela,
   porque regra de acesso precisa de teste direto — dentro do `State` só
   se verificava montando a árvore e fingindo rede. 14 casos em
   `test/models/acesso_as_equipes_test.dart`, inclusive o texto de cada
   estado: **o texto é a correção**, não enfeite.

2. **Nada no repositório cria o enum `team_key`.** O valor `hakunas`
   entrou em produção por comando à mão registrado apenas como
   *comentário* em `equipes_alarme_mapa_e_blocos.sql:17-18`. Comentário
   não roda: um schema reconstruído deste repositório sairia com 8
   equipes e a de salvamento desapareceria em silêncio. Hoje há
   `supabase/team_key_as_nove_equipes.sql`, idempotente, com a consulta
   de conferência.

**Ainda fora do repositório: `top_team_members` e `team_messages`.** As
duas só existem em produção. Não as escrevi de memória de propósito —
`create table` inventado parece fonte da verdade e diverge calado. Extrair
com `pg_dump --schema-only` e versionar.

## O módulo clínico é uma PARTE, e tem cerca própria

**O que passa por aqui inclui triagem, comorbidade e sinais vitais de
pessoas reais.** Erro de cálculo ou de permissão nessa parte tem
consequência clínica, não só bug. Por isso atendimento, prontuário, foto
de ferida e chat clínico (`top_hakuna_messages`) exigem estar em
`top_hakunas` com `released = true` — e deve continuar assim. Membro de
mídia não tem motivo para ler prontuário.

### Quem vê o quê — decidido em 11/10/2026

| Função | Quem pode | Por quê |
|---|---|---|
| Chat e anotações da equipe | membro **liberado** da equipe · **admin, nas 9** | `is_team_member` ou `is_admin()` |
| Mandar mensagem como **alerta** | coordenação da equipe · **admin, nas 9** | `is_alert` na RLS de `team_messages` |
| Atendimento, prontuário, foto, chat clínico | Hakuna liberado em `top_hakunas` | dado clínico tem cerca própria |
| **Disparar e receber alarme** | **TODO aprovado do Top** | `pode_alarmar_no_top()` |
| Ver o **lugar do alarme** no mapa | quem recebe o alarme — todos | vem de `top_alerts`, não de `hakuna_positions` |
| **Ver a posição dos outros** | admin · Hakuna liberado · coordenação/subcoordenação de qualquer equipe · membros de `seguranca` e `hakunas` | `pode_ver_mapa()` |
| Publicar a própria posição | qualquer um logado | quem caminha gera o ponto |
| Ver a própria trilha | sempre | alimenta `StatsService` |

**O alarme é mais aberto que o mapa de propósito.** Alarme é emergência:
quem vê um acidente é quem está por perto, não quem tem o papel certo. A
posição é vigilância contínua, e 200 pessoas vendo a localização de todas
as outras não é necessário para mídia, produção ou intercessão fazerem o
trabalho delas.

### Emergência: todos disparam, todos recebem, com GPS e nome

Decisão do dono em 11/10/2026: *"se alguma pessoa apertar emergência todos
devem ver o lugar via GPS e quem está chamando"*. Três defeitos achados ao
aplicar, e os três eram **a UI mais restrita que o banco**:

1. **O botão EMERGÊNCIA estava sob `if (isHakuna)`** — só Hakuna e admin.
   A RLS foi aberta na v1.0.35 para `pertence_ao_top()` e a UI nunca foi.
   O membro da **segurança**, cuja função é exatamente ver acidente, não
   tinha o botão. A tabela acima dizia "membro liberado de qualquer
   equipe" descrevendo a intenção, não o app.

2. **"Compartilhar minha posição" também era só de Hakuna**, e isso
   esvaziava o alarme pela raiz: sem ninguém publicando ponto, "quem está
   mais perto" não tem a quem responder. A RLS de INSERT em
   `hakuna_positions` sempre aceitou qualquer um logado.

3. **Com `top_team_members` vazia e 1 só Hakuna liberado, o único que
   recebia alarme era o admin.** Não é bug de código — é a guarda certa
   sobre um banco sem o dado que ela pressupõe, e é o tipo de falha que
   teste nenhum pega: a policy está correta, a fila funciona, o som toca,
   e não há ninguém do outro lado. `pode_alarmar_no_top()` passa a aceitar
   **todo aprovado de Top não-draft** — a mesma régua do chat geral — com
   a escada antiga somada por baixo.

**Quem está chamando viaja DENTRO do alarme**, em `top_alerts.sender_name`.
`profiles` é fechada para quem recebe (`id = auth.uid() or is_admin()`),
então o destinatário não tem como resolver o uuid; o Realtime não passa por
RPC; e offline não há rede para buscar. Desnormalizado de propósito — para
registro de emergência, guardar o nome *do momento do disparo* é a
vantagem, não o defeito. O nome vem do cache local (`ColunasEstado.meuNome`,
gravado por `fetchMyProfile`), e **sem nome o alarme sai mesmo assim**: a
faixa diz "Alguém do Top", que é verdade. Nunca mostrar uuid — ele ocupa a
linha do nome e não ajuda ninguém a achar a pessoa.

**`LugarDoAlarme` não depende de `pode_ver_mapa()`, e isso é deliberado.**
O ponto vem de `top_alerts`, não de `hakuna_positions`: é uma coordenada
única, do instante da emergência, publicada por quem pediu socorro. Mostra
**um marcador só** e nunca a posição dos outros — a distinção entre alarme
(aberto) e trilha contínua (restrita) continua de pé. A coordenada aparece
em texto e dá para copiar, porque sem tiles de mapa no mato é ela que se
dita no rádio.

SQL em `supabase/alarme_para_todo_o_top.sql`. Testes em
`test/services/alarme_quem_chama_e_onde_test.dart`, incluindo alarme antigo
sem a coluna, meia coordenada e `0,0` (que **é** posição válida).

**A trilha contínua NÃO foi aberta, e a escolha foi minha.** Perguntei ao
dono se as posições de todos deviam abrir durante a emergência; ele deixou
em aberto, então vale a leitura literal do pedido — "ver **o lugar** via
GPS e quem está chamando" é o ponto do acidente, não a localização de 200
pessoas. `pode_ver_mapa()` fica como estava, e a decisão anterior dele
("200 pessoas vendo a localização de todas as outras não é necessário")
continua valendo.

**O custo disso é real e precisa ser dito:** `QuemEstaMaisPerto` lê
`hakuna_positions` e devolve **lista vazia** para quem não passa em
`pode_ver_mapa()`. Ou seja, o botão "Quem está mais perto" aparece para
todos e só responde para admin, Hakuna liberado, coordenação, `seguranca` e
`hakunas`. Quem quiser mudar isso tem duas saídas: abrir de vez, ou abrir
só enquanto houver alarme da última hora (policy dependente de
`top_alerts`, que precisa ser medida antes — `hakuna_positions` cresce a
cada 15 m caminhados).

**`top_permissoes` sobrepõe a regra do mapa, pessoa por pessoa.** Três
estados: sem linha vale a regra automática; `ver_mapa = true` libera quem a
regra não liberaria; `ver_mapa = false` **bloqueia quem a regra liberaria**.
O terceiro é o que faz a tabela ser "editar" e não só "conceder" — sem ele,
tirar o mapa de um coordenador exigiria rebaixá-lo de cargo. Só admin
escreve nela.

## Stack

- **Flutter** (Android + iOS + web a partir do mesmo código)
- **Supabase** — auth, Postgres, Realtime. Projeto `jitfbambhmfnqiatwoud`, região sa-east-1
- **Kotlin nativo** (Android) — HCE / emulação de cartão
- `provider` para estado, `geolocator` para GPS, `nfc_manager` para NFC

## Rodar

Credenciais **nunca** são commitadas — entram por `--dart-define`:

```bash
# web (não precisa de Android SDK nem Mac)
flutter run -d chrome --web-port=5000 --dart-define-from-file=env.local.json

# Android físico
flutter run --dart-define-from-file=env.local.json
```

`env.local.json` está no `.gitignore` e contém `SUPABASE_URL` e
`SUPABASE_ANON_KEY`. Não commitar, não imprimir em log.

## Antes de dar qualquer tarefa por concluída

```bash
flutter analyze   # tem que dar "No issues found!"
flutter test      # tem que dar "All tests passed!"
```

## Limitações de plataforma (não são bugs, não tente "corrigir")

1. **HCE é Android-only.** A Apple não libera HCE genérico para apps de
   terceiros. No iOS o app só lê e grava tags.
2. **NFC não funciona em emulador nem no navegador.** Testar NFC exige
   aparelho Android físico com NFC.
3. **Build iOS exige Mac + Xcode.** Não existe Xcode para Windows. O
   workflow `ios-build.yml` builda no runner macOS do GitHub.
4. **HCE não emula UID de MIFARE Classic** — só cartões que respondem por
   APDU (ISO-DEP / ISO 14443-4).
5. **No web**, `nfc_service` e `nfc_hce_service` lançam
   `MissingPluginException`. Esperado.

## Convenções que importam neste projeto

### Acesso a dado é sempre escopado por Top
`Top` = evento. `Hakuna` = médico liberado para um Top específico.
`Senderista` = participante inscrito. Nenhuma consulta deve devolver dado
de um Top ao qual o usuário não pertence. As 18 tabelas têm RLS ativo —
**a RLS é a fronteira de segurança, não a UI**. Ao mexer em policy,
assuma que está mexendo em controle de acesso a prontuário.

### Serviços de cálculo não confiam na ordem da entrada
`TriageService.colorFor` ordena por `priority` internamente e
`StatsService.compute` ordena por `recordedAt`. Isso é deliberado: antes
dependiam de quem chamava ter feito `.order(...)` na query, e uma
consulta nova sem isso mudava o resultado clínico em silêncio. Mantenha
assim — não "otimize" removendo a ordenação.

### Leitura vem do SQLite, não da rede
`lib/offline/` tem o banco local, no padrão do **opentracksapp/opentracks**:
`tabelas.dart` descreve só o esquema, `cache_local.dart` só o acesso,
`dados_do_top.dart` é a fachada que as telas usam. Tela nenhuma deve
chamar `SupabaseService.fetchParticipants` direto — a rede alimenta o
disco e o disco alimenta a tela. Em cold start no mato é a única ordem que
funciona.

Nomes de coluna no SQLite são **idênticos** aos do Postgres, para o mesmo
`fromMap` servir às duas origens. Ao adicionar campo, adicione nos dois.

Ainda vêm **só da rede**, e isso é limite conhecido: a lista de perfis de
`TopSenderistasScreen` e o histórico do servidor em `ProntuarioScreen` (o
que está na fila local aparece sempre, com ou sem rede) e o mapa em tempo
real — posição dos outros não existe offline por natureza. As duas telas
dizem na cara que precisam de internet, em vez de mostrar tela de erro.

`busca_normalizada` e `familia_normalizada` são colunas derivadas,
gravadas por `TextoBusca` no momento do cache. Não compare contra
`full_name` ou `familia` crus: `"joao"` não acha `"JOÃO"`.

### A fila nunca pode travar
`SyncService` para no primeiro erro **transitório** — certo para queda de
rede. Mas recusa definitiva do servidor (RLS, dado inválido, esquema
incompatível) vai para **quarentena** e a sincronização **segue**.

Sem isso, uma entrada recusada bloqueia tudo que está atrás dela para
sempre: a próxima rodada relê a fila na mesma ordem e trava na mesma
entrada. O cenário que motivou isso: enquanto o Top 1782 estava em
`draft`, a RLS de `team_messages` recusava mensagem no chat geral, e uma
mensagem prendia atendimento, GPS, foto e auditoria atrás dela. O Top foi
ativado (conferido em 10/10/2026, `status = active`), mas o mecanismo
continua necessário — qualquer Top novo nasce em `draft`.

Quem classifica é `SupabaseService._envioDaFila`, porque é lá que os tipos
do Postgrest existem. **Na dúvida, classifica como transitória**: descartar
dado clínico é pior que atrasar. `SyncService.maxTentativas` é a rede de
segurança para o erro mal classificado.

Quarentena **não apaga** e é visível em `FilaOfflineScreen` (ícone de nuvem
na tela do Top, com badge). Entrada que sai da fila sem ninguém saber é
perda silenciosa — pior que fila travada, porque na travada alguém percebe.
Resolvida a causa, "Devolver à fila" reenvia.

### Nada escreve direto no Supabase — tudo passa pela fila
Atendimento, foto, posição, **chat**, **auditoria**, **alarme** e **sinais
vitais** entram no `outbox` e sobem depois. Tela nenhuma chama `insert` no
Supabase.

Alarme e sinais vitais entraram na lista em 10/10/2026 (ver
`supabase/revisao_completa_correcoes.sql`). Eram as duas últimas escritas
diretas, e as duas perdiam dado sem rede — o alarme com um aviso na tela, a
aferição sem aviso nenhum. **O alarme era a função mais crítica do app e a
única sem caminho offline.** Se aparecer um `insert` direto numa tela, é
regressão.

**Ficha de participante entrou na fila em 11/10/2026.** O formulário
gravava direto e é aberto de DUAS telas de campo — "Novo" na lista de
participantes e "Editar" dentro da ficha. Sem sinal, salvar falhava e a
ficha inteira (nome, comorbidade, alergia) era perdida. Hoje o caminho é
`ParticipanteService.criar` / `.atualizar`, que grava no cache local **e**
enfileira; `criarParticipante`/`atualizarParticipante` foram removidos de
`SupabaseService` para ninguém reintroduzir o atalho.

O `id` do participante é gerado NO APARELHO (`top_participants.id` aceita
uuid de fora). Resolve duas coisas: cadastro offline já tem identidade —
dá para abrir a ficha, atender e emitir pulseira antes de ter rede — e o
próprio id é a chave de idempotência do envio.

Cadastro e edição NÃO usam o mesmo verbo no envio, e isso é o que faz a
edição funcionar. Cadastro é `upsert(onConflict: 'id')`; edição é
`update().eq('id', ...)` sem `registered_by` (a autoria é de quem cadastrou
primeiro). Upsert na edição **não funciona**: o `INSERT ... ON CONFLICT`
tenta o INSERT primeiro, bate no `NOT NULL` de `registered_by` com 23502,
que `_motivoPermanente` classifica como PERMANENTE — e a edição vai para
quarentena e nunca sobe. Verificado no banco; por pouco não saiu assim.

Escrita de admin que **sobra** fora da fila: `AdminService` (papéis, Tops,
equipes) e a **exclusão**. Exclusão é a única exceção deliberada — ver
abaixo.

Toda entidade que passa pela fila precisa de **`client_id` no payload** e
de `upsert(onConflict: 'client_id', ignoreDuplicates: true)` no envio. O
motivo: "falhou" inclui o caso em que o insert chegou e a resposta se
perdeu, e com `insert` o reenvio duplica a linha. Ver
`supabase/fila_offline_chat_e_auditoria.sql`.

**O `client_id` é por LINHA, não por operação.** As fotos de um atendimento
iam todas com o `client_id` do atendimento, e da segunda em diante a linha
era descartada em silêncio pelo `ignoreDuplicates` — arquivo no Storage,
nada no banco. Cada foto tem o seu (ver `AtendimentoService.clientIdDaFoto`).

**UPDATE pela fila não usa o mesmo caminho do INSERT.** `enviarAtendimento`
faz `upsert(ignoreDuplicates: true)`, que é certo para registro novo e
errado para encerramento: a linha já existe e o `ignoreDuplicates` não faz
nada. O uploader decide por `entrada.operation` — ver
`AtendimentoService.registrarUploaders` e `atualizarAtendimento`.

Hora dos eventos vem **do aparelho** (`created_at`, `lida_em`,
`occurred_at`), nunca de `now()` no Postgres: offline a coisa acontece
horas antes do upload.

### Bloco de anotações: um por membro, EDITÁVEL

O equivalente não-médico do prontuário. Cada membro tem o bloco dele, e
edita — não há sobrescrita entre pessoas porque cada login tem o seu.

A chave é `bloco_id`, **texto**, calculada no aparelho por
`Anotacao.chaveDe`: `<top>|<team>|<autor>|<participante ou ->`. Não é
índice composto porque `participante_id` é nulo no bloco do turno, e em
Postgres **NULL não conflita com NULL** num índice único — dois blocos de
turno da mesma pessoa não colidiriam e virariam duplicata. Resolver com
índice parcial quebraria o upsert (o Postgres não infere parcial na forma
simples do `ON CONFLICT`: foi o bug da v1.0.29). **Não mudar o formato da
chave** — o valor está gravado, e mudá-lo faria cada aparelho criar bloco
novo em vez de editar o seu.

**Usa `Outbox.enqueueSubstituindo`, não `enqueue`.** `enqueue` tem
`ConflictAlgorithm.ignore`: reenfileirar o mesmo `client_id` descarta o
segundo pedido, o que é certo para append-only (atendimento) e
catastrófico aqui — a edição seria jogada fora sem erro na tela. E a
substituição mexe na linha em **qualquer** estado, inclusive já
sincronizada: `client_id` tem índice único, então a linha antiga continua
ali depois do envio e um `enqueue` novo também seria ignorado. Era perda
silenciosa duas camadas de profundidade; os dois níveis têm teste em
`test/offline/enqueue_substituindo_test.dart`.

No envio, `upsert(onConflict: 'bloco_id')` **sem** `ignoreDuplicates` — o
bloco é editável, a segunda chegada tem de atualizar.

Risco que resta, e é honesto registrar: a **mesma pessoa** editando em dois
aparelhos offline. Vale o último a sincronizar. Não há como resolver sem
mesclar texto automaticamente, o que erraria mais do que acerta.

**A tela avisa, fixo em cima do campo, que ali não se escreve sintoma,
pressão nem conduta.** Isso vai em `atendimentos`; escrito na anotação,
fica fora da triagem e invisível para quem vai atender. É o erro mais
provável daquela tela e o mais caro.

### Apagar é a única coisa que NÃO funciona offline, e é decisão

Tudo o mais grava no aparelho e sobe depois. Apagar usuário ou senderista
exige rede e **falha dizendo isso** (`ExclusaoService.mensagemDeErro`), por
três motivos:

1. É irreversível e chegaria atrasado. Uma exclusão enfileirada às 9h e
   executada às 16h pode apagar alguém que foi atendido às 11h.
2. A conferência de prontuário é feita no servidor — depende de contar
   atendimento, aferição e auditoria, que o aparelho não tem inteiros.
3. Não é tarefa de campo: apaga-se cadastro sentado, com internet.

**Só o admin master apaga.** `profiles_delete_master` e
`top_participants_delete_master` (esta última não existia: ninguém
conseguia apagar senderista, nem o admin).

**A regra é: apaga quem não deixou rastro clínico; quem deixou, desativa.**
`dependencias_do_perfil` e `dependencias_do_senderista` contam o que seria
perdido, e a tela lista nome por nome quem sai e quem fica, com o motivo.

Dois achados que vieram antes de escrever a tela, em
`supabase/exclusao_protegida.sql`:

- `atendimentos.opened_by` era `ON DELETE CASCADE`. Apagar um Hakuna
  **apagaria todos os atendimentos que ele registrou**. Hoje é `RESTRICT`.
- Apagar `profiles` deixa o `auth.users` órfão (a pessoa loga e cai num app
  sem perfil). A direção certa é apagar o `auth.users` e deixar o perfil
  cair em cascata — e isso exige `service_role`, daí a ação
  `apagar_usuarios` na Edge Function.

### NFC: `flutter_nfc_kit`, e o UID vem sempre

Trocado do `nfc_manager` em 11/10/2026, depois de abrir o APK do app de
NFC que já roda em campo nos Legendários (`com.trixx.hakunanfc`) e ver que
ele usa `flutter_nfc_kit` com `NfcAdapter.enableReaderMode`.

O motivo não é preferência de pacote. `nfc_manager` só entregava a tag
pela API de NDEF: `Ndef.from(tag)` devolvia null e `readTagText` devolvia
`null` seco. Cartão em branco, cartão de outro sistema e MIFARE Classic
que o chipset não formata eram **indistinguíveis de "nenhuma tag foi
encostada"**. Em campo é a diferença entre trocar a pulseira e ficar
batendo o celular nela.

`FlutterNfcKit.poll()` devolve `id` (o UID), `type`, `standard`,
`ndefAvailable` e `ndefWritable` **antes** de olhar conteúdo. `NfcService.lerTag`
embala isso em `LeituraNfc`, e a tela de leitura mostra UID e tipo quando
não identifica ninguém.

**UID identifica, não autentica.** Ele é lido por qualquer celular sem
senha e se copia com hardware de dezenas de reais. O token NDEF — 128 bits
aleatórios, revogável, em `participant_tags.token` — continua sendo a
identificação válida. `participant_tags.tag_uid` existe no banco e está
vazio: usar UID como identificação exige decisão de produto, porque
rebaixa a segurança da pulseira.

A leitura aceita registro de **texto** (o que o app grava) e de **URI** (o
que qualquer outro programa de NFC gravaria para a mesma URL). A gravação
usa texto de propósito: com URI, o celular de um estranho que encostasse
na pulseira abriria o navegador.

HCE **não** passa por aqui — segue em `nfc_hce_service.dart`, por canal
nativo, Android-only. `minSdk` do plugin é 24, igual ao do Flutter: não
houve bump.

### Importador de planilha: cabeçalho é a parte perigosa

`ImportadorDePessoas._campoDe` decide qual coluna é qual campo, e é a
função mais arriscada do importador — ela erra em silêncio.

Havia casamento por prefixo nos **dois sentidos**
(`n.startsWith(s) || s.startsWith(n)`). `normalizar('Nº')` devolve `'n'`,
o primeiro grupo de sinônimos é o de nome, e `'nome'.startsWith('n')` é
verdadeiro. Com `Nº | Nome | Família` o resultado era `nome = "12345"`,
`numero = null`, coluna `Nome` descartada — e **`problemas` vazio**, então
a tela de revisão mostrava tudo como bom e já marcado. Achado por revisão
em 11/10/2026, antes do primeiro uso.

Hoje são duas passadas: **igualdade** (é por aqui que passam os curtos —
`n`, `no`, `uf`, `cod`, `tel`) e depois **sinônimo como palavra inteira**,
o mais longo ganhando. É o que faz "Nome da família" cair em família e não
em nome. **Não reintroduzir prefixo**: "Código da camiseta" começa com
"codigo" e cairia em número.

Embaixo disso há uma rede que **não depende** do mapeamento ter acertado:
nome composto só de dígitos é recusado. Se um cabeçalho novo enganar o
`_campoDe` amanhã, a linha é recusada em vez de entrar calada.

`problemas` **bloqueia**; `avisos` **não**. Entra em `problemas` só o que
compromete identidade (sem nome, nome que é número, número inválido ou
repetido). Equipe e cargo vão para `avisos`: a importação nem consegue
aplicá-los a quem não tem conta, e retirar a pessoa por causa disso é
trocar o essencial pelo acessório.

**Equipe só é aplicável a quem já tem conta.** `top_team_members.profile_id`
referencia `profiles`, e planilha não cria conta. A tela casa o número da
planilha contra as contas existentes; quem não tem aparece listado por
nome como pendente. Antes isso era prometido no diálogo e o código que
faria era inalcançável — `criar` devolve ficha com `linked_profile_id`
nulo, sempre.

**Reimportar é o caminho natural e criava duplicata.** `criar` gera id novo
a cada chamada e `(top_id, participant_code)` não é único; com duas fichas
do mesmo número, `participante_elegivel` resolve com `limit 1` e o
autocadastro podia ligar a conta à ficha vazia enquanto comorbidade e
alergia ficavam na outra. A tela confere contra quem já está no Top (por
número e por nome), desmarca e escreve o motivo — desmarcar sem explicar
parece defeito da tela, e o admin marca de novo.

### Imagem de Top: caminho fixo exige selo de versão

`tops/<id>/imagem<ordem>`, **sem extensão**. Com extensão, trocar um PNG
por um JPG gravava outro arquivo e deixava o anterior órfão no bucket —
publicamente acessível e impossível de apagar depois, porque
`apagarImagemDoTop` só conhece o `storage_path` da linha, que já aponta
para o arquivo novo.

Caminho fixo significa **URL pública fixa**, e `ImageCache` do Flutter e
CDN são indexados por URL. Sem `TopImagem.selo` (`?v=<enviado_em>`) o
admin trocava a imagem com sucesso e continuava vendo a antiga — parece
falha de upload. Os dois achados são de 11/10/2026, por revisão, antes de
existir qualquer linha.

A tabela vive em `supabase/top_imagens.sql`. Ela foi criada direto em
produção e ficou **só lá** por um dia: nada no repositório a criava, e
`ImagensDoTop._carregar` engole o erro de leitura de propósito, então um
schema reconstruído daria uma tela que nunca mostra imagem e nunca diz por
quê.

### NFC: erro do plugin não vai cru para a tela

`ErroDeNfc` traduz os códigos do canal nativo (408 timeout, 406/503 tag
afastada, 405 não suportado, 404 NFC desligado, 400 NDEF corrompido, 500
comunicação). O 408 é o **mais comum de todos** — é simplesmente ninguém
ter encostado a pulseira em 30 segundos, e aparecia como
`PlatformException(408, polling tag timeout, null, null)`.

O `nfc_manager` lançava `TimeoutException` com texto em português; a troca
de plugin tirou isso sem reposição, e passou. Ao mexer no serviço de NFC,
confira se o caminho de erro continua traduzido.

### Sete ações é o teto da AppBar

Medido em 11/10/2026, não estimado: a oitava `IconButton` estoura a Row da
AppBar num celular de 360 dp, e o Flutter **corta em silêncio** o que passa
da borda direita. Em release não há aviso nenhum.

A tela do Top tinha chegado a **11 ações**. Para o admin, Pulseiras NFC,
Equipes do Top e Quem vê o mapa existiam, abriam por código, passavam em
teste — e eram inalcançáveis no aparelho. Achado antes da primeira
instalação.

A regra de corte é "quantas vezes isto é tocado com o paciente na frente".
Ficam como ícone: ler a pulseira, mapa, participantes, fila, chats. O
resto vai para o `PopupMenuButton` (`_MenuDoTop`), com nome escrito — mais
achável que um ícone a adivinhar. Emitir pulseira e montar equipe se faz
sentado, antes do evento; **ler** a pulseira é tarefa de campo e por isso
é o primeiro ícone depois da saída.

`test/appbar_cabe_no_celular_test.dart` mede o teto de verdade (360 e
320 dp) e varre `lib/screens`. Dois erros já cometidos nele, os dois
dignos de nota:

1. Ao medir, **derrube a árvore entre as iterações**: o `RenderFlex`
   reporta o estouro uma vez por instância, e reusar o render object
   engole o erro — a primeira versão mediu 14.
2. A varredura por **indentação não media nada**. `indexWhere` pegava o
   primeiro `actions: [` do arquivo, que em `top_detail_screen.dart` é um
   AlertDialog na linha 171; a AppBar, 160 linhas abaixo, nunca era
   contada. O teste passava sempre, e uma oitava ação passaria batida.
   Hoje é casamento de parênteses, pulando string e comentário, e só
   procura `actions:` **dentro de** `AppBar(`/`SliverAppBar(`.

O teste tem auto-teste do próprio contador, e isso não é zelo excessivo:
foi o auto-teste que pegou a vírgula do spread sendo contada duas vezes.
**Guarda que não é verificado é pior que guarda nenhum** — ele dá a
impressão de cobertura.

### Toda tela tem saída

Seta de voltar (automática) **e** `BotaoInicio` no `actions` do AppBar, que
volta à tela inicial de uma vez. São saídas diferentes: a seta devolve um
passo, e Top → participantes → ficha → prontuário → atendimento são cinco
toques para sair.

`test/toda_tela_tem_saida_test.dart` lê o código-fonte das telas e falha se
alguma ficar sem o botão, ou se alguém puser `leading:` próprio no AppBar —
que foi como a logo já prendeu a tela de detalhe do Top uma vez. Para
isentar uma tela, há uma lista no teste onde se escreve o motivo.

### Auditoria vai para duas tabelas, e não é redundância
`tag_leituras` recebe **toda** leitura de pulseira, inclusive as que falham.
`audit_log` recebe só o subconjunto de segurança (tag revogada apresentada,
tag desconhecida, emissão, revogação, ficha alterada). Mandar tudo para as
duas dobraria a escrita sem responder nada novo. Ver `AuditoriaService`.

### QR Code carrega o MESMO token da pulseira
`QrTokenService.conteudoPara` devolve exatamente `TagNdef.urlPara`. Não
inventar formato próprio para o QR: revogar a pulseira revoga o QR no mesmo
ato porque é o mesmo token, e a resolução reaproveita `TagService.resolver`
inteiro (cache em disco, fallback, auditoria). Há teste travando isso.

### Triagem tem dois níveis, e eles não se misturam
`TriageService` dá a cor de **cadastro** — `f(idade, comorbidades)`, das
regras do banco. `TriageDinamica` **escala** essa cor para vermelho quando
a última aferição tem SpO₂ < 90, sistólica > 180 ou diastólica > 110.

As DUAS portas de medição alimentam `cache_ultima_afericao`: o formulário
de atendimento (`AtendimentoService.registrar`) e a tela de sinais vitais
(`SinaisVitaisService.registrar`). Até 10/10/2026 só a primeira alimentava,
e o resultado era clinicamente incoerente — SpO2 85 no atendimento pintava
de vermelho, o mesmo 85 na outra tela não pintava nada. Ao criar uma
terceira forma de aferir, alimente o cache também.

Só escala, nunca rebaixa, e **não sobrescreve o cadastro** — sobrepõe na
leitura. `AlertaVital` (em `atendimento.dart`) é um terceiro conjunto de
limiares, mais largos, que só pinta o campo de amarelo. Não unifique os
três: se "alterado" mudasse a cor, metade da trilha ficaria vermelha e a
cor pararia de significar prioridade.

### Models usam `fromMap`, não geração de código
Os 7 models em `lib/models/` seguem o mesmo padrão manual
`factory X.fromMap(Map<String, dynamic> map)`. Não há `json_serializable`
nem `freezed`. Ao criar um model novo, siga o mesmo padrão.

### Plataforma se detecta com `kIsWeb` / `defaultTargetPlatform`
Nunca use `dart:io` (`Platform.isAndroid`) em `lib/` — quebra o build web.
Use `package:flutter/foundation.dart`.

### Erros de auth passam por `friendlyAuthError`
Exceção crua do Supabase não vai para a tela. Veja
`supabase_service.dart`.

## Estrutura

```
lib/
  models/      Profile, Top, HakunaPosition, VitalSigns, TriageRule,
               ChatMessage, TopAlert, TopStats
  services/    supabase_service (auth + queries + realtime)
               location_service (GPS -> Supabase, distanceFilter 15m)
               nfc_service / nfc_hce_service
               triage_service (cor por idade + comorbidades)
               stats_service (Haversine, MET, calorias)
               admin_service
  screens/     login, signup, auth_gate, tops, top_detail, top_chat,
               senderistas, vital_signs, admin/
  widgets/     app_logo, password_field, triage_badge
android/app/src/main/kotlin/   HceService.kt, HceBridge.kt, MainActivity.kt
supabase/schema.sql            tabelas + RLS + realtime
```

## Release

Fluxo obrigatório, nesta ordem:

1. Bumpar `version:` no `pubspec.yaml`
2. Commit + push para `main`
3. Criar tag `vX.Y.Z` e dar push nela
4. O workflow `android-build.yml` roda `analyze` + `test`, gera
   **`legendarios<versao>.apk`** (nome derivado do pubspec automaticamente)
   e anexa à Release
5. Avisar o usuário para baixar o APK e subir no Google Drive

**Assinatura:** `android/app/build.gradle.kts` procura chave de produção em
`android/key.properties` (local) ou nas variáveis `LEGENDARIOS_KEYSTORE_*`
(CI). Exige os **quatro** valores e o arquivo no lugar — config pela metade
não assina, cai no fallback. Sem nada disso, o release sai com a chave de
**debug**: instala por "fontes desconhecidas" (fluxo do Drive), não serve
para Play Store.

O workflow imprime no log, lendo do próprio APK, com qual chave ele saiu.
Keystore e `key.properties` estão no `.gitignore` — perder o `.jks` é
irreversível.

### Assinatura: resolvida a partir da v1.0.23

Conferido em 10/10/2026 com `apksigner verify --print-certs` nos APKs que
estão no Drive:

```
legendarios1.0.18.apk  CN=Android Debug          SHA-1 AB24D950...AC05AC
legendarios1.0.19.apk  CN=Android Debug          SHA-1 E882B41E...4CFF11
legendarios1.0.23.apk  CN=Legendarios Connect    SHA-1 0B992313...1D4B88
legendarios1.0.28.apk  CN=Legendarios Connect    SHA-1 0B992313...1D4B88
legendarios1.0.29.apk  CN=Legendarios Connect    SHA-1 0B992313...1D4B88
```

As duas primeiras saíram com chave de **debug**, e **diferentes entre si**:
o runner do GitHub Actions não tem `~/.android/debug.keystore`, então o
Gradle gerava uma nova a cada execução. Da v1.0.23 em diante o CI assina
com o keystore de produção, vindo dos secrets `LEGENDARIOS_KEYSTORE_*`.

Use `apksigner`, não `keytool -printcert -jarfile`: o Flutter assina só com
esquema v2/v3 e o `keytool` lê apenas assinatura v1 de JAR — ele não acha
nada e o silêncio parece "sem assinatura".

O que mudou com o keystore de produção:

1. **Atualizar por cima funciona** entre versões ≥ 1.0.23, e o SQLite local
   sobrevive. Vindo da 1.0.18/1.0.19 ainda falha com
   `INSTALL_FAILED_UPDATE_INCOMPATIBLE` e exige desinstalar — e desinstalar
   **apaga a fila**, ou seja, apaga atendimento que ainda não subiu.
   Sincronize antes.
2. **Login com Google passou a ser possível** — mas só passa a funcionar
   depois que o SHA-1 `0B:99:23:13:83:2C:54:BE:2A:0C:B3:ED:0F:DE:56:11:44:1D:4B:88`
   estiver registrado no Google Cloud como client OAuth do tipo Android
   (projeto `hakuna3colinas-app`, pacote `com.legendarios.hakuna_connect`).
   Enquanto não estiver, o plugin falha com DEVELOPER_ERROR antes de
   qualquer chamada de rede — não é problema de `clientId`, ver
   `SupabaseService.googleIndisponivelNoApk`.

**Perder o `.jks` é irreversível** e, agora que há base instalada assinada
com ele, significa não poder mais atualizar nenhum aparelho sem desinstalar.
O arquivo e sua senha estão fora do repositório (`.gitignore`); o backup
fora desta máquina é obrigação do dono do projeto.

### Versão instalada e aviso de atualização

`lib/versao.dart` carrega `nome` e `build` como constantes — compiladas
dentro do APK, que é o único jeito de o aparelho saber a própria versão sem
rede. Não há `package_info_plus` de propósito: ele não responderia nada
melhor. O esquecimento de atualizar essas constantes ao bumpar o
`pubspec.yaml` é travado por `test/versao_bate_com_pubspec_test.dart`, que
lê o pubspec e falha na divergência — então roda no CI antes de gerar o APK.

A tabela `app_versions` guarda a última versão publicada (`build_number` +
`apk_url`). `AtualizacaoService` lê a de maior `build_number` e
`GavetaDoApp` mostra o botão **ATUALIZAR** quando ela é mais alta que a
instalada. A comparação é pelo `build_number`, **nunca** pelo texto da
versão: como string, `"1.0.9" > "1.0.10"`, e o app diria que está em dia
estando atrasado.

Consulta sem rede devolve `null`, e `null` é tratado como "não sei" — a
gaveta diz que não deu para verificar, em vez de afirmar que está
atualizado. Publicar versão nova é inserir uma linha em `app_versions` com
o link do APK; só admin escreve (RLS).

## Regras de triagem

Vivem na tabela `triage_rules` (editáveis pela tela de admin do app), não
no código. As 8 ativas (ids 7-14, desde 09/10/2026) dão esta matriz:

```
idade |  0 comorb   1 comorb   2+ comorb
------+---------------------------------
 0-25 |     azul      verde     vermelho
26-40 |    verde    amarelo     vermelho
  41+ |  amarelo   vermelho     vermelho
```

Faixas explícitas, sem sobreposição e sem buraco — `triage_service_test`
verifica isso exaustivamente (0-110 anos × 0-8 comorbidades), além de
garantir que a gravidade nunca diminui quando idade ou comorbidades
aumentam.

A configuração anterior (ids 1-6, hoje `active = false`) tinha uma regra
`41+, 0..999 comorbidades -> vermelho` com `priority: 1` que atropelava
todas as outras. Acima de 40 as comorbidades deixavam de importar e a
triagem não discriminava nada justamente na faixa com mais participantes.
**Não reintroduzir regras "pega-tudo" de prioridade alta.**

Ao mudar as regras no banco, atualizar o fixture `_producao` em
`test/services/triage_service_test.dart` junto — senão os testes passam
validando uma configuração que não existe mais.

## Pendências conhecidas

- **`flutter_nfc_kit` aplica o Kotlin Gradle Plugin.** O build avisa:
  "Your app uses the following plugins that apply Kotlin Gradle Plugin
  (KGP): flutter_nfc_kit". Hoje é só warning e `android.builtInKotlin=false`
  em `android/gradle.properties` segura. Quando o Flutter tornar o Built-in
  Kotlin obrigatório, ou o plugin migra ou o build para. Vale olhar o
  changelog do pacote antes de atualizar o Flutter.
- **Memória do Gradle.** `org.gradle.jvmargs` ficou em `-Xmx4G` /
  metaspace 1G. Com os 8G/4G anteriores o Windows **matava** o
  `assembleRelease` no meio, sem erro de compilação — só o processo morto.
  Se um dia faltar memória de verdade, o sintoma é `OutOfMemoryError` no
  log, que é diferente de o build desaparecer.
- **Schema à frente do app.** O banco ainda tem tabelas que o app não usa:
  `direct_messages`, `notifications`, `attendance_members`, `nfc_tags`.
- **AID de exemplo.** `android/app/src/main/res/xml/apduservice.xml` usa
  `F0010203040506`. Trocar pelo AID real quando definido.
- **Despacho de atendimento: 7 dos 9 estados seguem sem uso, por decisão.**
  O app escreve `aberto` e `encerrado` (ver `AtendimentoService.encerrar`).
  `reconhecido`, `atribuido`, `a_caminho`, `no_local`, `em_andamento`,
  `escalado` e `cancelado` formam um fluxo de despacho que precisa de
  painel de coordenação e de regra de quem atribui o quê — decisão de
  produto. Meio-implementado seria pior que ausente: estado que ninguém
  atualiza mente sobre a situação do paciente.
- **Notificação com o app FECHADO não existe.** O alarme chega em
  qualquer tela, com som e vibração (`AlarmeService` + `FaixaDeAlarme`),
  mas só com o app aberto: o Realtime é um WebSocket do processo, e
  processo morto é conexão morta. Quem acorda app fechado no Android é o
  sistema, a pedido do FCM — não há outro caminho. **O levantamento
  completo do que falta está em `docs/push_com_app_fechado.md`**: as
  quatro peças, o SQL da tabela `dispositivos`, o que só o dono do projeto
  pode fazer (criar o Firebase) e o que o push NÃO resolve. Para quem está
  com o app fechado, continua valendo o rádio.
- **Nenhum teste de hardware.** Os 322 testes cobrem lógica. NFC, câmera,
  GPS com tela bloqueada, o som do alarme e o `launchUrl` do botão
  Atualizar só se verificam em aparelho físico.
- **`occurred_at` em `audit_log` não tem backfill.** As linhas antigas (não
  há nenhuma hoje) ficariam com null; ler sempre
  `coalesce(occurred_at, created_at)`.
- **Troca de usuário no mesmo aparelho.** Se o Hakuna A registrar offline e
  o B logar antes do sync, a fila de A é recusada pela RLS (`sender_id` /
  `lida_por` / `actor_id` presos a `auth.uid()`). Desde a v1.0.19 isso vai
  para quarentena em vez de travar a fila, mas **o registro de A não sobe** —
  precisaria ser reatribuído, e nada faz isso.
- **APK com 76 MB.** O modelo do ML Kit vai embutido para o QR funcionar
  sem rede (ver `android/gradle.properties`). Se virar problema, o caminho
  é `--split-per-abi`, não desligar o bundling.
- **144 dos 216 senderistas do Top 1782 estão sem `participant_code`.**
  Conferido em 10/10/2026: 72 têm número do Legendários, 144 não. O
  autocadastro exige número **na lista do Top** (`participante_elegivel`,
  chamado por `validarConvite`), então essas 144 pessoas recebem a recusa
  genérica "número ou senha do Top incorretos" e vão achar que a senha
  está errada. Elas não ficam trancadas — sobra o caminho de "pedir código
  ao administrador" (`solicitar` -> `liberar`), um a um —, mas é exatamente
  o gargalo que a senha compartilhada existia para eliminar. A correção é
  preencher os números na tabela; o campo existe na tela de admin
  (`participante_form_screen`, "Nº Legendários"). **Não inventar número.**
- **Só 1 Hakuna liberado no Top 1782** (o admin). As 8 policies que
  dependem de `top_hakunas` passam a valer para cada médico só depois que
  ele for liberado naquele Top.
- **`diretor_responsavel` do Top 1782 está nulo** de propósito: eu havia
  preenchido um nome inventado e apaguei. Quem define o responsável por um
  evento médico é o dono do evento.
