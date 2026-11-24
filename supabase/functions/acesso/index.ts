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

/**
 * Alfabeto sem 0/O/1/I/L: estas senhas sao DITADAS em voz alta e lidas de
 * cartaz impresso. 31 caracteres.
 */
const ALFABETO = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789'

/**
 * Sorteia [n] caracteres do alfabeto, SEM VIES.
 *
 * O jeito obvio -- `byte % 31` -- nao e uniforme: 256 nao e multiplo de
 * 31, entao os 8 primeiros caracteres sairiam 9 vezes em 256 e os outros
 * 23 sairiam 8. A perda era pequena (~0,06 bit na senha inteira) e por
 * isso passou batido. Entrou na conta em 24/11/2026, quando o hash da
 * senha do Top ganhou pepper: a partir dali a entropia da senha e a UNICA
 * barreira, e corrigir isto e de graca.
 *
 * Rejeicao de amostra: descarta byte >= 248 (o maior multiplo de 31 abaixo
 * de 256) e sorteia de novo. A chance de descartar cada byte e 8/256, logo
 * o laco termina na primeira passada quase sempre.
 */
function sortearDoAlfabeto(n: number): string {
  const limite = 256 - (256 % ALFABETO.length) // 248
  let saida = ''
  while (saida.length < n) {
    for (const b of crypto.getRandomValues(new Uint8Array(n))) {
      if (b >= limite) continue
      saida += ALFABETO[b % ALFABETO.length]
      if (saida.length === n) break
    }
  }
  return saida
}

/** Codigo de 6 caracteres, sem 0/O/1/I/L para nao confundir ao ditar. */
function gerarCodigo(): string {
  return sortearDoAlfabeto(6)
}

async function hash(texto: string): Promise<string> {
  const dados = new TextEncoder().encode(texto)
  const digest = await crypto.subtle.digest('SHA-256', dados)
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, '0'))
    .join('')
}

/**
 * Hash da SENHA DO TOP. HMAC-SHA256 com um segredo que NAO esta no banco.
 *
 * Por que nao o `hash()` acima, medido em 24/11/2026:
 *
 *   - `tops_select_linked` libera TODO Top nao-rascunho a TODA conta
 *     aprovada, e `authenticated` tem `GRANT SELECT` em
 *     `access_code_hash`. Medido com um membro comum aprovado
 *     (`is_admin() = false`): ele le a coluna.
 *   - O hash era SHA-256 cru. Conferido: `sha256("<senha de entao>")`
 *     batia exatamente com a coluna.
 *   - 31^8 = 852.891.037.441. Uma GPU modesta (2 GH/s) varre tudo em
 *     ~7 minutos; uma RTX 4090, em ~43 segundos.
 *
 * O estrago nao era "a senha vaza" -- quem le o hash e membro e ja tem a
 * senha. Era que a GARANTIA ESCRITA em `gerar_senha_top` ("gerar de novo
 * INVALIDA a anterior - e assim que se corta o acesso se a senha vazar")
 * NAO CORTAVA: quem vazou a senha e continua aprovado le o hash novo e
 * recupera a senha nova em minutos. Rotacionar nao expulsava ninguem. E
 * com `tops.aceitar_fora_da_lista` ligado, a senha BASTA para entrar.
 *
 * Com HMAC isso acaba: quebrar offline passa a exigir o pepper, que vive
 * so nos segredos da funcao. Continua DETERMINISTICO, entao a busca do Top
 * pelo hash (`validarConvite`) segue funcionando com um `maybeSingle()`
 * -- era por isso que bcrypt/argon2 nao servem aqui.
 *
 * FALHA FECHADA de proposito: sem o segredo, levanta. Cair de volta no
 * SHA-256 cru seria pior que o erro -- pareceria funcionar e estaria
 * desprotegido.
 *
 * Trocar OU PERDER o pepper invalida toda senha de Top em vigor, de todos
 * os Tops, de uma vez. Ele vive so nos segredos desta funcao: nao esta no
 * repositorio, nao esta no banco, nao esta em backup nenhum. Guardar uma
 * copia fora da maquina do dono e obrigacao dele, mesma categoria do
 * keystore. Reversivel (o master gera senha nova pela tela), mas custa
 * reanunciar a 216 pessoas.
 */
