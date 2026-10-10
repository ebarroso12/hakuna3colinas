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

`busca_normalizada` e `familia_normalizada` são colunas derivadas,
gravadas por `TextoBusca` no momento do cache. Não compare contra
`full_name` ou `familia` crus: `"joao"` não acha `"JOÃO"`.

### A fila nunca pode travar
`SyncService` para no primeiro erro **transitório** — certo para queda de
rede. Mas recusa definitiva do servidor (RLS, dado inválido, esquema
incompatível) vai para **quarentena** e a sincronização **segue**.

Sem isso, uma entrada recusada bloqueia tudo que está atrás dela para
sempre: a próxima rodada relê a fila na mesma ordem e trava na mesma
entrada. Cenário vivo: o Top 1782 está em `draft`, e a RLS de
`team_messages` recusa mensagem no chat geral enquanto for draft — uma
mensagem prenderia atendimento, GPS, foto e auditoria.

Quem classifica é `SupabaseService._envioDaFila`, porque é lá que os tipos
do Postgrest existem. **Na dúvida, classifica como transitória**: descartar
dado clínico é pior que atrasar. `SyncService.maxTentativas` é a rede de
segurança para o erro mal classificado.

Quarentena **não apaga** e é visível em `FilaOfflineScreen` (ícone de nuvem
na tela do Top, com badge). Entrada que sai da fila sem ninguém saber é
perda silenciosa — pior que fila travada, porque na travada alguém percebe.
Resolvida a causa, "Devolver à fila" reenvia.

### Nada escreve direto no Supabase — tudo passa pela fila
Atendimento, foto, posição, **chat** e **auditoria** entram no `outbox` e
sobem depois. Tela nenhuma chama `insert` no Supabase.

Toda entidade que passa pela fila precisa de **`client_id` no payload** e
de `upsert(onConflict: 'client_id', ignoreDuplicates: true)` no envio. O
motivo: "falhou" inclui o caso em que o insert chegou e a resposta se
perdeu, e com `insert` o reenvio duplica a linha. Ver
`supabase/fila_offline_chat_e_auditoria.sql`.

Hora dos eventos vem **do aparelho** (`created_at`, `lida_em`,
`occurred_at`), nunca de `now()` no Postgres: offline a coisa acontece
horas antes do upload.

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

### A chave de debug do CI é ALEATÓRIA a cada build

Verificado em 10/10/2026 lendo o APK Signing Block dos próprios arquivos:

```
legendarios1.0.18.apk  SHA-1 AB24D950BC3280D8E391943DE9FD026B32AC05AC
legendarios1.0.19.apk  SHA-1 E882B41E837A8CAC67944CF168585249474CFF11
```

Os dois são `CN=Android Debug` e **diferentes**: o runner do GitHub Actions
não tem `~/.android/debug.keystore`, então o Gradle gera um novo em cada
execução. Duas consequências, as duas sérias:

1. **Atualizar por cima FALHA** (`INSTALL_FAILED_UPDATE_INCOMPATIBLE`).
   Precisa desinstalar antes — e desinstalar **apaga o SQLite local**, ou
   seja, apaga atendimento enfileirado que ainda não subiu. Em campo isso
   é perda de dado clínico. Sincronize antes de atualizar.
2. **Login com Google nunca funciona no APK.** O Google exige client OAuth
   do tipo Android registrado com pacote + SHA-1 do certificado; com o
   SHA-1 mudando a cada build, nenhum registro casa, e o plugin falha com
   DEVELOPER_ERROR antes de qualquer chamada de rede. Não é problema de
   `clientId` — ver `SupabaseService.googleIndisponivelNoApk`.

**Criar o keystore de produção resolve os dois.** Deixou de ser polimento
para a Play Store; é pré-requisito para atualização segura e para o Google
Sign-In. Depois de criado, registrar o SHA-1 dele no Google Cloud como
client Android (pacote `com.legendarios.hakuna_connect`).

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
- **Triagem não usa os sinais vitais de `vital_signs`.** `TriageDinamica` lê
  só a última aferição vinda de `atendimentos` (cache local). A tela de
  `vital_signs` grava numa tabela separada que nada reclassifica.
- **Despacho de atendimento.** 9 estados no schema, o app grava `aberto`.
- **Lógica de proximidade.** Nada cruza GPS com atendimento: ninguém
  responde "quem está mais perto?".
- **Nenhum teste de hardware.** Os 240 testes cobrem lógica. NFC, câmera,
  GPS com tela bloqueada e permissões só se verificam em aparelho físico.
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
- **Top 1782 está em `draft`.** A RLS do chat geral recusa mensagem
  enquanto for draft — toda mensagem vai para quarentena. Ativar o Top
  resolve.
