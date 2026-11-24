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

### As equipes e as funções são FIXAS — ninguém cria outras pelo app

Pergunta do dono em 23/11/2026: *"o admin pode adicionar outros grupos e
funções?"* **Não, e não é esquecimento.** As três dimensões são enums,
fechados nos dois lados:

| | Valores | Onde está escrito |
|---|---|---|
| Equipes | 9 + `geral` | enum `team_key` no Postgres **e** `enum TeamKey` em `lib/models/team.dart` |
| Funções na equipe | `coordenador`, `subcoordenador`, `membro` | enum `team_role` **e** `enum TeamRole` |
| Papéis no app | `admin`, `hakuna`, `senderista` | enum `user_role` **e** `enum UserRole` |

Criar uma equipe nova exige **três coisas juntas**: `alter type team_key
add value`, o rótulo/ícone/cor em `TeamKeyUi` e um APK novo. Sem o terceiro
a equipe existe no banco e o app quebra ao ler um valor que o `enum` do
Dart não conhece. Então não é um botão que falta — é release.

O que o admin faz é **atribuir** o que existe: pôr pessoa em equipe, dar
cargo, liberar, bloquear, remover.

### Quem monta equipe, e quem cria ficha — medido, não deduzido

Medido em 23/11/2026 com contas de verdade (senderista aprovado, Hakuna
liberado, admin comum, coordenador de equipe), conferindo **o dado depois
de cada tentativa**:

| Ação | Senderista | Hakuna liberado | Coordenador da equipe | Admin | Master |
|---|---|---|---|---|---|
| Criar ficha de participante | não | **sim** | não | **sim** | sim |
| Editar ficha / **família** | não | **sim** | não | **sim** | sim |
| Apagar ficha | não | não | não | não | **só ele** |
| Pôr alguém na equipe | não | não | **sim, na dele** | **sim** | sim |
| Dar cargo de coordenador | não | não | não | **sim** | sim |
| Liberar / bloquear / remover membro | não | não | **sim, na dele** | **sim** | sim |
| Emitir pulseira NFC/QR | não | não | não | **sim** | sim |
| Liberar Hakuna no Top | não | não | não | **sim** | sim |
| Definir quem vê o mapa | não | não | não | **sim** | sim |
| Promover alguém a **admin** | não | não | não | **não** | **só ele** |
| Mudar regra de triagem | não | não | não | **não** | **só ele** |
| Gerar senha do Top / abrir cadastro | não | não | não | **não** | **só ele** |

**Família se adiciona por quatro caminhos**, e todos existem hoje: o campo
"Família" na ficha (admin e Hakuna, pela tela de participantes, funciona
offline), o importador de planilha, o autocadastro (a pessoa digita a dela)
e a edição posterior da ficha.

#### A lição do método: `204` não quer dizer que mudou

Três respostas desta tabela estavam **erradas na primeira medição**, e
todas pelo mesmo motivo: `UPDATE` e `DELETE` cuja linha a RLS esconde
voltam **204, sucesso, com zero linhas afetadas**. Pelo código de resposta,
"senderista apaga ficha" e "senderista muda regra de triagem" pareciam
permitidos. Eram 204 vazios.

**Conferir permissão de escrita pelo status é inútil.** Grave um valor
conhecido antes, tente mudar, leia depois. Foi assim que apareceu o defeito
do coordenador, abaixo.

### O coordenador tinha poder sobre a equipe e não via ninguém

Achado em 23/11/2026, na medição acima. `top_team_members_select` era
`profile_id = auth.uid() or is_admin()` — **o coordenador via só a própria
linha.** E `update ... where` / `delete ... where` precisam LER as linhas
para achar quais alterar, e essa leitura passa pela policy de SELECT.

Resultado: as policies que davam poder a ele eram letra morta.

```
coordenador inclui membro na equipe dele .... funcionava (201)
coordenador retira a liberação .............. 204, e NÃO retirava
coordenador bloqueia ........................ 204, e NÃO bloqueava
coordenador remove .......................... 204, e NÃO removia
```

E a equipe aparecia **vazia** para quem a coordena — inclusive quem ele
mesmo acabou de incluir.

Corrigido em `supabase/12_coordenador_ve_a_equipe_dele.sql`: a policy de
SELECT ganhou `or is_team_admin(top_id, team)`. É `is_team_admin` e não
`is_team_coordenador` porque a policy de INSERT já usa a primeira — o
subcoordenador pode incluir, então tem de poder ver.

**Não há recursão**, e isso precisa ser dito: `is_team_admin` lê
`top_team_members` e está sendo chamada de dentro de uma policy dessa
tabela. Não entra em laço porque é `security definer` — roda como o dono e
não passa pela RLS. O mesmo arranjo que `top_team_members_update` já usava.
Trocar a função por um `exists (select ... from top_team_members ...)`
escrito dentro da policy **faria** o laço.

Depois do conserto, medido: vê só a equipe dele (a linha do mesmo membro em
outra equipe não aparece), libera, bloqueia e remove; continua **sem**
promover a coordenador (403) e **sem** tocar em outra equipe.

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

**`top_team_members` e `team_messages` finalmente estão no repositório**,
desde 24/11/2026: `supabase/17_top_team_members_e_team_messages.sql`. Por
mais de um mês esta linha dizia que faltavam, com o motivo certo para não
inventá-las — `create table` escrito de memória parece fonte da verdade e
diverge calado.

Não foram escritas de memória: saíram do catálogo do banco
(`information_schema.columns`, `pg_constraint`, `pg_get_indexdef`,
`pg_get_expr` sobre `pg_policy`). E a cópia foi **verificada**: fotografia
das assinaturas das 12 policies antes, arquivo rodado duas vezes,
fotografia depois, `diff` vazio. É a diferença entre "escrevi o arquivo" e
"o arquivo é a produção".

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

SQL em `supabase/alarme_para_todo_o_top.sql`, **aplicado em produção em
11/10/2026** (confirmado pelo dono: policies, função e `sender_name` no
lugar). Testes em
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

### O alarme viaja pela malha de rádio, em paralelo com a fila

Entrou na v1.0.44. Antes, `AlarmeService.disparar` só enfileirava e
`MalhaService.espalhar` tinha **um único chamador**, o chat. Em modo
avião, apertar EMERGÊNCIA guardava o alarme no próprio celular e não
avisava ninguém — nem quem estava a dois metros. A função mais crítica
do app era a única que não usava o caminho sem rede que o app já tinha
pronto e funcionando. Achado em teste de campo com dois Android, não por
leitura de código.

**Rádio e fila são paralelos, não alternativos.** A fila alcança quem
está longe quando houver sinal; o rádio alcança agora quem está perto —
que numa emergência é quem pode socorrer. Falha no rádio não desfaz o
alarme.

Quatro coisas que não se pode mexer sem entender:

1. **O pacote continua `v: 1`.** `PacoteLocal.deBytes` descarta versão
   desconhecida, então subir para `v: 2` faria todo aparelho com a
   v1.0.41/42 **jogar o pedido de socorro fora em silêncio**. Com `v: 1`
   ele lê o alarme como mensagem de chat e **mostra** a linha
   `EMERGÊNCIA — Fulano — -19.9,-43.9`. Não toca, mas aparece. Daí
   `corpo` ser legível por gente e não JSON interno.

2. **O Top do alarme é conferido contra o Top da malha.** A malha liga
   por Top (`botao_da_malha.dart`). Sem a conferência, alarme do Top B
   sairia carimbado com o Top A — chegaria a quem não tem o que fazer e
   não chegaria a quem tem. Na divergência **não transmite**, e a tela
   manda ligar o rádio no Top certo.

3. **O envio por rádio tem teto de 3 segundos.** `TransporteNearby.enviar`
   faz um `await` por vizinho, em laço, e a tela espera `disparar`. Com o
   alarme já gravado, esperar o rádio só tira segundos de quem precisa
   agir.

4. **Nenhuma frase promete entrega.** Broadcast por rádio não tem ACK.
   `DisparoDeAlarme` tem cinco estados — desligado, outro Top, demorou,
   zero aparelhos, N aparelhos — e o que o número diz é para quantos
   aparelhos se **falou**, nunca quantos ouviram. "2 pessoas foram
   avisadas" é mentira e há teste travando isso.

**Alarme de rádio entra como não confirmado**, e a faixa diz isso. No
rádio não há autenticação: qualquer aparelho ao alcance pode afirmar o
que quiser em nome de quem quiser, e um alarme forjado move 200 pessoas.
Quando o mesmo alarme chega depois pelo servidor, `TopAlert.chave` funde
os dois pelo `client_id` e vale o do servidor — anunciar a mesma
emergência duas vezes ensina a equipe a ignorar o som.

30 testes em `test/services/alarme_pela_malha_test.dart`. **Nenhum deles
toca rádio** — isso só se prova com dois Android em modo avião.

**`top_permissoes` sobrepõe a regra do mapa, pessoa por pessoa.** Três
estados: sem linha vale a regra automática; `ver_mapa = true` libera quem a
regra não liberaria; `ver_mapa = false` **bloqueia quem a regra liberaria**.
O terceiro é o que faz a tabela ser "editar" e não só "conceder" — sem ele,
tirar o mapa de um coordenador exigiria rebaixá-lo de cargo. Só admin
escreve nela.

## Stack

- **Flutter** (Android + iOS + web a partir do mesmo código)
- **Supabase** — auth, Postgres, Realtime. Projeto **`vohowjyuvhalphstieqo`**,
  região sa-east-1, organização `hakunasconnect`, plano **free**.

  **O projeto anterior (`jitfbambhmfnqiatwoud`) FOI APAGADO** — confirmado em
  23/11/2026 por NXDOMAIN no 8.8.8.8 e por ausência na listagem da
  organização, com um hostname de controle resolvendo normalmente. O banco
  foi reconstruído do zero a partir dos arquivos de `supabase/`, e foi essa
  reconstrução que revelou **13 objetos que só existiam em produção** (ver
  "Objetos que só existiam em produção", abaixo). Referências ao ref antigo
  em outras partes deste arquivo são história, não configuração.
