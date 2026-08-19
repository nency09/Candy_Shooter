-- Candy Shooter: account profiles, cloud save data, and weekly scores.
-- The Flutter client uses only the publishable key. Row Level Security protects
-- every player-owned row; no service-role key is ever needed by the app.

create table public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  display_name text not null default 'Candy Player'
    check (char_length(display_name) between 1 and 30),
  email text,
  progress jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "Players can read their own profile"
  on public.profiles for select
  to authenticated
  using (auth.uid() = id);

create policy "Players can update their own profile"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);

create function public.create_profile_for_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, email)
  values (
    new.id,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), 'Candy Player'),
    new.email
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.create_profile_for_new_user();

create function public.set_updated_at()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_set_updated_at
  before update on public.profiles
  for each row execute procedure public.set_updated_at();

create table public.weekly_scores (
  week_start date not null,
  user_id uuid not null references public.profiles (id) on delete cascade,
  display_name text not null check (char_length(display_name) between 1 and 30),
  score integer not null check (score >= 0),
  updated_at timestamptz not null default now(),
  primary key (week_start, user_id)
);

create index weekly_scores_rank_index
  on public.weekly_scores (week_start, score desc, updated_at asc);

alter table public.weekly_scores enable row level security;

create policy "Signed-in players can read weekly scores"
  on public.weekly_scores for select
  to authenticated
  using (true);

create policy "Players can create their own weekly score"
  on public.weekly_scores for insert
  to authenticated
  with check (auth.uid() = user_id);

create policy "Players can update their own weekly score"
  on public.weekly_scores for update
  to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create function public.keep_highest_weekly_score()
returns trigger
language plpgsql
set search_path = public
as $$
begin
  if new.score < old.score then
    raise exception 'Weekly score cannot decrease';
  end if;
  new.updated_at = now();
  return new;
end;
$$;

create trigger weekly_scores_keep_highest
  before update on public.weekly_scores
  for each row execute procedure public.keep_highest_weekly_score();

create function public.submit_weekly_score(new_score integer)
returns public.weekly_scores
language plpgsql
set search_path = public
as $$
declare
  saved_score public.weekly_scores;
  current_week date := date_trunc('week', timezone('utc', now()))::date;
begin
  if auth.uid() is null then
    raise exception 'Sign in to submit a score';
  end if;
  if new_score < 0 then
    raise exception 'Score must be positive';
  end if;

  insert into public.weekly_scores (week_start, user_id, display_name, score)
  select current_week, id, display_name, new_score
  from public.profiles
  where id = auth.uid()
  on conflict (week_start, user_id) do update
    set score = greatest(public.weekly_scores.score, excluded.score),
        display_name = excluded.display_name,
        updated_at = now()
  returning * into saved_score;

  return saved_score;
end;
$$;

grant execute on function public.submit_weekly_score(integer) to authenticated;
