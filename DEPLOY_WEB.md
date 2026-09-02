# Guía de Despliegue Web Gratuito · BDJ Studio License

Esta guía describe cómo desplegar **BDJ Studio License** en servidores web 100% gratuitos (Vercel, Render y Supabase) para emitir licencias SPP3 desde cualquier dispositivo (PC, Mac, iPhone, iPad, Android) a través de un navegador web, garantizando la persistencia de usuarios y la descarga universal del archivo `.txt`.

---

## 1. Arquitectura y Seguridad

```
+-------------------------------------------------------------+
|              Cualquier Dispositivo (Móvil o PC)              |
|        Navegador Web (Chrome, Safari iOS, Edge, Firefox)    |
+------------------------------+------------------------------+
                               | HTTPS
                               v
+-------------------------------------------------------------+
|                  FRONTEND (Flutter Web)                     |
|                 Alojamiento: Vercel (Gratis)                |
|  - Interfaz de administración responsiva                    |
|  - Descarga universal de `.txt` vía Blob / Anchor HTML5     |
|  - Sesión persistente con JWT Token                         |
+------------------------------+------------------------------+
                               | REST API (HTTPS + JWT)
                               v
+-------------------------------------------------------------+
|                   BACKEND (NestJS API)                      |
|                 Alojamiento: Render (Gratis)                |
|  - Firma criptográfica segura Ed25519 (SPP3)                |
|  - Clave privada protegida en variables de entorno           |
|  - Endpoints de autenticación, usuarios y licencias         |
+------------------------------+------------------------------+
                               | Prisma ORM
                               v
+-------------------------------------------------------------+
|             BASE DE DATOS (PostgreSQL Remota)               |
|                Alojamiento: Supabase (Gratis)               |
|  - Base de datos persistente (nunca se borra al reiniciar)   |
|  - Almacén de credenciales hash (bcrypt), historial y tokens|
+-------------------------------------------------------------+
```

### Regla Crítica de Seguridad
> [!CAUTION]
> La clave privada Ed25519 de firma de licencias **NUNCA** debe incrustarse en el código de Flutter Web. En una web abierta, cualquier persona puede pulsar `F12` y extraer la clave privada del `.js` o `.wasm`. La firma se realiza exclusivamente en el backend (Render), que la custodia en una variable de entorno privada.

---

## 2. Servidores Gratuitos Recomendados

