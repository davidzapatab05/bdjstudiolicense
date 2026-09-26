# RBAC con Supabase Auth + RLS

La consola ya no guarda contraseñas ni roles en la app. El login es Supabase Auth y
cada lectura/escritura la autoriza la base de datos (RLS + `has_perm()`).

| Rol | Usuario | Licencias | Usuarios |
|---|---|---|---|
| `super_admin` | david.zapata@bdjstudio.com | CRUD | CRUD |
| `license_admin` | maylor.neyra@bdjstudio.com | CRUD (editable desde *Roles y Permisos*) | — |
| `operator` | prueba@bdjstudio.com | Crear + buscar | — |
| `auditor` | — | Buscar | — |

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

- **Crear usuario** desde la consola: crea la fila con su rol y registra el acceso en Auth
  (el usuario recibe correo de confirmación). Alternativa sin correo: crearlo en
  *Authentication → Users → Add user*; se vincula solo por correo.
- **Restablecer contraseña de otro**: *Authentication → Users → … → Send password recovery*.
  Cada usuario cambia la suya desde la consola.
- **Editar permisos de un rol** (p. ej. quitar *Eliminar* al Administrador de Licencias):
  *Usuarios → Roles y Permisos → lápiz*. Aplica a todos los usuarios con ese rol al instante.

## Qué garantiza la BD

- La anon key sin sesión no lee ni escribe nada.
- Un usuario autenticado sin fila activa en `admin_accounts` no ve nada.
- Solo `super_admin` cambia roles/permisos, crea otro `super_admin` o edita roles.
- No se puede eliminar ni degradar al último `super_admin`; nadie se borra a sí mismo.
- `licenses.issued_by` lo pone el servidor con el correo del token (no se falsifica).
- Renovar/cambiar plan de una licencia activa exige permiso **update**
  (la anterior queda con `status = 'replaced'`).

## Versión de las apps

`bdj_license_core` ya no valida versión (`Spp3Token.verify` ignora `expectedVersion`) y
acepta tokens sin campo `ver`. Todas las apps lo usan por `path:`, así que basta con
recompilarlas; los binarios ya instalados siguen con la validación vieja hasta actualizarse.
