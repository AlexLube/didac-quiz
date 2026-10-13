-- DidacCine Quiz · Administración (panel de DidacCine)
-- Solo pueden usarlas las cuentas cuyo id está en app_config.admin_uids
-- (se registra con la tarea «registrar-admin» del flujo de trabajo).

insert into public.app_config (key, value) values ('admin_uids', '[]'::jsonb)
  on conflict (key) do nothing;

create or replace function public.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select auth.uid() is not null
     and exists (select 1 from app_config c, jsonb_array_elements_text(c.value) u
                  where c.key = 'admin_uids' and u = auth.uid()::text)
$$;

create or replace function public._require_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not is_admin() then raise exception 'not_admin'; end if;
end $$;

-- ---------------------------------------------------------------------------
-- Cuadro de mando
-- ---------------------------------------------------------------------------
create or replace function public.admin_dashboard() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare
  v_today date := _today();
  v_out   jsonb;
begin
  perform _require_admin();
  select jsonb_build_object(
    'today', v_today,
    'users', jsonb_build_object(
      'registered', (select count(*) from profiles),
      'players_total', (select count(distinct user_id) from games),
      'active_today', (select count(distinct user_id) from games where challenge_date = v_today),
      'active_7d', (select count(distinct user_id) from games where challenge_date > v_today - 7),
      'active_30d', (select count(distinct user_id) from games where challenge_date > v_today - 30),
      'new_7d', (select count(*) from auth.users where created_at > now() - interval '7 days')
    ),
    'games', jsonb_build_object(
      'total', (select count(*) from games),
      'finished', (select count(*) from games where finished_at is not null),
      'today_started', (select count(*) from games where challenge_date = v_today),
      'today_finished', (select count(*) from games where challenge_date = v_today and finished_at is not null),
      'avg_points_7d', (select round(avg(total_points)::numeric, 1) from games
                         where finished_at is not null and challenge_date > v_today - 7)
    ),
    'daily', coalesce((
      select jsonb_agg(jsonb_build_object('date', d, 'started', s, 'finished', f) order by d)
        from (select challenge_date d, count(*) s, count(*) filter (where finished_at is not null) f
                from games where challenge_date > v_today - 30 group by challenge_date) x), '[]'),
    'challenges', jsonb_build_object(
      'days_left', (select count(*) from challenges where challenge_date >= v_today),
      'last_date', (select max(challenge_date) from challenges),
      'upcoming', coalesce((
        select jsonb_agg(jsonb_build_object('date', challenge_date, 'kind', kind, 'title', title,
                                             'theme', theme) order by challenge_date)
          from (select * from challenges where challenge_date >= v_today
                 order by challenge_date limit 14) c), '[]')
    ),
    'questions', jsonb_build_object(
      'total', (select count(*) from questions),
      'active', (select count(*) from questions where active),
      'scheduled', (select count(distinct q) from challenges c, unnest(c.question_ids) q
                     where c.challenge_date >= v_today),
      'by_format', coalesce((
        select jsonb_object_agg(format, n) from (select format, count(*) n from questions
                                                  where active group by format) f), '{}'),
      'accuracy_by_format', coalesce((
        select jsonb_object_agg(format, acc) from (
          select format, round(sum(times_correct)::numeric / nullif(sum(times_shown), 0), 2) acc
            from questions where times_shown >= 5 group by format) f), '{}')
    ),
    'hardest', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'format', format, 'prompt', prompt,
                                           'shown', times_shown,
                                           'accuracy', round(times_correct::numeric / times_shown, 2)))
        from (select * from questions where times_shown >= 10
               order by times_correct::numeric / times_shown limit 10) h), '[]'),
    'easiest', coalesce((
      select jsonb_agg(jsonb_build_object('id', id, 'format', format, 'prompt', prompt,
                                           'shown', times_shown,
                                           'accuracy', round(times_correct::numeric / times_shown, 2)))
        from (select * from questions where times_shown >= 10
               order by times_correct::numeric / times_shown desc limit 5) h), '[]'),
    'reports', coalesce((
      select jsonb_agg(jsonb_build_object('id', r.id, 'question_id', r.question_id, 'reason', r.reason,
                                           'created_at', r.created_at, 'prompt', q.prompt,
                                           'format', q.format, 'active', q.active)
                       order by r.created_at desc)
        from reports r join questions q on q.id = r.question_id where r.status = 'open'), '[]')
  ) into v_out;
  return v_out;
end $$;

-- ---------------------------------------------------------------------------
-- Editor de preguntas
-- ---------------------------------------------------------------------------
create or replace function public.admin_list_questions(
  p_search text default null, p_format text default null, p_only_manual boolean default false,
  p_limit integer default 30, p_offset integer default 0
) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  perform _require_admin();
  return coalesce((
    select jsonb_agg(to_jsonb(q) - 'entity_ids' order by q.id desc)
      from (select * from questions
             where (p_search is null or p_search = ''
                    or prompt::text ilike '%' || p_search || '%' or options::text ilike '%' || p_search || '%')
               and (p_format is null or p_format = '' or format = p_format)
               and (not p_only_manual or external_id like 'manual:%')
             order by id desc limit least(p_limit, 100) offset greatest(p_offset, 0)) q), '[]'::jsonb);
end $$;

create or replace function public.admin_save_question(p_id bigint, p_data jsonb) returns jsonb
language plpgsql volatile security definer set search_path = public as $$
declare
  v_id bigint;
  v_fmt text := p_data ->> 'format';
  v_diff smallint := coalesce((p_data ->> 'difficulty')::smallint, 2);
