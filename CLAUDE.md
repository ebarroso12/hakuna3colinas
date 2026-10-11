# Hakuna Connect

App de coordenação da equipe médica (Hakunas) dos eventos ("Tops") dos
Legendários. Rastreamento de posição em tempo real, triagem por cor,
sinais vitais, chat da equipe e NFC.

**Isto é software de apoio a atendimento médico em campo.** Triagem,
comorbidades e sinais vitais de pessoas reais passam por aqui. Erro de
cálculo ou de permissão tem consequência clínica, não só bug.

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
- **Notificação com o app FECHADO não existe.** O alarme chega em qualquer
  tela, com som e vibração (`AlarmeService` + `FaixaDeAlarme`), mas só com
  o app aberto. Push de app fechado exige FCM: projeto Firebase,
  `google-services.json` e um serviço no servidor para disparar. Para quem
  está com o app fechado, continua valendo o rádio.
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
