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

/**
 * Numero do Legendarios: so digito, de 1 a 12.
 *
 * Era {4,10}. Mudou porque ninguem sabe ate onde a numeracao vai chegar,
 * e um teto apertado quebraria o cadastro de gente real no dia do evento.
 * O minimo caiu para 1 pelo motivo inverso: Legendario antigo pode ter
 * numero curto, e barrar "7" seria inventar regra que o movimento nao tem.
 *
 * Validacao de FORMATO, nao de seguranca - quem decide se o numero vale e
 * a lista do Top, conferida em participante_elegivel.
 *
 * ESTA REGRA EXISTE EM DOIS LUGARES: aqui e em
 * AcessoService.regexNumero no app. TypeScript nao importa Dart; se um
 * mudar sem o outro, o app aceita e o servidor recusa.
 */
function numeroValido(n: unknown): n is string {
  return typeof n === 'string' && /^[0-9]{1,12}$/.test(n.trim())
}

/**
 * Senha de convite do Top: 8 caracteres do mesmo alfabeto sem 0/O/1/I/L.
 *
 * Oito e nao seis como o codigo individual porque esta aqui e
 * COMPARTILHADA e vale pelo evento inteiro - fica exposta por muito mais
 * tempo e em muito mais telas (grupo de WhatsApp, cartaz, voz). 31^8 e
 * cerca de 850 bilhoes de combinacoes.
 */
function gerarSenhaDoTop(): string {
  const alfabeto = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'
  const bytes = crypto.getRandomValues(new Uint8Array(8))
  return Array.from(bytes, (b) => alfabeto[b % alfabeto.length]).join('')
}

/** Senha pessoal minima. O padrao do Supabase e 6; aqui tem prontuario. */
const MIN_SENHA = 8

interface ConviteOk {
  topId: string
  topNome: string
  participanteId: string
  nome: string
  familia: string | null
}

/**
 * Confere a senha do Top e se o numero pertence aquele Top.
 *
 * A senha IDENTIFICA o Top: nao e preciso o Legendario escolher evento
 * numa lista. Ele digita numero + senha e o sistema descobre o resto.
 * Listar Tops para quem nao esta logado vazaria quais eventos existem.
 *
 * DUAS CONDICOES, e as duas importam:
 *
 *   - senha certa  -> prova que a pessoa recebeu o convite
 *   - numero na lista do Top -> prova que ELA e daquele Top
 *
 * So a senha nao basta: ela e compartilhada, entao quem a recebesse no
 * grupo poderia se cadastrar com o numero de outro Legendario e tomar o
 * lugar dele. So o numero tambem nao basta: numero nao e segredo.
 */
