-- =====================================================================
-- BDJ Studio License · RBAC con 3 módulos + gestión de contraseñas
-- Requiere 20260926_rbac_rls.sql. Idempotente.
--
-- Módulos:  gestion (licencias y clientes) · usuarios · roles (permisos y accesos)
-- Funciones RPC:
--   admin_create_user(email, password, role, permissions)  → usuarios.create
--   admin_set_password(email, password)                    → solo Super Admin
-- =====================================================================

begin;

-- ---------------------------------------------------------------------
-- 1. Módulo "roles" en la matriz de permisos
-- ---------------------------------------------------------------------
update public.roles
   set permissions = '{"gestion":{"create":true,"read":true,"update":true,"delete":true},"usuarios":{"create":true,"read":true,"update":true,"delete":true},"roles":{"create":true,"read":true,"update":true,"delete":true}}'
 where id = 'super_admin';

update public.roles
   set permissions = permissions || '{"roles":{"create":false,"read":false,"update":false,"delete":false}}'::jsonb
 where id not in ('super_admin', 'custom')
   and not (permissions ? 'roles');

update public.admin_accounts
   set permissions = permissions || '{"roles":{"create":false,"read":false,"update":false,"delete":false}}'::jsonb
 where role = 'custom'
   and permissions is not null
   and not (permissions ? 'roles');

update public.roles set description = 'Acceso total a Gestión, Usuarios y Roles (Creador).'           where id = 'super_admin';
update public.roles set description = 'CRUD completo de licencias. Sin acceso a Usuarios ni Roles.'   where id = 'license_admin';
update public.roles set description = 'Solo crear y buscar licencias. No puede actualizar ni eliminar.' where id = 'operator';
update public.roles set description = 'Solo búsqueda y consulta de licencias y clientes.'            where id = 'auditor';

-- ---------------------------------------------------------------------
-- 2. ¿Los permisos pedidos exceden los del usuario actual?
--    (nadie puede otorgar lo que él mismo no tiene)
-- ---------------------------------------------------------------------
create or replace function public.exceeds_own_perms(p_perms jsonb)
returns boolean
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  m record;
  a record;
begin
  if public.is_super_admin() or p_perms is null then
    return false;
  end if;
  for m in select key, value from jsonb_each(p_perms) loop
    if jsonb_typeof(m.value) <> 'object' then continue; end if;
    for a in select key, value from jsonb_each(m.value) loop
      if a.value = 'true'::jsonb and not public.has_perm(m.key, a.key) then
        return true;
      end if;
    end loop;
  end loop;
  return false;
end;
$$;