- **Kotlin nativo** (Android) — HCE / emulação de cartão
- `provider` para estado, `geolocator` para GPS, **`flutter_nfc_kit`** para
  NFC (era `nfc_manager`; trocado em 11/10/2026 — ver a seção de NFC)

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
   workflow `ios-build.yml` builda no runner macOS do GitHub e, com os
   secrets da Apple, envia ao **TestFlight** — iPhone não instala por
   arquivo, então não há equivalente do APK no Drive. Passo a passo da
   conta Apple em `docs/ios.md`.

   No iPhone **não existem** o rádio entre aparelhos (Nearby Connections
   é Android) nem o botão ATUALIZAR (quem atualiza é o TestFlight). O
   "Entrar com Google" fica **escondido** até haver `GOOGLE_IOS_CLIENT_ID`
   **e** o esquema de URL no Info.plist: sem os dois, o SDK do Google
   levanta exceção nativa e fecha o app — nenhum `catch` do Dart pega.

   `UIBackgroundModes: location` e `allowBackgroundLocationUpdates` andam
   juntos: um sem o outro, ou a trilha congela com a tela bloqueada, ou o
   app cai no primeiro ponto. E o entitlement de NFC leva só `TAG`:
   `NDEF` ali é recusado pela Apple no envio.
4. **HCE não emula UID de MIFARE Classic** — só cartões que respondem por
   APDU (ISO-DEP / ISO 14443-4).
5. **No web**, `nfc_service` e `nfc_hce_service` lançam
   `MissingPluginException`. Esperado.

## Convenções que importam neste projeto

### Migração tem de rodar DUAS vezes sem erro

`create policy` **não tem** `if not exists` em Postgres. Toda policy nova
precisa do `drop policy if exists` do próprio nome logo acima — não só das
policies antigas que ela substitui.

Isso foi aprendido caro em 11/10/2026. `alarme_para_todo_o_top.sql` dava
drop nas antigas e não nas suas próprias, e a segunda execução morria com
`42710: policy already exists`. O cabeçalho do arquivo afirmava
"idempotente"; era falso, e eu não havia rodado duas vezes para conferir.

**O estrago não foi a mensagem de erro.** O SQL Editor do Supabase roda o
script numa transação: o `alter table ... add column sender_name`, que vem
depois das policies, foi revertido junto. O erro reclamava de algo **já
aplicado** e de quebra impedia a única coisa que ainda faltava — a coluna
que carrega o nome de quem dispara o alarme. Quem lesse "already exists"
concluiria que estava pronto, e a faixa diria "Alguém do Top" para sempre,
sem erro em lugar nenhum.

A regra, então: `drop policy if exists` do próprio nome antes de cada
`create policy`, `if not exists` em todo `create index` e `add column`, e
**rodar o arquivo duas vezes seguidas antes de dar por pronto**.
"Idempotente" não é intenção, é propriedade que se verifica.

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

A lista de Tops da tela inicial também vem do disco desde 20/11/2026
(`ListaDeTops`, `cache_tops`): sem ela, todo o resto do cache era
inalcançável quando a rede faltava, porque é por ali que se chega ao Top.

Ainda vêm **só da rede**, e isso é limite conhecido: a lista de perfis de
`TopSenderistasScreen` e o histórico do servidor em `ProntuarioScreen` (o
que está na fila local aparece sempre, com ou sem rede) e o mapa em tempo
real — posição dos outros não existe offline por natureza. As duas telas
dizem na cara que precisam de internet, em vez de mostrar tela de erro.

`busca_normalizada` e `familia_normalizada` são colunas derivadas,
gravadas por `TextoBusca` no momento do cache. Não compare contra
`full_name` ou `familia` crus: `"joao"` não acha `"JOÃO"`.

### Travar coluna de permissão exige TRIGGER, não `with check`

Aprendido caro em 12/10/2026, e medido, não deduzido.

`profiles_update_own` prendia o `role` com
`with check (role = my_profile_role())` — função `stable security
definer` que lê a própria linha. Faltavam `is_master_admin` e `approved`,
e como `is_admin()` é `role = 'admin' or is_master_admin`, **qualquer
conta logada virava admin master** com um `PATCH` na API REST, usando a
chave anon que está dentro do APK.

Ao corrigir, estender o mesmo `with check` às outras duas colunas
**funcionou para `is_master_admin` e não funcionou para `approved`**:

```sql
begin;
  update profiles set approved = false where id = <uid>;
  set local role authenticated;  set local request.jwt.claims = ...;
  update profiles set approved = true  where id = <uid>;
-- 1 linha gravada, approved = true
```

Função que **lê a mesma tabela que está sendo alterada**, chamada de
dentro do `with check` daquela alteração, não dá garantia confiável sobre
qual versão da linha enxerga. Controle de acesso não se apoia em
comportamento que varia com o plano de execução.

O que vale é **trigger** `before update ... for each row`: recebe `OLD` e
`NEW` explicitamente, sem releitura e sem ambiguidade de snapshot. Ver
`supabase/profiles_sem_escalada_de_privilegio.sql`.

Dois detalhes que não são opcionais:

- **Reverte em silêncio**, não levanta erro. O app manda a linha inteira
  ao salvar o perfil; recusar quebraria a edição de nome e telefone por
  causa de campos que nem mudaram.
- **`auth.uid() is null` passa direto.** É `service_role` — a Edge
  Function `acesso` precisa aprovar no autocadastro. Sem essa saída, a
  correção quebraria o cadastro inteiro e ninguém entraria no Top por
  número + senha. Isso foi testado antes de aplicar.

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

### Entrada no app: pedido com número do Top, e LIBERAR = APROVAR

Decidido pelo dono em 28/10/2026: a pessoa manda **número do Legendários
e número do Top** logo no começo; o pedido chega ao admin em Pedidos de
acesso; o admin libera e a pessoa fica **aprovada para todos os Tops** e
dentro daquele Top. A aprovação é global de propósito: a policy
`tops_select_linked` já abre todo Top não rascunho para conta aprovada.

- `access_requests` tem `top_number` (o que foi DIGITADO, mesmo sem Top
  com esse número — "Top 1922 (não existe no app)" é informação para o
  admin), `top_id` e `profile_id` (`supabase/pedido_com_numero_do_top.sql`).
- `acesso/liberar` **aprova** (`approved = true`). Antes gerava o código e
  deixava a pessoa parada em "aguardando aprovação", esperando uma segunda
  liberação que ninguém sabia que faltava.
- Pedido de quem **já tem conta** (Google ou e-mail, mandado da tela de
  espera, que agora pede número e Top) é aprovado **sem código**: gerar
  código trocaria a senha de uma conta Google. E corrige o número: conta
  Google nasce com o uuid em `legendarios_number` (`handle_new_user` faz
  coalesce com `new.id`) e nunca entraria pelo número.
- `colocarNoTop` reaproveita a ficha com o mesmo número (a da planilha)
  em vez de criar outra.

**A função `acesso` publicada tinha uma linha que o repositório não tinha**
(`autocadastro_liberado: true` ao gerar a senha do Top). Achada ao
publicar a v10 em 28/10/2026 e trazida de volta. Antes de publicar
`acesso`, compare com a versão no ar (`get_edge_function`): deploy a
partir do repositório apaga em silêncio o que só existe lá.

**Senha do Top é ÚNICA por Top.** `validarConvite` acha o Top pelo hash
da senha com `maybeSingle`; dois Tops com a mesma senha fazem a consulta
falhar e ninguém se cadastra em nenhum dos dois. O 1782 usa a senha
escolhida pelo dono; o próximo Top precisa de outra.
escolhida pelo dono; o próximo Top precisa de outra.

**Desde 23/11/2026 isso não é mais regra escrita: é índice único.**
`idx_tops_access_code_unico` (parcial, `where access_code_hash is not
null`) faz a colisão falhar no `update` do admin, na hora, em vez de
falhar em 216 cadastros no dia do evento. `idx_tops_numero_unico` faz o
mesmo pelo `top_number`, que é o que a pessoa digita ao pedir acesso.

#### A senha do Top é do admin MASTER

Decisão do dono em 23/11/2026, nestas palavras: *"esta senha deve ser
gerada dentro do app somente pelos master... o master irá colocar o número
do top, local, nome da pista, e diretor, aí terá o botão gerar senha, neste
momento o admin tem a senha para distribuir entre os usuários do top... os
admin master terão todo acesso"*.

Antes **qualquer admin** gerava: a Edge Function liberava em
`ehAdmin = is_master_admin || role === 'admin'`, e a tela do Top mostrava o
botão para os dois.

| | Admin comum | Admin master |
|---|---|---|
| Criar e editar o Top (número, pista, cidade, diretor, datas, emblema) | sim | sim |
| **Gerar** a senha do Top | **não** (403) | sim |
| **Abrir** o cadastro | **não** (42501) | sim |
| **Fechar** o cadastro | **sim** | sim |
| Distribuir a senha | sim — falar não é permissão | sim |

**Fechar é de qualquer admin e abrir é só do master**, e a assimetria é
deliberada: fechar é sempre o lado seguro (porta fechada por engano alguém
reclama e resolve em um toque), abrir é dar acesso ao Top. Sem isso, a
trava do master seria contornável — gerar a senha abre a trava junto, então
um admin comum reabriria o cadastro com a senha antiga e o master não
controlaria nada.

Três camadas, e as três são necessárias:

1. **`supabase/07_senha_do_top_so_o_master.sql`** — trigger
   `tops_trava_senha`, `before update for each row`. É a fronteira.
   `with check` **não serve**, pela mesma razão medida em 12/10/2026 com
   `profiles.approved`: função que lê a tabela sendo alterada, chamada de
   dentro do `with check` daquela alteração, não dá garantia sobre qual
   versão da linha vê.
2. **A Edge Function `acesso`** confere `is_master_admin` em
   `gerar_senha_top`. Ela escreve com `service_role`, e o trigger deixa
   `service_role` passar **justamente porque a conferência é ali** — as
   duas andam juntas, e mexer numa sem a outra abre a porta.
3. **A tela** (`AdminTopFormScreen.isMasterAdmin`) esconde o botão e trava
   o interruptor na direção de abrir. É cortesia, não controle: a chave
   anônima está dentro do APK e alcança `tops` por `PATCH` direto.

E a tela **diz quem faz**, em vez de só esconder — "só o administrador
master gera a senha deste Top, peça a senha a ele para distribuir". Porta
fechada sem explicação parece defeito, e o admin tenta de novo.

**Gerar exige número, local/pista e diretor preenchidos e salvos.** Não é
zelo: sem `top_number` a pessoa não tem o que digitar no campo "número do
Top" ao pedir acesso, e o pedido chega ao admin sem evento. Aconteceu com o
Top criado em 23/11, que nasceu com `top_number` nulo porque foi criado por
SQL e não pela tela.

