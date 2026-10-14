# Desplegar el backend en Vercel (con PostgreSQL de Neon)

Con esto la app funciona en tu móvil **sin tener nada encendido en tu ordenador**.

> Lo que sigue se basa en cómo funcionaba Vercel a la fecha de escribirlo (octubre de 2026). Los
> menús o los límites del plan gratuito pueden cambiar: si algo no coincide, consulta
> https://vercel.com/docs. **Este despliegue no se ha podido probar en Vercel desde el entorno de
> desarrollo.** Sí se ha probado lo mismo en local: arranque en frío contra un PostgreSQL vacío,
> con `DATABASE_URL` en formato Neon y varias instancias arrancando a la vez.

## Cómo funciona en Vercel
- Vercel ejecuta la API como **función sin servidor**: no hay disco persistente ni procesos en
  segundo plano. Por eso:
  - los datos se guardan en **PostgreSQL de Neon**, que tiene plan gratuito y se conecta desde Vercel;
  - **la primera petición** tras un despliegue crea las tablas y carga el catálogo
    (`OPENFOOT_AUTO_BOOTSTRAP=true`);
  - cuando alguien pide partidos y los datos tienen **más de 10 minutos**, se actualizan los de ayer,
    hoy y los dos días siguientes antes de responder (`OPENFOOT_SYNC_ON_REQUEST=true`). Esa petición
    tarda un poco más, entre 1 y 3 segundos;
  - **una vez al día** (05:17 UTC), una tarea de Vercel actualiza el calendario completo (3 días
    atrás y 7 adelante), los datos de temporada y los goleadores de 4 competiciones, por turnos. El
    plan gratuito de Vercel solo permite tareas diarias.
- Varias instancias simultáneas no se pisan: se usan bloqueos de PostgreSQL compatibles con el
  pooler de Neon.

## Paso a paso

### 1. Cuenta en Vercel
Entra en https://vercel.com, regístrate con tu cuenta de **GitHub** y elige el plan **Hobby**
(gratuito, uso personal y no comercial).

### 2. Importa el proyecto
1. **Add New… → Project** e importa el repositorio **Gxxrazn21/Tv**.
2. En **Root Directory** pulsa *Edit* y elige **`backend`**. Este paso es importante.
3. **Framework Preset:** «Other» (o FastAPI, si lo detecta). No cambies los comandos.
4. **Todavía no pulses Deploy**: primero añade la base de datos y las variables.
   Si ya lo desplegaste, no pasa nada: haz los pasos 3 y 4 y luego **Redeploy**.

### 3. Base de datos (Neon)
1. En el proyecto, ve a **Storage → Create Database → Neon (Serverless Postgres)**.
2. Elige el plan gratuito y **una región cercana a la de tus funciones de Vercel**. Por defecto,
   Vercel usa Washington (iad1); elige la misma zona en Neon.
3. Conéctala al proyecto. Vercel creará la variable **`DATABASE_URL`**, que OpenFoot usa directamente.

### 4. Variables de entorno
En **Settings → Environment Variables** añade:

| Nombre | Valor |
|---|---|
| `OPENFOOT_FOOTBALL_DATA_TOKEN` | tu clave de football-data.org |
| `OPENFOOT_AUTO_BOOTSTRAP` | `true` |
| `OPENFOOT_SYNC_ON_REQUEST` | `true` |
| `OPENFOOT_TRUST_FORWARDED_FOR` | `true` |
| `CRON_SECRET` | una frase larga y aleatoria (por ejemplo, de un gestor de contraseñas) |

`CRON_SECRET` protege la tarea diaria: Vercel lo envía solo y nadie más puede lanzarla.

### 5. Despliega y comprueba
1. Pulsa **Deploy** (o **Deployments → … → Redeploy**).
2. Abre en el navegador, cambiando `TU-PROYECTO` por el nombre de tu proyecto:
   - `https://TU-PROYECTO.vercel.app/health` debe mostrar `{"status":"ok"}`;
   - `https://TU-PROYECTO.vercel.app/v1/sources` debe mostrar `football-data.org` con
     `"configured": true`;
   - `https://TU-PROYECTO.vercel.app/v1/matches?tz=America/Bogota` muestra los partidos de hoy.
     La primera vez puede tardar unos segundos mientras se prepara y sincroniza.
3. Si algo falla, mira **Deployments → (el último) → Logs** y pásame el error, sin la clave.

### 6. Conecta la app
- **Rápido:** en la app, **⚙ Ajustes → Servidor → `https://TU-PROYECTO.vercel.app` → Guardar**.
- **Para que el APK ya venga configurado:** en GitHub, ve a **Settings → Secrets and variables →
  Actions → Variables → New repository variable**. Nombre `OPENFOOT_API_URL`, valor
  `https://TU-PROYECTO.vercel.app`. Después relanza la CI (**Actions → CI → Run workflow**) y
  descarga el nuevo `openfoot-apk`.

## Límites y costes que conviene saber
- **Neon gratuito:** almacenamiento y horas de cómputo limitados, más que suficientes para uso
  personal. La base «se duerme» si no se usa y la primera conexión tarda algo más.
- **Vercel Hobby:** solo uso personal y no comercial, con límites mensuales de invocaciones y
  tiempo de ejecución. Cada petición puede durar como máximo 60 s según `vercel.json`.
- **football-data.org gratuito:** como mucho 10 solicitudes por minuto. OpenFoot sincroniza como
  mucho una vez cada 10 minutos, con un par de solicitudes, y la tarea diaria usa unas 7.
- **El catálogo manda:** en Vercel, `backend/data/catalog.yaml` se vuelve a cargar en cada arranque.
  Para aprobar o retirar un proveedor, edita el YAML y haz push. Los cambios hechos con
  `openfoot review` se sobrescribirían.
- **Comprobación de enlaces:** `openfoot check-links` no se ejecuta en Vercel. Lánzala desde tu
  ordenador apuntando a la base de Neon: copia `DATABASE_URL` en tu `backend/.env` y ejecuta
  `openfoot check-links`.

## Sin Vercel
El mismo backend funciona en cualquier servidor con `docker compose up` (ver `README.md`). Allí no
hace falta nada de lo anterior: el sincronizador periódico va dentro del proceso
(`OPENFOOT_SCHEDULER_ENABLED=true`).
