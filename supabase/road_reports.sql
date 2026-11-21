-- BAKE Navigator: local-first road reports with public anonymous REST access.
-- The app has no Supabase Auth login. Moderation uses the public anon/publishable key.

create table if not exists public.road_reports (
  id text primary key,
  device_id text not null default 'legacy',
  type text not null,
  latitude double precision not null check (latitude between -90 and 90),
  longitude double precision not null check (longitude between -180 and 180),
  accuracy_meters double precision,
  heading_degrees double precision,
  created_at timestamptz not null default now(),
  status text not null default 'На проверке'
    check (status in ('На проверке', 'Подтверждено', 'Отклонено')),
  camera_operational_status text,
  valid_until timestamptz,
  submitted_by uuid references auth.users(id),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);

-- Upgrade an existing table created by the previous authenticated version.
alter table public.road_reports
  add column if not exists device_id text;
update public.road_reports
  set device_id = 'legacy'
  where device_id is null;
alter table public.road_reports
  alter column device_id set default 'legacy',
  alter column device_id set not null,
  alter column submitted_by drop not null,
  alter column submitted_by drop default;

alter table public.road_reports enable row level security;

grant select, insert, update, delete on public.road_reports to anon, authenticated;

drop policy if exists "read confirmed reports or all as admin" on public.road_reports;
drop policy if exists "submit own pending reports" on public.road_reports;
drop policy if exists "admins moderate reports" on public.road_reports;
drop policy if exists "admins delete reports" on public.road_reports;
drop policy if exists "public can read road reports" on public.road_reports;
drop policy if exists "public can submit pending road reports" on public.road_reports;

create policy "public can read road reports"
on public.road_reports for select to anon, authenticated
using (true);

create policy "public can submit pending road reports"
on public.road_reports for insert to anon, authenticated
with check (
  status = 'На проверке'
  and length(trim(device_id)) > 0
);

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'road_reports'
  ) then
    alter publication supabase_realtime add table public.road_reports;
  end if;
end $$;


-- Public moderation through the Supabase anon/publishable key; no Auth session.
grant select, insert, update, delete on public.road_reports to anon, authenticated;

drop policy if exists "admins moderate road reports" on public.road_reports;
drop policy if exists "admins delete road reports" on public.road_reports;
drop policy if exists "public can moderate road reports" on public.road_reports;
drop policy if exists "public can delete road reports" on public.road_reports;

create policy "public can moderate road reports"
on public.road_reports for update to anon, authenticated
using (true)
with check (true);

create policy "public can delete road reports"
on public.road_reports for delete to anon, authenticated
using (true);
