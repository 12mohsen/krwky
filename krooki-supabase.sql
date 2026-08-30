-- ============================================================
--  كروكي — إعداد المزامنة السحابية على Supabase
--  الصق هذا كله مرة واحدة في:  SQL Editor  ثم اضغط Run
--  لا يعدّل أي جدول من تطبيقاتك الأخرى — يستخدم users كما هو
-- ============================================================

-- 1) جدول مشاريع كروكي
create table if not exists public.krooki_projects (
  id          text primary key,
  user_id     text not null,
  name        text not null default 'مخطط',
  walls       int  not null default 0,
  thumb       text,
  data        text not null,
  updated_at  timestamptz not null default now()
);

create index if not exists krooki_projects_user_idx
  on public.krooki_projects (user_id, updated_at desc);

-- 2) إقفال الجدول تماماً: لا أحد يصل إليه مباشرة بالمفتاح العام
alter table public.krooki_projects enable row level security;
revoke all on public.krooki_projects from anon, authenticated;

-- 3) دالة تحقق داخلية (تقبل صيغتَي التشفير المستعملتين في تطبيقاتك)
create or replace function public.krooki_auth(p_user text, p_hash text, p_alt text)
returns boolean
language sql
security definer
set search_path = public
as $$
  select exists (
    select 1 from public.users u
    where u.user_id = p_user
      and (u.pass_hash = p_hash or u.pass_hash = p_alt)
  );
$$;

-- 4) إنشاء مستخدم جديد لكروكي (إن لم يكن موجوداً)
create or replace function public.krooki_signup(p_user text, p_hash text, p_hint text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if length(coalesce(p_user,'')) < 2 then raise exception 'اسم مستخدم قصير'; end if;
  if exists (select 1 from public.users where user_id = p_user) then
    raise exception 'اسم المستخدم موجود مسبقاً';
  end if;
  insert into public.users (user_id, pass_hash, hint, created_from, created_at)
  values (p_user, p_hash, coalesce(nullif(p_hint,''),'EMPTY'), 'krooki', now());
  return p_user;
end;
$$;

-- 5) قائمة مشاريع المستخدم (بدون بيانات المخطط الثقيلة)
create or replace function public.krooki_list(p_user text, p_hash text, p_alt text)
returns table (id text, name text, walls int, thumb text, updated_at timestamptz)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.krooki_auth(p_user, p_hash, p_alt) then raise exception 'بيانات دخول غير صحيحة'; end if;
  return query
    select k.id, k.name, k.walls, k.thumb, k.updated_at
    from public.krooki_projects k
    where k.user_id = p_user
    order by k.updated_at desc;
end;
$$;

-- 6) فتح مشروع واحد
create or replace function public.krooki_get(p_user text, p_hash text, p_alt text, p_id text)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare v text;
begin
  if not public.krooki_auth(p_user, p_hash, p_alt) then raise exception 'بيانات دخول غير صحيحة'; end if;
  select k.data into v from public.krooki_projects k
   where k.user_id = p_user and k.id = p_id;
  if v is null then raise exception 'المشروع غير موجود'; end if;
  return v;
end;
$$;

-- 7) حفظ / تحديث مشروع
create or replace function public.krooki_save(
  p_user text, p_hash text, p_alt text,
  p_id text, p_name text, p_walls int, p_thumb text, p_data text)
returns text
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.krooki_auth(p_user, p_hash, p_alt) then raise exception 'بيانات دخول غير صحيحة'; end if;
  insert into public.krooki_projects (id, user_id, name, walls, thumb, data, updated_at)
  values (p_id, p_user, p_name, coalesce(p_walls,0), p_thumb, p_data, now())
  on conflict (id) do update
    set name = excluded.name,
        walls = excluded.walls,
        thumb = excluded.thumb,
        data  = excluded.data,
        updated_at = now()
    where public.krooki_projects.user_id = p_user;
  return p_id;
end;
$$;

-- 8) حذف مشروع
create or replace function public.krooki_del(p_user text, p_hash text, p_alt text, p_id text)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.krooki_auth(p_user, p_hash, p_alt) then raise exception 'بيانات دخول غير صحيحة'; end if;
  delete from public.krooki_projects where user_id = p_user and id = p_id;
end;
$$;

-- 9) الصلاحيات: التطبيق ينادي الدوال فقط، لا الجداول
grant execute on function public.krooki_signup(text,text,text) to anon, authenticated;
grant execute on function public.krooki_list(text,text,text) to anon, authenticated;
grant execute on function public.krooki_get(text,text,text,text) to anon, authenticated;
grant execute on function public.krooki_save(text,text,text,text,text,int,text,text) to anon, authenticated;
grant execute on function public.krooki_del(text,text,text,text) to anon, authenticated;
revoke execute on function public.krooki_auth(text,text,text) from anon, authenticated;

-- تم. لا حاجة لأي إعداد آخر.
