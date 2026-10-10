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
irreversível. **Trocar a chave obriga quem já tem o app a desinstalar
antes de atualizar.**

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

- **Não existe biblioteca de mapa.** `geolocator` grava as posições e
  `stats_service` calcula distância, mas nada desenha os Hakunas num mapa.
- **Schema à frente do app.** O banco tem tabelas que o app não usa:
  `direct_messages`, `team_messages`, `notifications`, `audit_log`,
  `attendance_members`, `top_participants`, `top_team_members`,
  `nfc_tags`, `atendimentos`.
- **AID de exemplo.** `android/app/src/main/res/xml/apduservice.xml` usa
  `F0010203040506`. Trocar pelo AID real quando definido.
- **Chat ainda não tem fila offline.** GPS, atendimentos e fotos passam
  pelo outbox; `top_chat` e `team_chat` escrevem direto no Supabase.
- **Nada escreve em `audit_log`.** A tabela existe e está vazia.
- **`listUsers()` na Edge Function `acesso` pagina em 50** — quebra a
  partir do 51º Legendário cadastrado.
