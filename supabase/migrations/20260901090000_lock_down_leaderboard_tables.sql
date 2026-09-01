-- Leaderboard source tables are written only by the SECURITY DEFINER RPC.
-- The Flutter publishable client may read the deliberately public views, but
-- must never be able to forge rows or retrieve player UUIDs from these tables.

revoke select, insert, update, delete on table public.weekly_scores
  from anon, authenticated;

revoke select, insert, update, delete on table public.global_player_progress
  from anon, authenticated;

drop policy if exists "Signed-in players can read weekly scores"
  on public.weekly_scores;
drop policy if exists "Players can create their own weekly score"
  on public.weekly_scores;
drop policy if exists "Players can update their own weekly score"
  on public.weekly_scores;

-- Defensive: the RPC below is the only public write route.  Reassert its
-- execute privilege after removing table permissions.
revoke all on function public.submit_weekly_score(integer) from public;
revoke all on function public.submit_weekly_score(integer) from authenticated;
grant execute on function public.submit_leaderboard_result(integer, integer, integer)
  to authenticated;