async function hashDoTop(texto: string): Promise<string> {
  const pepper = Deno.env.get('SENHA_TOP_PEPPER') ?? ''
  if (!pepper) {
    throw new Error(
      'SENHA_TOP_PEPPER nao configurado: a senha do Top nao pode ser ' +
        'conferida nem gerada sem ele',
    )
  }
  const chave = await crypto.subtle.importKey(
    'raw',
    new TextEncoder().encode(pepper),
    { name: 'HMAC', hash: 'SHA-256' },
    false,
    ['sign'],
  )
  const mac = await crypto.subtle.sign(
    'HMAC',
    chave,
    new TextEncoder().encode(texto),
  )
  return Array.from(new Uint8Array(mac))
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
  return sortearDoAlfabeto(8)
}

/** Senha pessoal minima. O padrao do Supabase e 6; aqui tem prontuario. */
const MIN_SENHA = 8

interface ConviteOk {
  topId: string
  topNome: string
  /**
   * `null` quando o numero NAO esta na lista do Top e o Top aceita isso
   * (`tops.aceitar_fora_da_lista`). Nesse caso `cadastrar` CRIA a ficha
   * com o que a pessoa digita, em vez de completar uma que ja existe.
   */
  participanteId: string | null
  nome: string
  familia: string | null
  /** Cadastro marcado como teste: a conta criada tambem sai marcada. */
  isTeste: boolean
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
  const hashDaSenha = await hashDoTop(senhaDoTop.trim().toUpperCase())

  // O hash vive em `top_access_codes`, nao em `tops`: `tops` e legivel por
  // toda conta aprovada e RLS e por LINHA, nao por coluna. Ver
  // `16_senha_do_top_fora_da_tabela_lida.sql`. `top_access_codes` tem RLS
  // ligada e NENHUMA policy -- so `service_role`, que e quem roda aqui.
  //
  // Sao duas consultas onde antes havia uma. O custo e um round-trip por
  // cadastro, uma vez por pessoa, contra o hash da senha do evento ficar
  // legivel por 216 aparelhos. Nao e troca difIcil.
  const { data: codigo, error: erroCodigo } = await admin
    .from('top_access_codes')
    .select('top_id')
    .eq('code_hash', hashDaSenha)
    .maybeSingle()

  if (erroCodigo) return { erro: 'falha ao verificar a senha' }

  // Mensagem IDENTICA para senha errada e para numero fora da lista. Sao
  // causas diferentes, mas distingui-las na resposta transformaria isto
  // num oraculo: daria para descobrir quem esta inscrito num Top testando
  // numeros com uma senha qualquer.
  const recusa = { erro: 'numero ou senha do Top incorretos' }

  // Sai aqui em vez de levar `codigo` nulo num ternario ate a consulta
  // seguinte: menos um estado para o leitor carregar, e nao depende de como
  // o TS alarga a uniao com `PostgrestSingleResponse`.
  if (!codigo) return recusa

  const { data: top, error: erroTop } = await admin
    .from('tops')
    .select('id, name, status, autocadastro_liberado, aceitar_fora_da_lista')
    .eq('id', codigo.top_id)
    .maybeSingle()

  if (erroTop) return { erro: 'falha ao verificar a senha' }
  if (!top) return recusa

  if (top.status === 'draft') {
    // Esta o admin ainda nao abriu o evento. Aqui a mensagem PODE ser
    // especifica: quem chegou ate aqui ja provou ter a senha.
    return { erro: 'este Top ainda nao foi aberto pelo administrador' }
  }

