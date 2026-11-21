alter table public.road_reports
  add column if not exists title text,
  add column if not exists address text,
  add column if not exists comment text;
alter table public.road_reports drop constraint if exists road_reports_status_check;
alter table public.road_reports add constraint road_reports_status_check
  check (status in ('На проверке', 'Подтверждено', 'Отклонено', 'approved'));
create index if not exists road_reports_approved_created_at_idx
  on public.road_reports (created_at desc)
  where status in ('approved', 'Подтверждено');
grant select, update on public.road_reports to anon, authenticated;
