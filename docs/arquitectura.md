# Fase 2 · Arquitectura técnica

## Visión general

```
┌──────────────────────────┐        HTTPS (solo lectura)        ┌───────────────────────────────┐
│  App Flutter (Android/iOS)│ ─────────────────────────────────▶ │  Backend FastAPI (Python)     │
│  · SQLite local:          │   /v1/matches, /v1/competitions,   │  · API pública /v1            │
│    favoritos, caché,      │   /v1/matches/{id}/watch, …        │  · Límite por cliente         │
│    recordatorios          │                                    │  · Sin endpoints de admin     │
│  · Notificaciones locales │ ◀── enlaza (navegador/app externa) │                               │
└──────────────────────────┘     a webs OFICIALES de proveedores └──────┬───────────┬────────────┘
                                                                         │           │
                                         Sincronización programada       │           │ CLI de administración
                                         (con límites y prioridades)     ▼           ▼ (openfoot …)
                                ┌───────────────────────┐   ┌─────────────────────────────────────┐
                                │ Adaptadores de fuentes │   │ PostgreSQL (producción)              │
                                │ · football-data.org    │──▶│ SQLite (desarrollo y pruebas)        │
                                │ · OpenLigaDB           │   │ Partidos, equipos, catálogo de       │
                                │ · (ampliable)          │   │ derechos, verificaciones, chequeos   │
                                └───────────────────────┘   └─────────────────────────────────────┘
                                                                         ▲
                                                 catalog.yaml (revisado  │  openfoot load-catalog
                                                 por pull request)  ─────┘  openfoot check-links (anti-SSRF)
                                                                            openfoot review approve|reject
```

## Decisiones y justificación

| Decisión | Motivo | Alternativas descartadas |
|---|---|---|
| **Flutter + Dart** | Un solo código para Android e iOS, BSD-3, buen soporte de accesibilidad y compilación del APK en CI. | Kotlin nativo (solo Android); React Native (más dependencias nativas que mantener). |
| **Backend propio (FastAPI)** | Las claves de API nunca llegan al cliente. Además: caché compartida (respeta los límites gratuitos), normalización entre fuentes y catálogo verificado centralizado. | Llamar a las APIs desde el móvil: expondría claves y multiplicaría las solicitudes por usuario. |
| **FastAPI + SQLAlchemy 2 + Alembic** | Código abierto (MIT), tipado, validación con Pydantic y migraciones versionadas. | Django (más pesado para una API de solo lectura). |
| **PostgreSQL / SQLite** | PostgreSQL en producción. SQLite para ejecutar todo en local sin instalar nada. El mismo modelo funciona en ambos y las pruebas pasan en los dos. | — |
| **Administración por CLI** | Sin endpoints de administración expuestos: menos superficie de ataque, sin gestión de usuarios. | Panel web con autenticación. |
| **Catálogo en YAML versionado** | Cada alta o cambio de derecho pasa por una revisión humana (pull request) y queda en el historial de git. | Editar la base de datos a mano (sin trazabilidad). |
| **Estado en el móvil con `provider` + `ChangeNotifier`** | Sencillo, mantenido por el equipo de Flutter, suficiente para el tamaño de la app. | Riverpod o BLoC (más ceremonia). |
| **SQLite local (`sqflite`) + `shared_preferences`** | Favoritos, caché sin conexión y recordatorios sin cuenta ni servidor. | Firebase (servicio comercial; enviaría datos a terceros). |
| **`flutter_local_notifications`** | Avisos locales sin servicios push. | FCM (requiere Google y un servidor de envío). |

## Backend

```
backend/
├── openfoot/
│   ├── config.py            # Variables OPENFOOT_* (pydantic-settings); los secretos van como SecretStr
│   ├── db.py                # Motor, sesiones, tipo UTCDateTime
│   ├── models.py            # Modelo de datos (ver más abajo)
│   ├── schemas.py           # Respuestas de la API
│   ├── main.py              # App FastAPI, límite por cliente, cabeceras, planificador
│   ├── api/routes.py        # Endpoints /v1
│   ├── adapters/            # Fuentes de datos
│   │   ├── base.py          # Contrato DataSource, estructuras normalizadas, RateLimiter
│   │   ├── football_data.py # football-data.org v4 (principal)
│   │   ├── openligadb.py    # OpenLigaDB (secundaria)
│   │   └── registry.py      # Orden de prioridad
│   ├── services/
│   │   ├── sync.py          # Inserción o actualización idempotente, cambios de horario, registro de ejecuciones
│   │   ├── catalog.py       # Carga y validación del catálogo YAML
│   │   ├── watch.py         # Resolución de «Dónde ver»
│   │   ├── linkcheck.py     # Verificador de enlaces con protección SSRF
│   │   ├── urls.py          # Normalización y validación de URL
│   │   └── search.py        # Búsqueda tolerante a errores (rapidfuzz)
│   └── cli.py               # openfoot init-db | load-catalog | sync | check-links | review
├── alembic/versions/        # Migraciones
├── data/catalog.yaml        # Catálogo inicial
└── tests/                   # 113 pruebas
```

