-- =====================================================================
-- BDJ Studio License · RBAC real en servidor (Supabase Auth + RLS)
-- Idempotente: se puede ejecutar más de una vez en el SQL Editor.
--
-- Roles:
--   super_admin    → david.zapata@bdjstudio.com (todo, protegido)
--   license_admin  → maylor.neyra@bdjstudio.com (CRUD de licencias; editable)
--   operator       → prueba@bdjstudio.com       (solo crear y buscar)
--   auditor        → solo lectura
--   custom         → permisos por usuario (admin_accounts.permissions)
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Tablas base (se crean si no existen; si existen se completan)
-- ---------------------------------------------------------------------
create table if not exists public.customers (
  id          text primary key,
  name        text not null,
  email       text not null,
  device      text not null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

create table if not exists public.licenses (
  id                  text primary key,
  customer_id         text references public.customers(id) on delete cascade,
  customer_name       text,
  product             text not null,
  device              text not null,
  plan                text not null,
  token               text,
  status              text not null default 'active',
  issued_at           timestamptz not null default now(),
  expires_at          timestamptz,
  exact_version       text,
  hwid_schema_version text not null default 'V2',
  issued_by           text,
  updated_at          timestamptz not null default now()
);

create table if not exists public.admin_accounts (
  id          text primary key,
  email       text not null,
  role        text not null default 'operator',
  is_active   boolean not null default true,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

alter table public.customers add column if not exists updated_at timestamptz not null default now();

alter table public.licenses add column if not exists customer_name       text;
alter table public.licenses add column if not exists token               text;
alter table public.licenses add column if not exists status              text not null default 'active';
alter table public.licenses add column if not exists expires_at          timestamptz;
alter table public.licenses add column if not exists exact_version       text;
alter table public.licenses add column if not exists hwid_schema_version text not null default 'V2';
alter table public.licenses add column if not exists issued_by           text;
alter table public.licenses add column if not exists updated_at          timestamptz not null default now();
-- La versión ya no se valida en ninguna app: la columna queda solo informativa.
alter table public.licenses alter column exact_version drop not null;

alter table public.admin_accounts add column if not exists user_id     uuid;
alter table public.admin_accounts add column if not exists permissions jsonb;
alter table public.admin_accounts add column if not exists created_at  timestamptz not null default now();
alter table public.admin_accounts add column if not exists updated_at  timestamptz not null default now();

create index if not exists licenses_customer_id_idx on public.licenses(customer_id);
create index if not exists licenses_device_idx      on public.licenses(device);

-- ---------------------------------------------------------------------
-- 2. Catálogo de roles
-- ---------------------------------------------------------------------
create table if not exists public.roles (
  id          text primary key,
  name        text not null,
  description text not null default '',
  permissions jsonb not null default '{}'::jsonb,
  is_system   boolean not null default false,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- Los permisos solo se siembran la primera vez: luego se editan desde la app.
insert into public.roles (id, name, description, permissions, is_system) values
  ('super_admin', 'Super Administrador',
   'Acceso total e irrestricto a todos los módulos (Creador).',
   '{"gestion":{"create":true,"read":true,"update":true,"delete":true},"usuarios":{"create":true,"read":true,"update":true,"delete":true}}', true),
  ('license_admin', 'Administrador de Licencias',
   'CRUD completo del módulo de licencias. Sin acceso a Usuarios.',
   '{"gestion":{"create":true,"read":true,"update":true,"delete":true},"usuarios":{"create":false,"read":false,"update":false,"delete":false}}', true),
  ('operator', 'Operador de Licencias',
   'Solo crear y buscar licencias. No puede actualizar ni eliminar.',
   '{"gestion":{"create":true,"read":true,"update":false,"delete":false},"usuarios":{"create":false,"read":false,"update":false,"delete":false}}', true),
  ('auditor', 'Auditor (Solo Lectura)',
   'Búsqueda y consulta de licencias y clientes.',
   '{"gestion":{"create":false,"read":true,"update":false,"delete":false},"usuarios":{"create":false,"read":false,"update":false,"delete":false}}', true),
  ('custom', 'Personalizado',
   'Permisos definidos individualmente en cada usuario.',
   '{}', true)
on conflict (id) do update
  set name = excluded.name,
      description = excluded.description,
      is_system = true;

-- super_admin siempre con todo (no editable).
update public.roles
   set permissions = '{"gestion":{"create":true,"read":true,"update":true,"delete":true},"usuarios":{"create":true,"read":true,"update":true,"delete":true}}'
 where id = 'super_admin';

-- ---------------------------------------------------------------------
-- 3. Normalizar admin_accounts existentes
-- ---------------------------------------------------------------------
-- Formato antiguo "custom:{json}" → role=custom + permissions jsonb
update public.admin_accounts
   set permissions = substring(role from 8)::jsonb,
       role = 'custom'
 where role like 'custom:%';

update public.admin_accounts set role = 'super_admin' where role in ('super', 'Super Admin');
update public.admin_accounts set role = 'operator'
 where role not in (select id from public.roles);

update public.admin_accounts set email = lower(trim(email));

-- Contraseñas: ahora las gestiona Supabase Auth. Los hashes PBKDF2 quedaban
-- legibles con la anon key, así que se eliminan.
alter table public.admin_accounts drop column if exists password_hash;
alter table public.admin_accounts drop column if exists password_salt;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'admin_accounts_role_fkey') then
    alter table public.admin_accounts
      add constraint admin_accounts_role_fkey foreign key (role)
      references public.roles(id) on update cascade;
  end if;
  if not exists (select 1 from pg_constraint where conname = 'admin_accounts_user_id_fkey') then
    alter table public.admin_accounts
      add constraint admin_accounts_user_id_fkey foreign key (user_id)
      references auth.users(id) on delete set null;
  end if;
end $$;

create unique index if not exists admin_accounts_email_lower_key on public.admin_accounts (lower(email));
create unique index if not exists admin_accounts_user_id_key on public.admin_accounts (user_id);

-- Asignaciones pedidas
insert into public.admin_accounts (id, email, role, is_active)
select v.email, v.email, v.role, true
  from (values
    ('david.zapata@bdjstudio.com', 'super_admin'),
    ('maylor.neyra@bdjstudio.com', 'license_admin')
  ) as v(email, role)
 where not exists (select 1 from public.admin_accounts a where lower(a.email) = v.email);

update public.admin_accounts set role = 'super_admin',   permissions = null, is_active = true where email = 'david.zapata@bdjstudio.com';
update public.admin_accounts set role = 'license_admin', permissions = null where email = 'maylor.neyra@bdjstudio.com';
-- prueba@bdjstudio.com se crea desde la consola (Usuarios → rol Operador de Licencias).
update public.admin_accounts set role = 'operator',      permissions = null where email = 'prueba@bdjstudio.com';

-- ---------------------------------------------------------------------
-- 4. Vincular admin_accounts ↔ auth.users por correo
-- ---------------------------------------------------------------------
update public.admin_accounts a
   set user_id = u.id
  from auth.users u
 where lower(u.email) = a.email
   and a.user_id is null;

create or replace function public.link_admin_account()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.admin_accounts
     set user_id = new.id
   where email = lower(new.email)
     and user_id is null;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created_link_admin on auth.users;
create trigger on_auth_user_created_link_admin
  after insert on auth.users
  for each row execute function public.link_admin_account();

-- ---------------------------------------------------------------------
-- 5. Funciones de autorización (se evalúan en el servidor)
-- ---------------------------------------------------------------------
create or replace function public.current_admin_role()
returns text
language sql
stable
security definer
set search_path = public, auth
as $$
  select a.role
    from public.admin_accounts a
    join auth.users u on u.id = a.user_id
   where a.user_id = auth.uid()
     and a.is_active
     and u.email_confirmed_at is not null
   limit 1;
$$;

create or replace function public.is_super_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(public.current_admin_role() = 'super_admin', false);
$$;

create or replace function public.has_perm(p_module text, p_action text)
returns boolean
language sql
stable
security definer
set search_path = public, auth
as $$
  select coalesce((
    select case
             when a.role = 'super_admin' then true
             when a.role = 'custom'
               then coalesce((a.permissions -> p_module ->> p_action)::boolean, false)
             else coalesce((r.permissions -> p_module ->> p_action)::boolean, false)
           end
      from public.admin_accounts a
      join public.roles r on r.id = a.role
      join auth.users u   on u.id = a.user_id
     where a.user_id = auth.uid()
       and a.is_active
       and u.email_confirmed_at is not null
     limit 1
  ), false);
$$;

revoke all on function public.has_perm(text, text)   from public, anon;
revoke all on function public.is_super_admin()       from public, anon;
revoke all on function public.current_admin_role()   from public, anon;
grant execute on function public.has_perm(text, text) to authenticated;
grant execute on function public.is_super_admin()     to authenticated;
grant execute on function public.current_admin_role() to authenticated;

-- ---------------------------------------------------------------------
-- 6. Guardas de integridad (anti escalamiento de privilegios)
-- ---------------------------------------------------------------------
create or replace function public.guard_admin_accounts()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_super boolean := public.is_super_admin();
begin
  -- Cambios internos (triggers/SQL Editor) no pasan por aquí con auth.uid()
  if auth.uid() is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    new.email := lower(trim(new.email));
    new.user_id := (select id from auth.users where lower(email) = new.email limit 1);
    if new.role = 'super_admin' and not v_super then
      raise exception 'Solo el Super Administrador puede crear otro Super Administrador' using errcode = '42501';
    end if;
    if new.role = 'custom' and not v_super then
      raise exception 'Solo el Super Administrador asigna permisos personalizados' using errcode = '42501';
    end if;
    if new.role <> 'custom' then
      new.permissions := null;
    end if;
    return new;
  end if;

  if tg_op = 'UPDATE' then
    if new.user_id is distinct from old.user_id then
      raise exception 'user_id no se puede modificar' using errcode = '42501';
    end if;
    new.email := lower(trim(new.email));
    if old.role = 'super_admin' and not v_super then
      raise exception 'No puedes modificar a un Super Administrador' using errcode = '42501';
    end if;
    if (new.role is distinct from old.role or new.permissions is distinct from old.permissions)
       and not v_super then
      raise exception 'Solo el Super Administrador cambia roles o permisos' using errcode = '42501';
    end if;
    if old.role = 'super_admin'
       and (new.role <> 'super_admin' or not new.is_active)
       and (select count(*) from public.admin_accounts
             where role = 'super_admin' and is_active and id <> old.id) = 0 then
      raise exception 'Debe existir al menos un Super Administrador activo' using errcode = '42501';
    end if;
    if new.role <> 'custom' then
      new.permissions := null;
    end if;
    new.updated_at := now();
    return new;
  end if;

  -- DELETE
  if old.role = 'super_admin' then
    raise exception 'Un Super Administrador no se puede eliminar desde la app' using errcode = '42501';
  end if;
  if old.user_id = auth.uid() then
    raise exception 'No puedes eliminar tu propia cuenta' using errcode = '42501';
  end if;
  return old;
end;
$$;

drop trigger if exists guard_admin_accounts on public.admin_accounts;
create trigger guard_admin_accounts
  before insert or update or delete on public.admin_accounts
  for each row execute function public.guard_admin_accounts();

create or replace function public.guard_roles()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    return coalesce(new, old);
  end if;
  if tg_op = 'DELETE' then
    if old.is_system then
      raise exception 'Los roles del sistema no se pueden eliminar' using errcode = '42501';
    end if;
    return old;
  end if;
  if tg_op = 'UPDATE' and old.id = 'super_admin' then
    raise exception 'El rol Super Administrador no se puede editar' using errcode = '42501';
  end if;
  if tg_op = 'INSERT' then
    new.is_system := false;
  else
    new.is_system := old.is_system;
    new.id := old.id;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists guard_roles on public.roles;
create trigger guard_roles
  before insert or update or delete on public.roles
  for each row execute function public.guard_roles();

-- "Creada por" siempre es el usuario autenticado (no se puede falsificar).
create or replace function public.stamp_license_issuer()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is not null then
    if tg_op = 'INSERT' then
      new.issued_by := coalesce(auth.jwt() ->> 'email', new.issued_by);
    else
      new.issued_by := old.issued_by;
    end if;
  end if;
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists stamp_license_issuer on public.licenses;
create trigger stamp_license_issuer
  before insert or update on public.licenses
  for each row execute function public.stamp_license_issuer();

-- ---------------------------------------------------------------------
-- 7. Row Level Security
-- ---------------------------------------------------------------------
alter table public.customers      enable row level security;
alter table public.licenses       enable row level security;
alter table public.admin_accounts enable row level security;
alter table public.roles          enable row level security;

-- La anon key ya no puede tocar nada.
revoke all on public.customers, public.licenses, public.admin_accounts, public.roles from anon;
grant select, insert, update, delete on public.customers, public.licenses, public.admin_accounts, public.roles to authenticated;

-- Limpiar políticas previas (si las hubiera)
do $$
declare p record;
begin
  for p in
    select schemaname, tablename, policyname from pg_policies
     where schemaname = 'public'
       and tablename in ('customers', 'licenses', 'admin_accounts', 'roles')
  loop
    execute format('drop policy %I on %I.%I', p.policyname, p.schemaname, p.tablename);
  end loop;
end $$;

-- customers / licenses → módulo "gestion"
create policy customers_select on public.customers for select to authenticated using (public.has_perm('gestion', 'read'));
create policy customers_insert on public.customers for insert to authenticated with check (public.has_perm('gestion', 'create'));
create policy customers_update on public.customers for update to authenticated using (public.has_perm('gestion', 'update')) with check (public.has_perm('gestion', 'update'));
create policy customers_delete on public.customers for delete to authenticated using (public.has_perm('gestion', 'delete'));

create policy licenses_select on public.licenses for select to authenticated using (public.has_perm('gestion', 'read'));
create policy licenses_insert on public.licenses for insert to authenticated with check (public.has_perm('gestion', 'create'));
create policy licenses_update on public.licenses for update to authenticated using (public.has_perm('gestion', 'update')) with check (public.has_perm('gestion', 'update'));
create policy licenses_delete on public.licenses for delete to authenticated using (public.has_perm('gestion', 'delete'));

-- admin_accounts → módulo "usuarios" (cada quien ve su propia fila)
create policy admins_select on public.admin_accounts for select to authenticated
  using (user_id = auth.uid() or public.has_perm('usuarios', 'read'));
create policy admins_insert on public.admin_accounts for insert to authenticated
  with check (public.has_perm('usuarios', 'create'));
create policy admins_update on public.admin_accounts for update to authenticated
  using (public.has_perm('usuarios', 'update')) with check (public.has_perm('usuarios', 'update'));
create policy admins_delete on public.admin_accounts for delete to authenticated
  using (public.has_perm('usuarios', 'delete'));

-- roles → cualquier admin activo los lee; solo el Super Admin los edita
create policy roles_select on public.roles for select to authenticated
  using (public.current_admin_role() is not null);
create policy roles_write on public.roles for all to authenticated
  using (public.is_super_admin()) with check (public.is_super_admin());

commit;

-- ---------------------------------------------------------------------
-- Verificación rápida (ejecutar aparte):
--   select email, role, user_id is not null as vinculado, is_active from public.admin_accounts order by role;
--   select tablename, rowsecurity from pg_tables where schemaname='public';
-- ---------------------------------------------------------------------
