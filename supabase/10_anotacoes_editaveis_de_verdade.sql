-- ===========================================================================
-- O BLOCO DE ANOTAÇÕES ERA "EDITÁVEL" E NUNCA PÔDE SER EDITADO
--
-- Achado em 23/11/2026, auditando o app caminho por caminho: gravei uma
-- anotação, mandei a segunda versão com o mesmo `bloco_id` — do jeito que o
-- app manda — e o servidor respondeu
--
--     42501: new row violates row-level security policy (USING expression)
--
-- `anotacoes` tem policy de SELECT e de INSERT. **Não tem UPDATE.** Com RLS
-- ligada, isso é negação: nenhuma edição entra.
--
-- E não é defeito da reconstrução. `anotacoes_das_equipes.sql` cria duas
-- policies, `anotacoes_select_equipe` e `anotacoes_insert_equipe`, e mais
-- nenhuma — conferido por busca em `create policy`. **O bloco nunca pôde
-- ser editado, nem no banco antigo.**
--
-- ---------------------------------------------------------------------------
-- POR QUE ISSO CONTRADIZ O PROJETO INTEIRO
--
-- O `CLAUDE.md` afirma, em três lugares:
--
--   . "Bloco de anotações: um por membro, **EDITÁVEL**";
--   . "No envio, `upsert(onConflict: 'bloco_id')` **sem**
--     `ignoreDuplicates` — o bloco é editável, a segunda chegada tem de
--     atualizar";
--   . e explica que o app usa `Outbox.enqueueSubstituindo` em vez de
--     `enqueue` justamente para a edição não ser descartada pela fila.
--
-- Ou seja: o app foi construído com cuidado em três camadas para que a
-- edição chegasse ao servidor — e o servidor recusava. Todo esse cuidado
-- terminava num 42501.
--
-- ---------------------------------------------------------------------------
-- O QUE A PESSOA VIA
--
-- `SupabaseService._envioDaFila` classifica 42501 como falha PERMANENTE, e
-- permanente vai para **quarentena**. Então: a primeira versão da anotação
-- sobe; toda correção depois dela fica presa na quarentena, e o texto no
-- servidor continua sendo o primeiro.
--
-- Não é perda silenciosa — a quarentena é visível em `FilaOfflineScreen`,
-- com badge. Mas é pior em um aspecto: a anotação **aparece certa no
-- aparelho de quem escreveu** (o cache local guardou a edição) e errada
-- para todo mundo. Quem corrigiu uma informação de turno jura que corrigiu.
--
-- ---------------------------------------------------------------------------
-- A REGRA: SÓ O AUTOR EDITA O BLOCO DELE
--
-- `using` é conferido contra a linha que JÁ ESTÁ no banco; `with check`,
-- contra a linha nova. As duas exigem `autor_id = auth.uid()`:
--
--   . no `using`, é o que impede editar o bloco de um colega;
--   . no `with check`, é o que impede trocar a autoria ao editar — sem
--     isso, daria para assumir o texto de outra pessoa com um `update`.
--
-- **Admin não entra por cima.** O `CLAUDE.md` é explícito: "cada membro tem
-- o dele, e edita — não há sobrescrita entre pessoas porque cada login tem
-- o seu". Admin LÊ tudo (está no `select`), e isso basta para coordenar.
-- Reescrever a anotação de alguém é outra coisa.
--
-- O resto da condição é **cópia literal** da policy de INSERT
-- (`anotacoes_das_equipes.sql:102-120`), e tem de continuar sendo: se um
-- membro perde a equipe, ele para de editar o bloco daquela equipe pela
-- mesma régua que o impediria de criar um novo. Incluída a cláusula do
-- canal `geral`, que é de todo aprovado do Top não-rascunho.
-- ===========================================================================

drop policy if exists anotacoes_update_propria on public.anotacoes;

create policy anotacoes_update_propria
  on public.anotacoes for update to authenticated
  using (
    autor_id = auth.uid()
    and (
      is_admin()
      or is_team_member(top_id, team)
      or is_team_admin(top_id, team)
      or (
        team = 'geral'::public.team_key
        and is_approved()
        and exists (
          select 1 from public.tops t
          where t.id = anotacoes.top_id
            and t.status <> 'draft'::public.top_status
        )
      )
    )
  )
  with check (
    autor_id = auth.uid()
    and (
      is_admin()
      or is_team_member(top_id, team)
      or is_team_admin(top_id, team)
      or (
        team = 'geral'::public.team_key
        and is_approved()
        and exists (
          select 1 from public.tops t
          where t.id = anotacoes.top_id
            and t.status <> 'draft'::public.top_status
        )
      )
    )
  );

-- Conferência (como o app faz: upsert por `bloco_id`, sem ignoreDuplicates):
--   POST /rest/v1/anotacoes?on_conflict=bloco_id
--   Prefer: resolution=merge-duplicates
--   -> a segunda chegada com o mesmo `bloco_id` tem de ATUALIZAR o texto,
--      e tem de continuar existindo UMA linha só para aquele bloco.
