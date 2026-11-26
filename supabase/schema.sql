begin;

create table public.admins (
  user_id uuid primary key references auth.users on delete cascade
);
alter table public.admins enable row level security;
revoke all on public.admins from anon, authenticated;

create function public.is_admin() returns boolean
language sql stable security definer set search_path = ''
as $$ select exists(select 1 from public.admins where user_id = auth.uid()) $$;
revoke all on function public.is_admin() from public;
grant execute on function public.is_admin() to authenticated, anon;

create table public.links (
  id uuid primary key default gen_random_uuid(),
  submitted_by uuid default auth.uid() references auth.users on delete set null,
  title text not null check (length(trim(title)) between 2 and 100),
  url text not null check (length(url) <= 2048 and url ~* '^https?://[a-z0-9][a-z0-9.-]*(:[0-9]+)?([/?#][^[:space:]]*)?$'),
  category text not null check (category in ('Sumber resmi','Materi belajar','Latihan & tryout','Grup WA & Telegram','Pengalaman peserta')),
  price text not null check (price in ('Gratis','Berbayar','Campuran')),
  description text not null check (length(trim(description)) between 5 and 500),
  status text not null default 'pending' check (status in ('pending','published','rejected','archived')),
  official boolean not null default false,
  reviewed_at timestamptz,
  created_at timestamptz not null default now()
);
create unique index links_url_unique on public.links ((rtrim(split_part(url, '#', 1), '/'))) where status in ('pending','published');

create table public.feedback (
  id uuid primary key default gen_random_uuid(),
  link_id uuid not null references public.links on delete cascade,
  author_id uuid not null default auth.uid() references auth.users on delete cascade,
  kind text not null check (kind in ('active','report')),
  reason text check (length(reason) <= 500),
  resolution text check (length(trim(resolution)) between 2 and 500),
  created_at timestamptz not null default now(),
  check ((kind = 'active' and reason is null) or (kind = 'report' and length(trim(coalesce(reason,''))) >= 5))
);
create unique index feedback_unique on public.feedback(link_id, author_id, kind) where resolution is null;

create table public.moderation_log (
  id bigint generated always as identity primary key,
  link_id uuid not null references public.links,
  admin_id uuid references auth.users on delete set null,
  action text not null,
  note text not null,
  created_at timestamptz not null default now()
);

alter table public.links enable row level security;
alter table public.feedback enable row level security;
alter table public.moderation_log enable row level security;
revoke all on public.links, public.feedback, public.moderation_log from anon, authenticated;
grant select (id,title,url,category,price,description,status,official,reviewed_at,created_at) on public.links to anon, authenticated;
grant select (id,link_id,kind,reason,resolution,created_at) on public.feedback to authenticated;
grant select on public.moderation_log to authenticated;
grant insert (title,url,category,price,description) on public.links to authenticated;
grant insert (link_id,kind,reason) on public.feedback to authenticated;

create policy read_links on public.links for select to anon, authenticated
using (status = 'published' or public.is_admin() or submitted_by = auth.uid());
create policy submit_links on public.links for insert to authenticated
with check (submitted_by = auth.uid() and status = 'pending' and not official);
create policy read_feedback on public.feedback for select to authenticated
using (author_id = auth.uid() or public.is_admin());
create policy submit_feedback on public.feedback for insert to authenticated
with check (author_id = auth.uid() and exists(select 1 from public.links where id = link_id and status = 'published'));
create policy read_moderation on public.moderation_log for select to authenticated using (public.is_admin());

create function public.active_checks()
returns table(link_id uuid, confirmations bigint, last_checked timestamptz)
language sql stable security definer set search_path = ''
as $$
  select f.link_id, count(*), max(f.created_at)
  from public.feedback f join public.links l on l.id = f.link_id
  where f.kind = 'active' and f.resolution is null and l.status = 'published'
  group by f.link_id
$$;
revoke all on function public.active_checks() from public;
grant execute on function public.active_checks() to anon, authenticated;

create function public.moderate_link(
  target uuid, expected_url text, new_title text, new_url text, new_category text,
  new_price text, new_description text, new_status text, new_official boolean, note text
) returns void language plpgsql security definer set search_path = '' as $$
declare previous_url text;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if length(trim(coalesce(note,''))) not between 2 and 500 then raise exception 'Isi alasan moderasi'; end if;
  select url into strict previous_url from public.links where id = target for update;
  if previous_url is distinct from expected_url then raise exception 'URL sudah berubah. Muat ulang dan tinjau kembali.'; end if;
  if new_url <> previous_url then
    new_status := 'pending';
    new_official := false;
    update public.feedback set resolution = 'URL telah diganti' where link_id = target and resolution is null;
  end if;
  update public.links set title = new_title, url = new_url, category = new_category,
    price = new_price, description = new_description, status = new_status,
    official = new_official and new_status = 'published',
    reviewed_at = case when new_status = 'published' then now() end
  where id = target;
  insert into public.moderation_log(link_id,admin_id,action,note)
  values(target,auth.uid(),new_status,note);
end $$;
revoke all on function public.moderate_link(uuid,text,text,text,text,text,text,text,boolean,text) from public;
grant execute on function public.moderate_link(uuid,text,text,text,text,text,text,text,boolean,text) to authenticated;

create function public.resolve_report(target uuid, note text)
returns void language plpgsql security definer set search_path = '' as $$
declare affected_link uuid;
begin
  if not public.is_admin() then raise exception 'Akses admin diperlukan'; end if;
  if length(trim(coalesce(note,''))) not between 2 and 500 then raise exception 'Isi hasil peninjauan'; end if;
  update public.feedback set resolution = note where id = target and kind = 'report' and resolution is null
  returning link_id into strict affected_link;
  insert into public.moderation_log(link_id,admin_id,action,note)
  values(affected_link,auth.uid(),'report_resolved',note);
end $$;
revoke all on function public.resolve_report(uuid,text) from public;
grant execute on function public.resolve_report(uuid,text) to authenticated;

insert into public.links(title,url,category,price,description,status,official)
values
('SSCASN','https://sscasn.bkn.go.id','Sumber resmi','Gratis','Portal BKN untuk informasi dan pendaftaran seleksi calon aparatur sipil negara.','published',true),
('Badan Kepegawaian Negara','https://www.bkn.go.id','Sumber resmi','Gratis','Situs BKN untuk membaca pengumuman dan informasi kepegawaian.','published',true);
commit;