  // TRAVA DO AUTOCADASTRO. A senha do Top e COMPARTILHADA e anunciada ao
  // grupo: circula em WhatsApp, cartaz e voz. Depois que a equipe se
  // cadastrou ela continua valendo, e nao deveria. Este interruptor fecha
  // a porta sem precisar gerar senha nova.
  //
  // Mensagem especifica, nao a generica: quem chegou aqui ja provou ter a
  // senha, entao nao ha oraculo a proteger — e "senha incorreta" faria a
  // pessoa tentar dez vezes e ligar para o admin.
  if (top.autocadastro_liberado !== true) {
    return {
      erro: 'o cadastro deste Top esta FECHADO pelo administrador. '
        + 'Fale com ele para liberar.',
    }
  }

  const { data: elegiveis, error: erroEleg } = await admin.rpc(
    'participante_elegivel',
    { p_top_id: top.id, p_numero: numero },
  )
  if (erroEleg) return { erro: 'falha ao verificar o numero' }

  const p = Array.isArray(elegiveis) ? elegiveis[0] : elegiveis

  // NUMERO FORA DA LISTA.
  //
  // O padrao e recusar: a lista e a segunda tranca, e a senha do Top e
  // compartilhada. Mas um Top pode comecar SEM lista — foi o caso do
  // "TRACK 3 Colinas 1 ano" em 23/11/2026, cuja lista morreu com o projeto
  // Supabase apagado. Sem esta saida, 216 pessoas digitariam a senha certa
  // e ouviriam "numero ou senha incorretos".
  //
  // Com `aceitar_fora_da_lista`, a ficha e criada no `cadastrar` a partir
  // do que a pessoa digita. Ver `11_autocadastro_sem_lista.sql`, inclusive
  // o que se perde ao ligar isto.
  if (!p) {
    if (top.aceitar_fora_da_lista !== true) return recusa

    // Sem ficha, `ja_tem_conta` nao responde nada — ele olha
    // `linked_profile_id` de uma ficha que nao existe. Entao a conta
    // repetida tem de ser conferida direto em `profiles`, senao o
    // `createUser` falharia depois com o texto cru do GoTrue
    // ("user already exists") no lugar da frase que explica o que fazer.
    const { data: conta, error: erroConta } = await admin
      .from('profiles')
      .select('id')
      .eq('legendarios_number', numero)
      .maybeSingle()
    if (erroConta) return { erro: 'falha ao verificar o numero' }
    if (conta) {
      return {
        erro: 'este numero ja tem conta. Entre com numero e senha, ou peca '
          + 'uma senha nova ao administrador.',
      }
    }

    return {
      topId: top.id,
      topNome: top.name,
      // Sem ficha: `cadastrar` cria uma.
      participanteId: null,
      // Nome vazio de proposito. O formulario de cadastro tem "Nome
      // completo *" como campo obrigatorio e editavel, pre-enchido com
      // isto — entao a pessoa digita o proprio nome, que e quem sabe.
      nome: '',
      familia: null,
      // Ficha nova nasce real. Teste se marca na ficha, pelo admin.
      isTeste: false,
    }
  }

  if (p.ja_tem_conta) {
    return {
      erro: 'este numero ja tem conta. Entre com numero e senha, ou peca '
        + 'uma senha nova ao administrador.',
    }
  }

  // `is_teste` nao vem de `participante_elegivel` (ela e usada pelo
  // caminho publico e devolve o minimo). Uma consulta a mais, com
  // service_role, para a conta criada sair marcada como teste tambem.
  const { data: marca } = await admin
    .from('top_participants')
    .select('is_teste')
    .eq('id', p.participante_id)
    .maybeSingle()

