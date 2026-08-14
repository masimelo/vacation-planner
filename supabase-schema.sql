-- ═══════════════════════════════════════════════════════════
--  병사 휴가 플래너 — Supabase 스키마
--  Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN 하세요.
-- ═══════════════════════════════════════════════════════════

-- 1) 테이블: 사용자 1명당 1행, 앱 상태 전체를 JSONB로 보관
create table if not exists public.planner_data (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  data       jsonb       not null default '{}'::jsonb,
  updated_at timestamptz not null default now()
);

-- 2) RLS 활성화 — 이게 켜져 있어야 anon key 공개가 안전합니다
alter table public.planner_data enable row level security;

-- 3) 정책: 자기 행만 읽고/쓰기 가능
drop policy if exists "own row select" on public.planner_data;
create policy "own row select" on public.planner_data
  for select using (auth.uid() = user_id);

drop policy if exists "own row insert" on public.planner_data;
create policy "own row insert" on public.planner_data
  for insert with check (auth.uid() = user_id);

drop policy if exists "own row update" on public.planner_data;
create policy "own row update" on public.planner_data
  for update using (auth.uid() = user_id) with check (auth.uid() = user_id);

drop policy if exists "own row delete" on public.planner_data;
create policy "own row delete" on public.planner_data
  for delete using (auth.uid() = user_id);

-- 4) updated_at 자동 갱신 (클라이언트가 값을 안 보내도 안전하게)
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists planner_data_touch on public.planner_data;
create trigger planner_data_touch
  before update on public.planner_data
  for each row execute function public.touch_updated_at();

-- ── 확인용 ────────────────────────────────────────────────
-- select * from public.planner_data;
