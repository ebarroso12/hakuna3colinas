// Push do alarme para quem esta com o app FECHADO.
//
// POR QUE EXISTE
//
// O alarme chega em qualquer tela, com som e vibracao, mas so com o app
// ABERTO: o Realtime e um WebSocket do processo, e processo morto e
// conexao morta. Quem guardou o celular no bolso nao recebia nada.
//
// Quem acorda app fechado no Android e o SISTEMA, a pedido do FCM. Nao ha
// outro caminho.
//
// O QUE ISTO NAO RESOLVE, E PRECISA FICAR DITO
//
// FCM exige INTERNET. No mato sem sinal ele nao entrega nada, e nenhuma
// configuracao muda isso. Para quem esta sem rede valem a malha por radio
// (`MalhaService`) e o radio HT. Push resolve quem esta COM sinal e com o
// app fechado — no acampamento, dormindo, celular no bolso. E um caso
// real e frequente, e e so esse.
//
// POR QUE AQUI E NAO NO APP
//
// Disparar push exige credencial de servidor (conta de servico do
// Firebase) e ler os tokens de TODO MUNDO do Top — as duas coisas que nao
// podem ir dentro do APK. Quem extraisse o arquivo mandaria alarme falso
// para a equipe inteira.
//
// SEGREDOS QUE ESTA FUNCAO PRECISA (Supabase > Edge Functions > Secrets):
//
//   FIREBASE_PROJECT_ID
//   FIREBASE_CLIENT_EMAIL
//   FIREBASE_PRIVATE_KEY     (a chave inteira, com os \n)
//
// Os tres saem do JSON da conta de servico:
//   Firebase Console > Configuracoes do projeto > Contas de servico >
//   Gerar nova chave privada

import { createClient } from 'jsr:@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })

// ---------------------------------------------------------------------------
// OAuth2 do Google por JWT assinado localmente.
//
// Nao ha SDK do Firebase Admin para Deno que valha a pena aqui: o que se
// precisa e UM token de acesso, e isso sao 30 linhas. Uma dependencia a
// menos num caminho que roda durante emergencia.
// ---------------------------------------------------------------------------

/** PEM -> ArrayBuffer, que e o que o WebCrypto aceita. */
function pemParaBytes(pem: string): ArrayBuffer {
  const limpo = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    // O secret chega com `\n` literal quando colado do JSON. Sem isto o
    // base64 quebra e o erro aparece como "chave invalida", que manda
    // procurar no lugar errado.
    .replace(/\\n/g, '')
    .replace(/\s/g, '')
  const bin = atob(limpo)
  const bytes = new Uint8Array(bin.length)
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i)
  return bytes.buffer
}

function base64url(dados: string | Uint8Array): string {
  const bin =
    typeof dados === 'string'
      ? dados
      : String.fromCharCode(...dados)
  return btoa(bin).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '')
}