7 testes em `test/widgets/senha_do_top_so_o_master_test.dart`. Eles travam
o lado da TELA; o lado do banco foi verificado chamando de verdade, com um
admin comum de teste: gerar → 403, abrir → 42501, fechar → 200, sobrescrever
`access_code_hash` por `PATCH` → revertido em silêncio, editar o Top →
200, e o master fazendo tudo.

#### Top SEM lista prévia: `tops.aceitar_fora_da_lista`

O Top de 26/11/2026 nasceu com a lista de participantes **vazia**, e a
lista dos 216 do Top anterior **não existe em lugar nenhum**. Procurada em
23/11/2026: nenhum `.csv`/`.xlsx` no repositório, nenhum em commit algum do
histórico, nada apagado, nenhum número de Legendários no código além do do
dono, nada nas transcrições das sessões, e o projeto antigo responde
**NXDOMAIN** — apagado, não pausado (pausado o host resolve e o upstream
falha). O token atual só alcança a organização `hakunasconnect`; o projeto
antigo ficava em outra e devolve 403, então restaurar, se ainda for
possível, só o dono consegue pelo painel da conta antiga.

Sem o interruptor, o autocadastro é inútil num Top assim:
`participante_elegivel` exige o número **na lista**, então todo mundo
digitaria a senha certa e ouviria "número ou senha do Top incorretos" — que
soa como senha errada.

Com `aceitar_fora_da_lista = true`, quem tem a senha se cadastra sem ficha
e **a ficha é criada a partir do que a pessoa digita**: nome, família,
nascimento, comorbidade, alergia, contato de emergência. O autocadastro
deixa de depender da lista e passa a ser **o jeito de construir a lista** —
pelas próprias pessoas, que são as que sabem os dados.

**O que se perde, e é real:** a lista era a segunda tranca. Ligado o
interruptor, **a senha do Top passa a bastar** — quem a tiver entra com
qualquer número. Quem entrar assim vê o Top, lê o chat geral e **pode
disparar alarme**; não alcança prontuário (`top_hakunas`) nem a posição
dos outros (`pode_ver_mapa`). Daí o padrão ser `false`, ser **por Top**, e
ser do admin **master**, igual à senha: quem decide quem entra no evento é
quem responde por ele. A mitigação continua a mesma — fechar
`autocadastro_liberado` depois que a equipe entrou.

A ficha criada assim sai com `notes = 'ficha criada no autocadastro'` e
`registered_by` = o id da própria pessoa. A marca não é enfeite: a tela de
participantes mostra `notes`, e se a lista oficial aparecer depois é por
ali que o admin confere. O importador já desmarca duplicata por número e
por nome.

SQL em `supabase/11_autocadastro_sem_lista.sql`; a trava do master é a
mesma função `tops_trava_senha_do_top`, estendida — **ligar** exige master,
**desligar** qualquer admin pode, pela mesma razão de fechar o cadastro.

#### O campo Família era descartado antes de sair do aparelho

Achado em 23/11/2026, cadastrando num Top sem lista. "Família" está na tela
de cadastro desde sempre, a pessoa preenche — e o mapa `ficha:` enviado a
`acesso/cadastrar` tinha 18 chaves, sem `familia`. O dado morria no
aparelho, antes de qualquer rede. A Edge Function também não gravava a
coluna.

Campo que a tela mostra e o app joga fora é **pior que campo ausente**: a
pessoa digita, vê "cadastro concluído" e o dado não existe. Ninguém
descobre até procurar por família e não achar — e é por família que a lista
de participantes busca e agrupa.

Corrigido nos dois lados. No servidor, `familia: ficha.familia ?? r.familia`
preserva a da lista oficial quando um app antigo não mandar o campo.

Travado por `test/cadastro_manda_a_ficha_inteira_test.dart`, que lê o
código-fonte e exige que **as 19 chaves** que a tela pede estejam no mapa
enviado. Teste de widget não pegaria: a tela renderiza o campo certo, o
defeito estava no envio. O teste tem a outra metade da guarda também — se
alguém tirar o campo da tela, ele falha em vez de passar por vacuidade.

### Lista de participantes: atualiza do servidor ao abrir

Até a v1.0.44 a lista buscava o servidor **só no primeiro "Baixar"**, e o
"Recarregar" relia o disco. Nada que entrasse por outro aparelho chegava
à tela — foi o "o banco não aparece para mim" do dono em 28/10/2026.
Hoje ela atualiza ao abrir (calada se não houver sinal) e no botão,
mandando a fila antes. `DadosDoTop.baixar` **não substitui** a lista se
houver ficha deste aparelho ainda não enviada (`Outbox.naoEnviadas`,
que conta a quarentena também): `salvarParticipantes` apaga o Top
inteiro do disco, e a ficha recém-feita sumiria da tela.

### Painel do Top (admin)

Menu do Top › Painel do Top. Uma chamada a `painel_do_top` (security
definer, recusa quem não é admin com 42501 — testado como senderista).
Só contagens. Precisa de internet e diz isso.

### Aviso de versão nova

Faixa com ATUALIZAR na tela inicial, além do ponto na logo. **O aviso
depende de `app_versions` ter a linha.** Da 1.0.40 a 1.0.44 nenhuma foi
escrita — o CI dependia do secret `SUPABASE_SERVICE_ROLE_KEY`, nunca
criado — e ninguém viu o botão (conferido em 28/10/2026).

Desde a 1.0.45 o caminho é outro, **sem segredo no CI**: o repositório é
público, o APK fica na própria Release (o link abre sem login) e o último
passo do `android-build.yml` chama a Edge Function `publicar_versao` com
o número da versão. A função **não confia em quem chama**: confere no
GitHub que a Release existe publicada, com `legendarios<versao>.apk`, e
lê o build do `pubspec.yaml` daquela tag. Só registra o que foi de fato
publicado; não dá para apontar o botão para um APK de fora. Testada com
1.0.45 (gravou), 9.9.9 (404) e lixo (400).

**Tags não saem desta sessão** (o proxy bloqueia push de tag e a API de
refs). Por isso o disparo manual do workflow (`workflow_dispatch`) cria a
tag `v<versão do pubspec>` sozinho, pela `action-gh-release`. Para
publicar: bumpar o pubspec, push no `main`, disparar o workflow.

**Builds pararam de 12/10 a 28/10/2026** por orçamento do Actions
("an Actions budget is preventing further use", 0 ms faturados). Tornar
o repositório público resolveu. Se voltar a acontecer, o sintoma é job
falhando em 2–3 s sem nenhum passo.

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

### A malha pedia permissão que o Android antigo NÃO TEM

Achado em 23/11/2026, lendo o `permission_handler` até o fim.
`MalhaService._pedirPermissoes` pedia `bluetoothScan`, `bluetoothAdvertise`
e `bluetoothConnect` em **toda** versão e exigia as três concedidas. As
três só existem no **Android 12 (SDK 31)**. E o plugin, ao receber um grupo
que não tem permissão nenhuma naquela versão, devolve DENIED:

```java
if (names == null || names.isEmpty()) { ...
    requestResults.put(permission, PERMISSION_STATUS_DENIED);
```

Então **em todo celular Android 11 ou mais antigo a malha se recusava a
ligar**, dizendo que faltava permissão de Bluetooth — num aparelho onde
`BLUETOOTH` e `BLUETOOTH_ADMIN` são de instalação, já concedidas, e o rádio
funcionaria. O chat sem rede simplesmente não existia para quem tem celular
mais velho, e a tela culpava o usuário.

O código **já tratava disso** para `nearbyWifiDevices`, com o comentário
certo. O mecanismo é idêntico para as três de Bluetooth, e elas ficaram
fora da correção — é o tipo de defeito que uma exceção bem explicada
esconde: parece que o caso já foi pensado.

Hoje a régua é por versão, lida do aparelho (`device_info_plus`), em
`MalhaService.permissoesPara(sdk)`:

- **localização**: obrigatória em toda versão (o Android exige localização
  para buscar por BLE, mesmo sem GPS);
- **trio do Bluetooth**: só no 31+, e ali obrigatório — negado, o Nearby
  não anuncia nem descobre, e falha calado;
- **`nearbyWifiDevices`**: só no 33+, pedida e **não exigida** — é o salto
  por WiFi depois do BLE; exigir faria quem recusasse perder a malha
  inteira por causa do acelerador.

Se não der para descobrir a versão, assume 31: pedir demais mostra um
diálogo a mais, pedir de menos liga a malha sem permissão e ela não acha
ninguém, calada.

16 testes em `test/services/malha_permissoes_por_versao_test.dart`, faixa
por faixa (24, 28, 29, 30, 31, 32, 33, 35, 36). A regra é pura e por isso
se testa direto — não montando árvore e fingindo um celular.

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
6. O mesmo push de tag dispara `ios-build.yml`, que manda o build ao
   TestFlight quando os secrets da Apple existem. O App Store Connect
   recusa reenviar o mesmo `+N` — reenviar a mesma versão exige bumpar o
   build.

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
2. **Login com Google: SHA cadastrado em 12/10/2026.** O dono registrou
   no Firebase (projeto `hakuna3colinas-app`, app
   `com.legendarios.hakuna_connect`) as duas impressões da chave de
   produção, lidas do APK assinado com `apksigner`:

       SHA-1    0B:99:23:13:83:2C:54:BE:2A:0C:B3:ED:0F:DE:56:11:44:1D:4B:88
       SHA-256  38:6D:32:85:3D:84:DA:7A:D6:7F:AB:01:B7:CF:01:22:6D:74:0B:CB:73:2E:E2:4A:F3:1D:7A:3B:4E:88:6D:5C

   Era a causa do `DEVELOPER_ERROR`, que estourava antes de qualquer
   chamada de rede — nunca foi problema de `clientId` (ver
   `SupabaseService.googleIndisponivelNoApk`).

   **Não verificado em aparelho.** Só o login real prova, e isso exige o
   APK assinado com a chave de produção instalado num celular.

   **Armadilha para o futuro:** esse é o certificado do keystore do
   projeto. Se um dia o app for para a Play Store com *Play App Signing*,
   o Google RE-ASSINA o APK e gera outro SHA — e o login quebraria de
   novo, com o mesmo erro, parecendo regressão. O SHA novo apareceria no
   console da Play e precisaria ser cadastrado também.

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

