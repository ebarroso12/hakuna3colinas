# Registro de versões — Legendario Connect

Toda versão publicada, o que mudou e o que **não** foi verificado.

A coluna "verificado" importa: `flutter analyze` pega erro de tipo e
`flutter test` pega erro de lógica, mas **nenhum dos dois toca hardware**.
NFC, câmera, GPS com tela bloqueada e permissões só se provam em aparelho
Android físico.

---

## 11/10/2026

### v1.0.37 — dez defeitos achados por revisao, um deles grave

Rodei revisao de codigo no commit da v1.0.36. Dez achados, todos
confirmados por mim antes de corrigir. Dois merecem destaque.

#### P0 — o importador trocava o NOME pelo NUMERO, em silencio

Com o cabecalho mais comum que existe, `Nº;Nome;Familia`, o resultado era:

    nome = "12345"   numero = null   problemas = []
    colunas ignoradas: [Nome]

O numero entrava como nome da pessoa, a coluna `Nome` de verdade era
descartada, ninguem ficava com `participant_code` — e `problemas` vinha
**vazio**, entao a tela de revisao mostrava as 216 linhas como boas e ja
marcadas. Era perda silenciosa de dado de todo mundo, no primeiro uso.

A causa: casamento de cabecalho por prefixo nos DOIS sentidos.
`normalizar('Nº')` da `'n'`, o primeiro grupo de sinonimos e o de nome, e
`'nome'.startsWith('n')` e verdadeiro.

Corrigido com igualdade primeiro e depois sinonimo como **palavra
inteira**, o mais longo ganhando — o que de quebra resolve "Nome da
familia", que antes virava nome. E entrou uma rede embaixo que **nao
depende** do cabecalho ter acertado: nome composto so de digitos e
recusado, porque ninguem se chama "12345".

Sete testes novos travam isso.

#### P1 — o teste de guarda da AppBar que eu escrevi na v1.0.36 era falso

Ele procurava o primeiro `actions: [` do arquivo. Em
`top_detail_screen.dart` isso e um AlertDialog na linha 171 — a AppBar
fica 160 linhas abaixo e **nunca era medida**. Contava 4 e passava sempre.
Uma oitava acao na barra passaria batido, que e exatamente o que o teste
existia para impedir.

Reescrito com casamento de parenteses, pulando string e comentario, e
procurando `actions:` **so dentro de** `AppBar(`/`SliverAppBar(`. Agora
tem auto-teste (o contador conta o que eu digo que conta, inclusive o caso
do dialog) e eu verifiquei que ele REPROVA: com uma oitava acao
provisoria, falhou com `{top_detail_screen.dart: 8}`.

#### Os outros oito

- **Reimportar a planilha criava duplicata.** `criar` gera id novo a cada
  chamada e `(top_id, participant_code)` nao e unico; com duas fichas do
  mesmo numero, `participante_elegivel` resolve com `limit 1` e o
  autocadastro podia ligar a conta a ficha vazia enquanto comorbidade e
  alergia ficavam na outra. Agora a tela confere contra quem ja esta no
  Top (por numero e por nome), **desmarca** e escreve o motivo.
- **O dialogo prometia equipe e nao entregava.** O bloco que chamava
  `addTeamMember` dependia de `criado.linkedProfileId`, que e sempre nulo
  — codigo morto. Agora o numero da planilha e casado contra as contas que
  existem, a equipe e aplicada de verdade a quem tem conta, e quem nao tem
  aparece listado por nome como pendente.
- **Equipe/cargo nao reconhecidos deixaram de retirar a pessoa.** Viraram
  aviso. Perder nome, numero e familia de alguem porque a planilha dizia
  "Cozinha" era trocar o essencial pelo acessorio.
- **Trocar a imagem do Top mostrava a antiga.** Caminho fixo no Storage =
  URL fixa, e `ImageCache` e CDN sao indexados por URL. Agora a URL leva
  selo de versao (`?v=<enviado_em>`) e o cache da borda caiu para 60 s.
- **Trocar PNG por JPG deixava arquivo orfao** e publicamente acessivel,
  que "Apagar" nunca mais removia. O caminho perdeu a extensao; o formato
  vai no `contentType`.
- **`top_imagens` existia so no banco de producao.** Nada em `supabase/`
  criava a tabela — rebuild do schema daria uma tela que carrega para
  sempre sem erro, porque o widget engole o erro de leitura de proposito.
  Migracao escrita a partir do que esta em producao, nao de memoria:
  `supabase/top_imagens.sql`.
- **Timeout de NFC virou codigo cru na tela.** A troca de plugin tirou a
  mensagem em portugues: o caso mais comum de todos (ninguem encostou em
  30 s) aparecia como `PlatformException(408, polling tag timeout, null,
  null)`. Os sete codigos do plugin foram traduzidos para o que a pessoa
  precisa fazer.
- **Membro comum via um botao de tres pontos que nao fazia nada** (o menu
  nao tinha item nenhum para ele), e o **LIBERAR** na tela de equipes era
  `.then()` sem `await` nem `catchError` — recusa da RLS nao aparecia e o
  admin achava que havia liberado. Liberacao perdida em silencio deixa a
  pessoa sem chat e sem bloco de anotacoes.

#### Nao verificado nesta versao

Continua sem teste de hardware: NFC, camera e GPS. E o importador nunca
rodou com planilha de verdade — rodou com 32 testes, o que nao e a mesma
coisa.

---


### v1.0.36 — o NFC do app que ja roda em campo, e a AppBar que cortava botao

#### Tres botoes de admin eram invisiveis no celular

Achado antes de voce instalar, e o pior desta rodada porque nao aparece em
teste nenhum: a AppBar da tela do Top tinha **11 acoes**.

Medi em vez de estimar. Num celular de 360 dp caibem **7**; a oitava
estoura a Row por 168 px e o Flutter **corta em silencio** o que passa da
borda direita — em release nao ha aviso, nao ha faixa amarela, nao ha erro.

