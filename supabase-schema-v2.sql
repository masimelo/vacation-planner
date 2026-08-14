-- ═══════════════════════════════════════════════════════════
--  병사 휴가 플래너 — 공동 편집 스키마 (v2)
--  Supabase 대시보드 → SQL Editor 에 붙여넣고 RUN 하세요.
--
--  v1(supabase-schema.sql)을 이미 실행했다면 그 위에 그대로 올리면 됩니다.
--  기존 planner_data 의 데이터는 아래 6) 에서 자동으로 옮겨집니다.
--  여러 번 실행해도 안전합니다.
-- ═══════════════════════════════════════════════════════════

-- ── 1) 플래너: 휴가표 1개 = 1행. 여러 사람이 공유합니다 ──────
create table if not exists public.planners (
  id          uuid primary key default gen_random_uuid(),
  owner_id    uuid        not null references auth.users(id) on delete cascade,
  title       text        not null default '휴가 플래너',
  data        jsonb       not null default '{}'::jsonb,
  invite_code text        not null unique default replace(gen_random_uuid()::text,'-',''),
  updated_at  timestamptz not null default now(),
  updated_by  uuid        references auth.users(id) on delete set null
);

-- ── 2) 멤버: 누가 어느 플래너를 편집할 수 있는지 ────────────
create table if not exists public.planner_members (
  planner_id uuid        not null references public.planners(id) on delete cascade,
  user_id    uuid        not null references auth.users(id) on delete cascade,
  role       text        not null default 'editor' check (role in ('owner','editor')),
  email      text,
  joined_at  timestamptz not null default now(),
  primary key (planner_id, user_id)
);

create index if not exists planner_members_user_idx on public.planner_members(user_id);

-- ── 3) 권한 확인 함수 ───────────────────────────────────────
-- security definer 로 RLS를 우회합니다. 이렇게 안 하면 정책끼리
-- 서로를 참조해서 무한 재귀(infinite recursion) 오류가 납니다.
create or replace function public.is_member(p_planner uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.planner_members m
    where m.planner_id = p_planner and m.user_id = auth.uid()
  );
$$;

create or replace function public.is_owner(p_planner uuid)
returns boolean language sql security definer stable set search_path = public as $$
  select exists (
    select 1 from public.planners p
    where p.id = p_planner and p.owner_id = auth.uid()
  );
$$;

-- ── 4) RLS: 멤버만 읽고 쓸 수 있게 ──────────────────────────
alter table public.planners        enable row level security;
alter table public.planner_members enable row level security;

drop policy if exists "planner select" on public.planners;
create policy "planner select" on public.planners
  for select using (public.is_member(id));

drop policy if exists "planner update" on public.planners;
create policy "planner update" on public.planners
  for update using (public.is_member(id)) with check (public.is_member(id));

drop policy if exists "planner delete" on public.planners;
create policy "planner delete" on public.planners
  for delete using (owner_id = auth.uid());

-- 생성은 create_planner() 함수로만 (플래너와 멤버를 한 번에 만들어야 하므로)
drop policy if exists "planner insert" on public.planners;

drop policy if exists "member select" on public.planner_members;
create policy "member select" on public.planner_members
  for select using (public.is_member(planner_id));

-- 나가기는 본인만, 내보내기는 소유자만
drop policy if exists "member delete" on public.planner_members;
create policy "member delete" on public.planner_members
  for delete using (user_id = auth.uid() or public.is_owner(planner_id));

-- ── 5) 함수들 ───────────────────────────────────────────────

-- 새 플래너 만들기 → 만든 사람이 자동으로 owner 멤버가 됩니다
create or replace function public.create_planner(p_title text default '휴가 플래너')
returns uuid language plpgsql security definer set search_path = public as $$
declare new_id uuid;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;

  insert into public.planners (owner_id, title, updated_by)
  values (auth.uid(), coalesce(nullif(p_title,''), '휴가 플래너'), auth.uid())
  returning id into new_id;

  insert into public.planner_members (planner_id, user_id, role, email)
  values (new_id, auth.uid(), 'owner', auth.jwt() ->> 'email');

  return new_id;
end $$;

-- 초대 코드로 참여하기
create or replace function public.join_planner(p_code text)
returns uuid language plpgsql security definer set search_path = public as $$
declare pid uuid;
begin
  if auth.uid() is null then raise exception '로그인이 필요합니다'; end if;

  select id into pid from public.planners where invite_code = p_code;
  if pid is null then raise exception '초대 링크가 유효하지 않습니다'; end if;

  insert into public.planner_members (planner_id, user_id, role, email)
  values (pid, auth.uid(), 'editor', auth.jwt() ->> 'email')
  on conflict (planner_id, user_id) do nothing;

  return pid;
end $$;

-- 저장. 마지막으로 읽은 시각을 같이 보내서 남의 저장본을 덮어쓰는 걸 막습니다.
-- p_expected 가 서버의 updated_at 과 다르면 예외를 던집니다(앱이 잡아서 물어봅니다).
create or replace function public.save_planner(
  p_id uuid, p_data jsonb, p_expected timestamptz default null, p_force boolean default false
) returns timestamptz language plpgsql security definer set search_path = public as $$
declare cur timestamptz; ts timestamptz;
begin
  if not public.is_member(p_id) then raise exception '이 플래너에 접근할 수 없습니다'; end if;

  select updated_at into cur from public.planners where id = p_id;

  if not p_force and p_expected is not null and cur is distinct from p_expected then
    raise exception 'CONFLICT:%', cur;
  end if;

  ts := now();
  update public.planners
     set data = p_data, updated_at = ts, updated_by = auth.uid()
   where id = p_id;

  return ts;
end $$;

-- 초대 링크 무효화 (소유자만). 새 코드를 돌려줍니다.
create or replace function public.rotate_invite(p_id uuid)
returns text language plpgsql security definer set search_path = public as $$
declare code text;
begin
  if not public.is_owner(p_id) then raise exception '소유자만 초대 링크를 바꿀 수 있습니다'; end if;
  code := replace(gen_random_uuid()::text,'-','');
  update public.planners set invite_code = code where id = p_id;
  return code;
end $$;

grant execute on function public.create_planner(text)                              to authenticated;
grant execute on function public.join_planner(text)                                to authenticated;
grant execute on function public.save_planner(uuid, jsonb, timestamptz, boolean)   to authenticated;
grant execute on function public.rotate_invite(uuid)                               to authenticated;

-- ── 6) v1 데이터 이사 (planner_data → planners) ─────────────
do $$
begin
  if to_regclass('public.planner_data') is not null then

    insert into public.planners (owner_id, title, data, updated_at, updated_by)
    select pd.user_id, '내 휴가 플래너', pd.data, pd.updated_at, pd.user_id
      from public.planner_data pd
     where not exists (
       select 1 from public.planners p where p.owner_id = pd.user_id
     );

    insert into public.planner_members (planner_id, user_id, role)
    select p.id, p.owner_id, 'owner'
      from public.planners p
    on conflict (planner_id, user_id) do nothing;

  end if;
end $$;

-- v1 테이블은 일부러 남겨둡니다. 위 이사가 잘 됐는지 확인한 뒤
-- 직접 지우세요:  drop table public.planner_data;

-- ── 확인용 ────────────────────────────────────────────────
-- select id, title, invite_code, updated_at from public.planners;
-- select * from public.planner_members;