/** Token de acesso do Google, valido por 1 hora. */
async function tokenDoGoogle(
  clientEmail: string,
  privateKey: string,
): Promise<string> {
  const agora = Math.floor(Date.now() / 1000)
  const cabecalho = base64url(JSON.stringify({ alg: 'RS256', typ: 'JWT' }))
  const corpo = base64url(
    JSON.stringify({
      iss: clientEmail,
      scope: 'https://www.googleapis.com/auth/firebase.messaging',
      aud: 'https://oauth2.googleapis.com/token',
      exp: agora + 3600,
      iat: agora,
    }),
  )

  const chave = await crypto.subtle.importKey(
    'pkcs8',
    pemParaBytes(privateKey),
    { name: 'RSASSA-PKCS1-v1_5', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const assinatura = new Uint8Array(
    await crypto.subtle.sign(
      'RSASSA-PKCS1-v1_5',
      chave,
      new TextEncoder().encode(`${cabecalho}.${corpo}`),
    ),
  )

  const resposta = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer',
      assertion: `${cabecalho}.${corpo}.${base64url(assinatura)}`,
    }),
  })
  if (!resposta.ok) {
    throw new Error(`OAuth do Google recusou: ${await resposta.text()}`)
  }
  return (await resposta.json()).access_token
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })

  try {
    const { top_id, titulo, corpo, latitude, longitude, excluir_profile } =
      await req.json()

    if (!top_id) return json({ erro: 'top_id obrigatorio' }, 400)

    const projectId = Deno.env.get('FIREBASE_PROJECT_ID')
    const clientEmail = Deno.env.get('FIREBASE_CLIENT_EMAIL')
    const privateKey = Deno.env.get('FIREBASE_PRIVATE_KEY')
    if (!projectId || !clientEmail || !privateKey) {
      // Erro explicito em vez de 200 calado: "nao configurado" e
      // "configurado e ninguem recebeu" sao problemas diferentes, e
      // confundi-los custa a proxima emergencia.
      return json({ erro: 'Firebase nao configurado nesta funcao' }, 500)
    }

    // `service_role` porque precisa ler os tokens de TODOS do Top, e a RLS
    // de `dispositivos` so deixa cada um ver os proprios — o que esta
    // certo para o app e errado para quem dispara.
    const supa = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    )

    // Quem deve ser avisado: a MESMA regua do alarme no banco, que e todo
    // aprovado de Top nao-draft (ver `pode_alarmar_no_top`). Duplicar a
    // regra aqui a faria divergir com o tempo, entao ela sai de la.
    const { data: elegiveis, error: erroPessoas } = await supa
      .from('profiles')
      .select('id')
      .eq('approved', true)
    if (erroPessoas) throw erroPessoas

    const ids = (elegiveis ?? [])
      .map((p: { id: string }) => p.id)
      // Nao avisa quem disparou: o celular apitando na mao de quem pediu
      // socorro e ruido, e a mesma regra ja vale no app.
      .filter((id: string) => id !== excluir_profile)

    if (ids.length === 0) return json({ enviados: 0, motivo: 'ninguem elegivel' })

    const { data: aparelhos, error: erroTokens } = await supa
      .from('dispositivos')
      .select('fcm_token')
      .in('profile_id', ids)
    if (erroTokens) throw erroTokens

    const tokens = (aparelhos ?? []).map((d: { fcm_token: string }) => d.fcm_token)
    if (tokens.length === 0) {
      return json({ enviados: 0, motivo: 'nenhum aparelho registrado' })
    }

    const acesso = await tokenDoGoogle(clientEmail, privateKey)
    const url = `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`

    let enviados = 0
    const mortos: string[] = []

    // Um envio por token. A API v1 do FCM nao tem lote, e `Promise.all`
    // com 200 tokens estoura o limite de conexoes da Edge Function.
    for (const token of tokens) {
      const r = await fetch(url, {
        method: 'POST',
        headers: {
          Authorization: `Bearer ${acesso}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({
          message: {
            token,
            notification: {
              title: titulo ?? 'EMERGENCIA no Top',
              body: corpo ?? 'Alguem pediu socorro. Abra o app.',
            },
            data: {
              tipo: 'alarme',
              top_id: String(top_id),
              latitude: latitude != null ? String(latitude) : '',
              longitude: longitude != null ? String(longitude) : '',
            },
            android: {
              // `high` acorda o aparelho em Doze. Sem isto a notificacao
              // pode esperar a proxima janela de manutencao do Android —
              // que em emergencia e tarde demais.
              priority: 'high',
              notification: {
                channel_id: 'alarme_legendarios',
                sound: 'default',
                // Vermelho: a mesma cor da faixa de alarme dentro do app.
                color: '#C62828',
              },
            },
          },
        }),
      })

      if (r.ok) {
        enviados++
      } else {
        const texto = await r.text()
        // UNREGISTERED / INVALID_ARGUMENT = o token morreu (app
        // desinstalado, dados limpos). Guardar para apagar: sem faxina a
        // lista cresce para sempre e cada alarme fica mais lento — e
        // alarme lento e alarme pior.
        if (texto.includes('UNREGISTERED') || texto.includes('NOT_FOUND')) {
          mortos.push(token)
        }
      }
    }

    if (mortos.length > 0) {
      await supa.from('dispositivos').delete().in('fcm_token', mortos)
    }

    return json({
      enviados,
      tentados: tokens.length,
      removidos: mortos.length,
    })
  } catch (e) {
    return json({ erro: String(e) }, 500)
  }
})
