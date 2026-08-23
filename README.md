# Hakuna Connect

App de coordenação da equipe médica (Hakunas) dos eventos ("Tops") dos
Legendários, com rastreamento de posição em tempo real e integração NFC
para identificação de Hakunas e Senderistas.

## Conceito

- **Top**: cada evento realizado pelos Legendários.
- **Hakuna**: médico vinculado/liberado para um Top específico.
- **Senderista**: participante externo inscrito num Top (não é Legendário).
- Acesso aos dados (ex: posição dos Hakunas) é sempre escopado por Top.

## Stack

- Flutter (Android + iOS a partir do mesmo código)
- Supabase (auth, banco Postgres, Realtime para a posição dos Hakunas)
- `nfc_manager` + `nfc_manager_ndef` — leitura/gravação de tags NFC (Android e iOS)
- HCE nativo (Android, Kotlin) — emulação/"clonagem" de cartão

## Setup

### 1. Supabase

Crie um projeto no Supabase e rode `supabase/schema.sql` (SQL Editor ou CLI)
para criar as tabelas, RLS e habilitar o Realtime na tabela `hakuna_positions`.

### 2. Rodar o app

As credenciais do Supabase **não ficam commitadas** — são passadas via
`--dart-define`:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://SEU-PROJETO.supabase.co \
  --dart-define=SUPABASE_ANON_KEY=SUA_ANON_KEY
```

Para builds de release, use `--dart-define-from-file` com um arquivo (fora
do git) contendo essas duas chaves.

## Limitações importantes (não são bugs — são da plataforma)

1. **Build iOS precisa de Mac + Xcode.** Não existe Xcode para Windows. O
   código Dart/Swift já está pronto (entitlements e Info.plist configurados
   em `ios/Runner`), mas a compilação/teste real do app iOS só acontece com
   acesso a um Mac ou um serviço de CI que rode macOS (Codemagic, GitHub
   Actions macOS runner, etc). Ao abrir o projeto no Xcode pela primeira
   vez, adicione a capability "Near Field Communication Tag Reading" em
   Signing & Capabilities — isso vincula `Runner.entitlements` ao projeto.

2. **Emulação de cartão (HCE) é Android-only.** A Apple não permite HCE
   genérico para apps de terceiros no iOS (só Apple Pay/Wallet, via
   parcerias que developer comum não tem acesso). No iOS o app só lê e
   grava tags — não emula.

3. **Mesmo no Android, HCE não emula qualquer tipo de cartão.** Ele emula
   cartões que respondem por APDU (protocolo ISO-DEP / ISO 14443-4, usado
   pela maioria dos crachás/credenciais modernos). Não emula o UID bruto de
   tags MIFARE Classic — isso exigiria hardware NFC específico do
   fabricante, que nenhum app consegue acessar via API pública do Android.

4. **NFC não funciona em emulador.** Testar leitura/gravação/emulação de
   NFC exige um aparelho Android físico com NFC.

5. **AID de exemplo.** `android/app/src/main/res/xml/apduservice.xml` usa
   um AID de exemplo (`F0010203040506`). Ajuste para o AID real do
   cartão/credencial do Top quando definido.

## Estrutura

```
lib/
  models/          Profile, Top, HakunaPosition
  services/
    supabase_service.dart   auth + queries + realtime
    location_service.dart   rastreamento GPS -> Supabase
    nfc_service.dart        leitura/gravação NDEF (Android + iOS)
    nfc_hce_service.dart    ponte para emulação HCE (Android only)
  screens/         Login, lista de Tops, detalhe do Top
android/app/src/main/kotlin/.../
  HceService.kt    HostApduService (emulação de cartão)
  HceBridge.kt     ponte estática entre o serviço e o MethodChannel
  MainActivity.kt  registra o MethodChannel "hce"
supabase/
  schema.sql       tabelas + RLS + realtime
```
