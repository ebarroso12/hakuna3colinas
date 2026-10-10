# Edge Function `acesso`

Entrada no app pelo numero do Legendarios.

## Por que existe

Criar usuario e definir senha exigem a chave `service_role`. Ela **nao pode
ir dentro do APK**: quem extraisse o arquivo viraria admin do projeto
inteiro e leria todos os prontuarios. A chave fica aqui no servidor; o app
so chama as acoes.

## Acoes

| acao | quem pode | o que faz |
|---|---|---|
| `solicitar` | qualquer um (com anon key) | registra o pedido de acesso |
| `liberar` | so admin | gera o codigo, cria/atualiza a conta, devolve o codigo UMA vez |
| `negar` | so admin | marca o pedido como negado |

## Decisoes

- **Resposta identica no `solicitar`**, exista o numero ou nao, pedido novo
  ou repetido. Senao daria pra descobrir quem e Legendario testando numeros.
- **O codigo vira a senha da conta.** Simples, sem tabela extra: o usuario
  entra com numero + codigo e a sessao persiste depois.
- **So o hash fica no banco.** O codigo em claro volta uma vez, pro admin
  que pediu. Perdeu? Gera outro.
- **Alfabeto sem 0/O/1/I/L** nos 6 caracteres do codigo — nao se confundem
  ao ditar por telefone.
- **`<numero>@legendarios.app`** porque o Supabase Auth exige identificador
  em formato de e-mail. Nenhum e-mail e enviado; o usuario digita so o
  numero.

## Publicar

```bash
supabase functions deploy acesso
```

O fonte vive em `index.ts` neste diretorio.
