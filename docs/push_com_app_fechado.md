# Push com o app FECHADO — o que falta e como fazer

Escrito em 11/10/2026, para ser executado depois.

Hoje o alarme **funciona bem com o app aberto** e **não existe** com o app
fechado. Isto não é um ajuste: são quatro peças que não existem, uma delas
fora do código. Este documento é o levantamento completo, feito olhando o
que está no repositório e no banco — não de memória.

---

## 1. O que existe HOJE (conferido, não suposto)

| Peça | Estado |
|---|---|
| `top_alerts` | existe: `id, top_id, sender_id, message, latitude, longitude, created_at, client_id` — **0 linhas** |
| Disparo do alarme | `AlarmeService.disparar` → fila (`outbox`) → `SupabaseService.enviarAlarme` |
| Recebimento | `AlarmeService.escutar()` → Realtime, assinatura **sem filtro de Top** (a RLS já corta) |
| Exibição | `FaixaDeAlarme`, montada no `MaterialApp.builder`, **acima do Navigator** |
| Som e vibração | dentro de `AlarmeService` |
| `firebase_messaging` no `pubspec.yaml` | **não existe** |
| `android/app/google-services.json` | **não existe** |
| `POST_NOTIFICATIONS` no AndroidManifest | **não existe** |
| Tabela de tokens de aparelho | **não existe** |

**Por que o app fechado não recebe:** o Realtime do Supabase é uma conexão
WebSocket aberta pelo processo do app. Processo morto, conexão morta.
Nenhum ajuste em `AlarmeService` muda isso — quem acorda um app fechado no
Android é o **sistema**, a pedido do FCM. Não há outro caminho.

**O app de referência faz assim.** Conferido no APK
`hakunaNFC-Oficial.apk` (`com.trixx.hakunanfc`): tem `FirebaseMessaging`
(13 ocorrências), `firebase_messaging`, `google-services`,
`gcm_defaultSenderId`, `POST_NOTIFICATIONS` e `default_notification_channel`.
É exatamente a lista abaixo.

---

## 2. As quatro peças

### Peça 1 — Projeto Firebase (só o dono do projeto faz)

**Não é código. É a única parte que eu não consigo fazer sozinho**, porque
exige a conta Google do dono.

1. https://console.firebase.google.com → **Adicionar projeto**
   - Nome sugerido: `legendarios-connect`
   - Google Analytics: **pode desligar**. Não usamos e simplifica o
     consentimento de dados.
2. Dentro do projeto → **Adicionar app** → **Android**
   - Nome do pacote: **`com.legendarios.hakuna_connect`** (tem de ser
     idêntico; está em `android/app/build.gradle.kts`)
   - SHA-1 de depuração: pode deixar vazio. **FCM não usa SHA-1** — quem
     usa é o login com Google.
3. Baixar **`google-services.json`** e colocar em
   **`android/app/google-services.json`**
4. No projeto Firebase → ⚙ → **Contas de serviço** → **Gerar nova chave
   privada**. Baixa um `.json` — é a credencial que o SERVIDOR usa para
   disparar. **Nunca vai para o repositório nem para o APK.**

#### O `google-services.json` vai para o Git?

**Vai.** Ele não é segredo: está dentro de todo APK publicado e qualquer um
o extrai. O que **não** pode vazar é a chave de conta de serviço do passo 4.

Conferido em 11/10/2026: o `.gitignore` deste projeto **não** ignora
`google-services.json`. Pode commitar direto, e o CI vai achar. Se alguém
adicionar esse padrão ao `.gitignore` depois, o build quebra com uma
mensagem que não explica nada — então essa linha não deve entrar.

#### A chave de serviço no CI e no Supabase

A chave do passo 4 vira um **secret do Supabase**, não um arquivo:

```
supabase secrets set FIREBASE_SERVICE_ACCOUNT="$(cat chave.json)" \
  --project-ref jitfbambhmfnqiatwoud
```

---

### Peça 2 — Tabela de tokens de aparelho

Um aparelho, um token. A mesma pessoa pode ter dois aparelhos, e o token
**muda sozinho** (reinstalação, limpeza de dados, rotação do próprio FCM).
Guardar o token no perfil daria um por pessoa e perderia o segundo aparelho.

```sql
create table if not exists public.dispositivos (
  id          uuid primary key default gen_random_uuid(),
  profile_id  uuid not null references public.profiles (id) on delete cascade,
  -- Token do FCM. ÚNICO: o mesmo aparelho reinstalado devolve o mesmo
  -- token, e sem unicidade a pessoa receberia o alarme duplicado.
  fcm_token   text not null unique,
  plataforma  text not null default 'android',
  -- Para faxina: token que falha com `UNREGISTERED` no envio é apagado.
  -- Sem isso a lista cresce para sempre e o disparo fica mais lento a
  -- cada evento.
  visto_em    timestamptz not null default now(),
  criado_em   timestamptz not null default now()
);

alter table public.dispositivos enable row level security;

-- Cada um gerencia os próprios aparelhos.
create policy dispositivos_proprios on public.dispositivos
  for all using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

-- O disparo roda com service_role e ignora RLS; nenhuma policy de
-- leitura ampla é necessária. Token de aparelho alheio não é dado que
-- membro de equipe precise ver.
create index if not exists idx_dispositivos_profile
  on public.dispositivos (profile_id);
```

---

### Peça 3 — App: registrar o token e tratar a mensagem