async function validarConvite(
  admin: Admin,
  numero: string,
  senhaDoTop: string,
): Promise<{ erro: string } | ConviteOk> {
  const hashDaSenha = await hash(senhaDoTop.trim().toUpperCase())

  const { data: top, error: erroTop } = await admin
    .from('tops')
    .select('id, name, status')
    .eq('access_code_hash', hashDaSenha)
    .maybeSingle()

  if (erroTop) return { erro: 'falha ao verificar a senha' }

  // Mensagem IDENTICA para senha errada e para numero fora da lista. Sao
  // causas diferentes, mas distingui-las na resposta transformaria isto
  // num oraculo: daria para descobrir quem esta inscrito num Top testando
  // numeros com uma senha qualquer.
  const recusa = { erro: 'numero ou senha do Top incorretos' }
  if (!top) return recusa

  if (top.status === 'draft') {
    // Esta o admin ainda nao abriu o evento. Aqui a mensagem PODE ser
    // especifica: quem chegou ate aqui ja provou ter a senha.
    return { erro: 'este Top ainda nao foi aberto pelo administrador' }
  }

  const { data: elegiveis, error: erroEleg } = await admin.rpc(
    'participante_elegivel',
    { p_top_id: top.id, p_numero: numero },
  )
  if (erroEleg) return { erro: 'falha ao verificar o numero' }

  const p = Array.isArray(elegiveis) ? elegiveis[0] : elegiveis
  if (!p) return recusa

  if (p.ja_tem_conta) {
    return {
      erro: 'este numero ja tem conta. Entre com numero e senha, ou peca '
        + 'uma senha nova ao administrador.',
    }
  }

  return {
    topId: top.id,
    topNome: top.name,
    participanteId: p.participante_id,
    nome: p.nome,
    familia: p.familia ?? null,
  }
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
  // VALIDAR_CONVITE - publico
  //
  // Passo 1 do autocadastro: confere numero + senha do Top e devolve o
  // que a tela precisa preencher. NAO cria nada e NAO loga ninguem.
  // ---------------------------------------------------------------
  if (acao === 'validar_convite') {
    const numero = String(corpo.numero ?? '').trim()
    const senhaDoTop = String(corpo.senha_top ?? '')
    if (!numeroValido(numero) || senhaDoTop.trim().length === 0) {
      return json({ error: 'numero ou senha do Top incorretos' }, 400)
    }

    const r = await validarConvite(admin, numero, senhaDoTop)
    if ('erro' in r) return json({ error: r.erro }, 403)

    // So o necessario para a tela de cadastro. Nada de dado clinico: quem
    // chamou ainda nao e ninguem no sistema.
    return json({
      ok: true,
      top_id: r.topId,
      top_nome: r.topNome,
      nome: r.nome,
      familia: r.familia,
    })
  }

  // ---------------------------------------------------------------
  // CADASTRAR - publico
  //
  // Passo 2: cria a conta com a senha PESSOAL e vincula a ficha que ja
  // existe. A senha do Top e revalidada aqui - o passo 1 serviu para a
  // tela, nao como permissao. Confiar na validacao do cliente deixaria
  // qualquer um pular direto para ca.
  // ---------------------------------------------------------------
  if (acao === 'cadastrar') {
    const numero = String(corpo.numero ?? '').trim()
    const senhaDoTop = String(corpo.senha_top ?? '')
    const senha = String(corpo.senha ?? '')

    if (!numeroValido(numero)) return json({ error: 'numero invalido' }, 400)
    if (senha.length < MIN_SENHA) {
      return json(
        { error: `a senha precisa ter pelo menos ${MIN_SENHA} caracteres` },
        400,
      )
    }
    // A senha pessoal NAO pode ser a do Top: seria entregar a conta a
    // todo mundo que recebeu o convite.
    if (senha.trim().toUpperCase() === senhaDoTop.trim().toUpperCase()) {
      return json(
        { error: 'escolha uma senha diferente da senha do Top' },
        400,
      )
    }

    const r = await validarConvite(admin, numero, senhaDoTop)
    if ('erro' in r) return json({ error: r.erro }, 403)

    const ficha = (corpo.ficha ?? {}) as Record<string, unknown>
    const email = `${numero}@${DOMINIO}`

    // 1. Cria a conta de autenticacao.
    const { data: criado, error: erroCriar } = await admin.auth.admin
      .createUser({
        email,
        password: senha,
        email_confirm: true,
        user_metadata: {
          legendarios_number: numero,
          full_name: ficha.full_name ?? r.nome,
        },
      })
    if (erroCriar || !criado?.user) {
      return json({ error: erroCriar?.message ?? 'falha ao criar conta' }, 400)
    }
    const perfilId = criado.user.id

    // 2. Completa o perfil. O trigger handle_new_user ja criou a linha com
    //    nome e numero; aqui entra o resto e a APROVACAO.
    //
    //    Aprovar aqui elimina a aprovacao dupla: antes a pessoa entrava
    //    com o codigo e caia numa tela de "aguardando aprovacao", porque
    //    profiles.approved nasce false e nada o mudava. Quem tem a senha
    //    do Top e esta na lista dele ja foi aprovado - pelo admin, quando
    //    distribuiu a senha.
    const { error: erroPerfil } = await admin
      .from('profiles')
      .update({
        full_name: ficha.full_name ?? r.nome,
        phone: ficha.phone ?? null,
        birth_date: ficha.birth_date ?? null,
        weight_kg: ficha.weight_kg ?? null,
        comorbidities: ficha.comorbidades ?? [],
        approved: true,
      })
      .eq('id', perfilId)

    if (erroPerfil) {
      // Conta criada mas perfil pela metade deixaria a pessoa logando sem
      // aprovacao e sem ficha. Desfaz para ela poder tentar de novo.
      await admin.auth.admin.deleteUser(perfilId)
      return json({ error: `falha ao salvar o perfil: ${erroPerfil.message}` }, 400)
    }

    // 3. Vincula a ficha que JA existe e completa os dados medicos.
    //    Nao cria participante novo: os Legendarios do Top ja estao
    //    cadastrados (hoje 71 dos 215), so sem conta.
    const { error: erroFicha } = await admin
      .from('top_participants')
      .update({
        linked_profile_id: perfilId,
        full_name: ficha.full_name ?? r.nome,
        nickname: ficha.nickname ?? null,
        phone: ficha.phone ?? null,
        birth_date: ficha.birth_date ?? null,
        cidade: ficha.cidade ?? null,
        estado: ficha.estado ?? null,
        emergency_contact: ficha.emergency_contact ?? null,
        height_cm: ficha.height_cm ?? null,
        weight_kg: ficha.weight_kg ?? null,
        blood_type: ficha.blood_type ?? null,
        biotipo: ficha.biotipo ?? null,
        cirurgias: ficha.cirurgias ?? null,
        atividade_fisica_semanal: ficha.atividade_fisica_semanal ?? null,
        comorbidades: ficha.comorbidades ?? [],
        alergias: ficha.alergias ?? null,
        plano_saude: ficha.plano_saude ?? null,
        medicamentos_continuos: ficha.medicamentos_continuos ?? null,
        restricoes_fisicas: ficha.restricoes_fisicas ?? null,
      })
      .eq('id', r.participanteId)

    if (erroFicha) {
      await admin.auth.admin.deleteUser(perfilId)
      return json({ error: `falha ao salvar a ficha: ${erroFicha.message}` }, 400)
    }

    // A senha em claro nao volta: quem cadastrou acabou de escolher ela.
    return json({
      ok: true,
      numero,
      top_id: r.topId,
      mensagem: 'Cadastro concluido. Entre com seu numero e a senha que voce criou.',
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
      // conta que nao usa codigo para entrar. Entao isto exige confirmacao
      // explicita em vez de acontecer calado.
      //
      // CORRECAO (10/10/2026): a versao anterior deste comentario dizia que
      // "o login pelo Google continuaria" como rede de seguranca. E FALSO e
      // nao havia sido verificado. Consultado em auth.identities: a conta
      // tem UMA identidade, provedor `email`. Nao existe login por Google.
      //
      // Isso torna o freio mais importante, nao menos: sobrescrever a senha
      // aqui elimina o UNICO jeito de entrar na conta do admin master, e
      // sobra apenas o link por e-mail.
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
  // GERAR_SENHA_DO_TOP - so admin
  //
  // Uma senha por Top, anunciada ao grupo. Ela libera o CADASTRO, nunca o
  // login: depois de cadastrar, cada Legendario entra com a senha dele.
  //
  // Gerar de novo INVALIDA a anterior na hora - e assim que se corta o
  // acesso se a senha vazar para fora do grupo.
  // ---------------------------------------------------------------
  if (acao === 'gerar_senha_top') {
    const topId = String(corpo.top_id ?? '').trim()
    if (!topId) return json({ error: 'top_id obrigatorio' }, 400)

    const senha = gerarSenhaDoTop()
    const { data: top, error } = await admin
      .from('tops')
      .update({
        access_code_hash: await hash(senha),
        access_code_set_at: new Date().toISOString(),
        access_code_set_by: user.id,
      })
      .eq('id', topId)
      .select('id, name, top_number, status')
      .maybeSingle()

    if (error) return json({ error: error.message }, 400)
    if (!top) return json({ error: 'Top nao encontrado' }, 404)

    // A senha em claro volta UMA vez, so para o admin que pediu. O banco
    // guarda apenas o hash: se o admin perder, gera outra (e a anterior
    // para de valer).
    return json({
      ok: true,
      senha,
      top_id: top.id,
      top_nome: top.name,
      top_numero: top.top_number,
      // O cadastro e recusado enquanto o Top estiver em draft. Avisar
      // aqui evita o admin distribuir a senha e so descobrir depois que
      // ninguem consegue entrar.
      aviso: top.status === 'draft'
        ? 'Este Top esta em RASCUNHO. Ninguem consegue se cadastrar ate voce ativa-lo.'
        : null,
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

  // ---------------------------------------------------------------
  // APAGAR_USUARIOS - exclusao em massa, SO admin master
  //
  // Por que passa por aqui e nao por um `delete` do app:
  //
  // `profiles.id` referencia `auth.users(id) ON DELETE CASCADE`. Apagar a
  // linha de `profiles` pelo app NAO apaga o usuario do auth — deixa um
  // ORFAO que continua conseguindo fazer login e cai num app sem perfil,
  // numa tela de erro sem saida. O caminho certo e o inverso: apagar o
  // `auth.users`, e o perfil vai em cascata. Isso exige service_role, que
  // nunca pode estar dentro do APK.
  //
  // A protecao de prontuario esta em `dependencias_do_perfil`, no banco, e
  // e conferida AQUI tambem — nao so na tela. Tela e conveniencia; a
  // fronteira e o servidor.
  // ---------------------------------------------------------------
  if (acao === 'apagar_usuarios') {
    if (perfil?.is_master_admin !== true) {
      return json({ error: 'apenas o administrador master' }, 403)
    }

    const ids = Array.isArray(corpo.ids)
      ? corpo.ids.map((v: unknown) => String(v)).filter((v: string) => v)
      : []
    if (ids.length === 0) return json({ error: 'nenhum id recebido' }, 400)
    // Teto por chamada: evita um toque errado varrer a base inteira e
    // mantem a requisicao dentro do tempo da Edge Function.
    if (ids.length > 50) {
      return json({ error: 'no maximo 50 por vez' }, 400)
    }
    if (ids.includes(user.id)) {
      return json({ error: 'nao da para apagar a propria conta' }, 400)
    }

    const { data: deps, error: erroDeps } = await admin.rpc(
      'dependencias_do_perfil',
      { p_ids: ids },
    )
    if (erroDeps) {
      return json({ error: `falha ao conferir dependencias: ${erroDeps.message}` }, 500)
    }

    const porId = new Map<string, Record<string, unknown>>()
    for (const d of (deps ?? [])) {
      porId.set(String(d.profile_id), d)
    }

    const apagados: string[] = []
    const recusados: { id: string; motivo: string }[] = []

    for (const id of ids) {
      const d = porId.get(id)
      if (!d) {
        recusados.push({ id, motivo: 'perfil nao encontrado' })
        continue
      }
      if (d.pode_apagar !== true) {
        // Mensagem com o NUMERO, nao "nao foi possivel": e a diferenca
        // entre o admin entender e o admin tentar de novo.
        const partes: string[] = []
        const n = (k: string) => Number(d[k] ?? 0)
        if (n('atendimentos_feitos') > 0) {
          partes.push(`${n('atendimentos_feitos')} atendimento(s) registrado(s)`)
        }
        if (n('atendimentos_fechados') > 0) {
          partes.push(`${n('atendimentos_fechados')} atendimento(s) encerrado(s)`)
        }
        if (n('afericoes_feitas') > 0) {
          partes.push(`${n('afericoes_feitas')} afericao(oes) feita(s)`)
        }
        if (n('afericoes_proprias') > 0) {
          partes.push(`${n('afericoes_proprias')} afericao(oes) propria(s)`)
        }
        if (n('auditoria') > 0) partes.push(`${n('auditoria')} registro(s) de auditoria`)
        if (n('tags_emitidas') > 0) partes.push(`${n('tags_emitidas')} pulseira(s)`)
        if (n('alarmes') > 0) partes.push(`${n('alarmes')} alarme(s)`)
        recusados.push({
          id,
          motivo: partes.length > 0
            ? `tem ${partes.join(', ')} — desative em vez de apagar`
            : 'e o administrador master',
        })
        continue
      }

      // Apaga o auth.users; o profile cai em cascata.
      const { error } = await admin.auth.admin.deleteUser(id)
      if (error) {
        recusados.push({ id, motivo: error.message })
        continue
      }
      apagados.push(id)
    }

    return json({ ok: true, apagados, recusados })
  }

  return json({ error: 'acao desconhecida' }, 400)
})