**O arquivo no Drive tem de estar COMPARTILHADO, e nunca esteve.**
Conferido pela API do Drive em 12/10/2026: os APKs 1.0.35, 1.0.37, 1.0.38
e 1.0.39, a pasta "Legendarios APK" e a pasta `apk1035` voltaram todos
apenas o dono, sem permissão de link. Isso significa que o botão ATUALIZAR
nunca funcionou para ninguém além dele — quem tocasse caía em "Solicitar
acesso", e isso explicaria a base instalada não acompanhar as versões.

**Compartilhe a PASTA, não o arquivo** ("Qualquer pessoa com o link",
Leitor): assim todo APK futuro nasce compartilhado e o erro não se repete
a cada release. Conferir depois de publicar faz parte do fluxo — a linha
em `app_versions` com link fechado é pior que nenhuma linha, porque avisa
200 pessoas e manda todas para uma tela de pedir acesso.

Para desarmar um aviso já publicado:
`update public.app_versions set published = false where version = '...'` —
`AtualizacaoService.consultar` filtra por `published = true`.

Detalhe de campo: para arquivo de 76 MB o Drive não baixa direto, mostra
"não foi possível verificar se há vírus" e um botão **Baixar mesmo
assim**. Funciona, mas avise a equipe para não acharem que deu erro.

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
validando uma configuração que não existe mais.

**E vale na direção oposta também — foi o que aconteceu em 23/11/2026.**
O banco reconstruído tinha **14 regras ativas**, não 8: o conjunto canônico
mais o antigo, com o pega-tudo `41+, 0..999 -> vermelho` em `priority 1`.
Como `_corPara` ordena por prioridade e devolve a primeira que casa, **todo
participante de 41 anos ou mais era pintado de vermelho**, inclusive quem
não tem comorbidade nenhuma (devia ser amarelo). Os 575 testes passavam:
eles validam o fixture, que estava certo, e nunca olham o banco.

A causa está no repositório e foi corrigida no mesmo dia: `schema.sql` e
`admin_master_and_triage.sql` inseriam as 6 regras antigas **sem informar
`active`**, e a coluna é `not null default true`. Qualquer reexecução
desses arquivos — uma segunda passada dirigida, por exemplo — ressuscitava
o pega-tudo. Hoje os dois inserem com `active = false` explícito, porque
são história, não configuração. A correção de dados está em
`supabase/08_triagem_uma_configuracao_so.sql`, e ela casa pela FORMA da
regra, não por id.

**Conferir a triagem é uma consulta, não leitura de código.** O rodapé
daquele arquivo tem a consulta que calcula a matriz pelo mesmo critério do
app; se o resultado não for exatamente

```
 18 anos: blue  green  red     30 anos: green yellow red     50 anos: yellow red red
```

há duas configurações ativas de novo.

## A auditoria linha a linha de 23/11/2026

Depois de consertar 4 P0 pela manhã, o dono pediu revisão linha a linha. A
auditoria achou **mais três**, e nenhum deles aparece em conferência de
esquema — os três estavam no banco antigo também.

| | O que estava quebrado |
|---|---|
| **P0** | Triagem com duas configurações ativas (acima) |
| **P0** | `team_messages` fora da publicação `supabase_realtime` — o chat das 9 equipes e do `geral` **não recebia mensagem nova**. O `.stream()` faz a leitura inicial, então o histórico aparecia e nada mais chegava: dois celulares lado a lado não se viam. Corrigido em `09_realtime_do_chat_das_equipes.sql` |
| **P0** | `anotacoes` sem policy de UPDATE — o bloco "editável" **nunca pôde ser editado**, nem em produção. A primeira versão subia; toda correção batia em 42501, que a fila classifica como permanente, e ia para a quarentena. Pior: aparecia certa no aparelho de quem escreveu e errada para os outros. Corrigido em `10_anotacoes_editaveis_de_verdade.sql` |

### O que a auditoria conferiu, e o que vale repetir

Cinco checagens valeram o tempo e devem ser refeitas em qualquer
reconstrução:

1. **A publicação do Realtime contra o que o app assina.**
   `select tablename from pg_publication_tables where pubname =
   'supabase_realtime'` tem de conter toda tabela que aparece num
   `.stream(` do app. Faltava uma de cinco.
2. **A matriz de policies por comando.** Para cada tabela, quantas
   policies de SELECT/INSERT/UPDATE/DELETE existem — e cruzar com o que o
   app faz. Tabela com `upsert` **sem** `ignoreDuplicates` precisa de
   UPDATE; era o buraco de `anotacoes`. As append-only (`audit_log`,
   `tag_leituras`, `vital_signs`, `top_alerts`, `atendimento_fotos`,
   `hakuna_positions`, `top_hakuna_messages`) estão certas sem UPDATE.
3. **Índice único completo, não parcial, para todo `onConflict`.** O
   `CLAUDE.md` já registrava o risco (bug da v1.0.29); conferido, os 12
   índices de `client_id`/`bloco_id` são completos.
4. **Todo nome de coluna que o app usa contra `information_schema`.** As
   142 chaves extraídas dos models e dos filtros dos services existem no
   esquema; as 39 que não existem são chaves do JSON do `painel_do_top` e
   textos de erro. Foi essa checagem que teria achado
   `atendimentos.participant_id` de manhã.
5. **Exercitar cada caminho com os VERBOS do app.** Não basta um `insert`:
   a fila usa `upsert` com `resolution=ignore-duplicates` (append-only) ou
   `merge-duplicates` (bloco editável), e a revogação de pulseira usa
   `update`. Testar com o verbo errado produz falso alarme — três das
   minhas primeiras falhas eram erro do teste, não do app. **Falso alarme
   custa tempo; verbo certo acha defeito de verdade.**

Exercitados e verificados em 23/11/2026, com dado de teste criado e
apagado: autocadastro completo, login por número, chat geral (escreve,
recusa alerta de membro comum, recusa outra equipe), chat de equipe com
alerta de coordenador, chat clínico, alarme com GPS, posição própria,
atendimento pela fila (incluindo reenvio idempotente) e encerramento,
aferição, foto de ferida, pulseira emitida/lida/revogada, auditoria,
anotação criada e editada três vezes, equipe montada, permissão de mapa,
imagem de Top, dispositivo de push, pedido de acesso com código individual,
Painel do Top, exclusão oficial de conta e as travas: anônimo barrado,
membro não edita bloco alheio, não-membro não lê anotação de equipe.


## "Ninguém consegue entrar": confira o SERVIDOR antes do código

Em 20/11/2026 ninguém entrava. O código não tinha mudado desde 28/10; o
projeto `jitfbambhmfnqiatwoud` estava **pausado** — o plano gratuito do
Supabase pausa após ~7 dias sem uso, e o endereço `<ref>.supabase.co`
deixa de existir ("upstream dial failed", igual a um projeto que o
painel mostra como `INACTIVE`). Sai do ar o login, a função `login`, o
chat, tudo. **Restaurar é no painel do Supabase** (Restore project); só
o dono da conta faz. Se ficar pausado por mais de 90 dias, não volta.

O app mostrava o texto cru do Dart (`Failed host lookup`) e quem já
estava logado ficava preso em "Erro ao carregar perfil" sem botão. Hoje
`pareceErroDeRede` + `avisoServidorFora` dizem que é o servidor (e que a
senha não tem nada a ver), e o `AuthGate` dá "Tentar de novo" e "Sair".
Travado por `test/services/login_com_servidor_fora_test.dart`.

**O workflow `manter_servidor_acordado.yml` evita a pausa.** Faz uma
leitura mínima a cada 2 dias, e o GitHub só roda agendamento a partir da
branch padrão (`main`) — em outra branch ele não existe para o cron.
Execução **vermelha** quer dizer que o servidor não respondeu: restaurar
no painel do Supabase, não mexer no código. O segundo passo reabilita o
próprio workflow pela API, porque o GitHub desliga agendamento de
repositório sem commit há 60 dias; se esse passo falhar, ele aparece com
aviso (`continue-on-error`) sem esconder o primeiro.

**Flutter fixo em 3.47.8**, no `android-build.yml` **e** no
`ios-build.yml`. Subir é decisão deliberada: testar numa branch e mudar os
dois arquivos juntos. Com `stable` solto o CI pegou a 3.50.1, que dá 66
avisos no `flutter analyze` (depreciações de `material.dart`) e derruba o
build sem nenhuma linha nossa ter mudado.

**Entrada sem servidor.** Quem já foi aprovado NESTE aparelho entra mesmo
com o servidor fora (`entrada_sem_servidor.dart`: `entraNaFalha` só abre
com falha de rede, sessão e aprovação guardada da mesma conta) e vê a
lista de Tops guardada no disco (`cache_tops`, esquema v6, separada por
conta). O perfil real volta a mandar na próxima abertura do app com rede
(ou nos botões "Tentar de novo"/"Verificar"). O limite, dito sem
enfeite: **aprovação revogada só vale na próxima abertura com rede** —
até lá o aparelho vê o que já tinha no disco. A RLS continua sendo a
fronteira: nada novo chega do servidor para quem não passa nela.

**Abertura com sessão vencida e servidor fora: teto de 8 s.** Medido em
21/11/2026 contra o projeto pausado: com uma sessão vencida no aparelho
(quem não abria o app havia semanas), a biblioteca do Supabase tenta
renovar o token por até 10 s a cada pedido, e o perfil levava **36 s**
para falhar — com a rodinha girando sem texto, que o dono descreveu como
"tela branca parada". E o erro (`AuthRetryableFetchException`) não era
reconhecido como rede. Hoje `AuthGate` espera no máximo
`tempoMaximoParaEntrar` (8 s), a tela de espera diz "Conectando ao
servidor…", e `pareceErroDeRede` reconhece esse erro. Não aumentar o teto
sem medir de novo: acima de ~10 s a pessoa fecha o app achando que travou.

## Objetos que só existiam em produção — 13 até agora

Reconstruir o banco do zero em 23/11/2026 provou que o repositório **não
descreve o esquema inteiro**. Treze objetos eram chamados pelo app ou pelas
Edge Functions e nenhum arquivo os criava. Oito apareceram montando o
schema; **cinco só apareceram quando o app foi exercitado de verdade.**