revoke all on function public.exceeds_own_perms(jsonb) from public, anon;
grant execute on function public.exceeds_own_perms(jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 3. Guardas actualizadas
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
  if auth.uid() is null then
    return coalesce(new, old);
  end if;

  if tg_op = 'INSERT' then
    new.email := lower(trim(new.email));
    new.user_id := (select id from auth.users where lower(email) = new.email limit 1);
    if new.role = 'super_admin' and not v_super then
      raise exception 'Solo el Super Administrador puede crear otro Super Administrador' using errcode = '42501';
    end if;
    if new.role = 'custom' then
      if not public.has_perm('roles', 'update') then
        raise exception 'Necesitas permiso de Roles para asignar permisos personalizados' using errcode = '42501';
      end if;
      if public.exceeds_own_perms(new.permissions) then
        raise exception 'No puedes otorgar permisos que tú no tienes' using errcode = '42501';
      end if;
    else
      new.permissions := null;
      if public.exceeds_own_perms((select permissions from public.roles where id = new.role)) then
        raise exception 'No puedes asignar un rol con más permisos que el tuyo' using errcode = '42501';
      end if;
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
    if new.role is distinct from old.role or new.permissions is distinct from old.permissions then
      if old.user_id = auth.uid() and not v_super then
        raise exception 'No puedes cambiar tu propio rol' using errcode = '42501';
      end if;
      if new.role = 'super_admin' and not v_super then
        raise exception 'Solo el Super Administrador asigna ese rol' using errcode = '42501';
      end if;
      if new.role = 'custom' then
        if not public.has_perm('roles', 'update') then
          raise exception 'Necesitas permiso de Roles para asignar permisos personalizados' using errcode = '42501';
        end if;
        if public.exceeds_own_perms(new.permissions) then
          raise exception 'No puedes otorgar permisos que tú no tienes' using errcode = '42501';
        end if;
      elsif public.exceeds_own_perms((select permissions from public.roles where id = new.role)) then
        raise exception 'No puedes asignar un rol con más permisos que el tuyo' using errcode = '42501';
      end if;
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
    if exists (select 1 from public.admin_accounts where role = old.id) then
      raise exception 'El rol está asignado a usuarios: reasígnalos antes de eliminarlo' using errcode = '42501';
    end if;
    return old;
  end if;

  if tg_op = 'UPDATE' then
    if old.id in ('super_admin', 'custom') then
      raise exception 'Este rol no se puede editar' using errcode = '42501';
    end if;
    if old.id = public.current_admin_role() and not public.is_super_admin() then
      raise exception 'No puedes editar el rol que tienes asignado' using errcode = '42501';
    end if;
    new.id := old.id;
    new.is_system := old.is_system;
  else
    new.is_system := false;
  end if;

  if public.exceeds_own_perms(new.permissions) then
    raise exception 'No puedes otorgar permisos que tú no tienes' using errcode = '42501';
  end if;
  new.updated_at := now();
  return new;
end;
$$;

-- ---------------------------------------------------------------------
-- 4. Políticas de la tabla roles → módulo "roles"
-- ---------------------------------------------------------------------
drop policy if exists roles_select on public.roles;
drop policy if exists roles_write  on public.roles;
drop policy if exists roles_insert on public.roles;
drop policy if exists roles_update on public.roles;
drop policy if exists roles_delete on public.roles;

-- Todos los usuarios activos leen el catálogo (nombres de rol en pantalla).
create policy roles_select on public.roles for select to authenticated
  using (public.current_admin_role() is not null);
create policy roles_insert on public.roles for insert to authenticated
  with check (public.has_perm('roles', 'create'));
create policy roles_update on public.roles for update to authenticated
  using (public.has_perm('roles', 'update')) with check (public.has_perm('roles', 'update'));
create policy roles_delete on public.roles for delete to authenticated
  using (public.has_perm('roles', 'delete'));

-- ---------------------------------------------------------------------
-- 5. RPC: crear usuario (cuenta de acceso ya confirmada + rol)
-- ---------------------------------------------------------------------
create or replace function public.admin_create_user(
  p_email       text,
  p_password    text,
  p_role        text,
  p_permissions jsonb default null
)
returns text
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_email text := lower(trim(p_email));
  v_id    uuid;
begin
  if not public.has_perm('usuarios', 'create') then
    raise exception 'No tienes permiso para crear usuarios' using errcode = '42501';
  end if;
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    raise exception 'Correo no válido';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;
  if not exists (select 1 from public.roles where id = p_role) then
    raise exception 'El rol % no existe', p_role;
  end if;
  if exists (select 1 from public.admin_accounts where email = v_email) then
    raise exception 'Ese usuario ya existe';
  end if;

  select id into v_id from auth.users where lower(email) = v_email;
  if v_id is null then
    v_id := gen_random_uuid();
    insert into auth.users (
      instance_id, id, aud, role, email, encrypted_password,
      email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
      created_at, updated_at,
      confirmation_token, recovery_token, email_change, email_change_token_new
    ) values (
      '00000000-0000-0000-0000-000000000000', v_id, 'authenticated', 'authenticated',
      v_email, crypt(p_password, gen_salt('bf')),
      now(), '{"provider":"email","providers":["email"]}', '{}',
      now(), now(), '', '', '', ''
    );
    insert into auth.identities (
      id, user_id, provider_id, identity_data, provider,
      last_sign_in_at, created_at, updated_at
    ) values (
      gen_random_uuid(), v_id, v_id::text,
      jsonb_build_object('sub', v_id::text, 'email', v_email, 'email_verified', true),
      'email', now(), now(), now()
    );
  else
    update auth.users
       set encrypted_password = crypt(p_password, gen_salt('bf')),
           email_confirmed_at = coalesce(email_confirmed_at, now()),
           updated_at = now()
     where id = v_id;
  end if;

  -- La guarda valida rol/permisos con la identidad de quien llama.
  insert into public.admin_accounts (id, email, role, permissions, is_active)
  values (v_email, v_email, p_role, case when p_role = 'custom' then p_permissions end, true);

  return v_email;
end;
$$;

-- ---------------------------------------------------------------------
-- 6. RPC: restablecer contraseña de otro usuario (solo Super Admin)
-- ---------------------------------------------------------------------
create or replace function public.admin_set_password(p_email text, p_password text)
returns void
language plpgsql
security definer
set search_path = public, auth, extensions
as $$
declare
  v_email text := lower(trim(p_email));
  v_id    uuid;
begin
  if not public.is_super_admin() then
    raise exception 'Solo el Super Administrador puede restablecer contraseñas' using errcode = '42501';
  end if;
  if length(coalesce(p_password, '')) < 8 then
    raise exception 'La contraseña debe tener al menos 8 caracteres';
  end if;
  select user_id into v_id from public.admin_accounts where email = v_email;
  if v_id is null then
    raise exception 'El usuario no existe o no tiene cuenta de acceso';
  end if;

  update auth.users
     set encrypted_password = crypt(p_password, gen_salt('bf')),
         updated_at = now()
   where id = v_id;

  -- Cierra sus sesiones abiertas: debe entrar con la contraseña nueva.
  if v_id <> auth.uid() then
    begin
      if to_regclass('auth.sessions') is not null then
        execute 'delete from auth.sessions where user_id = $1' using v_id;
      end if;
      if to_regclass('auth.refresh_tokens') is not null then
        execute 'delete from auth.refresh_tokens where user_id = $1' using v_id::text;
      end if;
    exception when insufficient_privilege then
      null;  -- sin permiso sobre auth.sessions: la contraseña igual queda cambiada
    end;
  end if;
end;
$$;

revoke all on function public.admin_create_user(text, text, text, jsonb) from public, anon;
revoke all on function public.admin_set_password(text, text)            from public, anon;
grant execute on function public.admin_create_user(text, text, text, jsonb) to authenticated;
grant execute on function public.admin_set_password(text, text)            to authenticated;

commit;
