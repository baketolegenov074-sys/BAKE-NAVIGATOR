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


-- Admin moderation RPC. Replace the bootstrap PIN below before running this block.
-- Use a unique random PIN/passphrase of at least 12 characters.
-- Only a bcrypt hash is stored in a non-exposed schema.
create extension if not exists pgcrypto with schema extensions;

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

create table if not exists private.road_admin_pin (
  singleton boolean primary key default true check (singleton),
  pin_hash text not null,
  failed_attempts integer not null default 0,
  locked_until timestamptz
);

alter table private.road_admin_pin enable row level security;
revoke all on private.road_admin_pin from public, anon, authenticated;

insert into private.road_admin_pin (singleton, pin_hash)
values (
  true,
  extensions.crypt('REPLACE_WITH_YOUR_OWN_RANDOM_PIN_12_CHARACTERS_MINIMUM', extensions.gen_salt('bf', 12))
)
on conflict (singleton) do nothing;

create or replace function public.bake_admin_moderate_report(
  p_report_id text,
  p_action text,
  p_pin text
)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $function$
declare
  v_pin_hash text;
  v_status text;
begin
  if p_report_id is null or length(trim(p_report_id)) = 0 then
    raise exception 'Не указан ID отметки' using errcode = '22023';
  end if;
  if p_action not in ('approve', 'reject', 'delete') then
    raise exception 'Недопустимое действие' using errcode = '22023';
  end if;

  select pin_hash into v_pin_hash
  from private.road_admin_pin
  where singleton = true
  for update;

  if v_pin_hash is null then
    raise exception 'PIN администратора не настроен';
  end if;

  if p_pin is null or length(p_pin) < 12
     or extensions.crypt(p_pin, v_pin_hash) <> v_pin_hash then
    update private.road_admin_pin
       set failed_attempts = failed_attempts + 1,
           locked_until = case
             when failed_attempts + 1 >= 5 then now() + interval '30 minutes'
             else locked_until
           end
     where singleton = true;
    raise exception 'Неверный PIN администратора' using errcode = '42501';
  end if;

  if exists (
    select 1 from private.road_admin_pin
    where singleton = true and locked_until > now()
  ) then
    raise exception 'Вход временно заблокирован. Попробуйте позже' using errcode = '42501';
  end if;

  if p_action = 'delete' then
    delete from public.road_reports where id = p_report_id;
    if not found then raise exception 'Отметка не найдена' using errcode = 'P0002'; end if;
    update private.road_admin_pin set failed_attempts = 0, locked_until = null where singleton = true;
    return jsonb_build_object('ok', true, 'action', 'delete', 'id', p_report_id);
  end if;

  v_status := case p_action
    when 'approve' then 'Подтверждено'
    when 'reject' then 'Отклонено'
  end;

  update public.road_reports
     set status = v_status, reviewed_at = now(), reviewed_by = null
   where id = p_report_id;
  if not found then raise exception 'Отметка не найдена' using errcode = 'P0002'; end if;

  update private.road_admin_pin set failed_attempts = 0, locked_until = null where singleton = true;
  return jsonb_build_object('ok', true, 'action', p_action, 'id', p_report_id, 'status', v_status);
end;
$function$;

revoke all on function public.bake_admin_moderate_report(text, text, text) from public;
revoke all on function public.bake_admin_moderate_report(text, text, text) from anon, authenticated;
grant execute on function public.bake_admin_moderate_report(text, text, text) to anon, authenticated;