| Objeto | O que quebrava sem ele |
|---|---|
| `top_participants` | fichas, prontuário, autocadastro |
| `team_messages` | chat de todas as equipes |
| `top_team_members` | equipes, anotações, `is_team_member` |
| `audit_log` | auditoria de segurança |
| bucket `emblemas` | imagem do Top (403 enganoso) |
| `is_approved()` | alarme não compilava; anotações negadas a todos |
| `tops.autocadastro_liberado` | autocadastro inteiro (42703) |
| índice `idx_atendimentos_participante` | histórico da ficha lento |
| `profiles.is_teste` | **ninguém se autocadastrava** |
| versão certa de `tops_select_linked` | conta nova não via nenhum Top |
| 6 valores de `atendimento_status` | **Painel do Top morria (22P02)** |
| `atendimentos.participant_id` | **registrar e ler atendimento** |
| `dependencias_do_perfil` / `_do_senderista` | admin master não apagava ninguém |

### A lição é sobre o MÉTODO de conferir, não sobre o esquema

A conferência que eu fiz primeiro foi por área do app: existe a tabela?
tem RLS? tem policy? tem a função? **Passou em tudo, e quatro P0 estavam
vivos.** Porque aquela conferência não vê:

- **coluna faltando** numa tabela que existe (`profiles.is_teste`,
  `atendimentos.participant_id`);
- **valor faltando** num enum que existe (`atendimento_status`);
- **policy restritiva demais**, que é o pior de todos: o objeto existe, o
  nome está certo, e ela nega em silêncio (`tops_select_linked`);
- **função chamada e inexistente**, que só aparece quando alguém chama.

O que acha isso é **exercitar o caminho real de ponta a ponta**: cadastrar
uma ficha marcada com `is_teste`, fazer o autocadastro por número + senha
do Top, entrar com ela, escrever no chat, disparar alarme, registrar
atendimento, abrir o Painel, e apagar a conta pelo caminho oficial. Dá uma
hora de trabalho e foi o que achou os cinco últimos. **`is_teste` existe
exatamente para isso** — a conta e a ficha de teste saem marcadas e se
apagam em bloco depois.

Ao mexer no esquema, a pergunta certa não é "a tabela existe?" e sim
"**este fluxo funciona chamando de verdade?**".

### A senha do Top saía do hash em 43 segundos

Achado na revisão de 24/11/2026, **medido, não deduzido**. Três elos, e os
três estavam abertos ao mesmo tempo:

| Elo | Como estava |
|---|---|
| `tops_select_linked` | `is_approved() and status <> 'draft'` — **toda** conta aprovada vê **todo** Top não-rascunho |
| `GRANT SELECT` por coluna em `tops` | `authenticated` e `anon` tinham `access_code_hash` na lista. **RLS é por LINHA, não por coluna** |
| `fetchMyTops` | `.select()` sem lista de colunas virava `select *`, e `*` inclui o hash |

A medição foi feita criando um membro comum aprovado dentro de uma
transação, lendo pela RLS e desfazendo: com `is_admin() = false` ele leu a
coluna do hash. E o hash era **SHA-256 cru, sem sal** — conferido
recalculando-o a partir da senha em claro e comparando com a coluna.
Alfabeto de 31 caracteres, 8 posições → `31^8` = 852.891.037.441. Uma GPU
modesta (2 GH/s) varre tudo em ~7 minutos; uma RTX 4090, em **~43
segundos**.

**O estrago não era "a senha vaza".** Quem lê o hash é membro e já tem a
senha. O estrago era que a garantia ESCRITA em `gerar_senha_top` —
*"gerar de novo INVALIDA a anterior na hora, é assim que se corta o acesso
se a senha vazar"* — **não cortava**: quem vazou a senha e continua com
conta aprovada lê o hash novo e recupera a senha nova em minutos.
Rotacionar não expulsava ninguém. E com `aceitar_fora_da_lista` ligado, a
senha BASTA para entrar no Top.

Escopo extra: a policy abre todo Top não-rascunho, então um membro do Top A
lia e quebrava a senha do Top B. E não precisa do app — a chave anon está
dentro do APK e um `curl` no PostgREST devolve a coluna.

**Conserto: HMAC-SHA256 com um pepper que não está no banco**
(`hashDoTop` na Edge Function `acesso`, segredo `SENHA_TOP_PEPPER`).
Continua **determinístico**, então a busca do Top pelo hash com
`maybeSingle()` segue funcionando — era por isso que bcrypt/argon2 não
servem aqui. Quebrar fora do servidor passa a exigir o segredo.

Três coisas que não se pode mexer sem entender:

1. **Falha fechada.** Sem o segredo, `hashDoTop` levanta. Cair de volta no
   SHA-256 cru pareceria funcionar e estaria desprotegido — pior que o erro.
2. **Trocar OU PERDER o pepper invalida toda senha de Top em vigor** — de
   todos os Tops, de uma vez. O pepper vive só nos segredos da Edge
   Function: não está no repositório, não está no banco, não está em backup
   nenhum. **Guardar uma cópia fora desta máquina é obrigação do dono do
   projeto**, mesma categoria do keystore `.jks`. A diferença: perder o
   pepper é reversível (o master gera senha nova pela tela), mas custa
   **reanunciar a 216 pessoas** — e no dia do evento isso é caro.
3. **O código individual (`access_requests.code_hash`) continua no `hash()`
   simples, e isso foi conferido, não presumido:** `access_requests` **não
   tem policy de SELECT nenhuma**, e RLS sem policy nega para todos. Aquele
   hash não vaza.

A senha em vigor foi **migrada** (o hash reescrito como HMAC), em vez de
gerada de novo — a que o dono já tinha anotado continuou valendo. Conferido
de ponta a ponta na função publicada: senha certa devolve o Top, senha
errada devolve "numero ou senha do Top incorretos".

**Nunca escrever hash de senha neste arquivo nem em commit.** O repositório
é PÚBLICO. Na primeira tentativa de documentar isto eu ia colar o hash
antigo aqui, e a ação foi barrada — a lição vale mais que o exemplo.

**Falta a outra metade, e ela depende da base instalada.** `fetchMyTops`
já pede colunas explícitas (v1.0.53), mas o
`revoke select (access_code_hash) on tops from authenticated, anon` só pode
entrar quando todo aparelho estiver na 1.0.53+: hoje ele quebraria todo APK
≤ 1.0.52, que ainda manda `*`.

### `auth.uid() is null` NÃO é "é o service_role"

`07_senha_do_top_so_o_master.sql` e `11_autocadastro_sem_lista.sql` abriam a
porta do trigger assim, com o comentário afirmando que era o `service_role`.
Era também **a chave anon**, que está dentro do APK. A regra já estava
escrita neste arquivo, no mesmo dia em que o furo foi introduzido.

**Não era explorável, e isso precisa ser dito sem maquiagem:** `is_admin()`
usa `exists (...)`, que devolve FALSE (nunca NULL) para quem não tem perfil,
e `tops_admin_update` é `is_admin()` — a RLS barrava o anônimo antes do
trigger disparar. O que estava quebrado era a **segunda tranca**.

A versão válida é `13_trava_do_top_sem_uid_nulo.sql`, e os dois ramos de
passagem foram **medidos** com uma sonda `session_user` /
`request.jwt.claims` pelos dois caminhos:

| quem chama | claims role | `session_user` |
|---|---|---|
| Edge Function (`service_role`) | `service_role` | `authenticator` |
| chave ANON (dentro do APK) | `anon` | `authenticator` |
| usuário logado | `authenticated` | `authenticator` |
| psql / Management API / migração | *sem claims* | `postgres` |

```sql
if v_papel = 'service_role'
   or (v_papel is null and session_user <> 'authenticator') then
```

O segundo ramo existe para a migração que conserta dados não ter a escrita
revertida em silêncio. **`session_user` é o discriminador certo porque não é
afetado por `security definer`** — `current_user` vira o dono da função e
não distingue nada (lição de 12/10/2026).

Medido depois de aplicar, isolando o trigger (rodando como `postgres`, com
as claims trocadas, RLS fora do caminho):

```
claims anon tenta sobrescrever o hash ... revertido em silencio
claims anon tenta ABRIR o cadastro ...... 42501
service_role abre o cadastro ............ passa
```

### Arquivo de migração que REBAIXA outro tem de falhar alto

`07` e `11` definiam a mesma função `tops_trava_senha_do_top()`, e a do `07`
**não tinha** o ramo de `aceitar_fora_da_lista`. Rodar o `07` sozinho — o
uso mais natural dele, "restaurar a trava da senha" — removia a proteção do
interruptor, calado.

É a mesma classe do que custou caro em 23/11/2026: `schema.sql` reexecutado
ressuscitou a regra pega-tudo da triagem e repintou de vermelho todo mundo
acima de 40 anos, sem erro em lugar nenhum.

Hoje os dois arquivos têm uma guarda que confere se a função já está na
versão nova (procura `request.jwt.claims` no corpo) e **levanta 42501** em
vez de rebaixar. Conferido: rodar `07` ou `11` agora falha, e a trava
continua na versão nova.

**A regra geral: arquivo antigo que possa sobrescrever objeto mais novo não
pode ser idempotente em silêncio — tem de recusar.** "Idempotente" não
basta quando o arquivo é *história*.

### O interruptor `aceitar_fora_da_lista` não tinha tela

Ligado por SQL em 23/11 e sem nenhuma UI: não havia como desligar pelo app.
A mitigação documentada ("feche o cadastro depois que a equipe entrar")
cobria só `autocadastro_liberado` — e `gerar_senha_top` reabre esse junto,
então o Top voltaria a aceitar qualquer número sem ninguém poder impedir.

Hoje é um `SwitchListTile` no mesmo bloco da senha, com a **mesma
assimetria**: ligar é do master (e pede confirmação dizendo que a senha
passa a bastar), desligar é de qualquer admin. O default do modelo é
`false` nos dois caminhos — construtor e `fromMap` sem a coluna —, o
**inverso** de `autocadastroLiberado`, que é `true`. A diferença é
deliberada: não trazer a coluna não pode AFIRMAR uma permissão.

Entrou junto a v7 do esquema local (`cache_tops` ganhou a coluna, default
0). E os dois `SwitchListTile` ganharam `Key`: com dois na mesma tela,
`find.byType(SwitchListTile)` passou a achar os dois e os testes antigos
quebraram com "Too many elements".

### `is_approved()` devolvia NULL quando não havia perfil

Era `select coalesce(approved, false) from profiles where id = auth.uid()`.
O `coalesce` cobre a COLUNA nula; não cobre a **linha ausente** —
subconsulta sem linha é NULL. Inofensivo enquanto toda policy a usa dentro
de um `AND` (NULL nega). Vira armadilha no primeiro `not is_approved()`:
`not null` é null, que nega também, e a policy faria o oposto do nome, sem
erro. Corrigido com `coalesce` por fora, em `13`.

