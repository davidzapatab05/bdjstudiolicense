# RBAC con Supabase Auth + RLS

La consola ya no guarda contraseñas ni roles en la app. El login es Supabase Auth y
cada lectura/escritura la autoriza la base de datos (RLS + `has_perm()`).

Tres módulos, cada uno con CRUD propio: **Gestión** (licencias y clientes), **Usuarios**, **Roles** (permisos y accesos).

| Rol | Usuario | Gestión | Usuarios | Roles |
|---|---|---|---|---|
| `super_admin` | david.zapata@bdjstudio.com | CRUD | CRUD | CRUD |
| `license_admin` | maylor.neyra@bdjstudio.com | CRUD (editable) | — | — |
| `operator` | prueba@bdjstudio.com | Crear + buscar | — | — |
| `auditor` | — | Buscar | — | — |

Migraciones (en orden): `20260926_rbac_rls.sql` → `20260926_02_modulo_roles_passwords.sql`.

## Puesta en marcha (en este orden)

1. **Supabase → Authentication → Providers → Email**: activo, con *Confirm email* encendido.
2. **Authentication → Users → Add user** (marca *Auto Confirm User*) para:
   `david.zapata@bdjstudio.com`, `maylor.neyra@bdjstudio.com`, `prueba@bdjstudio.com`.
3. **SQL Editor**: ejecuta `migrations/20260926_rbac_rls.sql`.
   Verifica: `select email, role, user_id is not null as vinculado from admin_accounts;`
   → las 3 filas deben salir con `vinculado = true`.
4. Compila y publica la consola (`flutter build web --release`) y las apps (ver abajo).

> Mientras no publiques la consola nueva, la versión anterior deja de funcionar
> (RLS bloquea la anon key). Haz los pasos 3 y 4 seguidos.

## Operación diaria

- **Crear usuario** (Usuarios → Crear): la cuenta queda lista para entrar, sin correo de confirmación.
- **Contraseñas**: cada usuario cambia la suya; el Super Administrador restablece la de cualquiera
  (Usuarios → Restablecer contraseña) y se cierran sus sesiones abiertas.
- **Roles** (menú Roles): crear roles nuevos y editar la matriz de permisos de cada uno.
  El cambio aplica al instante a todos los usuarios con ese rol.

## Qué garantiza la BD

- La anon key sin sesión no lee ni escribe nada.
- Un usuario autenticado sin fila activa en `admin_accounts` no ve nada.
- Solo `super_admin` crea o modifica a otro `super_admin`.
- Nadie puede otorgar permisos que él mismo no tiene, ni editar su propio rol o cambiarse de rol.
- Un rol asignado a usuarios no se puede eliminar.
- No se puede eliminar ni degradar al último `super_admin`; nadie se borra a sí mismo.
- `licenses.issued_by` lo pone el servidor con el correo del token (no se falsifica).
- Renovar/cambiar plan de una licencia activa exige permiso **update**
  (la anterior queda con `status = 'replaced'`).

## Versión de las apps

`bdj_license_core` ya no valida versión (`Spp3Token.verify` ignora `expectedVersion`) y
acepta tokens sin campo `ver`. Todas las apps lo usan por `path:`, así que basta con
recompilarlas; los binarios ya instalados siguen con la validación vieja hasta actualizarse.