begin
  perform _require_admin();
  if p_id is null then
    insert into questions (external_id, format, difficulty, max_points, topic, prompt, options, answer,
                           explanation, image_url, image_attribution, audio_url, audio_attribution,
                           extra, time_limit_ms, source, active)
    values ('manual:' || gen_random_uuid(), v_fmt, v_diff,
            coalesce((p_data ->> 'max_points')::smallint, v_diff), coalesce(p_data ->> 'topic', 'manual'),
            p_data -> 'prompt', coalesce(p_data -> 'options', '[]'), p_data -> 'answer',
            p_data -> 'explanation', nullif(p_data ->> 'image_url', ''), nullif(p_data ->> 'image_attribution', ''),
            nullif(p_data ->> 'audio_url', ''), nullif(p_data ->> 'audio_attribution', ''),
            coalesce(p_data -> 'extra', '{}'), nullif(p_data ->> 'time_limit_ms', '')::integer,
            'manual', coalesce((p_data ->> 'active')::boolean, true))
    returning id into v_id;
  else
    -- No se editan preguntas ya jugadas hoy o antes: se crea una copia (evita falsear rankings).
    update questions set
      format = v_fmt, difficulty = v_diff,
      max_points = coalesce((p_data ->> 'max_points')::smallint, v_diff),
      prompt = p_data -> 'prompt', options = coalesce(p_data -> 'options', '[]'), answer = p_data -> 'answer',
      explanation = p_data -> 'explanation',
      image_url = nullif(p_data ->> 'image_url', ''), image_attribution = nullif(p_data ->> 'image_attribution', ''),
      audio_url = nullif(p_data ->> 'audio_url', ''), audio_attribution = nullif(p_data ->> 'audio_attribution', ''),
      extra = coalesce(p_data -> 'extra', '{}'), time_limit_ms = nullif(p_data ->> 'time_limit_ms', '')::integer,
      active = coalesce((p_data ->> 'active')::boolean, active)
    where id = p_id returning id into v_id;
    if v_id is null then raise exception 'question_not_found'; end if;
  end if;
  return jsonb_build_object('id', v_id);
end $$;

create or replace function public.admin_set_question_active(p_id bigint, p_active boolean) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  perform _require_admin();
  update questions set active = p_active where id = p_id;
end $$;

create or replace function public.admin_resolve_report(p_id bigint, p_status text) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  perform _require_admin();
  if p_status not in ('fixed', 'dismissed') then raise exception 'bad_status'; end if;
  update reports set status = p_status where id = p_id;
end $$;

-- ---------------------------------------------------------------------------
-- Retos: ver y cambiar una pregunta de un reto futuro
-- ---------------------------------------------------------------------------
create or replace function public.admin_get_challenge(p_date date) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare v_ch challenges%rowtype;
begin
  perform _require_admin();
  select * into v_ch from challenges where challenge_date = p_date;
  if not found then return null; end if;
  return jsonb_build_object('date', v_ch.challenge_date, 'kind', v_ch.kind, 'title', v_ch.title,
    'editable', v_ch.challenge_date > _today(),
    'questions', (select jsonb_agg(jsonb_build_object('position', o.pos - 1, 'id', q.id, 'format', q.format,
                                    'difficulty', q.difficulty, 'max_points', q.max_points,
                                    'prompt', q.prompt, 'active', q.active) order by o.pos)
                    from unnest(v_ch.question_ids) with ordinality o(qid, pos)
                    join questions q on q.id = o.qid));
end $$;

create or replace function public.admin_replace_challenge_question(
  p_date date, p_position integer, p_question_id bigint
) returns void
language plpgsql volatile security definer set search_path = public as $$
begin
  perform _require_admin();
  if p_date <= _today() then raise exception 'challenge_already_open'; end if;
  if not exists (select 1 from questions where id = p_question_id and active) then
    raise exception 'question_not_found';
  end if;
  update challenges set question_ids[p_position + 1] = p_question_id where challenge_date = p_date;
end $$;

-- ---------------------------------------------------------------------------
-- Subida de imágenes propias al almacenamiento (solo administradores)
-- ---------------------------------------------------------------------------
do $$
begin
  if exists (select 1 from pg_namespace where nspname = 'storage')
     and exists (select 1 from pg_class c join pg_namespace n on n.oid = c.relnamespace
                  where n.nspname = 'storage' and c.relname = 'objects') then
    execute 'drop policy if exists media_admin_insert on storage.objects';
    execute $p$create policy media_admin_insert on storage.objects for insert to authenticated
               with check (bucket_id = 'media' and public.is_admin())$p$;
    execute 'drop policy if exists media_admin_update on storage.objects';
    execute $p$create policy media_admin_update on storage.objects for update to authenticated
               using (bucket_id = 'media' and public.is_admin())$p$;
  end if;
end $$;

grant execute on function public.is_admin()                       to authenticated;
grant execute on function public.admin_dashboard()                to authenticated;
grant execute on function public.admin_list_questions(text, text, boolean, integer, integer) to authenticated;
grant execute on function public.admin_save_question(bigint, jsonb) to authenticated;
grant execute on function public.admin_set_question_active(bigint, boolean) to authenticated;
grant execute on function public.admin_resolve_report(bigint, text) to authenticated;
grant execute on function public.admin_get_challenge(date)        to authenticated;
grant execute on function public.admin_replace_challenge_question(date, integer, bigint) to authenticated;
revoke execute on function public._require_admin() from public, anon, authenticated;