O que estava cortado, para o admin: **Pulseiras NFC**, **Equipes do Top** e
**Quem ve o mapa**. Os tres existiam, abriam por codigo, passavam em teste
e nao davam para tocar no aparelho. Duas dessas telas eu entreguei ontem
como funcionando.

Agora: ler a pulseira, mapa, participantes, fila e chats ficam como icone;
o resto vai para um menu com nome escrito. `test/appbar_cabe_no_celular_test.dart`
mede o teto de verdade e varre todas as telas.

#### NFC: passamos a usar exatamente o que o seu app de campo usa

Voce mandou o APK (`hakunaNFC-Oficial`). Abri: pacote `com.trixx.hakunanfc`,
Flutter, e o NFC e `flutter_nfc_kit` com `NfcAdapter.enableReaderMode`.
Troquei o nosso `nfc_manager` por ele.

Nao foi preferencia de pacote. O caminho antigo so sabia ler NDEF: cartao
em branco, cartao de outro sistema e MIFARE Classic que o chipset nao
formata voltavam todos como `null`, **indistinguiveis de "nenhuma tag foi
encostada"**. Com o aparelho na mao e a pessoa esperando, isso e a
diferenca entre trocar a pulseira e achar que o celular quebrou.

Agora o UID e o tipo do chip vem sempre, antes de olhar conteudo, e a tela
mostra `UID 04:A2:B3:C4 · mifareClassic · sem NDEF` quando nao identifica
ninguem. A leitura passou a aceitar registro de **texto** e de **URI** — o
segundo e o que qualquer outro programa de NFC gravaria para a mesma URL, e
antes era recusado como formato invalido.

**Ler a pulseira subiu para o primeiro icone** depois da saida. Estava dois
toques fundo, dentro de Participantes; e o celular que encosta no paciente.

Dito claro: **UID identifica, nao autentica.** Qualquer celular le sem
senha e se copia com hardware barato. `participant_tags.tag_uid` existe no
banco e esta vazio — usar UID como identificacao rebaixa a seguranca da
pulseira e e decisao sua, nao minha.

#### Tambem entrou

- **Importador de planilha** (CSV, XLSX, TXT delimitado), ligado no menu do
  Top. Nada grava antes de voce revisar linha por linha; da para marcar
  tudo como cadastro de teste.
- **Ate 3 imagens por Top**, estilo logo da trilha.
- **Quem ve o mapa**, pessoa por pessoa, com o terceiro estado que
  **bloqueia** quem o cargo liberaria.
- **Liberar** na tela de equipes (o metodo existia sem nenhum chamador).
- A ficha aberta pela pulseira voltou a ter **cor de triagem**: quem abria
  `LerTagScreen` sem passar as regras mostrava o participante sem cor, e a
  prioridade dele desaparecia no caminho mais rapido. Agora a tela busca as
  regras sozinha, do SQLite.

#### Nao verificado nesta versao

Nada de NFC foi testado em hardware. A troca de plugin compila e passa nos
testes de logica, mas **encostar o celular numa pulseira so se prova no
aparelho** — e e justamente o que mudou. Se a leitura falhar, e aqui que se
olha primeiro.

Push com o app fechado continua nao existindo (exige FCM). O outro app tem
Firebase Messaging; o nosso nao.

---


### v1.0.35 — a equipe HAKUNAS, alarme para todos, mapa por cargo, bloco editavel

#### A equipe de salvamento faltava no banco

Voce corrigiu: "hakuna e equipe tb, equipe de saude salvamento", e depois
"o nome dela e HAKUNAS". Conferi — `team_key` tinha 8 equipes + `geral`, e
a de salvamento **nao existia no enum**. Por isso ela nao tinha chat de
equipe nem bloco de anotacoes como as outras; so o chat clinico, numa
tabela separada.

Com `hakunas` fecham os 9 times que voce disse, e `geral` e o canal.

Erro meu no caminho: eu adicionei `saude` por conta propria antes de voce
dizer o nome. Corrigi com `RENAME VALUE` em vez de adicionar o certo e
deixar o errado — valor orfao num enum reaparece em todo dropdown e em
toda migracao futura.

#### Alarme: todos disparam e recebem

Antes exigia ser Hakuna liberado nas duas pontas, e a seguranca — cuja
funcao e exatamente isso — ficava de fora. Agora e `pertence_ao_top()`:
membro liberado de qualquer equipe, Hakuna liberado, ou admin. Nao e
"qualquer pessoa logada".

#### Mapa: por cargo, com o admin sobrepondo pessoa por pessoa

Regra automatica: admin, Hakuna liberado, coordenacao/subcoordenacao de
qualquer equipe, e membros de `seguranca` e `hakunas`.

Mais restrito que o alarme **de proposito**: alarme e emergencia, posicao e
vigilancia continua. 200 pessoas vendo a localizacao de todas as outras nao
e necessario para midia, producao ou intercessao trabalharem.

E `top_permissoes` sobrepoe, com TRES estados: sem linha vale a regra;
`ver_mapa = true` libera quem a regra nao liberaria; `ver_mapa = false`
**bloqueia quem a regra liberaria**. O terceiro e o que faz ser "editar" e
nao so "conceder" — sem ele, tirar o mapa de um coordenador exigiria
rebaixa-lo de cargo. So admin escreve nela.

Provado com sessao simulada, quatro usuarios liberados:

```
MIDIA (membro) dispara alarme       -> conseguiu
MIDIA recebe alarme                 -> 1
MIDIA (membro) ve posicao de outro  -> 0
SEGURANCA (membro) ve posicao       -> 1
COORDENADOR de midia ve posicao     -> 1
LOGISTICA (membro) ve posicao       -> 0
LOGISTICA apos admin LIBERAR        -> 1
COORDENADOR apos admin BLOQUEAR     -> 0
MIDIA ve a PROPRIA trilha           -> 1
```

#### Bloco de anotacoes: editavel, um por membro

