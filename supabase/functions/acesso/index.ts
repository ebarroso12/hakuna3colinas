// Acesso por numero do Legendarios.
//
// Esta funcao existe por um motivo de seguranca: criar usuario e definir
// senha exige a chave service_role, que NAO pode ir dentro do APK - quem
// extraisse o arquivo viraria admin do projeto inteiro. A chave fica aqui
// no servidor; o app so chama as acoes.
//
// Fluxo:
//   1. solicitar  (publico)  - Legendario pede acesso com o numero
//   2. liberar    (so admin)  - admin gera o codigo e entrega a pessoa
//   3. negar      (so admin)
//
// Nao ha envio automatico de SMS/e-mail: o admin entrega o codigo pelo
// canal que ja usa com a equipe. Custo zero e o admin segue controlando
// quem entra.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Dominio interno. Nenhum e-mail e enviado para ele: serve so porque o
// Supabase Auth exige um identificador em formato de e-mail. O usuario
// digita apenas o numero.
const DOMINIO = 'legendarios.app'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })

/** Codigo de 6 caracteres, sem 0/O/1/I/L para nao confundir ao ditar. */
function gerarCodigo(): string {
  const alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
  const bytes = crypto.getRandomValues(new Uint8Array(6))
  return Array.from(bytes, (b) => alfabeto[b % alfabeto.length]).join('')
}

async function hash(texto: string): Promise<string> {
  const dados = new TextEncoder().encode(texto)
  const digest = await crypto.subtle.digest('SHA-256', dados)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/** So digito, 4 a 10 - evita lixo e injecao no campo do numero. */
function numeroValido(n: unknown): n is string {
  return typeof n === 'string' && /^[0-9]{4,10}$/.test(n.trim())
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'metodo nao suportado' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  let corpo: Record<string, unknown>
  try {
    corpo = await req.json()
  } catch {
    return json({ error: 'corpo invalido' }, 400)
  }

  const acao = corpo.acao

  // ---------------------------------------------------------------
  // SOLICITAR - publico
  // ---------------------------------------------------------------
  if (acao === 'solicitar') {
    const numero = String(corpo.numero ?? '').trim()
    if (!numeroValido(numero)) {
      return json({ error: 'Numero do Legendarios invalido.' }, 400)
    }

    const { data: existente } = await admin
      .from('access_requests')
      .select('id')
      .eq('legendarios_number', numero)
      .eq('status', 'pendente')
      .maybeSingle()

    if (!existente) {
      await admin.from('access_requests').insert({
        legendarios_number: numero,
        full_name: typeof corpo.nome === 'string' ? corpo.nome.trim() : null,
        phone: typeof corpo.telefone === 'string' ? corpo.telefone.trim() : null,
      })
    }

    // Resposta IDENTICA tendo pedido novo ou repetido, e sem dizer se o
    // numero ja existe no sistema: senao daria pra descobrir quem e
    // Legendario testando numeros.
    return json({
      ok: true,
      mensagem:
        'Pedido registrado. Um administrador vai te passar o codigo de acesso.',
    })
  }

  // ---------------------------------------------------------------
  // Daqui pra baixo exige admin autenticado.
  // ---------------------------------------------------------------
  const auth = req.headers.get('Authorization')
  if (!auth) return json({ error: 'nao autenticado' }, 401)

  const comUsuario = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
    global: { headers: { Authorization: auth } },
  })
  const { data: { user }, error: erroUser } = await comUsuario.auth.getUser()
  if (erroUser || !user) return json({ error: 'nao autenticado' }, 401)

  const { data: perfil } = await admin
    .from('profiles')
    .select('role, is_master_admin')
    .eq('id', user.id)
    .maybeSingle()

  const ehAdmin = perfil?.is_master_admin === true || perfil?.role === 'admin'
  if (!ehAdmin) return json({ error: 'apenas administradores' }, 403)

  // ---------------------------------------------------------------
  // LIBERAR - gera o codigo e cria/atualiza a conta
  // ---------------------------------------------------------------
  if (acao === 'liberar') {
    const numero = String(corpo.numero ?? '').trim()
    if (!numeroValido(numero)) return json({ error: 'numero invalido' }, 400)

    const codigo = gerarCodigo()
    const email = `${numero}@${DOMINIO}`

    // O codigo VIRA a senha da conta. Simples e sem tabela extra: o
    // usuario entra com numero + codigo, e a sessao persiste depois.
    const { data: existentes } = await admin.auth.admin.listUsers()
    const jaExiste = existentes?.users?.find((u) => u.email === email)

    if (jaExiste) {
      const { error } = await admin.auth.admin.updateUserById(jaExiste.id, {
        password: codigo,
      })
      if (error) return json({ error: error.message }, 400)
    } else {
      const { error } = await admin.auth.admin.createUser({
        email,
        password: codigo,
        email_confirm: true,
        user_metadata: { legendarios_number: numero },
      })
      if (error) return json({ error: error.message }, 400)
    }

    const expira = new Date(Date.now() + 7 * 24 * 60 * 60 * 1000)
    await admin
      .from('access_requests')
      .update({
        status: 'liberado',
        handled_by: user.id,
        handled_at: new Date().toISOString(),
        code_hash: await hash(codigo),
        code_expires_at: expira.toISOString(),
      })
      .eq('legendarios_number', numero)
      .eq('status', 'pendente')

    // O codigo em claro volta UMA vez, so pro admin que pediu. O banco
    // guarda apenas o hash: se o admin perder, gera outro.
    return json({
      ok: true,
      numero,
      codigo,
      expira_em: expira.toISOString(),
      mensagem: `Entregue este codigo ao Legendario ${numero}.`,
    })
  }

  // ---------------------------------------------------------------
  // NEGAR
  // ---------------------------------------------------------------
  if (acao === 'negar') {
    const numero = String(corpo.numero ?? '').trim()
    if (!numeroValido(numero)) return json({ error: 'numero invalido' }, 400)
    await admin
      .from('access_requests')
      .update({
        status: 'negado',
        handled_by: user.id,
        handled_at: new Date().toISOString(),
        notes: typeof corpo.motivo === 'string' ? corpo.motivo : null,
      })
      .eq('legendarios_number', numero)
      .eq('status', 'pendente')
    return json({ ok: true })
  }

  return json({ error: 'acao desconhecida' }, 400)
})
