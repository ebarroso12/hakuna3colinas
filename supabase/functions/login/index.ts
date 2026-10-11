// Entrar pelo NUMERO do Legendarios, qualquer que seja o e-mail da conta.
//
// POR QUE ISTO EXISTE
//
// O app converte o numero digitado em `<numero>@legendarios.app` e manda
// pro GoTrue. Isso so acerta quem se cadastrou pelo "Primeiro acesso", que
// e o unico caminho que cria a conta com esse e-mail. Quem criou a conta
// com e-mail proprio — ou entrou pelo Google — tem OUTRO e-mail em
// `auth.users`, e o numero dele nao abre porta nenhuma: a tela diz "numero
// ou senha incorretos" com a senha certa na mao.
//
// Aconteceu com o admin master em 11/10/2026 (numero 203460, conta no
// Gmail). Estava escrito no codigo do app como "armadilha conhecida" e
// tratado como limitacao aceita. Nao e: ia atingir todo mundo que entrasse
// pelo Google, que e justamente o login que o projeto esta habilitando.
//
// Descobrir o e-mail real a partir do numero exige ler `auth.users`, e so
// a chave service_role le. Ela NAO pode ir dentro do APK — quem extraisse
// o arquivo viraria admin do projeto inteiro. Dai existir esta funcao.
//
// POR QUE E UMA FUNCAO SEPARADA, e nao mais uma acao dentro de `acesso`
//
// `acesso` tem 780 linhas e cuida de pedido de acesso, autocadastro e
// exclusao de usuario. Publicar uma alteracao nela exige reenviar o
// arquivo inteiro, e foi assim que ela ja foi destruida uma vez neste
// projeto. Login e uma preocupacao distinta e cabe em 100 linhas: separada,
// uma nao pode quebrar a outra.
//
// DECISOES DE SEGURANCA
//
// 1. A senha e conferida pelo GOTRUE, com a chave ANONIMA — nunca
//    comparando hash aqui dentro com service_role. Assim o rate limit do
//    proprio GoTrue continua valendo. Comparar hash aqui entregaria um
//    endpoint de forca bruta sem limite nenhum.
//
// 2. A recusa e IDENTICA para numero inexistente e para senha errada, e o
//    numero sem conta ainda e enviado ao GoTrue (com o e-mail interno) em
//    vez de voltar na hora — responder mais rapido ja denunciaria que o
//    numero nao existe. Descobrir quem e Legendario testando numeros aqui
//    custa o mesmo que adivinhar a senha.
//
// 3. O e-mail resolvido NUNCA volta no corpo da resposta. Ele ja esta
//    dentro do JWT, que so chega a quem acertou a senha.

import { createClient } from 'jsr:@supabase/supabase-js@2'

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers':
    'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

// Dominio interno. Nenhum e-mail e enviado para ele: existe so porque o
// Supabase Auth exige identificador em formato de e-mail. Tem de ser o
// MESMO de `acesso/index.ts` e de `AcessoService.emailPara` no app.
const DOMINIO = 'legendarios.app'

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS, 'Content-Type': 'application/json' },
  })

/**
 * Numero do Legendarios: so digito, de 1 a 12.
 *
 * ESTA REGRA EXISTE EM TRES LUGARES: aqui, em `acesso/index.ts` e em
 * `AcessoService.regexNumero` no app. TypeScript nao importa Dart; se um
 * mudar sem os outros, o app aceita e o servidor recusa.
 */
function numeroValido(n: string): boolean {
  return /^[0-9]{1,12}$/.test(n.trim())
}

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS })
  if (req.method !== 'POST') {
    return json({ error: 'metodo nao suportado' }, 405)
  }

  const url = Deno.env.get('SUPABASE_URL')!
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  const anonKey = Deno.env.get('SUPABASE_ANON_KEY')!

  let corpo: Record<string, unknown>
  try {
    corpo = await req.json()
  } catch {
    return json({ error: 'corpo invalido' }, 400)
  }

  const identificador = String(corpo.identificador ?? '').trim()
  const senha = String(corpo.senha ?? '')

  const recusa = () =>
    json({ error: 'Numero/e-mail ou senha incorretos.' }, 401)

  if (!identificador || !senha) return recusa()

  let email: string

  if (identificador.includes('@')) {
    // Ja e e-mail: segue direto, sem consultar nada.
    email = identificador
  } else {
    if (!numeroValido(identificador)) return recusa()

    // `profiles.legendarios_number` tem indice UNICO e o trigger
    // `handle_new_user` copia o numero do metadata na criacao da conta —
    // uma consulta indexada resolve, e o custo nao cresce com o numero de
    // Legendarios cadastrados.
    const admin = createClient(url, serviceKey, {
      auth: { autoRefreshToken: false, persistSession: false },
    })

    const interno = `${identificador}@${DOMINIO}`

    try {
      const { data: perfil, error } = await admin
        .from('profiles')
        .select('id')
        .eq('legendarios_number', identificador)
        .maybeSingle()

      // `error` aqui e falha de banco, nao "nao encontrou" (maybeSingle
      // devolve data null sem erro). Falha de banco NAO pode virar "senha
      // errada": isso mandaria a pessoa trocar a senha por causa de um
      // timeout.
      if (error) {
        return json({ error: 'Servico indisponivel. Tente de novo.' }, 503)
      }

      if (perfil?.id) {
        const { data: u } = await admin.auth.admin.getUserById(perfil.id)
        email = u?.user?.email ?? interno
      } else {
        // Sem perfil: pode ser conta antiga, criada antes do trigger. O
        // e-mail interno e o palpite certo, e se nao existir o GoTrue
        // devolve a mesma recusa de senha errada.
        email = interno
      }
    } catch (_) {
      return json({ error: 'Servico indisponivel. Tente de novo.' }, 503)
    }
  }

  // Chave ANONIMA de proposito: quem confere a senha e o GoTrue, com o
  // rate limit dele. Ver a nota 1 no cabecalho.
  const anon = createClient(url, anonKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  })

  const { data, error } = await anon.auth.signInWithPassword({
    email,
    password: senha,
  })

  if (error || !data.session) return recusa()

  return json({
    access_token: data.session.access_token,
    refresh_token: data.session.refresh_token,
  })
})