Voce apontou que o meu medo de perda de texto nao se aplica: cada membro
tem login proprio e o bloco e dele, entao nao ha duas pessoas editando o
mesmo. Estava certo, e troquei de append-only para editavel.

**Mas trocar abriu um buraco de verdade, em duas camadas.** `Outbox.enqueue`
usa `ConflictAlgorithm.ignore`: reenfileirar o mesmo `client_id` DESCARTA o
segundo pedido. Isso e certo para atendimento (append-only) e catastrofico
aqui — a segunda edicao offline seria jogada fora sem erro nenhum na tela.
Criei `enqueueSubstituindo`.

E ai um teste pegou a segunda camada: `client_id` tem indice UNICO, entao
depois que o bloco sobe a linha CONTINUA na tabela, e um `enqueue` novo
tambem era ignorado. **Toda edicao feita apos o primeiro envio
desaparecia.** `enqueueSubstituindo` passou a mexer na linha em qualquer
estado, devolvendo-a a fila.

Os dois niveis tem teste em `test/offline/enqueue_substituindo_test.dart`.

#### Divida latente no banco local, achada pelo mesmo teste — schema v4

`client_id` era unico GLOBALMENTE no outbox, nao por entidade. Com uuid
aleatorio a colisao nunca aconteceria; o bloco usa `client_id`
DETERMINISTICO em texto (`top|team|autor|-`), e ai deixou de ser
hipotetico: uma escrita de outra entidade com o mesmo id fazia a anotacao
ser descartada em silencio. Agora e unico por `(entity, client_id)`,
migracao v3 -> v4 com teste.

#### Top de Franca cadastrado

`Comemoração de 1 ano`, Franca, 26 a 29/11/2026. Nasce em **draft** de
proposito: e a trava que impede alguem se cadastrar antes de voce terminar
de montar. `diretor_responsavel` e `top_number` ficaram NULOS — quem define
o responsavel e o numero de um evento e voce.

#### Verificado

`analyze` limpo em modo estrito, **380 testes**. Tres guardas antigas
quebraram e fizeram o trabalho delas: a que fixava os valores do enum
`team_key`, a que fixava 8 equipes e as de migracao que fixavam o schema
v3. Todas atualizadas com o motivo escrito.

**Nao verificado em aparelho**: nada.

### v1.0.34 — o app e dos 9 TIMES: anotacoes das equipes, trava do autocadastro e marcacao de teste

#### Correcao de premissa minha, e ela era de fundo

Tratei o app como "da equipe medica (Hakunas)" a sessao inteira. Estava
errado, e a origem era o proprio `CLAUDE.md`, que abria com isso. O app e
dos **Legendarios** — das 9 equipes. Conferido no banco:

```
team_key  = adm, logistica, voz, intercessao, producao, midia,
            eventos, seguranca, geral   (9)
team_role = coordenador, subcoordenador, membro
user_role = admin, hakuna, senderista
```

`hakuna` NAO e equipe, e papel. `geral` nao e equipe, e o canal que todo
aprovado enxerga — dai `TeamKeyUi.equipes` devolver 8. O app ja tinha as 9
com chat, cor e icone proprios; o erro era meu, de leitura e de
documentacao. `CLAUDE.md` reescrito com as tres dimensoes numa tabela.

#### Bloco de anotacoes das equipes (novo)

A diferenca entre Hakuna e as outras equipes e que o Hakuna tem
PRONTUARIO. As outras 8 precisavam do equivalente nao-medico, e agora tem:
um bloco de texto que salva, aberto do lado do chat de cada equipe.

Dois usos no mesmo modelo: **sobre uma pessoa** (abrindo da ficha) ou
**sobre o turno** (abrindo da equipe).

APPEND-ONLY, e isso e decisao, nao limitacao. Um bloco unico editavel
offline PERDE TEXTO: duas pessoas da mesma equipe editam sem sinal e a
ultima a sincronizar sobrescreve a outra, sem aviso. Com registros
separados nada se perde, e fica rastreavel quem anotou o que e quando —
numa ocorrencia de seguranca isso e metade do valor. Para corrigir,
escreve-se outra. Se preferir o bloco unico, e trocavel, mas o risco de
perda passa a existir.

Funciona sem rede, como tudo que se escreve em campo. O que esta esperando
sinal aparece na lista, marcado.

**A tela avisa, FIXO em cima do campo, que ali nao se escreve sintoma,
pressao nem conduta** — isso vai no atendimento. Sintoma escrito na
anotacao fica fora da triagem e invisivel para quem vai atender. E o erro
mais provavel desta tela e o mais caro, entao o aviso nao e um dialogo que
se dispensa.

Provado com sessao simulada (dois usuarios, um em `seguranca` e um em
`midia`, ambos liberados):

```
seguranca liberada anotou     -> OK
reenviado 2x gravou N linhas  -> 1
anotar no NOME de outro       -> bloqueado pela RLS
anotar em EQUIPE alheia       -> bloqueado pela RLS
seguranca LE a propria        -> 1
midia LE a da seguranca       -> 0
```

A primeira tentativa desse teste FALHOU, e o motivo vale saber:
`is_team_member` exige `released = true AND blocked = false`. **Estar na
equipe nao basta — o admin tem de LIBERAR cada membro**, igual aos
Hakunas. Sem isso nem chat nem anotacao funcionam para a pessoa.

#### Trava do autocadastro por Top

CORRECAO DE PREMISSA: "a senha teste e somente teste" nao era verdade.
`Top000000` e a senha de PRODUCAO do Top 1782 — o `access_code_hash` do
Top real — e vale para os 72 senderistas que tem numero. Nao existia senha
de teste separada.

A senha do Top e COMPARTILHADA e anunciada ao grupo: circula em WhatsApp,
cartaz e voz. Depois que a equipe se cadastrou ela continua valendo, e nao
deveria. A unica forma de fechar era gerar outra senha — invalidando a que
todos anotaram, por efeito colateral.