```yaml
# pubspec.yaml
firebase_core: ^3.x
firebase_messaging: ^15.x
flutter_local_notifications: ^18.x   # ver nota abaixo
```

**`flutter_local_notifications` é necessário**, e não é redundância: com o
app **em primeiro plano** o Android **não** desenha a notificação sozinho —
o FCM entrega e cabe ao app mostrar. Sem ele, quem estiver com o app aberto
em outra tela não vê nada, que é o cenário mais comum durante a trilha.

```xml
<!-- android/app/src/main/AndroidManifest.xml -->
<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

<!-- Canal padrão: sem isto o Android 8+ joga a notificação num canal
     genérico, silencioso, e o alarme chega mudo. -->
<meta-data
    android:name="com.google.firebase.messaging.default_notification_channel_id"
    android:value="alarme_legendarios"/>
```

**`POST_NOTIFICATIONS` precisa ser PEDIDA em tempo de execução** no Android
13+ (o app tem `targetSdk 36`). Declarar no manifest não basta. O pedido
deve acontecer **depois do login**, junto com a explicação do porquê — não
no primeiro frame, onde a pessoa nega por reflexo.

Pontos de código:

- `main.dart`: `Firebase.initializeApp()` antes do `runApp`, e
  `FirebaseMessaging.onBackgroundMessage` com um handler **top-level**
  (função de topo, anotada `@pragma('vm:entry-point')` — handler como
  método de classe não sobrevive ao tree-shaking em release).
- `auth_gate.dart`: onde hoje chama `AlarmeService.instance.escutar()`,
  registrar também o token (`getToken()` → upsert em `dispositivos`) e
  assinar `onTokenRefresh`.
- Ao deslogar (`AlarmeService.instance.parar()`): **apagar a linha do
  token**. Sem isso, o próximo alarme do Top vai para o aparelho de quem
  saiu — vazamento de informação operacional.
- `AlarmeService`: ao receber push com o app aberto, **não duplicar** com o
  que o Realtime já entregou. Deduplicar por `client_id`, que já existe na
  tabela e já é a chave de idempotência da fila.

---

### Peça 4 — Servidor: quem dispara

Edge Function **separada**, `alarme_push`. Separada pelo mesmo motivo que
`login` ficou separada de `acesso`: função grande é arriscada de republicar.

Gatilho: um **Database Webhook** (Supabase → Database → Webhooks) em
`INSERT` na tabela `top_alerts`, apontando para a função.

```
INSERT em top_alerts
   → webhook
      → Edge Function alarme_push
         → quem recebe? (a mesma regra do app: pertence_ao_top())
         → busca tokens em `dispositivos`
         → FCM HTTP v1  (autenticado com FIREBASE_SERVICE_ACCOUNT)
```

Detalhes que decidem se funciona:

- **`priority: high` e `android.notification.channel_id`**. Sem prioridade
  alta, o Doze do Android atrasa a entrega — e alarme atrasado não é alarme.
- **Não mandar dado clínico no corpo da notificação.** A notificação
  aparece na tela bloqueada, à vista de qualquer um. Manda o `top_id` e o
  `client_id`; a ficha abre dentro do app, depois do login.
- **Quem envia não recebe.** Filtrar `sender_id` — receber o próprio alarme
  assusta sem motivo.
- **Token morto se apaga.** Resposta `UNREGISTERED` ou `INVALID_ARGUMENT` →
  `delete from dispositivos where fcm_token = ...`.
- A regra de quem recebe tem de ser a **mesma** do app
  (`pertence_ao_top()`, membro liberado de qualquer equipe — ver CLAUDE.md,
  "Quem vê o quê"). Se divergirem, um grupo recebe push de um Top do qual
  não participa.

---

## 3. Ordem de execução

1. **Você:** criar o projeto Firebase, baixar `google-services.json`, gerar
   a chave de conta de serviço (Peça 1). **Nada anda sem isto.**
2. Eu: tabela `dispositivos` (SQL pronto acima — você aplica, mudança de
   schema é sensível).
3. Eu: `supabase secrets set FIREBASE_SERVICE_ACCOUNT`.
4. Eu: Edge Function `alarme_push` + webhook.
5. Eu: app — pacotes, manifest, registro de token, handler, deduplicação.
6. **Teste em dois aparelhos reais, com o app FECHADO.** Não há como provar
   isto em teste automatizado, e eu não vou dizer que funciona sem ver.

---

## 4. O que isto custa

- **Firebase/FCM: gratuito**, sem teto prático para o volume deste app.
- **+6 a 10 MB no APK** (Firebase Core + Messaging). Hoje são 79 MB.
- Uma dependência a mais no caminho crítico do alarme. O Realtime
  **continua** sendo o caminho principal com o app aberto; o push é a rede
  por baixo. Se o FCM falhar, nada do que funciona hoje piora.

---

## 5. O que este documento NÃO resolve

- **iOS.** Exige conta paga de desenvolvedor Apple, certificado APNs e um
  Mac. Fora de alcance hoje.
- **Som de alarme com o celular no silencioso.** Nem o FCM força isso;
  precisaria de canal com `IMPORTANCE_HIGH` e, ainda assim, o usuário pode
  silenciar. O rádio continua sendo o caminho que não depende de ninguém.
- **Entrega garantida.** FCM é melhor esforço. Celular sem sinal no mato
  não recebe push — e é justamente onde o Top acontece. **Push é camada
  extra, não substitui o rádio.** Prometer o contrário seria mentir sobre
  uma função de emergência.
