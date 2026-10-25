# Versão iOS: o que falta e como publicar

O código já builda para iPhone. O que falta é **conta Apple**, e isso só o
dono do projeto pode criar. Este documento é o passo a passo.

## Como o iPhone recebe o app

iPhone **não instala app por arquivo** como o Android instala o APK do
Drive. Não existe "fontes desconhecidas" no iOS. Os caminhos possíveis:

| Caminho | Quantas pessoas | Revisão da Apple | Validade do build | Serve? |
|---|---|---|---|---|
| **TestFlight, testadores externos** | até 10.000, por link público | só no 1º build de cada versão (~1 dia) | **90 dias** | **Sim. É o recomendado.** |
| TestFlight, testadores internos | até 100, precisam ser usuários do App Store Connect | nenhuma | 90 dias | Para a equipe que testa antes |
| App Store | qualquer um | revisão completa a cada versão | sem validade | Possível depois, dá mais trabalho |
| Ad Hoc | 100 aparelhos, cadastrados um a um pelo UDID | nenhuma | 1 ano | Não: cadastrar 200 UDIDs é inviável |

**O build do TestFlight expira em 90 dias.** Depois disso o app não abre
mais no iPhone. Com release a cada poucas semanas isso não pesa, mas antes
de um Top confira a data do último build no App Store Connect.

## Passo a passo (uma vez só)

### 1. Conta de desenvolvedor Apple

1. Entre em <https://developer.apple.com/programs/enroll/> com um Apple ID.
2. Escolha **pessoa física** (sai no seu nome) ou **organização** (precisa
   de CNPJ e número D-U-N-S, que demora alguns dias).
3. Pague a anuidade: **US$ 99/ano**.
4. Depois de aprovada, anote o **Team ID** (10 caracteres) em
   developer.apple.com › Account › **Membership details**.

### 2. Registrar o app

1. Em developer.apple.com › **Identifiers** › **+** › App IDs › App.
2. Bundle ID **explícito**: `com.legendarios.hakunaConnect` (é o que está
   no projeto).
3. Em **Capabilities**, marque **NFC Tag Reading**. Sem ela a pulseira não
   lê, e o erro só aparece na hora de assinar.
4. Em <https://appstoreconnect.apple.com> › **Apps** › **+** › Novo app:
   plataforma iOS, nome **Legendario Connect**, idioma português, o mesmo
   Bundle ID, e um SKU qualquer (ex.: `legendario-connect`).

### 3. Chave de API (é ela que deixa o GitHub assinar e enviar)

1. App Store Connect › **Users and Access** › **Integrations** ›
   **App Store Connect API** › **+**.
2. Nome `github-actions`, papel **Admin**. Com papel menor o Xcode recusa
   criar o certificado sozinho, e o build falha na assinatura.
3. Baixe o arquivo `.p8`. **Ele só pode ser baixado uma vez.** Guarde junto
   com o keystore do Android.
4. Anote o **Key ID** (na linha da chave) e o **Issuer ID** (no topo da
   página).

### 4. Secrets no GitHub

Repositório › Settings › Secrets and variables › Actions › New secret:

| Secret | Valor |
|---|---|
| `APPLE_TEAM_ID` | Team ID do passo 1 |
| `APPSTORE_API_KEY_ID` | Key ID do passo 3 |
| `APPSTORE_API_ISSUER_ID` | Issuer ID do passo 3 |
| `APPSTORE_API_PRIVATE_KEY` | o conteúdo inteiro do `.p8`, inclusive as linhas `BEGIN`/`END` |

`SUPABASE_URL` e `SUPABASE_ANON_KEY` já existem (o Android usa os mesmos).

### 5. Primeiro envio

1. Actions › **iOS (TestFlight)** › **Run workflow**. Ou empurre a próxima
   tag `v*`: o workflow roda junto com o do Android.
2. O build aparece em App Store Connect › o app › **TestFlight** depois do
   processamento da Apple (5 a 30 minutos).
