-- BAKE Navigator: local-first road reports with public anonymous REST access.
-- Safe for ordinary app users: INSERT and SELECT only. No Auth login is required.
-- Public clients cannot approve, edit, or delete reports.

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

grant select, insert on public.road_reports to anon, authenticated;
revoke update, delete on public.road_reports from anon, authenticated;

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


-- Administrator moderation for road_reports.
-- Only authenticated users listed in road_admins can moderate reports.
grant select, insert, update, delete on public.road_reports to authenticated;
grant select, insert on public.road_reports to anon;
revoke update, delete on public.road_reports from anon;

drop policy if exists "admins moderate road reports" on public.road_reports;
drop policy if exists "admins delete road reports" on public.road_reports;

create policy "admins moderate road reports"
on public.road_reports for update to authenticated
using (exists (select 1 from public.road_admins ra where ra.user_id = (select auth.uid())))
with check (exists (select 1 from public.road_admins ra where ra.user_id = (select auth.uid())));

create policy "admins delete road reports"
on public.road_reports for delete to authenticated
using (exists (select 1 from public.road_admins ra where ra.user_id = (select auth.uid())));
