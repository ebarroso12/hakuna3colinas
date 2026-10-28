// Publica uma versao do app em `app_versions` - e o que faz a faixa
// ATUALIZAR aparecer para todo mundo.
//
// Chamada pelo CI ao fim de cada release. Existe porque o caminho antigo
// exigia o secret SUPABASE_SERVICE_ROLE_KEY no GitHub, que nunca foi
// criado: da 1.0.40 a 1.0.44 nenhuma versao foi registrada e ninguem viu o
// botao (conferido em 28/10/2026).
//
// SEM SEGREDO NO CI, E SEM CONFIAR EM QUEM CHAMA. A funcao recebe so o
// numero da versao e tira TODO o resto do proprio GitHub, que e publico:
//
//   - a Release `v<versao>` tem de existir, publicada (nao rascunho, nao
//     pre-release), com o anexo `legendarios<versao>.apk`;
//   - o build_number vem do pubspec.yaml DAQUELA tag.
//
// Quem chamar com qualquer coisa so consegue registrar uma versao que de
// fato foi publicada no repositorio, apontando para o APK que o CI
// assinou. Nao da para apontar o botao para um APK de fora.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const REPO = 'ebarroso12/hakuna3colinas'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' },
  })

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json({ error: 'metodo nao suportado' }, 405)

  let corpo: Record<string, unknown>
  try {
    corpo = await req.json()
  } catch {
    return json({ error: 'corpo invalido' }, 400)
  }

  const versao = String(corpo.versao ?? '').trim()
  if (!/^[0-9]+\.[0-9]+\.[0-9]+$/.test(versao)) {
    return json({ error: 'versao invalida (ex.: 1.0.45)' }, 400)
  }

  const cabecalhos = {
    'Accept': 'application/vnd.github+json',
    'User-Agent': 'legendario-connect-publicar-versao',
  }

  // 1. A Release, publicada, com o APK.
  const rel = await fetch(
    `https://api.github.com/repos/${REPO}/releases/tags/v${versao}`,
    { headers: cabecalhos },
  )
  if (rel.status === 404) {
    return json({ error: `release v${versao} nao existe no repositorio` }, 404)
  }
  if (!rel.ok) return json({ error: `GitHub respondeu ${rel.status}` }, 502)
  const release = await rel.json()
  if (release.draft || release.prerelease) {
    return json({ error: `v${versao} e rascunho ou pre-release` }, 409)
  }

  const nomeDoApk = `legendarios${versao}.apk`
  const anexo = (release.assets ?? []).find(
    (a: { name?: string }) => a.name === nomeDoApk,
  )
  if (!anexo?.browser_download_url) {
    return json({ error: `a release nao tem ${nomeDoApk}` }, 409)
  }

  // 2. O build_number do pubspec DAQUELA tag. E por ele que o app compara
  //    (como texto, "1.0.9" > "1.0.10").
  const pub = await fetch(
    `https://raw.githubusercontent.com/${REPO}/v${versao}/pubspec.yaml`,
    { headers: { 'User-Agent': cabecalhos['User-Agent'] } },
  )
  if (!pub.ok) return json({ error: `pubspec da tag: ${pub.status}` }, 502)
  const linha = (await pub.text()).match(/^version:\s*([0-9.]+)\+([0-9]+)\s*$/m)
  if (!linha || linha[1] !== versao) {
    return json(
      { error: `pubspec da tag v${versao} nao declara essa versao` },
      409,
    )
  }
  const build = Number(linha[2])

  // Notas da release em texto curto: a gaveta mostra no dialogo.
  const notas = typeof release.body === 'string' && release.body.trim()
    ? release.body.trim().slice(0, 500)
    : null

  const admin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )
  const { error } = await admin.from('app_versions').upsert(
    {
      version: versao,
      build_number: build,
      apk_url: anexo.browser_download_url,
      notes: notas,
      published: true,
      published_at: new Date().toISOString(),
    },
    { onConflict: 'version' },
  )
  if (error) return json({ error: error.message }, 500)

  return json({
    ok: true,
    versao,
    build,
    apk_url: anexo.browser_download_url,
  })
})