Agora ha um interruptor na tela do Top. Fechar nao apaga a senha: ela
volta a valer ao reabrir. `gerar_senha_top` abre a trava junto (gerar
senha e querer que gente se cadastre).

Validado contra a funcao em producao, nos DOIS passos — travar so o passo 1
nao bastaria, porque `cadastrar` revalida por conta propria e alguem
poderia pular direto para ele:

```
trava fechada + senha CERTA, validar_convite -> recusado
trava fechada + senha CERTA, cadastrar       -> recusado
reaberto -> volta a liberar; contas criadas na tentativa: 0
```

#### Marcacao de cadastro de teste

Antes o unico sinal era o nome em caixa alta ("TESTE AUTOCADASTRO (apagar
depois)") — e nome nao e dado, nao serve de critorio de exclusao. Agora
`is_teste` em `top_participants` e em `profiles`, com:

- interruptor no TOPO do formulario, antes de qualquer campo. No fim
  ninguem veria, e errar e assimetrico nas duas direcoes.
- selo TESTE na lista, no subtitulo e nao no nome (o nome e o que se busca).
- botao "apagar cadastros de teste", so para o admin master, listando nome
  por nome antes de confirmar.
- a marca PROPAGA para a conta criada no autocadastro: quem se cadastra
  com numero de teste cria uma conta, e ela tambem precisa sair depois.

Teste que RECEBEU atendimento nao e apagado: `participant_id` e SET NULL e
o prontuario ficaria orfao.

#### Falha ESTRUTURAL corrigida no AndroidManifest

Faltava `<queries>` com intent de VIEW para http/https. A partir do Android
11 (API 30) um app nao resolve intents de outros apps sem declarar o que
consulta, e este tem `targetSdk 36`. **O botao ATUALIZAR que eu entreguei
na v1.0.30 como funcionando nao abriria nada no aparelho.** Nenhum teste de
unidade pega isso: nao existe Android num teste de unidade.

#### Teste que prova que o app ABRE

Os testes anteriores provavam logica isolada e nenhum montava o widget
raiz — um erro na montagem do `MaterialApp` passaria por todos e so
apareceria no celular, como tela branca. `test/o_app_abre_test.dart` monta
`HakunaConnectApp` de verdade e verifica que a arvore sobe, que o
`navigatorKey` esta instalado e que a tela de login aparece.

Nao prova que o APK instala, que o NFC le, que o GPS funciona com a tela
bloqueada nem que o som toca. Nada disso se verifica sem aparelho.

#### ACHADO ESTRUTURAL NAO CORRIGIDO — precisa da sua decisao

Num app de 9 equipes, GPS e ALARME estao restritos a Hakunas. Conferido
nas policies:

| Funcao | Quem pode hoje |
|---|---|
| chat das equipes | membro liberado da equipe — **correto** |
| atendimento, prontuario, chat clinico | Hakuna liberado — **correto** |
| `hakuna_positions` SELECT | **so Hakuna** — seguranca nao ve o mapa |
| `hakuna_positions` INSERT | qualquer um publica a propria posicao |
| `top_alerts` INSERT e SELECT | **so Hakuna** — seguranca nao dispara nem recebe alarme |

Disparar alarme e literalmente a funcao da seguranca, e ver o mapa e a da
logistica. Mas abrir o GPS para as 9 equipes significa mais gente vendo a
localizacao de todos — e isso e decisao de privacidade do movimento, nao
minha. **Nao alterei por conta propria.**

#### Verificado

`analyze` limpo em modo estrito, **366 testes** (15 novos das anotacoes),
trava provada contra a funcao em producao, RLS das anotacoes provada com
sessao simulada e revertida.

**Nao verificado em aparelho**: nada. Zero minutos de uso real.

### v1.0.33 — apagar com selecao nome a nome, botao voltar em toda tela, e ficha offline

Tres pedidos nesta versao, e um deles destravou um defeito grave.

#### Apagar usuarios e senderistas, marcando nome a nome

Toque e segure um nome na lista de Usuarios ou de Participantes e entra o
modo de selecao, com checkbox por nome. Com a busca ativa, "marcar todos"
pega so os filtrados — e isso e de proposito: marcar os 216 a partir de uma
tela filtrada seria o jeito mais facil de apagar o Top inteiro achando que
se apagou tres nomes. Teto de 50 por vez.

So o admin master ve e usa. Apagar pessoa de um evento medico nao e
operacao de rotina.

**DOIS ACHADOS NO BANCO, ANTES DE ESCREVER A TELA:**

1. `atendimentos.opened_by` era `ON DELETE CASCADE`. Apagar um Hakuna
   **APAGARIA TODOS OS ATENDIMENTOS QUE ELE REGISTROU** — um clique de
   limpeza de cadastro destruindo prontuario de dezenas de pessoas, em
   silencio e sem volta. Se eu tivesse escrito a tela antes de olhar isso,
   o recurso teria saido pronto para destruir dado clinico. Hoje e
   `RESTRICT`.

2. `top_participants` nao tinha **nenhuma** policy de DELETE. Ninguem
   conseguia apagar senderista, nem o admin — e nao era protecao pensada,
   era ausencia.

A regra que ficou: **apaga quem nao deixou rastro clinico; quem deixou,
desativa.** O dialogo lista nome por nome quem sai e quem fica, com o
numero ("3 atendimentos no prontuario"), e oferece Desativar para os
bloqueados — tira das listas e mantem o historico inteiro. Mostrar so
"nao foi possivel" faria o admin tentar de novo; pior, apagar o que der e
avisar depois faria ele nao saber que 4 dos 30 ficaram.

Provado com sessao simulada, revertida depois:

```
quem registrou atendimento pode_apagar       -> false
delete do perfil com atendimento             -> bloqueado pelo RESTRICT
atendimentos que sobreviveram                -> 1
perfil sem rastro pode_apagar                -> true
apagando auth.users, o profile cai em cascata-> true
dos 3 senderistas, podem ser apagados        -> 2
prontuario apos desativar                    -> 1 (preservado)
```

