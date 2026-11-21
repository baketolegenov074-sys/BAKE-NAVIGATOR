-- BAKE Navigator: shared road reports with administrator moderation.
-- Run once in Supabase Dashboard -> SQL Editor.

create table if not exists public.road_reports (
  id text primary key,
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
  submitted_by uuid not null default auth.uid() references auth.users(id),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id)
);

create table if not exists public.road_admins (
  user_id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

alter table public.road_reports enable row level security;
alter table public.road_admins enable row level security;

grant select, insert, update, delete on public.road_reports to authenticated;
grant select on public.road_admins to authenticated;

drop policy if exists "read confirmed reports or all as admin" on public.road_reports;
create policy "read confirmed reports or all as admin"
on public.road_reports for select to authenticated
using (
  status = 'Подтверждено'
  or exists (select 1 from public.road_admins a where a.user_id = auth.uid())
);

drop policy if exists "submit own pending reports" on public.road_reports;
create policy "submit own pending reports"
on public.road_reports for insert to authenticated
with check (
  submitted_by = auth.uid()
  and status = 'На проверке'
);

drop policy if exists "admins moderate reports" on public.road_reports;
create policy "admins moderate reports"
on public.road_reports for update to authenticated
using (exists (select 1 from public.road_admins a where a.user_id = auth.uid()))
with check (exists (select 1 from public.road_admins a where a.user_id = auth.uid()));

drop policy if exists "admins delete reports" on public.road_reports;
create policy "admins delete reports"
on public.road_reports for delete to authenticated
using (exists (select 1 from public.road_admins a where a.user_id = auth.uid()));

drop policy if exists "admins can read own admin record" on public.road_admins;
create policy "admins can read own admin record"
on public.road_admins for select to authenticated
using (user_id = auth.uid());

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
