begin;

create table public.tips (
  id uuid primary key default gen_random_uuid(),
  author_id uuid default auth.uid() references auth.users on delete set null,
  title text not null check (length(trim(title)) between 5 and 120),
  stage text not null check (stage in ('Administrasi','SKD','SKB','Pemberkasan','Lainnya')),
  body text not null check (length(trim(body)) between 20 and 5000),
  selection_year integer check (selection_year between 2000 and 2100),
  source_url text check (length(source_url) <= 2048 and source_url ~* '^https?://[a-z0-9][a-z0-9.-]*(:[0-9]+)?([/?#][^[:space:]]*)?$'),
  status text not null default 'pending' check (status in ('pending','published','rejected','archived')),
  created_at timestamptz not null default now()
);

create table public.tip_feedback (
  id uuid primary key default gen_random_uuid(),
  tip_id uuid not null references public.tips on delete cascade,
  author_id uuid not null default auth.uid() references auth.users on delete cascade,
  kind text not null check (kind in ('helpful','report')),
  reason text,
  resolved_at timestamptz,
  created_at timestamptz not null default now(),
  check ((kind = 'helpful' and reason is null) or (kind = 'report' and length(trim(coalesce(reason,''))) between 5 and 500))
);
create unique index tip_feedback_open_unique on public.tip_feedback(tip_id,author_id,kind) where resolved_at is null;

create table public.tip_moderation (
  id bigint generated always as identity primary key,
  tip_id uuid not null references public.tips,
  admin_id uuid references auth.users on delete set null,
  action text not null,
  note text not null,
  created_at timestamptz not null default now()
);

alter table public.tips enable row level security;
alter table public.tip_feedback enable row level security;
alter table public.tip_moderation enable row level security;
revoke all on public.tips, public.tip_feedback, public.tip_moderation from anon, authenticated;
grant select (id,title,stage,body,selection_year,source_url,status,created_at) on public.tips to anon, authenticated;
grant insert (title,stage,body,selection_year,source_url) on public.tips to authenticated;
grant select (id,tip_id,kind,reason,resolved_at,created_at) on public.tip_feedback to authenticated;
grant insert (tip_id,kind,reason) on public.tip_feedback to authenticated;
grant select on public.tip_moderation to authenticated;

create policy read_tips on public.tips for select to anon, authenticated
using (status = 'published' or author_id = auth.uid() or public.is_admin());
create policy submit_tips on public.tips for insert to authenticated
with check (author_id = auth.uid() and status = 'pending');
create policy read_tip_feedback on public.tip_feedback for select to authenticated
using (author_id = auth.uid() or public.is_admin());
create policy submit_tip_feedback on public.tip_feedback for insert to authenticated
with check (author_id = auth.uid() and exists (
  select 1 from public.tips where id = tip_id and status = 'published'
));
create policy read_tip_moderation on public.tip_moderation for select to authenticated
using (public.is_admin());

create function public.tip_helpful_counts() returns table(tip_id uuid, total bigint)
language sql stable security definer set search_path = ''
as $$
  select f.tip_id, count(*) from public.tip_feedback f join public.tips t on t.id = f.tip_id
  where f.kind = 'helpful' and t.status = 'published' group by f.tip_id
$$;

create function public.moderate_tip(
  target uuid, expected_status text, new_title text, new_stage text, new_body text,
  new_year integer, new_source text, new_status text, note text
) returns void language plpgsql security definer set search_path = '' as $$
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if length(trim(coalesce(note,''))) not between 2 and 500 then raise exception 'Isi alasan moderasi'; end if;
  update public.tips set title = new_title, stage = new_stage, body = new_body,
    selection_year = new_year, source_url = new_source, status = new_status
  where id = target and status = expected_status;
  if not found then raise exception 'Status tips sudah berubah. Muat ulang dan tinjau kembali.'; end if;
  insert into public.tip_moderation(tip_id,admin_id,action,note) values(target,auth.uid(),new_status,note);
end $$;

create function public.resolve_tip_report(target uuid, note text)
returns void language plpgsql security definer set search_path = '' as $$
declare affected_tip uuid;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if length(trim(coalesce(note,''))) not between 2 and 500 then raise exception 'Isi hasil peninjauan'; end if;
  update public.tip_feedback set resolved_at = now()
  where id = target and kind = 'report' and resolved_at is null
  returning tip_id into strict affected_tip;
  insert into public.tip_moderation(tip_id,admin_id,action,note) values(affected_tip,auth.uid(),'report_resolved',note);
end $$;

revoke all on function public.tip_helpful_counts(), public.moderate_tip(uuid,text,text,text,text,integer,text,text,text), public.resolve_tip_report(uuid,text) from public;
grant execute on function public.tip_helpful_counts() to anon, authenticated;
grant execute on function public.moderate_tip(uuid,text,text,text,text,integer,text,text,text), public.resolve_tip_report(uuid,text) to authenticated;

commit;
