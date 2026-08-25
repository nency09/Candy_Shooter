-- Public global leaderboards expose only player name, level, stars and score.
-- Private profile data, email and user UUIDs remain protected by RLS.

alter table public.weekly_scores
  add column if not exists level_reached integer not null default 1
    check (level_reached between 1 and 100),
  add column if not exists total_stars integer not null default 0
    check (total_stars between 0 and 300);

create table if not exists public.global_player_progress (
  user_id uuid primary key references public.profiles (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 30),
  level_reached integer not null check (level_reached between 1 and 100),
  total_stars integer not null check (total_stars between 0 and 300),
  best_score integer not null check (best_score >= 0),
  updated_at timestamptz not null default now()
);

create index if not exists global_player_progress_rank_index
  on public.global_player_progress
    (level_reached desc, total_stars desc, best_score desc, updated_at asc);

alter table public.global_player_progress enable row level security;

-- Seed the new public ranking table from each player's existing private cloud
-- save.  Only the deliberately public game values are copied; email, user ID,
-- coins and boosters never appear in either leaderboard view.
insert into public.global_player_progress (
  user_id, display_name, level_reached, total_stars, best_score
)
select
  p.id,
  p.display_name,
  greatest(
    1,
    least(
      100,
      case
        when coalesce(p.progress ->> 'unlocked', '') ~ '^[0-9]+$'
          then (p.progress ->> 'unlocked')::integer - 1
        else 1
      end
    )
  ),
  least(
    300,
    coalesce((
      select sum(
        case when star.value ~ '^[0-9]+$' then star.value::integer else 0 end
      )
      from jsonb_array_elements_text(
        case
          when jsonb_typeof(p.progress -> 'stars') = 'array'
            then p.progress -> 'stars'
          else '[]'::jsonb
        end
      ) as star(value)
    ), 0)::integer
  ),
  coalesce((
    select max(
      case when saved_score.value ~ '^[0-9]+$' then saved_score.value::integer else 0 end
    )
    from jsonb_array_elements_text(
      case
        when jsonb_typeof(p.progress -> 'scores') = 'array'
          then p.progress -> 'scores'
        else '[]'::jsonb
      end
    ) as saved_score(value)
  ), 0)
from public.profiles p
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
  current_week date := date_trunc('week', timezone('utc', now()))::date;
begin
  if auth.uid() is null then
    raise exception 'Sign in to submit a score';
  end if;
  if new_score < 0 or new_score > 1000000 then
    raise exception 'Score is outside the allowed range';
  end if;
  if new_level not between 1 and 100 then
    raise exception 'Level is outside the allowed range';
  end if;
  if new_total_stars not between 0 and 300 then
    raise exception 'Stars are outside the allowed range';
  end if;

  select display_name into player_name
  from public.profiles
  where id = auth.uid();

  if player_name is null then
    raise exception 'Player profile was not found';
  end if;

  insert into public.weekly_scores (
    week_start, user_id, display_name, score, level_reached, total_stars
  ) values (
    current_week, auth.uid(), player_name, new_score, new_level, new_total_stars
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
    auth.uid(), player_name, new_level, new_total_stars, new_score
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

revoke execute on function public.submit_weekly_score(integer) from authenticated;
grant execute on function public.submit_leaderboard_result(integer, integer, integer)
  to authenticated;

create or replace view public.weekly_global_leaderboard
with (security_invoker = false)
as
select
  dense_rank() over (
    order by score desc, level_reached desc, total_stars desc, updated_at asc
  )::integer as rank,
  display_name,
  score,
  level_reached,
  total_stars
from public.weekly_scores
where week_start = date_trunc('week', timezone('utc', now()))::date;

create or replace view public.global_progress_leaderboard
with (security_invoker = false)
as
select
  dense_rank() over (
    order by level_reached desc, total_stars desc, best_score desc, updated_at asc
  )::integer as rank,
  display_name,
  best_score as score,
  level_reached,
  total_stars
from public.global_player_progress;

grant usage on schema public to anon;
grant select on public.weekly_global_leaderboard,
  public.global_progress_leaderboard to anon, authenticated;