Usuario passa pela Edge Function e senderista nao, e a razao e concreta:
`profiles.id` referencia `auth.users(id) ON DELETE CASCADE`. Apagar o
perfil pelo app **nao** apaga a conta de autenticacao — sobra um orfao que
continua logando e cai num app sem perfil, numa tela de erro sem saida.
Era o que `AdminService.deleteProfile` fazia. O caminho certo e apagar o
`auth.users`, e isso exige `service_role`, que nunca pode estar no APK.

**Apagar e a unica coisa do app que nao funciona offline, e por decisao.**
Uma exclusao enfileirada as 9h e executada as 16h pode apagar alguem que
foi atendido as 11h. Entao sem rede ela falha e **diz por que** nao fica
guardada para depois, em vez de mostrar `SocketException`.

#### Botao voltar e voltar ao inicio em toda tela

`BotaoInicio` entrou nas 26 telas internas, no `actions` do AppBar. Fica ao
lado da seta de voltar, nao no lugar dela: sao saidas diferentes. A seta
devolve um passo, e Top -> participantes -> ficha -> prontuario ->
atendimento sao cinco toques para sair.

`test/toda_tela_tem_saida_test.dart` le o codigo-fonte das telas e falha se
alguma ficar sem o botao — ou se alguem puser `leading:` proprio no AppBar,
que foi como a logo ja prendeu a tela de detalhe do Top uma vez. Para
isentar uma tela, ha uma lista no teste onde se escreve o motivo.

Nas telas de selecao a barra entra como `bottom` do AppBar, nao no lugar do
titulo: numa tela que apaga gente, a saida nao pode desaparecer.

#### Ficha de participante agora funciona sem sinal

Achado ao conferir o reforco da regra offline: o formulario de participante
gravava **direto no Supabase**, e e aberto de duas telas de campo. Sem
sinal, o Hakuna digitava a ficha inteira de alguem no mato — nome,
comorbidade, alergia, tipo sanguineo — tocava em salvar e recebia uma
mensagem tecnica. O dado nao ia para lugar nenhum.

Mesma falha do alarme e dos sinais vitais, na terceira tela. Agora grava no
cache local (aparece na lista na hora, com ou sem rede) **e** enfileira. O
`id` vem do aparelho, entao o cadastro offline ja tem identidade: da para
abrir a ficha, registrar atendimento e emitir pulseira antes de ter rede.

`criarParticipante` e `atualizarParticipante` foram **removidos** de
`SupabaseService` — nao basta parar de usar, tem de sair do caminho.

**E um bug que eu quase deixei passar.** A primeira versao usava
`upsert(onConflict: 'id')` para cadastro E edicao, removendo
`registered_by` na edicao (a autoria e de quem cadastrou primeiro). Nao
funciona: `INSERT ... ON CONFLICT DO UPDATE` tenta o INSERT primeiro e bate
no `NOT NULL` de `registered_by` com erro 23502, que `_motivoPermanente`
classifica como PERMANENTE. **Toda edicao de ficha iria para quarentena e
nunca subiria.** Os testes Dart passavam — eles nao tocam o servidor. Quem
pegou foi o teste no banco:

```
7. upsert sem registered_by -> 23502 - iria para QUARENTENA
```

Corrigido: cadastro e `upsert`, edicao e `update().eq('id', ...)`.

#### Correcao de um erro meu, grave, em producao

Durante esta sessao eu chamei o deploy da Edge Function `acesso` passando
`"content": "PLACEHOLDER"` em vez do arquivo. Isso **substituiu a funcao em
producao por essa string** por alguns minutos (versao 6). Enquanto esteve
assim, autocadastro, liberar por codigo e gerar senha do Top estavam fora
do ar.

Restaurada na versao 7 a partir do arquivo do repositorio, que estava
intacto, e conferida com chamadas reais: senha errada recusa, senha certa
libera o cadastro, `apagar_usuarios` exige login. Nenhum dado foi perdido —
a funcao nao guarda estado. Registro aqui porque o erro foi meu e aconteceu
em producao.

#### Verificado

`analyze` limpo em modo estrito, **347 testes** (25 novos). Prova no banco
com RLS valendo e sessao simulada, revertida (conferido: 216 senderistas
intactos, zero atendimento, zero tabela de teste).

**Nao verificado em aparelho**: o toque longo entrando no modo de selecao,
o cadastro de ficha com o aviao ligado, o som do alarme, camera, NFC e GPS
com tela bloqueada.

---

## 10/10/2026

### v1.0.32 — a mesma revisao, com um defeito que o CI pegou

A v1.0.31 **nao gerou APK**: o CI falhou nos testes e a esteira para antes
de buildar, de proposito. Esta versao e a v1.0.31 com essa correcao.

