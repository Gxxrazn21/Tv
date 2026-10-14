# OpenFoot

**Calendario de fútbol internacional y dónde verlo de forma legal.** Gratis de verdad: sin anuncios,
sin suscripciones, sin compras, sin cuentas y sin rastreadores.

> OpenFoot **no emite ni redistribuye señales**. Solo enlaza a páginas oficiales de proveedores cuya
> relación con la competición y el territorio se ha verificado manualmente. Que la app sea gratuita
> no significa que lo sean todos los proveedores enlazados.

| | |
|---|---|
| **App** | Flutter (Android; iOS preparado sin probar): Inicio, Partidos, Competiciones, Favoritos, búsqueda y ficha con «Dónde ver» |
| **Backend** | FastAPI + SQLAlchemy + Alembic, PostgreSQL o SQLite |
| **Datos** | football-data.org (principal) y OpenLigaDB (secundaria) mediante adaptadores ampliables |
| **Licencia** | Apache-2.0 (solo el código; ver [NOTICE](NOTICE)) |

## Qué hace
- Partidos de hoy, en directo, próximos y finalizados, con estados claros (**EN DIRECTO**, **PRÓXIMO**,
  **FINALIZADO**, **APLAZADO**…) en la zona horaria del dispositivo o en la que elijas.
- Calendario de ±1 año con filtros por competición, país y equipo, resultados, goles (cuando la fuente
  los da) y aviso de cambios de horario.
- **Dónde ver:** proveedores verificados para tu país, con distinción entre **Gratis**, **Suscripción**,
  **Pago por evento** y **Acceso no especificado**. Indica la fuente y la fecha de verificación y lleva
  a la web oficial. Si no hay nada verificado, lo dice claramente y ofrece el directorio oficial del
  organizador.
- Búsqueda tolerante a errores de equipos, jugadores, ligas, países y partidos por fecha.
- Favoritos, recordatorios locales y modo sin conexión, todo guardado en el dispositivo.
- Catálogo de competiciones de Europa, Sudamérica y torneos internacionales. Las que no tienen una
  fuente gratuita verificada lo indican en lugar de mostrar datos inventados.

## Estructura
```
backend/           API, adaptadores, catálogo (data/catalog.yaml), migraciones y pruebas
mobile/            App Flutter (lib/, test/, android/, ios/)
docs/              Investigación, arquitectura, diseño, privacidad, seguridad, licencias…
.github/workflows/ CI: lint, pruebas, auditoría, imagen Docker y APK
docker-compose.yml Despliegue autoalojado (PostgreSQL + API)
.env.example       Configuración de ejemplo sin secretos
```

## Puesta en marcha local

### Backend
```bash
cd backend
python3 -m venv .venv && . .venv/bin/activate
pip install -e ".[dev]"
cp ../.env.example .env                 # y rellena OPENFOOT_FOOTBALL_DATA_TOKEN (gratis, con registro)
openfoot init-db                        # migraciones
openfoot load-catalog data/catalog.yaml # competiciones, proveedores y derechos
openfoot sync --scorers                 # descarga partidos de las fuentes configuradas
uvicorn --factory openfoot.main:app_factory --reload --port 8000
# Documentación interactiva: http://localhost:8000/docs
```
Sin clave de football-data.org solo se sincroniza OpenLigaDB (Bundesliga y 2. Bundesliga).

Otras órdenes útiles:
```bash
openfoot check-links                                 # comprobación técnica de enlaces (con protección SSRF)
openfoot review list                                 # estado del catálogo
openfoot review approve right 9 --by "Nombre" --note "Comprobado en premierleague.com"
openfoot review reject right 9 --note "Ya no tiene los derechos"
pytest && ruff check .                               # pruebas y lint
```
Para tener sincronización periódica dentro del servidor, define `OPENFOOT_SCHEDULER_ENABLED=true`.

### Autoalojado con Docker
```bash
export POSTGRES_PASSWORD='una-contraseña-larga'
docker compose up --build      # API en http://127.0.0.1:8000 (pon un proxy con TLS delante)
```

### En la nube con Vercel (sin ordenador encendido)
Guía paso a paso en [docs/despliegue-vercel.md](docs/despliegue-vercel.md): Vercel + PostgreSQL de
Neon (planes gratuitos), con preparación automática de la base, sincronización bajo demanda y una
tarea diaria.

### App
```bash
cd mobile
flutter pub get && flutter test
flutter run --dart-define=OPENFOOT_API_URL=http://10.0.2.2:8000   # emulador + backend local
```
APK: ver [docs/compilar-apk.md](docs/compilar-apk.md). La CI publica `openfoot-apk` en cada push.

## Documentación
| Documento | Contenido |
|---|---|
| [docs/investigacion-apis.md](docs/investigacion-apis.md) | Fase 1: APIs, condiciones, derechos y viabilidad (con grado de confianza de cada dato) |
| [docs/arquitectura.md](docs/arquitectura.md) | Arquitectura justificada, API, modelo de datos y cómo añadir fuentes |
| [docs/diseno-pantallas.md](docs/diseno-pantallas.md) | Pantallas, estados y accesibilidad |
| [docs/catalogo-y-verificacion.md](docs/catalogo-y-verificacion.md) | Reglas del catálogo, revisión manual y verificación de enlaces |
| [docs/privacidad.md](docs/privacidad.md) | Política de privacidad (qué recibe cada parte) |
| [docs/seguridad.md](docs/seguridad.md) | Secretos, validación, SSRF y dependencias |
| [docs/licencias.md](docs/licencias.md) | Licencia, atribuciones e inventario de dependencias |
| [docs/retirada-y-correcciones.md](docs/retirada-y-correcciones.md) | Cómo pedir retiradas o corregir enlaces |
| [docs/sostenibilidad.md](docs/sostenibilidad.md) | Costes reales y modelo sin ingresos |
| [docs/compilar-apk.md](docs/compilar-apk.md) | Compilación y firma del APK |
| [docs/despliegue-vercel.md](docs/despliegue-vercel.md) | Despliegue en Vercel + Neon, paso a paso |
| [docs/limitaciones.md](docs/limitaciones.md) | **Qué está probado y qué falta** |

## Contribuir al catálogo
Añade proveedores o derechos en `backend/data/catalog.yaml` con `status: pending_review` y la URL de
la **fuente oficial**. Una persona revisora la verifica antes de publicarla. No se aceptan enlaces a
retransmisiones no autorizadas ni a webs que eludan suscripciones o bloqueos geográficos.

## Aviso legal
Los nombres de equipos, competiciones y proveedores pertenecen a sus titulares y se usan solo con
fines informativos. La licencia Apache-2.0 cubre el código de este repositorio y no concede derechos
sobre partidos, emisiones, escudos ni bases de datos de terceros.
