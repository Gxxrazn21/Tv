# Limitaciones conocidas y trabajo pendiente

Lista honesta del estado a **14 de octubre de 2026**.

## Probado
- Backend: 113 pruebas automatizadas que pasan sobre **SQLite y PostgreSQL 16**. Además: `ruff`,
  `pip-audit` sin vulnerabilidades, migración de ida y vuelta y comprobación de que no hay desfase
  entre modelo y migraciones.
- Backend real con `uvicorn`: `/health`, `/v1/sources` y `/v1/competitions` responden. La CLI
  (`init-db`, `load-catalog`, `review`, `check-links`) funciona sobre PostgreSQL.
- App: `flutter analyze` sin avisos y 22 pruebas (unitarias, repositorio con SQLite real y widgets).
  Compilación completa del código Dart en modo release (dart2js) y **APK de release compilado en
  GitHub Actions** (artefacto `openfoot-apk`).
- Imagen Docker del backend construida y arrancada en GitHub Actions.

## No probado o pendiente
| Área | Situación | Qué falta |
|---|---|---|
| **Datos reales** | **Verificado el 14/10/2026 en Vercel + Neon:** sincronización correcta con football-data.org (Champions, Championship…) y OpenLigaDB (`last_sync_ok: true` en ambas). Las pruebas automáticas siguen usando *fixtures* sintéticos. | Capturar respuestas reales (sin la clave) como *fixtures* de regresión. |
| **Comprobación HTTP del catálogo** | No se pudo ejecutar (sin DNS ni acceso a esos dominios). | `openfoot check-links` antes de desplegar. |
| **Condiciones de uso de las APIs** | Investigadas con buscador; muchos datos vienen de terceros (ver `docs/investigacion-apis.md`). | Leer los términos oficiales de football-data.org y OpenLigaDB (uso público, caché, atribución). |
| **Catálogo de derechos** | Solo 8 derechos verificados (Mundial 2026 en los países nórdicos, ya terminado) y 3 directorios oficiales. Para la temporada 2026/27 casi todas las consultas mostrarán «No se encontró una transmisión oficial verificada…» y, si existe, el directorio oficial del organizador. | Revisar las entradas `pending_review` contra las fuentes oficiales y ampliar el catálogo por países. |
| **APK en un dispositivo real** | Compilado en la CI, pero no instalado ni ejecutado en un móvil o emulador (el entorno no tenía Android SDK). | Probarlo en un emulador o dispositivo: arranque, notificaciones, apertura de enlaces y zona horaria. |
| **iOS** | Plataforma generada, sin compilar. | macOS + Xcode. |
| **Competiciones sin fuente** | Europa League, Conference League, Liga Profesional Argentina, Série B, Libertadores, Sudamericana, Copa Argentina, Copa do Brasil, copas europeas, eliminatorias, Copa América, Nations League, amistosos y fútbol femenino. | Adaptador de API-Football (100 solicitudes/día) u otra fuente autorizada. |
| **Directo** | El plan gratuito de football-data.org va con retraso. OpenLigaDB no informa del estado: se deduce y se marca «SIN CONFIRMAR» si el partido no se cierra. | Plan de pago o fuente autorizada con directo. |
| **Jugadores** | Solo se sincronizan los goleadores de cada competición (`openfoot sync --scorers`). | Plantillas completas (no están en el plan gratuito). |
| **Escudos** | Monogramas por defecto. | Obtener permisos o recursos con licencia compatible. |
| **Reproductor integrado** | No implementado a propósito: ningún proveedor del catálogo tiene una inserción autorizada (`embed_allowed=false`). | Solo con autorización expresa del proveedor. |
| **Límite de solicitudes** | En memoria, por proceso. | Con varias réplicas, aplicarlo en el proxy inverso. |
| **Accesibilidad** | Etiquetas semánticas y textos junto a los colores. | Auditoría con TalkBack y prueba con tamaños de texto grandes. |
| **Localización** | Solo español. | Inglés y portugués. |
| **Vercel** | **Funcionando** en `https://tv-backend-five.vercel.app` (preset FastAPI, Neon). Se corrigieron dos fallos encontrados al desplegar: reescrituras a `/api/index` (404 en todo) y psycopg como extra opcional (`ModuleNotFoundError`). Preparación automática y sincronización bajo demanda verificadas. La tarea diaria aún no se ha observado ejecutándose. | Seguir `docs/despliegue-vercel.md`. |
| **Docker** | La imagen se construye y arranca en la CI (`/health` y `/v1/competitions` responden). `docker-compose.yml` con PostgreSQL no se ha levantado. | `docker compose up --build`. |