O defeito valia o atraso. `clientIdDaFoto` usava
`p.basenameWithoutExtension`, e o `package:path` escolhe o estilo de
caminho pelo sistema onde o Dart esta rodando. No Windows desta maquina o
teste passava; no Linux do runner, `\` nao e separador e a funcao
devolvia o caminho do Windows INTEIRO como se fosse o nome do arquivo.
Isso viraria um `client_id` invalido, recusado por tipo no Postgres,
classificado como PERMANENTE e mandado para quarentena — a foto clinica
nao subiria.

Na pratica o app roda em Android (POSIX) e funcionaria. Mas a correcao de
um `client_id` nao deve depender de em qual sistema o codigo executa:
agora corta nos dois separadores a mao, e o teste verifica os dois.

E o registro honesto: foi o CI que achou, nao eu. Rodar `flutter test`
local nao bastava, porque o ambiente local era justamente o que escondia o
problema.

### v1.0.31 — revisao completa: 8 defeitos corrigidos e 4 faltas preenchidas

Varredura das 35 telas, 25 servicos e 22 models, cruzada com o banco.
Nenhuma pagina em branco: todas as telas renderizam conteudo real e tem
texto de estado vazio. O que havia eram defeitos de INTEGRACAO — nada que
`flutter analyze` ou teste de unidade pegasse sozinho.

Raciocinio completo em `supabase/revisao_completa_correcoes.sql`.

#### O pior: o alarme nao tinha fila

`sendTopAlert` era `insert` direto no Supabase. Sem sinal — o estado
normal na trilha — falhava, a tela dizia "nao foi possivel disparar o
alarme" e o registro era **descartado**. Atendimento, foto, posicao, chat e
auditoria todos passavam pela fila offline. O alarme, nao. Justamente ele,
que e usado em acidente.

E o recebimento era pior: o alarme so existia como faixa dentro da tela de
detalhe do Top. Quem estivesse na lista de participantes, no chat, ou com o
celular no bolso **nao recebia nada** — sem som, sem vibracao.

Agora: entra na fila com `client_id` e com a hora do APARELHO (offline o
acidente acontece horas antes do upload), chega em QUALQUER tela por um
overlay acima do Navigator, com tres toques de vibracao e som do sistema. A
assinatura e uma so, sem filtro de Top — a RLS ja limita aos Tops em que a
pessoa e Hakuna liberado, e filtrar era o que causava o defeito.

A mensagem na tela passou a dizer a verdade: "alarme GRAVADO e aguardando
sinal, use o radio" quando esta na fila, em vez de "disparado".

**Continua sem**: notificacao com o app FECHADO. Exige FCM (Firebase,
`google-services.json`, servico no servidor). Para quem esta com o app
fechado, vale o radio.

#### Sinais vitais: perdidos offline E fora da triagem

`recordVitalSigns` tambem ia direto. Offline a medicao era perdida e nao
aparecia nem na fila: o Hakuna media a pressao, via "registrado" e o dado
nao existia em lugar nenhum.

Pior que a perda, a incoerencia clinica: `TriageDinamica` escala a cor para
vermelho a partir de `cache_ultima_afericao`, alimentada so por
`AtendimentoService`. Entao SpO2 85 medido no formulario de ATENDIMENTO
pintava a pessoa de vermelho, e o MESMO 85 medido na tela de SINAIS VITAIS
nao pintava nada. Duas portas para a mesma medida, uma funcionando.

Agora as duas vao pela fila e as duas alimentam o cache. A tela mostra o
que esta esperando sinal, separado do historico do servidor.

#### Da segunda foto em diante, a linha era descartada

Todas as fotos subiam com o `client_id` do ATENDIMENTO — o mesmo para
todas. Como `atendimento_fotos.client_id` e unico e o envio usa
`ignoreDuplicates: true`, o arquivo ia para o Storage e a LINHA era
ignorada em silencio. Foto clinica orfa: bytes no servidor que nenhuma
consulta alcanca.

O identificador por foto JA EXISTIA no codigo, no nome do arquivo, e nao
era levado ao payload. E esse nome tinha um bug proprio: era
`'<atendimento>-${n+1}'` com n = fotos na tela, entao remover uma foto e
tirar outra repetia o numero e o `File.copy` **sobrescrevia** a anterior.

Agora e um uuid por foto, usado nos dois lugares. Provado no banco: duas
fotos do mesmo atendimento gravam **2 linhas**.

#### Nenhuma tela exibia as fotos

Nada em `lib/screens/` lia `atendimento_fotos`. A camera gravava, a fila
subia, o Storage guardava — e nao havia como rever. Em registro de ferida
isso e metade do atendimento jogada fora.

O prontuario passa a mostrar miniaturas, com toque para ampliar e zoom. Do
servidor por URL assinada de 1 hora (o bucket e privado e continua: foto de
ferida e dado clinico); o que esta na fila vem do arquivo local e
**funciona sem rede**, que e quando mais importa.

#### Atendimento nunca fechava

`status` vinha so do default da coluna e `closed_at` nunca era escrito.
Todo atendimento ficava `aberto` para sempre; numa lista de 30 nao se
distinguia quem ainda precisava de atencao.

Agora da para encerrar, pela fila (funciona offline), gravando quem e
quando. Coluna nova `closed_by`: sem ela `closed_at` diz que fechou mas nao
quem, e em prontuario isso nao serve.

Achado no caminho: a policy de UPDATE **nao tinha WITH CHECK**, e sem ele o
Postgres reaproveita o USING — um Hakuna liberado podia gravar `closed_by`
com o id de OUTRA pessoa, assinando o fechamento no nome de um colega.
Corrigido e provado com sessao simulada de Hakuna comum (nao admin):

```
assinar no nome do colega  -> bloqueado pela RLS
assinar no proprio nome    -> permitido
```

Os outros 7 estados (`a_caminho`, `no_local`, ...) seguem sem uso **por
decisao**: formam um fluxo de despacho que precisa de painel de coordenacao
e regra de atribuicao. Meio-implementado seria pior que ausente — estado
que ninguem atualiza mente sobre a situacao do paciente.

#### Prontuario cego sem rede

Lia os atendimentos direto do Supabase, contra a regra do projeto. E o
contador de pendentes era lido DEPOIS da chamada de rede, no mesmo `try`:
quando a rede falhava, o `catch` engolia tudo e o Hakuna nao via nem o
historico nem o atendimento que ele mesmo tinha registrado cinco minutos
antes. Agora o que esta no aparelho e lido primeiro e fora do try da rede.

#### `audit_log` nao registrava edicao de ficha

`AcaoAuditada.fichaAlterada` existia no enum e NADA no app a usava. Alterar
comorbidade, tipo sanguineo ou alergia de um paciente nao deixava rastro.
Agora registra, com os NOMES dos campos que mudaram — nunca os valores:
`audit_log` e legivel por qualquer admin, e copiar comorbidade e alergia
para la criaria um segundo prontuario com regra de acesso mais frouxa que o
primeiro.

#### "Quem esta mais perto?" nao tinha resposta

Havia GPS dos Hakunas, havia alarme com coordenada, e nada cruzava os dois.
Agora o alarme tem um botao que lista os Hakunas por distancia.

Duas limitacoes ficam DITAS na tela, nao escondidas: a distancia e em linha
reta (a trilha e sempre mais longa) e a idade da posicao aparece ao lado do
numero, porque "250 m" de um ponto de 40 minutos atras e ficcao. Ponto com
mais de 2 horas e descartado em vez de mostrado com ressalva. E usa a
ULTIMA posicao de cada um, nao a mais proxima da trilha — senao diria que
alguem esta a 50 m porque passou ali de manha.

#### Analisador em modo estrito

`strict-casts`, `strict-inference` e `strict-raw-types` ligados. Pegou de
imediato um `dynamic` passando para `.eq()` no codigo novo — e e o mesmo
tipo de passagem silenciosa que quase deixou um `VitalSigns.fromMap` com
`map['id'] as int` rodar sobre um payload de fila que nao tem `id` (esse eu
peguei lendo, nao o analisador). 35 `MaterialPageRoute` sem argumento de
tipo tambem foram corrigidos.

#### Divida de tipo paga

`client_id` era `text` em `atendimentos`/`atendimento_fotos` e `uuid` nas
outras. Convertido agora porque as tabelas estao vazias; depois do evento
nao seria seguro.

Verificado: `analyze` limpo em modo estrito, **322 testes passando** (35
novos). Provado no banco com RLS valendo e sessao simulada, tudo revertido
depois (conferido: zero linhas em atendimentos, alarmes, vitais, auditoria).

**Nao verificado em aparelho**: o som e a vibracao do alarme, a camera, o
NFC, o GPS com tela bloqueada e o `launchUrl` do botao Atualizar.

### v1.0.30 — versao na gaveta e botao "Atualizar"

Pedido que estava em aberto: "mostre na lateral a versao que esta no
momento; caso esteja desatualizado, crie o botao Atualizar".

A versao instalada vem de `lib/versao.dart`, duas constantes compiladas
dentro do APK. Nao entrou `package_info_plus`: ele nao responderia nada
melhor, porque o que interessa e a versao DESTA build, e ela esta no
binario. O preco e a duplicacao com o `pubspec.yaml`, travada por
`test/versao_bate_com_pubspec_test.dart` — divergencia falha no CI antes
de gerar o APK.

A versao publicada vem da tabela nova `app_versions` (leitura para quem
esta logado, escrita so de admin). A comparacao e pelo `build_number`,
nunca pelo texto: em ordem lexicografica "1.0.9" e maior que "1.0.10", e
o app diria que esta em dia estando atras. Ha teste com esse par exato.

Consulta sem rede devolve `null`, e `null` e tratado como **"nao sei"**:
a gaveta diz que nao deu para verificar, em vez de afirmar que esta
atualizado. Era o jeito facil de errar — na trilha o app passa a maior
parte do tempo sem sinal, e um "voce esta na ultima versao" inventado
nessas horas e pior que nao dizer nada.

O botao abre o link do APK no navegador; nao instala. Instalacao
silenciosa exigiria Play Store, e o app e distribuido por "fontes
desconhecidas". O APK fica no Drive, que e para onde `apk_url` aponta —
o Release do GitHub nao serve porque o repositorio e privado e o link
exigiria conta no projeto.

Verificado: `analyze` limpo, 284 testes passando na tag, 14 novos (4 da
gaveta, 8 do servico, 2 do guarda de versao). Mais 3 testes de
`AppLogoAbreGaveta` entraram depois da tag (287 no total em `main`); eles
provam, contra este mesmo codigo, que tocar na logo abre a gaveta — a
falha seria o recurso existir e ser inalcancavel, porque o `Scaffold` so
desenha o hamburguer quando `leading` e nulo.

**Nao verificado em aparelho**: o `launchUrl` saindo para o navegador do
Android e a instalacao do APK baixado.

### Correcao de um fato que o CLAUDE.md afirmava errado

O arquivo dizia, em presente, que o CI assina com chave de debug aleatoria
por build, e que por isso atualizar por cima falha. Conferi com
`apksigner verify --print-certs` nos cinco APKs do Drive:

```
1.0.18  CN=Android Debug        SHA-1 AB24D950...AC05AC
1.0.19  CN=Android Debug        SHA-1 E882B41E...4CFF11
1.0.23  CN=Legendarios Connect  SHA-1 0B992313...1D4B88
1.0.28  CN=Legendarios Connect  SHA-1 0B992313...1D4B88
1.0.29  CN=Legendarios Connect  SHA-1 0B992313...1D4B88
```

Da v1.0.23 em diante a chave e a de producao e **a mesma**. Atualizar por
cima funciona entre essas versoes, e o SQLite local sobrevive. O aviso que
eu havia escrito na gaveta ("pode exigir desinstalar, e desinstalar apaga
a fila") estava desatualizado e foi reescrito: o texto agora diz que
instala por cima e mantem os dados, e so menciona a desinstalacao como o
que fazer SE o Android recusar.


### v1.0.23 — corrige a decodificação do keystore no CI

A build da v1.0.21, a primeira com chave de produção, falhou com
`base64: invalid input`. Causa: o secret foi gravado canalizando pelo
PowerShell, que injeta CRLF no stdin, e o `base64 -d` do GNU recusa `\r`.
O arquivo local estava correto — quem corrompeu foi o cano.

O workflow deixou de confiar no formato do secret: limpa CR, quebra de
linha e espaço antes de decodificar, e **valida o keystore com keytool**
antes de começar o build. Secret errado falha no segundo passo dizendo
qual conferir, em vez de estourar 8 minutos depois dentro do Gradle.

### v1.0.22 — branding "Legendario Connect" e ícone nativo

Nome de exibição, título do app e nome do pacote Dart renomeados.
`applicationId` **não** mudou (`com.legendarios.hakuna_connect`): mudá-lo
cria um app diferente para o Android — instalação nova e dados locais
apagados.

Ícone adaptativo novo. Quatro correções na especificação recebida, cada
uma das quais quebraria o build ou o visual:

| Problema | Consequência |
|---|---|
| `xmlns:android="http://android.com"` | namespace errado, aapt2 ignora tudo |
| `<circle>` | não existe em VectorDrawable |
| anel com raio 40 em viewport 108 | cortado pela máscara do sistema |
| fundo dentro do foreground, em `drawable/` | camada e pasta erradas |

PNGs legados gerados para Android 7− (o `minSdk` é 21), mais as versões
redondas e `android:roundIcon` no manifest.

### v1.0.21 — número do Legendários validado no cadastro

O campo já existia e era obrigatório; faltava validação. Dava para se
cadastrar com `12` ou `abc`, e então o admin **nunca** conseguiria liberar
essa pessoa — a Edge Function exige `^[0-9]{4,10}$` e recusaria em
silêncio. Passa a usar `AcessoService.numeroValido`, o mesmo validador da
tela de login. Número duplicado deixou de devolver
"Database error saving new user".

### v1.0.20 — diagnóstico do Google Sign-In no APK

Lendo o APK Signing Block dos próprios arquivos publicados:

```
legendarios1.0.18.apk  SHA-1 AB24D950BC3280D8E391943DE9FD026B32AC05AC
legendarios1.0.19.apk  SHA-1 E882B41E837A8CAC67944CF168585249474CFF11
```

Ambos `CN=Android Debug` e **diferentes**: o runner do GitHub Actions gera
um keystore novo a cada execução. Duas consequências:

1. **Login com Google nunca funciona** nesses APKs — o Google exige client
   OAuth Android registrado com pacote + SHA-1, e o SHA-1 muda sempre.
   Falha com `DEVELOPER_ERROR` antes de qualquer chamada de rede
   (confirmado: zero eventos nos logs do Auth no período).
2. **Atualizar por cima falha** (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`), e
   desinstalar **apaga o SQLite local** — ou seja, apaga atendimento
   enfileirado que ainda não subiu.

