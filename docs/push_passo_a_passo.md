# Push com o app fechado — o que falta, e é só isto

Tudo o que é **código** está pronto e no repositório. O que sobra são
três coisas que exigem a sua conta Google, e nenhuma delas leva mais que
alguns minutos.

O projeto Firebase **já existe**: `hakuna3colinas-app` (está no
`.firebaserc`, criado para o login com Google).

---

## Passo 1 — Autorizar o Firebase CLI (2 minutos)

Eu instalei o CLI (`firebase-tools` 15.33.0), mas o login exige um código
que **você** cola no seu terminal — eu não devo intermediar credencial.

Abra um PowerShell e rode:

```
firebase login
```

Ele abre o navegador. Autorize com `edson.barroso@gmail.com`.

Se ele pedir código em vez de abrir o navegador, rode:

```
firebase login --reauth
```

Confirme com:

```
firebase projects:list
```

`hakuna3colinas-app` tem de aparecer na lista.

---

## Passo 2 — Baixar o `google-services.json` (1 minuto)

Depois do login, **me avise** e eu rodo isto por você. Ou rode:

```
cd C:\hakunas\hakuna3colinas
firebase apps:list --project hakuna3colinas-app
```

Se não houver app Android na lista, crie:

```
firebase apps:create android com.legendarios.hakuna_connect --project hakuna3colinas-app
```

E baixe o arquivo:

```
firebase apps:sdkconfig android --project hakuna3colinas-app --out android/app/google-services.json
```

**O arquivo vai para `android/app/google-services.json`.** Ele não é
segredo (vai dentro do APK de qualquer forma), mas confira o `.gitignore`
antes de commitar.

---

## Passo 3 — A conta de serviço, para o servidor disparar (3 minutos)

O push é disparado pela Edge Function, e ela precisa de credencial de
servidor. **Essa sim é segredo** e nunca pode ir no APK: quem a tivesse
mandaria alarme falso para a equipe inteira.

1. Abra:
   `https://console.firebase.google.com/project/hakuna3colinas-app/settings/serviceaccounts/adminsdk`
2. Clique em **Gerar nova chave privada** → baixa um JSON
3. Do JSON, pegue três campos: `project_id`, `client_email`,
   `private_key`
4. Cadastre como segredos da Edge Function:

```
supabase secrets set FIREBASE_PROJECT_ID=hakuna3colinas-app
supabase secrets set FIREBASE_CLIENT_EMAIL=<client_email do JSON>
supabase secrets set FIREBASE_PRIVATE_KEY="<private_key do JSON, inteira>"
```

A `private_key` tem `\n` no meio — **cole inteira, com aspas**. A função
já trata esse caso (`pemParaBytes` limpa os `\n` literais), porque é o
erro mais comum aqui e ele aparece como "chave inválida", mandando
procurar no lugar errado.

5. Publique a função:

```
supabase functions deploy push_alarme
```

---

## Como testar, e o teste tem de ser este

1. Instale o APK em **dois** celulares, com contas diferentes
2. **Feche o app completamente** no segundo (deslize para fora dos
   recentes — não basta minimizar)
3. Dispare EMERGÊNCIA no primeiro
4. O segundo tem de **acordar com som**, mostrando
   `EMERGÊNCIA — <seu nome>`

Se não chegar, olhe nesta ordem:

```sql
-- 1. Os aparelhos se registraram?
select profile_id, plataforma, visto_em from public.dispositivos;

-- esperado: uma linha por celular. Zero = o app não conseguiu o token,
-- e o problema está no Passo 2.
```

```
-- 2. A função respondeu o quê?
supabase functions logs push_alarme
```

`{"enviados":0,"motivo":"nenhum aparelho registrado"}` aponta para o
Passo 2. `Firebase nao configurado nesta funcao` aponta para o Passo 3.

---

## O que o push NÃO resolve, e precisa ficar dito

**FCM exige internet.** No mato sem sinal ele não entrega nada, e nenhuma
configuração muda isso.

Push resolve quem está **com sinal e com o app fechado** — no
acampamento, dormindo, celular no bolso. É um caso real e frequente, e é
só esse.

Para quem está sem rede continuam valendo a malha por rádio
(`MalhaService`, v1.0.41) e o rádio HT. São três caminhos para problemas
diferentes, e nenhum substitui os outros.
