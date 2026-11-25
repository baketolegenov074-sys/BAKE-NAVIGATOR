-- BAKE Navigator automatic diagnostics.
-- Reports are insert-only for the public mobile client.
-- ChatGPT reads reports through the connected Supabase project tools.
create table if not exists public.app_error_reports (
  id text primary key,
  created_at timestamptz not null default now(),
  app_version text not null default '1.0.0+1',
  platform text not null default 'unknown',
  category text not null,
  message text not null,
  stack_trace text,
  details jsonb not null default '{}'::jsonb,
  constraint app_error_reports_category_check
    check (category in ('flutter', 'platform', 'gps', 'gps_stream')),
  constraint app_error_reports_message_length_check
    check (char_length(message) between 1 and 4000),
  constraint app_error_reports_stack_length_check
    check (stack_trace is null or char_length(stack_trace) <= 10000),
  constraint app_error_reports_details_object_check
    check (jsonb_typeof(details) = 'object')
);

create index if not exists app_error_reports_created_at_idx
  on public.app_error_reports (created_at desc);

alter table public.app_error_reports enable row level security;
revoke all on public.app_error_reports from anon, authenticated;
grant insert on public.app_error_reports to anon, authenticated;

drop policy if exists "public can read app error reports" on public.app_error_reports;
drop policy if exists "public can submit app error reports" on public.app_error_reports;
create policy "public can submit app error reports"
  on public.app_error_reports
  for insert to anon, authenticated
  with check (
    category in ('flutter', 'platform', 'gps', 'gps_stream')
    and char_length(message) between 1 and 4000
    and (stack_trace is null or char_length(stack_trace) <= 10000)
    and jsonb_typeof(details) = 'object'
  );
