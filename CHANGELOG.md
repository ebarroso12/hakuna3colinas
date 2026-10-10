# Registro de versões — Legendario Connect

Toda versão publicada, o que mudou e o que **não** foi verificado.

A coluna "verificado" importa: `flutter analyze` pega erro de tipo e
`flutter test` pega erro de lógica, mas **nenhum dos dois toca hardware**.
NFC, câmera, GPS com tela bloqueada e permissões só se provam em aparelho
Android físico.

---

## 10/10/2026

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

Verificado: `analyze` limpo, 284 testes passando, 14 novos (4 da gaveta, 8 do
servico, 2 do guarda de versao). **Nao verificado em aparelho**: o toque
na logo abrindo a gaveta e o `launchUrl` saindo para o navegador.

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