### Viés de módulo no sorteio da senha

`b % 31` com `b` em 0..255 não é uniforme: 256 não é múltiplo de 31, então
os 8 primeiros caracteres sairiam 9 vezes em 256 e os outros 23 sairiam 8.
A perda era ~0,06 bit na senha inteira e por isso passou batido. Entrou na
conta quando o hash ganhou pepper: **a partir dali a entropia da senha é a
única barreira**. Hoje `sortearDoAlfabeto` usa rejeição de amostra
(descarta byte ≥ 248) e serve aos dois geradores.

### Passo de migração local novo tem de conferir, não supor

Cometido e pego em 24/11/2026, na v7 do esquema local. O passo era um
`ALTER TABLE cache_tops ADD COLUMN aceitar_fora_da_lista` seco, e está
**correto olhando só para ele**. O defeito mora na combinação:

```dart
if (from < 6) await _criarCacheDeTops(db);   // roda ColunasTop.criar
if (from < 7) await _aceitarForaDaLista(db); // ALTER ... ADD COLUMN
```

`ColunasTop.criar` é o esquema de HOJE, com a coluna nova. Num aparelho
vindo da v5 ou de antes, o passo da v6 cria a tabela **já com ela**, e o
passo da v7 bate em `duplicate column name`. E isso acontece dentro do
`onUpgrade`: **o banco local não abre**. O app subia e morria na primeira
leitura, em todo celular que não fosse aberto desde a v5 — a base mais
antiga, justamente a que mais precisa do cache.

Pego pelos **testes de migração**, não por revisão: `migracao_v2_para_v3`
e `cache_de_tops` abrem um banco antigo de arquivo e deixam subir até a
versão atual. São os únicos testes do projeto que exercitam a combinação
de passos em vez de um passo isolado.

A correção confere a coluna antes (`PRAGMA table_info`) e sai se já
existir. A alternativa seria `if (from < 7 && from >= 6)`, e é pior: vale
só para esta versão, não sobrevive a um upgrade interrompido no meio, e
obriga quem acrescentar a v8 a refazer a conta.

**A regra: todo passo de `onUpgrade` que mexe em tabela criada por um passo
anterior tem de ser idempotente por conferência.** É a mesma regra das
migrações do Postgres (`if not exists`, rodar duas vezes), aplicada ao
SQLite — que não tem `ADD COLUMN IF NOT EXISTS`. E ao bumpar
`_schemaVersion`, a asserção `expect(db.getVersion(), completion(N))` em
`cache_local_test.dart` tem de subir junto; ela é a guarda que lembra do
resto.

### Um falso alarme que vale registrar: a malha JÁ tem porteiro de plataforma

Na mesma revisão eu afirmei que `BotaoDaMalha` era montado sem checar
plataforma e que no iOS pediria o trio de Bluetooth do Android 12.
**Errado.** O porteiro está em `TransporteNearby.disponivel`
(`!kIsWeb && defaultTargetPlatform == TargetPlatform.android`),
`BotaoDaMalha.build` devolve `SizedBox.shrink()` quando não está disponível,
e `MalhaService.ligar` recusa **antes** de `_pedirPermissoes()`.

O erro foi do método: procurei `kIsWeb` em `botao_da_malha.dart` e
`malha_service.dart` e concluí da ausência. O porteiro mora na terceira
camada. **Ausência de uma marca nos arquivos que eu escolhi olhar não é
ausência da proteção** — seguir a chamada até o fim custa um grep a mais.

### Segunda rodada de 24/11/2026: advisors, duplicatas e o hash fora de alcance

Depois de consertar o crítico da senha, o dono pediu "conserte tudo, revise
e deixe perfeito". O que a segunda varredura achou, e o que foi feito.

#### Os advisors do Supabase: 168 avisos, 7 reais

Nunca tinha usado `/v1/projects/<ref>/advisors/{security,performance}`.
Vale usar, **mas quase tudo é ruído para este projeto** — e saber quais são
é o que torna a ferramenta útil em vez de assustadora.

**Segurança: 35 avisos, 1 real.**

Trinta e quatro são `*_security_definer_function_executable`. Medido um por
um, chamando pela API com a chave anon:

| Tipo | Veredito |
|---|---|
| `handle_new_user`, `profiles_trava_colunas_de_permissao`, `tops_trava_senha_do_top` | **Falso positivo.** PostgREST **não expõe** função que retorna `trigger` — as três devolvem `PGRST202`, "could not find the function". Não há o que revogar |
| `is_admin`, `is_approved`, `is_master_admin`, `my_*`, `is_team_*`, `pertence_ao_top`, `pode_ver_mapa`, `pode_alarmar_no_top` | Por design. Só falam do PRÓPRIO chamador. E `authenticated` **precisa** de `EXECUTE`: as policies as chamam, e revogar faria a avaliação da policy falhar com permission denied |
| `dependencias_do_perfil`, `dependencias_do_senderista` | Guardadas por dentro. Medido: `42501 apenas administradores` para anon |
| `painel_do_top` | `42501 permission denied for function` — anon não tem nem EXECUTE |

O único real é `auth_leaked_password_protection`, e **não foi ligado** — ver
abaixo.

