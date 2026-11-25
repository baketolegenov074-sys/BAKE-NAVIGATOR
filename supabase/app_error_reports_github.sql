-- BAKE Navigator diagnostic-to-GitHub bridge.
-- Applied to project cnyshqvdonqhkkcqgucf.

alter table public.app_error_reports
  add column if not exists github_issue_number bigint,
  add column if not exists github_issue_url text,
  add column if not exists github_synced_at timestamptz,
  add column if not exists github_sync_error text,
  add column if not exists github_sync_started_at timestamptz;

create index if not exists app_error_reports_created_github_issue_idx
  on public.app_error_reports (created_at desc)
  where github_issue_number is not null;