  return {
    topId: top.id,
    topNome: top.name,
    participanteId: p.participante_id,
    nome: p.nome,
    familia: p.familia ?? null,
    isTeste: marca?.is_teste === true,
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

/** Numero do Top: so digito. Hoje sao 4 (1782); 8 sobra. */
function numeroDoTopValido(n: unknown): n is string {
  return typeof n === 'string' && /^[0-9]{1,8}$/.test(n.trim())
}

/**
 * Coloca a pessoa DENTRO do Top: participante (top_senderistas) e ficha
 * ligada a conta (top_participants).
 *
 * A ficha e reaproveitada quando ja existe com o mesmo numero no Top - e
 * o caso de quem veio na planilha. Criar outra duplicaria a pessoa, e com
 * duas fichas `participante_elegivel` escolhe com `limit 1`: comorbidade
 * e alergia podiam ficar na ficha que ninguem abre.
 *
 * Falha aqui NAO desfaz a liberacao: a conta ja esta aprovada e ve todos
 * os Tops ativos. O que falta (a ficha) o admin completa pela tela.
 */
async function colocarNoTop(
  admin: Admin,
  topId: string,
  perfilId: string,
  numero: string,
  nome: string | null,
  adminId: string,
): Promise<string | null> {
  const { error: erroPart } = await admin
    .from('top_senderistas')
    .upsert(
      { top_id: topId, profile_id: perfilId },
      { onConflict: 'top_id,profile_id', ignoreDuplicates: true },
    )
  if (erroPart) return `participante: ${erroPart.message}`

  const { data: fichas } = await admin
    .from('top_participants')
    .select('id, linked_profile_id')
    .eq('top_id', topId)
    .eq('participant_code', numero)
    .limit(1)
  const ficha = Array.isArray(fichas) ? fichas[0] : null

  if (ficha) {
    if (!ficha.linked_profile_id) {
      const { error } = await admin
        .from('top_participants')
        .update({ linked_profile_id: perfilId })
        .eq('id', ficha.id)
      if (error) return `ficha: ${error.message}`
    }
    return null
  }

  const { error: erroFicha } = await admin.from('top_participants').insert({
    top_id: topId,
    full_name: (nome ?? '').trim().toUpperCase() || `LEGENDARIO ${numero}`,
    participant_code: numero,
    linked_profile_id: perfilId,
    registered_by: adminId,
  })
  return erroFicha ? `ficha: ${erroFicha.message}` : null
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') return json({ error: 'metodo nao suportado' }, 405)

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const admin = createClient(url, serviceKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  // O pepper e conferido AQUI, e nao so dentro de `hashDoTop`.
  //
  // `hashDoTop` falha fechada levantando -- o que esta certo, porque cair de
  // volta no SHA-256 cru pareceria funcionar e estaria desprotegido. Mas uma
  // excecao escapando deste handler vira **500 cru, sem os headers de CORS e
  // sem corpo JSON**: o app nao tem o que mostrar, e no build web o navegador
  // bloqueia a resposta antes de qualquer `catch` do Dart. Ou seja: falha
  // fechada, porem indiagnosticavel.
  //
  // Acontece de verdade se o segredo nao estiver configurado -- projeto
  // recriado, rotacao de segredo, deploy novo. Entao o erro sai aqui,
  // nomeando o que falta, para quem le o log saber em um segundo.
  if (!Deno.env.get('SENHA_TOP_PEPPER')) {
    return json({
      error: 'servidor sem SENHA_TOP_PEPPER configurado: a senha do Top nao ' +
        'pode ser conferida nem gerada. Avise o administrador.',
    }, 500)
  }

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

    // Numero do Top: o que a pessoa digitou fica guardado mesmo sem Top
    // correspondente. "Top 1922" na lista do admin diz que ela errou ou
    // que o evento nao foi criado - jogar fora esconderia as duas coisas.
    const topNumero = numeroDoTopValido(corpo.top) ? String(corpo.top).trim() : null
    let topId: string | null = null
    if (topNumero) {
      const { data: top } = await admin
        .from('tops')
        .select('id')
        .eq('top_number', topNumero)
        .maybeSingle()
      topId = top?.id ?? null
    }

    // Quem pede JA LOGADO (entrou pelo Google ou por e-mail e parou na
    // tela de aprovacao) tem conta. Guardar o id faz o liberar aprovar
    // essa conta em vez de criar outra com o mesmo numero - ou trocar a
    // senha de quem nem usa senha. Sem login, o Authorization e a chave
    // anon, `getUser` nao acha ninguem e segue sem conta.
    let perfilId: string | null = null
    const authPedido = req.headers.get('Authorization')
    if (authPedido) {
      const cliente = createClient(url, Deno.env.get('SUPABASE_ANON_KEY')!, {
        global: { headers: { Authorization: authPedido } },
      })
      const { data } = await cliente.auth.getUser()
      perfilId = data?.user?.id ?? null
    }

    const nome = typeof corpo.nome === 'string' && corpo.nome.trim()
      ? corpo.nome.trim()
      : null
    const telefone = typeof corpo.telefone === 'string' && corpo.telefone.trim()
      ? corpo.telefone.trim()
      : null

    const { data: existente } = await admin
      .from('access_requests')
      .select('id')
      .eq('legendarios_number', numero)
      .eq('status', 'pendente')
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    if (!existente) {
      await admin.from('access_requests').insert({
        legendarios_number: numero,
        full_name: nome,
        phone: telefone,
        top_number: topNumero,
        top_id: topId,
        profile_id: perfilId,
      })
    } else {
      // Pedido repetido ATUALIZA o que veio de novo, sem apagar o que ja
      // estava: quem pediu sem o Top e mandou de novo com ele tem de
      // aparecer com o Top para o admin.
      const novo: Record<string, unknown> = {}
      if (nome) novo.full_name = nome
      if (telefone) novo.phone = telefone
      if (topNumero) {
        novo.top_number = topNumero
        novo.top_id = topId
      }
      if (perfilId) novo.profile_id = perfilId
      if (Object.keys(novo).length > 0) {
        await admin.from('access_requests').update(novo).eq('id', existente.id)
      }
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
      // A tela avisa em cima que e cadastro de teste, para ninguem
      // confundir com o cadastro real da equipe.
      is_teste: r.isTeste,
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
        // Conta nascida de cadastro de teste sai marcada: e o que permite
        // apagar o teste em bloco depois, sem olhar nome por nome.
        is_teste: r.isTeste,
      })
      .eq('id', perfilId)

    if (erroPerfil) {
      // Conta criada mas perfil pela metade deixaria a pessoa logando sem
      // aprovacao e sem ficha. Desfaz para ela poder tentar de novo.
      await admin.auth.admin.deleteUser(perfilId)
      return json({ error: `falha ao salvar o perfil: ${erroPerfil.message}` }, 400)
    }

    // 3. A FICHA.
    //
    //    Dois caminhos, e a diferenca e `r.participanteId`:
    //
    //    . ficha JA EXISTE (numero na lista do Top) -> `update`. E o
    //      caminho normal: os Legendarios do Top ja estao cadastrados, so
    //      sem conta, e a ficha pode ter comorbidade e alergia que o admin
    //      preencheu antes.
    //    . ficha NAO EXISTE (`participanteId` nulo, Top com
    //      `aceitar_fora_da_lista`) -> `insert`. Top sem lista previa; a
    //      ficha nasce do que a pessoa digitou.
    //
    //    Os campos sao os MESMOS nos dois casos, por isso o payload e um
    //    so: duas listas divergiriam, e divergir aqui significa campo
    //    clinico que entra por um caminho e nao pelo outro.
    const campos = {
        linked_profile_id: perfilId,
        full_name: ficha.full_name ?? r.nome,
        // `familia` nao era gravada. O formulario mostra o campo, a pessoa
        // preenche e o dado era DESCARTADO — o app nem o mandava. Achado em
        // 23/11/2026. Num Top sem lista previa e o unico jeito de ter a
        // familia, e e por ela que a tela de participantes busca e agrupa
        // (`familia_normalizada`). `?? r.familia` preserva a da lista
        // oficial quando o app antigo nao mandar o campo.
        familia: ficha.familia ?? r.familia,
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
    }

    const { error: erroFicha } = r.participanteId
      ? await admin
        .from('top_participants')
        .update(campos)
        .eq('id', r.participanteId)
      : await admin
        .from('top_participants')
        .insert({
          ...campos,
          id: crypto.randomUUID(),
          top_id: r.topId,
          participant_code: numero,
          // `registered_by` e `not null` e aponta para `profiles`: quem
          // cadastrou foi a propria pessoa, e a conta dela ja existe neste
          // ponto do fluxo.
          registered_by: perfilId,
          // Marca de onde a ficha veio. A tela de participantes mostra
          // `notes`, e o admin precisa distinguir a ficha da lista oficial
          // da que a pessoa digitou — se a lista real aparecer depois, e
          // por aqui que ele confere.
          notes: 'ficha criada no autocadastro',
          is_teste: false,
        })

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

    const { data: pedido } = await admin
      .from('access_requests')
      .select('id, full_name, top_id, profile_id')
      .eq('legendarios_number', numero)
      .eq('status', 'pendente')
      .order('requested_at', { ascending: false })
      .limit(1)
      .maybeSingle()

    const topDoPedido: string | null =
      (typeof corpo.top_id === 'string' && corpo.top_id) || pedido?.top_id || null

    let nomeDoTop: string | null = null
    if (topDoPedido) {
      const { data: t } = await admin
        .from('tops').select('name').eq('id', topDoPedido).maybeSingle()
      nomeDoTop = t?.name ?? null
    }

    // PEDIDO DE QUEM JA TEM CONTA (Google ou e-mail, parado na tela de
    // aprovacao). Nao ha codigo a gerar: a pessoa ja entra do jeito dela.
    // Gerar codigo aqui TROCARIA a senha de uma conta Google, que nem usa
    // senha - e a pessoa receberia um codigo para algo que nao precisa.
    if (pedido?.profile_id) {
      const perfilId = pedido.profile_id as string
      const { data: atual } = await admin
        .from('profiles')
        .select('legendarios_number')
        .eq('id', perfilId)
        .maybeSingle()

      const mudancas: Record<string, unknown> = { approved: true }
      // Conta criada pelo Google nasce com o uuid no lugar do numero
      // (`handle_new_user` faz coalesce com new.id). Sem corrigir, ela
      // nunca entra pelo numero e o admin nao a reconhece em Usuarios.
      if (!numeroValido(String(atual?.legendarios_number ?? ''))) {
        mudancas.legendarios_number = numero
      }
      const { error: erroAprovar } = await admin
        .from('profiles').update(mudancas).eq('id', perfilId)
      if (erroAprovar) {
        const duplicado = erroAprovar.code === '23505'
        return json(
          {
            error: duplicado
              ? `O numero ${numero} ja pertence a outra conta. Confira com a pessoa.`
              : erroAprovar.message,
          },
          duplicado ? 409 : 400,
        )
      }

      const aviso = topDoPedido
        ? await colocarNoTop(admin, topDoPedido, perfilId, numero, pedido.full_name, user.id)
        : null

      await admin
        .from('access_requests')
        .update({
          status: 'liberado',
          handled_by: user.id,
          handled_at: new Date().toISOString(),
        })
        .eq('id', pedido.id)

      return json({
        ok: true,
        numero,
        codigo: null,
        top_nome: nomeDoTop,
        aviso,
        mensagem: 'Conta aprovada. A pessoa ja pode entrar do jeito que entrou.',
      })
    }

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
      const { data: criado, error } = await admin.auth.admin.createUser({
        email,
        password: codigo,
        email_confirm: true,
        user_metadata: {
          legendarios_number: numero,
          ...(pedido?.full_name ? { full_name: pedido.full_name } : {}),
        },
      })
      if (error || !criado?.user) {
        return json({ error: error?.message ?? 'falha ao criar conta' }, 400)
      }
      conta = { id: criado.user.id, email }
    }

    // LIBERAR = APROVAR. Antes o codigo era gerado e `approved` ficava
    // false: a pessoa entrava com o codigo e parava em "aguardando
    // aprovacao", esperando uma segunda liberacao que ninguem sabia que
    // faltava. A aprovacao vale para todos os Tops.
    await admin.from('profiles').update({ approved: true }).eq('id', conta.id)

    const aviso = topDoPedido
      ? await colocarNoTop(admin, topDoPedido, conta.id, numero, pedido?.full_name ?? null, user.id)
      : null

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
      top_nome: nomeDoTop,
      aviso,
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
    // SO O ADMIN MASTER. Decisao do dono em 23/11/2026: "esta senha deve
    // ser gerada dentro do app somente pelos master". Antes bastava ser
    // admin comum.
    //
    // Distribuir continua sendo de qualquer admin — distribuir e falar, nao
    // e permissao. Gerar e que muda: uma senha nova INVALIDA a anterior na
    // hora e ABRE o cadastro do Top, que e dar acesso.
    //
    // A trava de verdade e o trigger `tops_trava_senha`
    // (`07_senha_do_top_so_o_master.sql`): esta funcao escreve com
    // `service_role`, e o trigger deixa `service_role` passar justamente
    // porque a conferencia e aqui. As duas andam juntas — mexer numa sem a
    // outra abre a porta.
    if (perfil?.is_master_admin !== true) {
      return json({ error: 'apenas o administrador master' }, 403)
    }

    const topId = String(corpo.top_id ?? '').trim()
    if (!topId) return json({ error: 'top_id obrigatorio' }, 400)

    const senha = gerarSenhaDoTop()

    // A SENHA PRIMEIRO, o cadastro depois. A ordem importa e foi corrigida
    // em 24/11/2026, numa revisao de codigo.
    //
    // Na ordem inversa (abrir o cadastro, depois gravar a senha), falhar no
    // segundo passo deixava o PIOR estado possivel: cadastro **ABERTO** com
    // a senha **antiga** valendo -- mudanca persistente que o admin nao
    // pediu, num caminho de erro. Com `aceitar_fora_da_lista` ligado isso e
    // exatamente "a senha basta" mais a porta aberta.
    //
    // Nesta ordem o pior caso e "senha nova vale, cadastro nao abriu", que
    // `validarConvite` reporta com mensagem propria ("o cadastro deste Top
    // esta FECHADO") em vez de dar acesso a quem nao devia.
    //
    // E o medo que justificava a ordem antiga -- codigo orfao apontando para
    // Top nenhum -- nao existe: `top_access_codes.top_id` e FK para
    // `tops(id)`, entao id invalido falha com 23503 e nada e gravado.
    //
    // `upsert` por `top_id` porque gerar de novo SUBSTITUI a senha do Top --
    // e assim que se corta o acesso se ela vazar para fora do grupo.
    const { error: erroCodigo } = await admin
      .from('top_access_codes')
      .upsert({
        top_id: topId,
        code_hash: await hashDoTop(senha),
        set_at: new Date().toISOString(),
        set_by: user.id,
      }, { onConflict: 'top_id' })

    if (erroCodigo) {
      // 23503 = o `top_id` nao existe. Vale a pena distinguir: "Top nao
      // encontrado" e erro do admin; o resto e erro do servidor.
      const naoExiste = erroCodigo.code === '23503'
      return json({
        error: naoExiste
          ? 'Top nao encontrado'
          : 'a senha NAO foi gravada: ' + erroCodigo.message +
            '. A senha anterior continua valendo e o cadastro nao foi aberto.',
      }, naoExiste ? 404 : 400)
    }

    // Agora abre o cadastro: gerar senha e querer que gente se cadastre.
    // Sem isto o admin geraria a senha, anunciaria ao grupo e so descobriria
    // depois que o cadastro estava fechado. Esta linha existia SO na versao
    // publicada (v9) e nao no repositorio; trazida de volta em 28/10/2026,
    // senao o deploy a apagaria em silencio.
    const { data: top, error } = await admin
      .from('tops')
      .update({ autocadastro_liberado: true })
      .eq('id', topId)
      .select('id, name, top_number, status')
      .maybeSingle()

    if (error) {
      return json({
        error: 'a senha NOVA ja vale, mas o cadastro nao foi aberto: ' +
          error.message + '. Abra o cadastro na tela do Top.',
      }, 400)
    }
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
