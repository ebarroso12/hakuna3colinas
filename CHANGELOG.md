# Registro de versões — Legendario Connect

Toda versão publicada, o que mudou e o que **não** foi verificado.

A coluna "verificado" importa: `flutter analyze` pega erro de tipo e
`flutter test` pega erro de lógica, mas **nenhum dos dois toca hardware**.
NFC, câmera, GPS com tela bloqueada e permissões só se provam em aparelho
Android físico.

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