### API pública (solo lectura)

| Método y ruta | Descripción |
|---|---|
| `GET /health` | Comprobación de vida. |
| `GET /v1/competitions?region=` | Catálogo con el estado de los datos (`available` o `unavailable`, con nota explicativa). |
| `GET /v1/matches?date_from&date_to&tz&competition&country&team_id&phase` | Partidos por fecha **en la zona horaria pedida** (rango máximo de 31 días). |
| `GET /v1/matches/{id}` | Ficha del partido con goles cuando la fuente los da. |
| `GET /v1/matches/{id}/watch?country=XX` | Proveedores verificados y vigentes para ese país, directorio oficial y mensaje si no hay ninguno. |
| `GET /v1/teams/{id}/matches?upcoming=` | Próximos o recientes de un equipo. |
| `GET /v1/providers?country=` | Catálogo de proveedores y número de derechos verificados. |
| `GET /v1/search?q=&tz=` | Equipos, jugadores, competiciones, países y partidos por fecha (`dd/mm/aaaa` o `aaaa-mm-dd`). |
| `GET /v1/sources` | Fuentes activas, atribución y última sincronización. |

La documentación interactiva (OpenAPI) está en `/docs` cuando el servidor se ejecuta.

### Añadir una fuente nueva

1. Crea `adapters/mi_fuente.py` con una clase que cumpla el protocolo `DataSource` (`name`,
   `attribution`, `is_configured`, `competition_codes`, `fetch_competitions`, `fetch_matches`,
   `fetch_scorers`). Debe devolver las estructuras normalizadas de `adapters/base.py`.
2. Aplica un `RateLimiter` con el límite **publicado** por el proveedor.
3. Regístrala en `adapters/registry.py`. El orden decide la prioridad: si dos fuentes cubren la misma
   competición, solo se usa la primera que esté configurada, para no duplicar partidos.
4. Añade la competición al catálogo con `data_status: available` y escribe pruebas con *fixtures*.

## Modelo de datos

```
competitions ─┬─< seasons
              ├─< matches >── teams (local / visitante)
              │      └─< match_events
              ├─< broadcast_rights >── broadcasters
              └── official_directories
players >── teams
external_refs   (fuente, tipo, id_externo) → id interno       ← evita duplicar entre fuentes
link_checks     (destino: derecho | directorio) resultado técnico de cada comprobación
sync_runs       registro de cada sincronización (correcta o con error)
```

- **Identificadores externos:** `external_refs` asigna cada `(fuente, tipo, id)` a una entidad
  interna. Así, varias fuentes pueden describir el mismo equipo sin duplicarlo.
- **Aplazamientos y cambios de horario:** si la fuente cambia la fecha, se guarda la anterior en
  `matches.previous_utc_date` y la app muestra «Horario cambiado».
- **Fechas:** siempre en UTC con zona horaria (`UTCDateTime`). La conversión a la hora local se hace
  en la consulta (`tz`) y en la app.
- **Derechos y territorios:** `broadcast_rights` (proveedor × competición × país ISO-3166 × temporada,
  con validez, tipo de acceso, fuente, estado de revisión, verificado por y fecha).
- **Favoritos y preferencias:** **solo en el dispositivo**, en las tablas SQLite locales `favorites`,
  `cache` y `reminders` y en `shared_preferences`. El servidor no guarda nada del usuario.

## App móvil

```
mobile/lib/
├── main.dart, app.dart          # Arranque y navegación inferior (Inicio, Partidos, Competiciones, Favoritos)
├── core/                        # Tema, zona horaria, países y banderas emoji
├── data/                        # Modelos, cliente HTTP, SQLite local, repositorio con caché
├── state/                       # Ajustes y favoritos (ChangeNotifier)
├── services/reminders.dart      # Notificaciones locales
└── ui/screens|widgets/          # Pantallas y componentes
```

- **Sin conexión:** cada respuesta se guarda en la caché local. Si la red falla, se muestran los datos
  guardados con un aviso y su fecha, sin inventar nada.
- **URL del servidor:** se fija al compilar (`--dart-define=OPENFOOT_API_URL=…`) y se puede cambiar en
  Ajustes para usar un servidor autoalojado. Solo se admite https, salvo localhost y el emulador.

## Infraestructura

- **Local:** `uvicorn` + SQLite (ver `README.md`).
- **Autoalojado:** `docker compose up` (PostgreSQL + API, puerto ligado a 127.0.0.1). Delante va un
  proxy inverso con TLS (Caddy o nginx con Let's Encrypt).
- **Vercel + Neon:** función sin servidor (`backend/api/index.py`) con preparación automática,
  sincronización cuando los datos tienen más de N minutos y una tarea diaria protegida por secreto.
  Ver `docs/despliegue-vercel.md`.
- **CI:** GitHub Actions ejecuta el lint, las pruebas, `pip-audit`, las migraciones y el catálogo, y
  compila el APK como artefacto.
