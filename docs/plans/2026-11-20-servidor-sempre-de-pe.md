# Plano: o app não pode parar por pausa do servidor nem por troca de versão

**Pedido do dono (20/11/2026):** "criar algo que não gaste e não fique
mudando, que seja independente, porque senão sempre vai dar este erro".

**Causa que motivou:** o projeto Supabase `jitfbambhmfnqiatwoud` (plano
gratuito) foi PAUSADO por inatividade (~7 dias sem uso) e ninguém conseguiu
entrar. Separadamente, o CI usa `channel: stable` sem versão fixa e a
stable de hoje (3.50.1) gera 66 avisos no `flutter analyze`, o que quebraria
o próximo APK.

## Global Constraints

- Custo zero: nada de plano pago, nada de serviço novo. Só GitHub Actions
  (repositório público, minutos grátis) e o que o app já tem.
- Nenhum segredo novo e nenhum segredo impresso em log. Os secrets
  `SUPABASE_URL` e `SUPABASE_ANON_KEY` já existem no repositório (usados
  por `.github/workflows/android-build.yml`).
- Antes de dar por pronto: `flutter analyze` sem nenhum problema novo e
  `flutter test` com "All tests passed!".
- Mensagens e comentários em português, no estilo do projeto (o comentário
  explica o PORQUÊ).
- Não usar `dart:io` em `lib/`.

## Task 1: Workflow que mantém o Supabase acordado

Criar `.github/workflows/manter_servidor_acordado.yml`:

- `on: schedule` com cron `17 9 */2 * *` (a cada 2 dias, 09:17 UTC) e
  `workflow_dispatch`.
- `permissions: actions: write, contents: read`.
- Passo 1: faz `curl` em `"$SUPABASE_URL/rest/v1/app_versions?select=build_number&limit=1"`
  com os headers `apikey: $ANON` e `Authorization: Bearer $ANON`, usando
  `--fail-with-body`, `--retry 3`, `--max-time 30`. Os secrets entram por
  `env:`. Não imprimir a chave. Se falhar, `::error::` dizendo em português
  que o servidor não respondeu e que provavelmente foi pausado: entrar em
  supabase.com, abrir o projeto e clicar em Restore project. A falha do job
  faz o GitHub mandar e-mail ao dono — é esse o aviso.
- Passo 2 (sempre roda, `if: always()`): `gh api -X PUT
  repos/${{ github.repository }}/actions/workflows/manter_servidor_acordado.yml/enable`
  com `GH_TOKEN: ${{ github.token }}`. Motivo: o GitHub desliga workflows
  agendados de repositório público após 60 dias sem commit; reabilitar pela
  API reinicia essa contagem. `|| true` para não falhar por isso.
- Cabeçalho de comentário explicando o que aconteceu em 20/11/2026 e por
  que 2 dias (folga de 3x sobre os ~7 dias de pausa).

## Task 2: Fixar a versão do Flutter no CI

Em `.github/workflows/android-build.yml` e `.github/workflows/ios-build.yml`,
no passo `subosito/flutter-action@v2`, acrescentar
`flutter-version: 3.47.8` (mantendo `channel: stable` e `cache: true`).
Comentário: 3.47.8 é a versão que gerou o último APK verde (run 117,
28/10/2026); a stable 3.50.1 deprecia `package:flutter/material.dart` e o
analyze sai com 66 avisos. Atualizar a versão é decisão deliberada, testada
num branch, nunca automática.

## Task 3: Quem já entrou continua entrando sem servidor

Em `lib/screens/auth_gate.dart` (`_checkApproval`) e onde o perfil é
buscado: quando `fetchMyProfile` falha com erro de rede
(`pareceErroDeRede(erro.toString())`, já existe em
`lib/services/supabase_service.dart`), usar a última aprovação conhecida
desta conta, guardada no cache local, em vez de mostrar erro.

- Guardar, a cada `fetchMyProfile` bem-sucedido, o par (id do usuário,
  aprovado) no `CacheLocal` (`lib/offline/cache_local.dart`,
  `guardarEstado` / leitura correspondente, `ColunasEstado` em
  `lib/offline/tabelas.dart` — criar a chave nova lá, no padrão das
  existentes).
- Na falha de rede: se o cache tem aprovação = true para ESTE mesmo user id,
  entra (TopsScreen). Qualquer outro caso (sem cache, outro usuário, não
  aprovado, erro que não é de rede) segue o comportamento atual (tela de
  erro com Tentar de novo / Sair).
- A regra de decisão fica numa função pura testável (ex.:
  `bool podeEntrarSemServidor({required String uid, required String? uidGuardado, required bool? aprovadoGuardado})`)
  e tem teste em `test/services/` cobrindo: mesmo uid aprovado → entra;
  outro uid → não; não aprovado → não; sem cache → não.
- Comentário: a RLS continua sendo a fronteira; offline a pessoa só vê o que
  já está no disco do próprio aparelho, e na volta da rede o perfil real
  manda.