| Componente | Proveedor Gratuito | Ventajas del Plan Gratuito |
| :--- | :--- | :--- |
| **Base de Datos** | **[Supabase](https://supabase.com)** | PostgreSQL dedicado gratis, 500 MB de almacenamiento, copias de seguridad automáticas, no se suspende. |
| **Backend API** | **[Render](https://render.com)** | Web Service gratuito con Node.js, HTTPS automático, despliegue continuo desde GitHub. |
| **Frontend Web** | **[Vercel](https://vercel.com)** | Alojamiento estático global ultra-rápido, CDN mundial, HTTPS SSL gratuito, 100% activo sin suspensión. |

---

## 3. Paso a Paso del Despliegue

### Paso 1: Configurar la Base de Datos en Supabase (Gratis)

1. Crea una cuenta gratuita en [supabase.com](https://supabase.com).
2. Haz clic en **New Project**, asígnale un nombre (ejemplo: `bdj-license-db`) y define una contraseña segura para la base de datos.
3. Elige la región más cercana a ti.
4. Una vez creado el proyecto, ve a **Project Settings** > **Database**.
5. Copia la cadena de conexión en modo **Connection string (URI)** (sustituyendo `[YOUR-PASSWORD]` por tu contraseña):
   ```
   postgresql://postgres:[TU_PASSWORD]@db.xxxx.supabase.co:5432/postgres
   ```
   *(Esta será tu variable `DATABASE_URL`)*.

---

### Paso 2: Desplegar el Backend en Render (Gratis)

1. Sube tu repositorio a GitHub (puedes crear un repositorio privado para `BDJ_Studio_License`).
2. Entra en [render.com](https://render.com) y regístrate con tu cuenta de GitHub.
3. Haz clic en **New +** > **Web Service**.
4. Conecta tu repositorio de GitHub.
5. Configura los parámetros del servicio:
   * **Name**: `bdj-license-api`
   * **Root Directory**: `backend`
   * **Environment**: `Node`
   * **Build Command**:
     ```bash
     npm install && npx prisma generate && npx prisma db push && npm run build
     ```
   * **Start Command**:
     ```bash
     npm run start:prod
     ```
   * **Instance Type**: `Free`
6. En la pestaña **Environment Variables**, añade las siguientes variables:
   * `DATABASE_URL`: *(La URL de conexión que copiaste de Supabase)*
   * `JWT_SECRET`: *(Cadena secreta aleatoria de al menos 32 caracteres)*
   * `JWT_REFRESH_SECRET`: *(Otra cadena secreta aleatoria de al menos 32 caracteres)*
   * `NODE_ENV`: `production`
   * `PORT`: `3000`
   * `CORS_ORIGIN`: `*` *(o el dominio que te asigne Vercel en el Paso 3)*
   * `BOOTSTRAP_SUPER_ADMIN_EMAIL`: `admin@tudominio.com`
   * `BOOTSTRAP_SUPER_ADMIN_PASSWORD`: `TuPasswordMuySegura123!`
   * `BOOTSTRAP_SUPER_ADMIN_NAME`: `Administrador BDJ Studio`
7. Haz clic en **Create Web Service**. Render compilará tu API, creará las tablas en Supabase y te entregará una URL HTTPS (por ejemplo: `https://bdj-license-api.onrender.com`).

---

### Paso 3: Compilar el Frontend para Web

En tu máquina local, abre una terminal en la carpeta `frontend/` de `BDJ_Studio_License`:

```bash
cd "c:\Users\David Zapata\Desktop\Aplicacion_para_DJs\BDJ_Studio_License\frontend"

# 1. Obtener dependencias limpias
flutter pub get

# 2. Compilar para la Web en modo release optimizado
flutter build web --release --base-href "/"
```

El resultado compilado quedará listo en la carpeta:
`frontend/build/web/`

---

### Paso 4: Desplegar el Frontend en Vercel (Gratis)

#### Opción A: Vía Vercel CLI (La más rápida)
1. Instala Vercel globalmente si no lo tienes:
   ```bash
   npm install -g vercel
   ```
2. Entra en la carpeta compilada y sube el sitio:
   ```bash
   cd "frontend/build/web"
   vercel --prod
   ```
3. Sigue las instrucciones interactivas en pantalla. En 30 segundos tendrás tu enlace público HTTPS (ejemplo: `https://bdj-studio-license.vercel.app`).

#### Opción B: Vía Panel de GitHub + Vercel
1. En [vercel.com](https://vercel.com), haz clic en **Add New** > **Project**.
2. Conecta tu repositorio.
3. En **Root Directory**, selecciona `frontend`.
4. En **Build Command** pon:
   ```bash
   flutter build web --release
   ```
   *(O sube directamente la carpeta `build/web` como proyecto estático)*.
5. En **Output Directory** pon: `build/web`.
6. Haz clic en **Deploy**.

---

## 4. Garantía de Descarga del Archivo `.txt` en Cualquier Dispositivo

El guardado de licencias en la versión web está diseñado para ser 100% independiente del sistema operativo:

1. **En Móviles (Android / iPhone / iPad)**:
   * Al hacer clic en **"Descargar .txt"**, el navegador web dispara una descarga directa mediante un objeto `Blob` y un elemento `<a>` virtual con atributo `download`.
   * En **Android**: El archivo se guarda en la carpeta de descargas de tu teléfono (`/Download`) sin requerir permisos de almacenamiento ni dar error de Storage Access Framework.
   * En **iOS (Safari)**: Aparece el aviso nativo de iOS: *"¿Deseas descargar «Licencia_XXX.txt»?"*, guardándolo directamente en la app **Archivos (Files)** o iCloud Drive.
2. **En Computadores (Windows / macOS / Linux)**:
   * Funciona exactamente como cualquier descarga web de Chrome, Edge o Safari, guardándose al instante en la carpeta `Descargas` del usuario.

---

## 5. Mantenimiento del Tier Gratuito (Evitar Cold Starts)

> [!TIP]
> Los Web Services gratuitos de Render entran en reposo ("sleep") si pasan 15 minutos sin peticiones. Cuando alguien entra a la web tras horas de inactividad, la primera petición puede tardar 30-40 segundos mientras el contenedor despierta.
> 
> **Cómo mantenerlo despierto 24/7 gratis**:
> 1. Regístrate gratis en [cron-job.org](https://cron-job.org) o [uptimerobot.com](https://uptimerobot.com).
> 2. Crea un monitor HTTP de tipo ping apuntando a:
>    `https://tu-api.onrender.com/api/v1/health` (o la ruta raíz de tu API).
> 3. Configura el intervalo cada **10 minutos**.
> 4. Con esto, Render nunca se dormirá y tu panel web responderá siempre de manera instantánea.