Não é problema de `clientId`: a configuração já estava certa. O erro do
plugin deixou de chegar cru na tela.

### v1.0.19 — a fila não trava mais

Bug introduzido na v1.0.18 ao enfileirar o chat. O `SyncService` parava no
primeiro erro — certo para queda de rede, catastrófico para recusa
definitiva: a próxima rodada relê a fila na mesma ordem e trava na mesma
entrada, prendendo atendimento, GPS, foto e auditoria atrás de uma
mensagem.

Não era hipótese: o Top 1782 está em `draft`, e a RLS de `team_messages`
recusa mensagem no chat geral enquanto for draft.

Recusa definitiva passa a ir para **quarentena** e o sync segue. Quarentena
não apaga e é visível em `FilaOfflineScreen`, com "Devolver à fila".
`purgeSynced` tinha teste e nunca era chamado em produção — a fila crescia
sem fim.

### v1.0.18 — paginação, auditoria offline, fila do chat e QR

- **Edge Function**: `listUsers()` parava na primeira página de 50. A
  correção não foi paginar (continuaria O(n) em requisições) e sim usar o
  índice único de `profiles.legendarios_number`. Achei também que
  `liberar 203460` estava quebrado por outro motivo, e que corrigi-lo
  sobrescreveria a senha do Gmail do admin — agora exige confirmação.