3. Em **External Testing**, crie um grupo (ex.: "Top"), adicione o build e
   envie para a **revisão beta**. Na primeira vez a Apple pede e-mail de
   contato, descrição do app e **uma conta de teste**. Crie um usuário
   comum aprovado num Top de teste e informe número e senha, senão a
   revisão não passa da tela de login.
4. Aprovado, ative o **link público** do grupo e mande o link à equipe.

### Na ponta: como a pessoa instala

1. Instala o app **TestFlight** da App Store (gratuito, da Apple).
2. Abre o link público e toca em **Aceitar** e depois em **Instalar**.
3. Dali em diante o TestFlight avisa e instala as versões novas. Por isso
   o botão ATUALIZAR da gaveta não aparece no iPhone.

## O que funciona diferente no iPhone

| Função | Android | iPhone | Por quê |
|---|---|---|---|
| Ler pulseira (NFC) | sim | sim, pela folha de leitura do sistema | — |
| Gravar pulseira | sim | sim | — |
| MIFARE Classic | lê o UID | **não lê** | a Apple não expõe esse chip |
| Emulação de cartão (HCE) | sim | **não** | a Apple não libera para apps de terceiros |
| **Rádio entre aparelhos** | sim | **não** | Nearby Connections só existe no Android. O alarme do iPhone sem rede fica gravado e sobe com sinal, e a tela diz que ninguém por perto foi avisado |
| QR da pulseira | sim | sim | — |
| GPS com tela bloqueada | notificação fixa | barra azul no topo da tela | jeito do iOS de mostrar que o app usa localização |
| Atualizar o app | ATUALIZAR na gaveta (APK) | TestFlight sozinho | iPhone não instala APK |
| Entrar com Google | sim | **escondido** até o passo abaixo | sem configuração própria o botão derruba o app |
| Alarme com o app fechado | só com push configurado | só com push configurado | ver `push_com_app_fechado.md` |

## Opcional: Entrar com Google no iPhone

No iPhone o botão fica escondido até existir um client ID próprio. Sem
ele, tocar no botão **fecha o app**, com exceção nativa que nenhum `catch`
do Dart pega. Para ligar:

1. Google Cloud Console, no projeto do client Web que já existe › APIs e
   serviços › Credenciais › Criar ID do cliente OAuth › tipo **iOS**,
   Bundle ID `com.legendarios.hakunaConnect`.
2. Crie o secret `GOOGLE_IOS_CLIENT_ID` com o ID gerado
   (`xxxx.apps.googleusercontent.com`).
3. No `ios/Runner/Info.plist`, acrescente o esquema de URL invertido,
   `com.googleusercontent.apps.xxxx` (o ID ao contrário):

   ```xml
   <key>CFBundleURLTypes</key>
   <array>
     <dict>
       <key>CFBundleURLSchemes</key>
       <array>
         <string>com.googleusercontent.apps.xxxx</string>
       </array>
     </dict>
   </array>
   ```

   **Os dois andam juntos.** Com o secret e sem o esquema, o botão aparece
   e derruba o app.
4. No Supabase › Authentication › Google, acrescente o client ID iOS em
   "Authorized Client IDs".

## Opcional: alarme com o app fechado no iPhone

O push do iPhone passa pela Apple (APNs), e o Firebase só repassa. Além do
que está em `push_passo_a_passo.md` para o Android:

1. developer.apple.com › Keys › **+** › marque **Apple Push Notifications
   service (APNs)**. Baixe o `.p8`.
2. Firebase › Configurações do projeto › Cloud Messaging › app iOS ›
   envie a chave APNs com o Key ID e o Team ID.
3. Firebase › adicione um app **iOS** com o Bundle ID acima e baixe o
   `GoogleService-Info.plist` para `ios/Runner/`.
4. No App ID (passo 2), ligue a capability **Push Notifications**.
5. Em `ios/Runner/Runner.entitlements`, `aps-environment` = `production`;
   no `Info.plist`, `remote-notification` em `UIBackgroundModes`.

Sem isso o app abre normalmente: `Firebase.initializeApp()` falha em
silêncio e o alarme continua chegando com o app aberto.
