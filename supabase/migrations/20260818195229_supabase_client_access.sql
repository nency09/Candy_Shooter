-- Explicit Data API permissions for the Flutter publishable client.
-- Row Level Security policies remain the authority for every request.

grant usage on schema public to authenticated;
grant select, insert, update on public.profiles to authenticated;
grant select, insert, update on public.weekly_scores to authenticated;

create policy "Players can create their own profile"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- The leaderboard screen listens for score changes in real time.
do $$
begin
  alter publication supabase_realtime add table public.weekly_scores;
exception
  when duplicate_object then null;
end;
$$;