- **Auditoria**: a leitura de tag chamava o Supabase dentro de um
  `try/catch` vazio. Sem sinal, a leitura feita no mato não deixava rastro
  nenhum. Agora vai para a fila.
- **Chat**: `insert` direto virou outbox, com deduplicação por `client_id`.
- **QR Code**: contingência do NFC, com o **mesmo token** de 128 bits —
  revogar a pulseira revoga o QR no mesmo ato.

### v1.0.17 — cache de leitura em SQLite e triagem dinâmica

- Leitura de tag e lista de participantes passam a vir do **disco**. Antes
  o cache era um `Map` em memória, e a função que o populava **não era
  chamada por lugar nenhum**.
- `TriageDinamica` escala para vermelho com SpO₂ < 90, PAS > 180 ou
  PAD > 110. Antes, PA 190x120 e SpO₂ 88% ficavam **verdes** na lista.
- Rastreamento deixou de morrer em silêncio no primeiro soluço do GPS.

---

## Infraestrutura criada hoje (fora do repositório)

| O quê | Onde | Observação |
|---|---|---|
| Keystore de produção | `C:\hakunas\keystore\legendarios-release.jks` | RSA 2048, válido até 2054. **Perder é irreversível** |
| Senha do keystore | `C:\hakunas\keystore\SENHA-NAO-COMPARTILHAR.txt` | nunca passou por conversa |
| SHA-1 do certificado | `0B:99:23:13:83:2C:54:BE:2A:0C:B3:ED:0F:DE:56:11:44:1D:4B:88` | registrar no Google Cloud |
| JDK 17 (Temurin) | `C:\Program Files\Eclipse Adoptium` | mesma versão do CI |
| Android SDK | `C:\Android` | build-tools 36.0.0, platform-tools, android-36 |
| APKs baixados | `C:\hakunas\apks` | |
| APKs no Drive | `Meu Drive / Legendarios APK` | privado; falta compartilhar com a equipe |

---

## Pendente — depende de ação fora do código

1. **Registrar o SHA-1 no Google Cloud** como client OAuth Android, pacote
   `com.legendarios.hakuna_connect`. Sem isso o Google Sign-In não
   funciona, e número + senha segue sendo o caminho.
2. **Guardar cópia do keystore fora desta máquina.**
3. **Ativar o Top 1782** (está em `draft`): a RLS recusa toda mensagem do
   chat geral enquanto estiver.
4. **Compartilhar a pasta do Drive** com a equipe.
5. **Testar em aparelho Android físico.** Nenhuma das sete versões de hoje
   rodou em hardware.
