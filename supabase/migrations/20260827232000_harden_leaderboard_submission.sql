-- Derive leaderboard values from the caller's saved profile rather than
-- trusting the score/level/star values supplied by the mobile client RPC.
-- This prevents a request from directly impersonating a higher result. A
-- fully cheat-proof game would still require server-authoritative gameplay,
-- but this closes the direct leaderboard-payload loophole.

create or replace function public.submit_leaderboard_result(
  new_score integer,
  new_level integer,
  new_total_stars integer
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  player_name text;
  player_progress jsonb;
  saved_level integer;
  saved_total_stars integer;
  saved_best_score integer;
  current_week date := date_trunc('week', timezone('utc', now()))::date;
begin
  if auth.uid() is null then
    raise exception 'Sign in to submit a score';
  end if;

  select display_name, progress
    into player_name, player_progress
  from public.profiles
  where id = auth.uid();

  if player_name is null then
    raise exception 'Player profile was not found';
  end if;

  saved_level := greatest(
    1,
    least(
      100,
      case
        when coalesce(player_progress ->> 'unlocked', '') ~ '^[0-9]+$'
          then greatest(1, (player_progress ->> 'unlocked')::integer - 1)
        else 1
      end
    )
  );

  saved_total_stars := least(
    300,
    coalesce((
      select sum(
        case when value ~ '^[0-9]+$' then value::integer else 0 end
      )
      from jsonb_array_elements_text(
        case
          when jsonb_typeof(player_progress -> 'stars') = 'array'
            then player_progress -> 'stars'
          else '[]'::jsonb
        end
      ) as star(value)
    ), 0)::integer
  );

  saved_best_score := coalesce((
    select max(
      case when value ~ '^[0-9]+$' then value::integer else 0 end
    )
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(player_progress -> 'scores') = 'array'
          then player_progress -> 'scores'
        else '[]'::jsonb
      end
    ) as saved_score(value)
  ), 0);

  -- A completed level with no score has nothing meaningful to publish.
  if saved_best_score <= 0 then
    return;
  end if;

  insert into public.weekly_scores (
    week_start, user_id, display_name, score, level_reached, total_stars
  ) values (
    current_week, auth.uid(), player_name,
    saved_best_score, saved_level, saved_total_stars
  )
  on conflict (week_start, user_id) do update
    set score = greatest(public.weekly_scores.score, excluded.score),
        level_reached = greatest(
          public.weekly_scores.level_reached,
          excluded.level_reached
        ),
        total_stars = greatest(
          public.weekly_scores.total_stars,
          excluded.total_stars
        ),
        display_name = excluded.display_name,
        updated_at = now();

  insert into public.global_player_progress (
    user_id, display_name, level_reached, total_stars, best_score
  ) values (
    auth.uid(), player_name, saved_level, saved_total_stars, saved_best_score
  )
  on conflict (user_id) do update
    set display_name = excluded.display_name,
        level_reached = greatest(
          public.global_player_progress.level_reached,
          excluded.level_reached
        ),
        total_stars = greatest(
          public.global_player_progress.total_stars,
          excluded.total_stars
        ),
        best_score = greatest(
          public.global_player_progress.best_score,
          excluded.best_score
        ),
        updated_at = now();
end;
$$;
