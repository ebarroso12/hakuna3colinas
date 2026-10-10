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

// deno-lint-ignore no-explicit-any
type Admin = any

/** Quantos usuarios por pagina na varredura de fallback. 1000 e o teto da API. */
const POR_PAGINA = 1000

/**
 * Teto de paginas na varredura. 50 x 1000 = 50 mil usuarios.
 *
 * Existe para a funcao nao rodar para sempre se a API passar a devolver
 * pagina cheia indefinidamente. Estourar o teto NAO devolve "nao achei":
 * lanca erro, porque "nao achei" faria o liberar criar um usuario
 * duplicado e a criacao falharia com violacao de unicidade de e-mail.
 */
const MAX_PAGINAS = 50

interface ContaEncontrada {
  id: string
  /** E-mail real da conta. Pode NAO ser `numero@legendarios.app`. */
  email: string | null
}

/**
 * Acha o id do usuario de auth a partir do numero do Legendarios.
 *
 * ESTA FUNCAO SUBSTITUI `listUsers()` SEM ARGUMENTO.
 *
 * O bug: `admin.auth.admin.listUsers()` devolve a PRIMEIRA PAGINA de 50 e
 * mais nada. O `.find()` em cima disso achava o usuario so se ele estivesse
 * entre os 50 primeiros. A partir do 51o Legendario, `jaExiste` vinha
 * `undefined`, o codigo caia no `createUser` e o Supabase recusava com
 * "email already registered" — ou seja, o admin nao conseguia mais gerar
 * codigo novo para quem ja tinha conta.
 *
 * A correcao NAO e paginar. Varrer paginas para achar um e-mail e O(n) em
 * requisicoes e continuaria ficando mais lento a cada Legendario
 * cadastrado. `profiles.legendarios_number` tem indice UNICO e o trigger
 * `handle_new_user` copia o numero do metadata na criacao: uma consulta
 * indexada resolve, e o custo nao cresce.
 *
 * A varredura paginada fica como FALLBACK, para o caso de existir usuario
 * em `auth.users` sem linha em `profiles` (conta criada antes do trigger,
 * ou linha apagada a mao). Nesse caminho ela percorre TODAS as paginas —
 * e e esse o trecho que antes parava em 50.
 */
async function acharUsuarioPorNumero(
  admin: Admin,
  numero: string,
  email: string,
): Promise<ContaEncontrada | null> {
  // Caminho normal: indice unico, uma consulta, custo constante.
  const { data: perfil, error } = await admin
    .from('profiles')
    .select('id')
    .eq('legendarios_number', numero)
    .maybeSingle()

  // `error` aqui e falha de banco, nao "nao encontrou" (maybeSingle devolve
  // data null sem erro). Propagar: seguir em frente levaria a criar conta
  // duplicada por causa de um timeout.
  if (error) throw new Error(`falha ao consultar profiles: ${error.message}`)

  if (perfil?.id) {
    // Busca o e-mail real: `profiles` nao guarda e-mail, e saber se a conta
    // usa `numero@legendarios.app` ou um e-mail proprio decide se trocar a
    // senha e seguro (ver o bloco LIBERAR).
    const { data: u } = await admin.auth.admin.getUserById(perfil.id)
    return { id: perfil.id as string, email: u?.user?.email ?? null }
  }

  // Fallback: varre auth.users pagina por pagina, ate o fim.
  for (let pagina = 1; pagina <= MAX_PAGINAS; pagina++) {
    const { data, error: erroLista } = await admin.auth.admin.listUsers({
      page: pagina,
      perPage: POR_PAGINA,
    })
    if (erroLista) {
      throw new Error(`falha ao listar usuarios: ${erroLista.message}`)
    }

    const usuarios = data?.users ?? []
    const achado = usuarios.find((u: { email?: string }) => u.email === email)
    if (achado) return { id: achado.id, email: achado.email ?? null }

    // Pagina incompleta = ultima pagina. Nao da para confiar em `total`:
    // a API nao o devolve de forma consistente entre versoes.
    if (usuarios.length < POR_PAGINA) return null
  }

  throw new Error(
    `varredura excedeu ${MAX_PAGINAS} paginas sem conclusao — ` +
      `nao da para afirmar que o usuario ${numero} nao existe`,
  )
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
    let conta: ContaEncontrada | null
    try {
      conta = await acharUsuarioPorNumero(admin, numero, email)
    } catch (e) {
      // Falha em DESCOBRIR se a conta existe nao pode virar tentativa de
      // criar: criaria duplicata ou falharia com erro confuso de e-mail
      // repetido. Melhor o admin tentar de novo.
      return json(
        { error: `nao foi possivel verificar a conta: ${e}` },
        503,
      )
    }

    if (conta) {
      // A conta pode nao ter sido criada por esta funcao. O admin master,
      // por exemplo, tem legendarios_number 203460 e e-mail de Gmail,
      // porque entrou por e-mail/senha e Google.
      //
      // Trocar a senha dele aqui seria um RESET SILENCIOSO de senha de uma
      // conta que nao usa codigo para entrar — o admin perderia o login por
      // senha sem ter pedido isso (o login pelo Google continuaria). Entao
      // isto exige confirmacao explicita em vez de acontecer calado.
      //
      // Nao e cautela teorica: antes da v1.0.18 esta acao simplesmente
      // falhava para esse caso (o find por e-mail nao achava a conta, caia
      // no createUser e o indice unico de legendarios_number recusava). O
      // caminho nunca funcionou; agora funciona, e por isso precisa de
      // freio.
      const ehContaDeCodigo = conta.email === email
      const confirmou = corpo.confirmar_troca_de_senha === true

      if (!ehContaDeCodigo && !confirmou) {
        return json(
          {
            error: 'conta_com_email_proprio',
            email_da_conta: conta.email,
            mensagem:
              `O Legendario ${numero} ja tem conta com e-mail proprio ` +
              `(${conta.email}). Gerar codigo SUBSTITUI a senha dessa ` +
              `conta. Para seguir, repita a chamada com ` +
              `"confirmar_troca_de_senha": true.`,
          },
          409,
        )
      }

      const { error } = await admin.auth.admin.updateUserById(conta.id, {
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