**Performance: 133 avisos, 6 reais.** `auth_rls_initplan` (34) pede
`(select auth.uid())` no lugar de `auth.uid()` para não reavaliar por linha:
é real, e irrelevante com 216 pessoas e tabelas pequenas — reescrever 34
policies de controle de acesso a prontuário a 2 dias do evento é risco sem
retorno. `multiple_permissive_policies` (~60) é a soma deliberada de
policies que este arquivo já documenta ("policies do mesmo comando são OR
entre si, então somar `is_admin()` amplia e não tira nada").

Os 6 reais eram `duplicate_index`.

#### A checagem de senha vazada NÃO foi ligada, e o motivo é concreto

O cadastro dos 216 passa por `admin.auth.admin.createUser` (service_role).
**Eu não tenho certeza se a checagem do HaveIBeenPwned se aplica à API de
admin.** Se aplicar, alguém com senha fraca é recusado com o texto cru do
GoTrue, em inglês, no meio do cadastro — e são 216 pessoas em dois dias.

Trocar um risco certo de quebrar o cadastro por um ganho que o caminho
principal nem usa é mau negócio. Fica para depois do evento, e com teste:
criar uma conta pela API de admin com uma senha conhecidamente vazada e ver
se passa.

O que FOI feito de graça: `friendlyAuthError` passou a traduzir
`weak_password` / "known to be weak" / "pwned". Antes caía no `return
message` do fim e saía em inglês. Quando a checagem for ligada, a frase já
está pronta — e ela diz **o que fazer**, porque quem lê "senha fraca" tenta
a mesma senha com um "1" no fim.

#### Seis pares de índices idênticos, e por que apagar no banco não bastava

`duplicate_index` achou seis pares — mesma tabela, mesmas colunas, mesmo
`WHERE`, nomes diferentes (um em português, outro em inglês). Não dão
resposta errada; custam escrita em todo insert e confundem quem lê o
esquema.

A causa é a reconstrução: arquivos diferentes de `supabase/` criam o mesmo
índice com nomes diferentes, e o Postgres obedece aos dois.

Cinco conferências antes de apagar qualquer um, todas necessárias:

1. os pares são idênticos de verdade (`pg_get_indexdef`, não o nome);
2. **nenhum é apoiado por constraint** (`pg_constraint.conindid` nulo nos
   doze) — apagar um que sustenta constraint derrubaria a constraint;
3. **nenhum é alvo de `onConflict`**. O app usa `id`, `client_id`,
   `bloco_id`, `fcm_token`, `top_id,ordem`, `top_id,profile_id`; nenhum par
   cobre essas colunas. Este era o risco grande: índice parcial quebra
   `upsert(onConflict:)` (bug da v1.0.29);
4. de cada par ÚNICO, um fica — `atendimentos.client_id` continua com
   unicidade, que é o que faz o reenvio da fila ser idempotente;
5. nenhum nome aparece em `lib/` nem nas Edge Functions.

**E o conserto teve de ser nos DOIS lados.** Todo nome dos doze é criado por
algum arquivo do repositório: apagar só no banco faria o duplicado VOLTAR na
próxima reconstrução — o mesmo mecanismo que ressuscitou a regra pega-tudo
da triagem em 23/11. Então `15_indices_duplicados.sql` apaga o que existe, e
a criação do nome descartado **saiu do arquivo que a fazia** (quatro
arquivos editados). Conferido depois: zero pares idênticos no banco.

#### O hash da senha saiu da tabela que todo mundo lê

Segunda metade do conserto do crítico. O pepper já tinha tirado o valor do
vazamento; faltava o vazamento.

O caminho óbvio, `revoke select (access_code_hash)`, **não serve**: APK
≤ 1.0.52 manda `select *` em `fetchMyTops`, e com a coluna revogada o
PostgREST recusa a CONSULTA INTEIRA — a lista de Tops sumiria para quem não
atualizou, e é por ela que se chega a todo o resto do app.

A saída foi **mover o valor, não a coluna** (`16_senha_do_top_fora_da_tabela_lida.sql`):
o hash vive em `top_access_codes`, com RLS ligada e **nenhuma policy**, mais
`revoke all` — cinto e suspensório. As colunas de `tops` ficam, **vazias**:

* APK antigo manda `select *`, recebe as colunas nulas e **nada quebra**;
* o trigger `tops_trava_senha` segue referenciando as três. Dropá-las faria
  `new.access_code_hash := old.access_code_hash` estourar em TODO update de
  Top — o admin não editaria nem o nome do evento;
* nenhuma linha de `lib/` lê essas colunas (conferido por grep).

**Aplicado em três passos, para não haver um segundo de janela:** criar a
tabela e COPIAR o hash (a função antiga ainda funcionava) → publicar a
função nova (v9) → esvaziar as colunas antigas. Fazer na ordem contrária
deixaria o cadastro quebrado entre um passo e outro.

Medido depois, com um membro comum aprovado em transação desfeita:

```
membro ve hash em tops? ....... NENHUM (nulo)
membro le top_access_codes? ... BARRADO: 42501
policies em top_access_codes .. 0      RLS ligada: true
```

E a senha em vigor continuou valendo, testada na função publicada depois de
cada passo. **A senha nunca mudou** — nenhum aviso precisou ser repetido a
ninguém.

Falta dropar as três colunas vestigiais, e isso espera a base instalada
estar toda na 1.0.53+.

#### `top_team_members` e `team_messages`, finalmente versionadas

Eram as duas últimas da lista de "objetos que só existiam em produção".
Este arquivo pedia, desde 11/10/2026, para extrair com `pg_dump
--schema-only` em vez de escrever de memória, porque `create table`
inventado "parece fonte da verdade e diverge calado".

`17_top_team_members_e_team_messages.sql` saiu do **catálogo**:
`information_schema.columns`, `pg_constraint`, `pg_get_indexdef` e
`pg_get_expr` sobre `pg_policy`. Inclui as 12 policies, a coluna GERADA
`is_team_admin`, o índice único **não parcial** de `client_id` e o
`alter publication supabase_realtime`.

**E foi verificado em vez de presumido.** O arquivo recria as 12 policies de
uma tabela de prontuário, então: fotografia das assinaturas (nome, comando,
roles, `using`, `with check`) antes, roda duas vezes, fotografia depois,
`diff`. Saiu **vazio** — as 12 ficaram idênticas, caractere por caractere. É
a diferença entre "escrevi o arquivo" e "o arquivo é a produção".

### A revisão de código de 24/11/2026: seis defeitos, três deles criados no mesmo dia

Depois das duas rodadas de conserto, o dono pediu uma revisão de código
formal. Ela achou **um crítico e cinco importantes** — e três eram efeito
colateral dos próprios consertos. Vale registrar, porque o padrão se repete:
**mexer em arquivo histórico conserta uma coisa e desarma outra.**

#### O crítico: remover um índice duplicado deixou o `drop` órfão

`revisao_completa_correcoes.sql` tinha, nesta ordem:

```sql
drop index if exists idx_atendimentos_client_id;   -- linha 84
...
create unique index atendimentos_client_id_key     -- linha 95, a duplicata
  on public.atendimentos (client_id);
```

O `drop` só existia porque o `create` logo abaixo recriava a unicidade sob o
outro nome. Ao apagar a duplicata (`15_indices_duplicados.sql`) eu removi o
`create` e **deixei o `drop`**.

E este arquivo é o **último** a falar sobre esse índice numa reexecução
ordenada: `participantes_e_atendimentos.sql` <
`revisao_10_10_correcoes.sql` < `revisao_completa_correcoes.sql`. Resultado
de um banco reconstruído deste repositório: `atendimentos.client_id` **sem
unicidade**, `upsert(onConflict: 'client_id')` devolvendo **42P10**, que
`_motivoPermanente` classifica como PERMANENTE — e **todo atendimento indo
para quarentena**. Dado clínico, sem erro visível em lugar nenhum.

Produção não estava afetada (o índice existia). O gatilho é qualquer replay
— e este projeto reconstruiu o banco do zero no dia anterior.

**A regra: `drop` e `create` do mesmo objeto são um PAR. Ao remover um
`create` de um arquivo, procure o `drop` que o acompanhava.** Um `drop`
sozinho num arquivo que roda por último é a forma mais silenciosa de perder
uma constraint.

No mesmo rastro apareceu um segundo defeito, independente e mais antigo:
`participantes_e_atendimentos.sql` criava o mesmo índice **parcial**
(`where client_id is not null`), que pela regra deste arquivo já quebra
`onConflict` (bug da v1.0.29). Os dois agora criam completo.

#### Guarda que aborta o arquivo inteiro deixa órfão o que vem depois

As guardas postas em `07` e `11` (levantar 42501 em vez de rebaixar a trava)
rodam **no topo** do arquivo. Correto para o que elas protegem — e elas
tornaram **inalcançável tudo o que vinha depois**, inclusive
`idx_tops_numero_unico`, que `07` era o **único** arquivo a criar.

Em produção o índice existe (foi criado antes da guarda); um banco
reconstruído sairia sem ele, calado. Resgatado em
`14_idx_tops_numero_unico.sql`.

**A regra: ao pôr uma guarda que aborta um arquivo, a pergunta seguinte é
obrigatória — "o que mais este arquivo criava?"** Guarda que protege um
objeto e abandona três não é conserto, é troca de defeito.

#### `00_TABELAS_QUE_FALTAVAM.sql` rebaixava controle de acesso a prontuário

O arquivo-base da reconstrução dá `drop policy if exists` do próprio nome e
recriava `top_team_members_select` na versão **pré-12**
(`profile_id = auth.uid() or is_admin()`) — exatamente a policy que deixava
o coordenador com poder sobre a equipe e **sem ver ninguém**. Rodá-lo
sozinho rebaixava a RLS em silêncio.

Também declarava `is_team_admin boolean` comum (produção tem **GERADA**, e
sem isso `is_team_admin()` devolveria falso para todo coordenador) e criava
`idx_team_messages_client_id` **parcial** (produção tem completo — o
`onConflict` do chat offline depende dele).

Os três alinhados com produção. **Arquivo-base de reconstrução não é
história: ele tem de descrever o presente**, senão cada conserto posterior
vira uma corrida entre arquivos.

#### Ordem de duas escritas: o pior estado não pode morar no caminho de erro

`gerar_senha_top` escrevia na ordem: abre o cadastro, depois grava a senha.
Falhando o segundo passo, o estado persistente era o **pior possível** —
cadastro **ABERTO** com a senha **antiga** valendo, mudança que o admin não
pediu. Com `aceitar_fora_da_lista` ligado é "a senha basta" mais a porta
aberta.

Invertido: senha primeiro. O medo que justificava a ordem antiga — código
órfão apontando para Top nenhum — **não existe**, e isso foi medido:
`top_access_codes.top_id` é FK para `tops(id)`, então id inválido falha com
**23503** e nada é gravado (conferido: a tabela ficou com as mesmas linhas).

Agora o pior caso é "senha nova vale, cadastro não abriu", que
`validarConvite` reporta com mensagem própria em vez de dar acesso.

**A regra: numa sequência de escritas sem transação, ordene para que a
falha intermediária deixe o estado MAIS restritivo, não o mais permissivo.**

#### Falhar fechado também precisa de entrega

`hashDoTop` levanta se o pepper não estiver configurado — certo, porque cair
no SHA-256 cru pareceria funcionar e estaria desprotegido. Mas o
`Deno.serve` **não tem `try/catch` global**: a exceção virava **500 cru, sem
os headers de CORS e sem corpo JSON**. No app não cai em mensagem tratada
nenhuma, e no build web o navegador bloqueia a resposta antes de qualquer
`catch` do Dart.

Ou seja: falha fechada e **indiagnosticável** — o pior dos dois mundos para
quem está no suporte. Hoje o pepper é conferido no topo do handler e o erro
sai nomeando o segredo que falta.

#### A lista de colunas precisava de guarda, e o default dela falha ABERTO

Trocar `select()` por lista explícita resolveu o vazamento do hash e criou
duas armadilhas novas:

1. **Duas consultas divergirem.** `fetchMyTops` ganhou a lista;
   `AdminService.createTop` ficou com `.select()` pelado e só não quebrou
   porque o `revoke` da coluna ainda não entrou — quando entrar, **criar Top
   falharia em qualquer versão do app**.
2. **Esquecer uma coluna nova na lista.** O default de
   `autocadastro_liberado` em `Top.fromMap` é `true`, de propósito — então
   coluna fora da lista faz o app **afirmar que o cadastro está aberto** sem
   ter perguntado ao servidor. Falha aberta, silenciosa.

Hoje a lista é `Top.colunasSelect`, uma constante só, e
`test/top_select_tem_todas_as_colunas_test.dart` trava as duas pontas: toda
chave lida por `fromMap` está na lista, nada além dela está, as três colunas
de senha **nunca** aparecem, e nenhum `from('tops')` volta a usar
`.select()` pelado. Com auto-teste do varredor, pela razão já registrada
neste arquivo: guarda que não é verificada é pior que guarda nenhuma.

#### O que a revisão NÃO conseguiu verificar, e por isso continua sendo tarefa

A restrição dura — "a senha em circulação tem de continuar valendo" — **não
é verificável lendo o repositório**. O que dá para provar daqui é
`validar_convite` contra a função publicada (feito, depois de cada passo, e
de novo na v10). A prova completa é um `cadastrar` de verdade com a senha que
está com o dono, em conta marcada `is_teste` e apagada depois. É o método que
este arquivo prescreve — "este fluxo funciona chamando de verdade?" — e é
decisão do dono, porque cria ficha no Top real.

### A cadeia de atualização, auditada elo por elo (24/11/2026)

Pedido do dono, nestas palavras: *"sempre colocar a versão que está e avisar
aos usuários sobre atualização, ter o botão de atualizar que irá baixar do
github a atualização"*. Tudo isso já existia; auditar achou **três buracos
reais** e um alinhamento que faltava.

#### `launchUrl` LEVANTA, e o botão ficava sem resposta nenhuma

O botão ATUALIZAR fazia:

```dart
final abriu = uri != null &&
    await launchUrl(uri, mode: LaunchMode.externalApplication);
if (!abriu && mounted) { ...snackbar... }
```

O tratamento cobria o `false` e **não cobria a exceção**. `launchUrl`
levanta `PlatformException` quando nada resolve o intent — e exceção
escapando de um callback `async` é **engolida em release**. Para quem
aperta: nada acontece, sem mensagem. Num botão cuja única função é baixar a
atualização, isso é indistinguível de app quebrado, e é o pior lugar
possível para uma falha calada: quem está desatualizado é quem mais precisa
que funcione.

Hoje tem `try/catch`, a mensagem **diz o motivo** (endereço inválido,
nenhum app abriu, o celular recusou) e **mostra a URL**, porque digitar no
navegador é a saída real quando o `launchUrl` não serve.

A armadilha do Android 11+ já estava coberta e vale dizer, para ninguém
"limpar" o manifest: `<queries>` com `VIEW` + esquemas `http`/`https` é o
que faz o `url_launcher` ver que existe navegador instalado. Sem isso
`canLaunchUrl` devolve false e o botão não faz nada — e **não aparece em
emulador antigo**.

#### A caixa "o que mudou" estava sempre vazia

`gaveta_do_app.dart` mostra `v.notas` no diálogo de atualizar, e
`VersaoPublicada.fromMap` lê `map['notes']`. Mas **nada nunca escreveu a
coluna**: `publicar_versao`, chamada pelo CI, grava versão, build e link, e
`notes` fica nula.

Ou seja: havia um lugar pronto para dizer ao usuário o que mudou, e ele
nunca disse nada. Desde a 1.0.54 as notas são escritas junto da publicação,
em português e **do ponto de vista de quem usa** — não "corrigido o hash da
senha do Top", mas "correções de segurança (nada muda para quem usa)".

#### A versão só aparecia depois de entrar

`Versao.completa` aparecia na gaveta, que exige estar logado. **Quem não
consegue entrar é exatamente quem mais precisa responder "qual versão você
está usando?"** — e era a única pessoa que não tinha como descobrir.

Agora aparece também no fim da tela de login.

#### O repositório estava à frente do APK, e isso não pode virar hábito

As correções da revisão de código estavam commitadas e **em nenhum APK**. Eu
havia decidido deixá-las para "o próximo release" para não fazer o dono
instalar duas vezes; ele corrigiu a decisão, e com razão: **versão no
repositório que não existe em aparelho nenhum é dívida invisível** — some do
radar e reaparece como "mas isso não estava consertado?".

A regra fica: conserto que entra no `main` entra num APK. Se não vale um
release, provavelmente não valia o commit separado.

#### Travado por teste, porque cada elo já falhou uma vez

`test/aviso_de_atualizacao_test.dart`, 13 casos: comparação por
`build_number` (incluindo a armadilha `"1.0.9" > "1.0.10"`), `fromMap` com
`num` em vez de `int` (o Postgrest manda `100.0`), colunas explícitas na
consulta, `<queries>` no manifest, o `try/catch` **com** mensagem **e** com
o endereço, a versão nas duas telas, e o portão do iOS (no iPhone não se
oferece APK, porque `app_versions` aponta para um arquivo que o aparelho não
abre).

#### A lição de método desta rodada: teste que lê o fonte não compila o fonte

Ao escrever esses testes eu quebrei um literal de string em
`gaveta_do_app.dart` (um `\n` que virou quebra de linha de verdade ao passar
pelo heredoc). Rodei os dois arquivos de teste novos: **passaram os 18**.

Passaram porque eles leem o arquivo como **texto** — `File(...).readAsStringSync()`
— e nunca o compilam. Quem pegou foi a suíte completa, onde
`gaveta_do_app_test.dart` e `o_app_abre_test.dart` falharam em *loading*.

**A regra: teste que varre código-fonte não substitui compilar.** Ao mexer
num arquivo de widget, `flutter analyze` naquele arquivo é mais rápido que
a suíte e pega o que a varredura textual é cega para ver.

## Pendências conhecidas

- **Dropar as 3 colunas vestigiais de `tops` espera a base instalada.**
  Desde 24/11/2026 o hash vive em `top_access_codes` (RLS sem policy) e
  `tops.access_code_hash/_set_at/_set_by` estao NULAS. As colunas ficam
  porque APK <= 1.0.52 manda `select *` e porque o trigger
  `tops_trava_senha` as referencia. Quando todo aparelho estiver na
  1.0.53+:

  ```sql
  -- primeiro tirar as 3 linhas do trigger em 13_..., senao todo update de Top estoura
  alter table public.tops
    drop column access_code_hash,
    drop column access_code_set_at,
    drop column access_code_set_by;
  ```

  Conferir `app_versions` e o aviso de atualizacao antes. **Nao e urgente:**
  as colunas estao vazias, nao vaza nada.
- **Checagem de senha vazada (HaveIBeenPwned) segue DESLIGADA.** O advisor
  de seguranca pede para ligar. Nao foi ligada porque o cadastro dos 216
  passa por `admin.auth.admin.createUser`, e nao esta medido se a checagem
  se aplica a API de admin -- se aplicar, senha fraca e recusada com texto
  cru em ingles no meio do cadastro. Ligar DEPOIS do evento, testando
  primeiro: criar conta pela API de admin com uma senha conhecidamente
  vazada e ver se passa. A traducao da mensagem ja esta em
  `friendlyAuthError`.

- **O Top novo está VAZIO, e é o que falta para o app servir.** Estado em
  23/11/2026, conferido no banco: Top "TRACK 3 Colinas 1 ano"
  (`46d03f35-8588-4fb4-8afb-8bd0416d70bc`), `active`, 26/11 00:00 →
  29/11 23:59, Franca-SP. **0 fichas**, 1 perfil (o admin master), 1 Hakuna
  liberado (o admin, liberado em 23/11 — sem ele ninguém registra
  atendimento, porque a cerca clínica exige `top_hakunas.released`).

  Três coisas pendem, e nenhuma é de código:

  1. **Importar os senderistas.** `participante_elegivel` exige o número
     **na lista do Top**, então com a lista vazia o autocadastro recusa
     todo mundo com a mensagem genérica "número ou senha do Top
     incorretos" — que soa como senha errada. O importador lê CSV/XLSX.
  2. **`tops.top_number` está NULO.** O pedido de acesso pede "número do
     Legendários e número do Top", e `gerar_senha_top` devolve
     `top_numero`. Sem número, a pessoa não tem o que digitar nesse campo
     e o pedido chega ao admin como "Top X (não existe no app)". **Não
     inventar** — quem define o número do evento é o dono.
  3. **`autocadastro_liberado` está `false` de propósito.** A senha do Top
     já foi gerada e está com o dono. Abrir antes de importar a lista
     faria 216 pessoas digitarem a senha certa e ouvirem "senha
     incorreta". Gerar a senha de novo pela tela de admin reabre a trava
     sozinho — e invalida a senha anterior.

  `diretor_responsavel` do Top segue nulo, pela mesma razão de sempre: quem
  define o responsável por um evento médico é o dono do evento.
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
  pode fazer (criar o Firebase) e o que o push NÃO resolve.

  **Esta frase estava aqui e era FALSA: "para quem está com o app fechado,
  continua valendo o rádio".** Corrigida em 23/11/2026. O rádio **também**
  exige o app aberto — ver abaixo. App fechado hoje significa **nada
  chega**: nem Realtime, nem rádio, nem push (que não existe). É a maior
  lacuna do produto, e não é de código: é de arquitetura.
- **A malha por rádio exige o app ABERTO, nos dois aparelhos.** Medido em
  23/11/2026, lendo o plugin: `nearby_connections` 4.3.0 chama
  `Nearby.getConnectionsClient(activity)` — o rádio está amarrado à
  **Activity** —, e nem o plugin nem o app declaram serviço em primeiro
  plano. Celular no bolso com a tela apagada: o Android congela o processo
  e a malha para, sem aviso.

  Em campo isso muda a instrução: quem for ficar sem sinal precisa deixar
  o app aberto, na tela, com a malha ligada. Resolver exige serviço nativo
  em primeiro plano com notificação fixa — trabalho real, e o plugin não
  ajuda, porque a sessão morre com a Activity.
- **Comunicação sem rede nenhuma (3G/4G/WiFi) não existe no app.** Pedido
  do dono em 11/10/2026. **O levantamento está em
  `docs/comunicacao_sem_rede.md`**: alcance real de cada via, custo, e o
  que cabe em cada canal.

  **Para CHAT DE EQUIPE a conclusão é outra**, e está em
  `docs/comunicacao_de_equipe_sem_rede.md`: equipe trabalha junto, e
  "junto" é exatamente a condição em que BLE e WiFi funcionam. Seis das
  nove equipes ficam concentradas na base (ADM, produção, mídia, eventos,
  voz, intercessão); só `seguranca` e `hakunas` estão espalhadas na
  trilha, e são justamente as de emergência. Para as seis, rede local no
  acampamento resolve com TODAS as funções — chat, foto, prontuário — e
  não só texto curto.

  **A ordem certa é medir o sinal no local antes de comprar qualquer
  coisa.** Se houver 3G em algum ponto do acampamento, um roteador comum
  sem link próprio (R$150–400) já põe as seis equipes em rede, sem uma
  linha de código — porque o app volta a alcançar o Supabase. Servidor de
  campo é o caminho mais caro e o que depende de mais coisas darem certo.

  **Sem Bluetooth no caminho** — pedido de 12/10/2026 — a resposta está em
  `docs/radio_sem_bluetooth.md`: LoRa ligado ao celular por **USB-C
  (OTG)**, não por BLE. O cabo é mais confiável que pareamento em campo e
  **o celular alimenta o nó**, tirando a bateria do rádio da equação. O nó
  também pode criar a própria rede WiFi (ponto de acesso, sem internet).

  **A regra que decide é legal, não técnica: 915 MHz é faixa ISM livre no
  Brasil; 144 MHz (APRS/radioamador) exige licença da ANATEL.** Dá para
  mandar texto e GPS pelos rádios HT que a equipe já tem, por cabo de
  áudio e AFSK (APRSdroid, cabo de R$50–150) — mas só com habilitação de
  radioamador. Confira o tipo de rádio e se há alguém licenciado ANTES de
  comprar cabo; sem isso, o caminho honesto é LoRa.

  O resumo que importa: **não é escolha de software, é de física.** BLE e
  WiFi Direct dão 10–150 m no mato (2,4 GHz é absorvido por corpo e
  vegetação), então não servem para alarme — quem está nesse raio já viu o
  acidente. Alcance de trilha exige LoRa (R$150–400 por nó, 2–20 km) e o
  canal tem ~1–5 kbps: cabe "EMERGÊNCIA — nome — lat,lng", não cabe foto
  nem prontuário.

  **O obstáculo da parte em software não é rádio, é autoria.** A fila já é
  idempotente por `client_id` e carrega a hora do aparelho, então
  transportá-la entre celulares não corrompe nada — mas a RLS prende
  `sender_id = auth.uid()`, e o aparelho de B enviando a fila de A é
  RECUSADO. É a mesma pendência de "Troca de usuário no mesmo aparelho",
  com outro nome. Destravar exige Edge Function com `service_role` **e**
  payload assinado no aparelho de origem — sem a assinatura, qualquer um
  injeta atendimento no nome de qualquer pessoa. Em dado clínico isso não
  se improvisa.
- **Nenhum teste de hardware.** Os 573 testes cobrem lógica. NFC, câmera,
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
As três pendências abaixo são **história**: o Top 1782 vivia no projeto
`jitfbambhmfnqiatwoud`, que foi apagado. Ficam porque a armadilha que elas
descrevem se repete em qualquer Top novo — e o Top de hoje começa com a
lista inteira vazia, que é o caso extremo da primeira.

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
