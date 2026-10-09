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

**Assinatura:** `android/app/build.gradle` usa `signingConfig debug` no
release. O APK instala com "fontes desconhecidas" liberado — que é o fluxo
de distribuição por Drive — mas não serve para Play Store. Se um dia
criarem um keystore real, quem já tem o app vai precisar desinstalar antes
de atualizar.

## Pendências conhecidas

- **Sobreposição nas regras de triagem:** as regras 2 (`0-25`) e 3
  (`25-40`) casam ambas em 25 anos. A prioridade decide. Efeito: 25 anos
  com 1 comorbidade dá verde, 26 anos com a mesma dá amarelo. Fixado em
  teste. **Decisão clínica do usuário**, não mexer sem ele pedir.
- **Não existe biblioteca de mapa.** `geolocator` grava as posições e
  `stats_service` calcula distância, mas nada desenha os Hakunas num mapa.
- **Schema à frente do app.** O banco tem tabelas que o app não usa:
  `direct_messages`, `team_messages`, `notifications`, `audit_log`,
  `attendance_members`, `top_participants`, `top_team_members`,
  `nfc_tags`, `atendimentos`.
- **AID de exemplo.** `android/app/src/main/res/xml/apduservice.xml` usa
  `F0010203040506`. Trocar pelo AID real quando definido.
- **Sem estratégia offline.** Evento de trilha tem conectividade ruim;
  GPS, chat e sinais vitais escrevem direto no Supabase, sem fila local.
