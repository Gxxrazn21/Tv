# Licencias, atribuciones y derechos de terceros

## Licencia del proyecto
El código y la documentación de OpenFoot se publican bajo **Apache License 2.0** (`LICENSE`).
Se eligió frente a MIT porque incluye una concesión explícita de patentes y el mecanismo `NOTICE`
para las atribuciones.

## Lo que la licencia **no** cubre
La licencia del código **no concede ningún derecho** sobre:
- partidos, retransmisiones ni señales audiovisuales;
- escudos, logotipos, marcas ni nombres comerciales de clubes, competiciones, federaciones o
  proveedores;
- bases de datos ni contenidos de terceros (calendarios, resultados, listas de emisoras).

Estos elementos pertenecen a sus titulares. OpenFoot muestra nombres de equipos y competiciones con
fines informativos, enlaza a webs oficiales y no reproduce escudos por defecto.

## Atribuciones obligatorias
| Fuente | Texto | Dónde aparece |
|---|---|---|
| football-data.org | "Football data provided by the Football-Data.org API" | App (Ajustes → Fuentes), `GET /v1/sources`, `NOTICE` |
| OpenLigaDB | "Datos de OpenLigaDB (https://www.openligadb.de), aportados por su comunidad" | Ídem |

Revisa los términos vigentes de cada fuente antes de publicar (ver `docs/investigacion-apis.md`).

## Recursos externos
- **Banderas:** emojis Unicode dibujados por la fuente del sistema. No hay ficheros de imagen en el
  repositorio.
- **Escudos:** no se incluyen. Si el operador activa `OPENFOOT_SERVE_CREST_URLS`, la app carga las
  imágenes desde la URL que dé la fuente de datos. El operador es responsable de tener permiso.
- **Iconos:** Material Icons y Cupertino Icons, incluidos en Flutter.

## Inventario de dependencias directas (14/10/2026)

### Backend (Python)
| Paquete | Versión probada | Licencia |
|---|---|---|
| fastapi | 0.143.0 | MIT |
| starlette | 1.8.0 | BSD-3-Clause |
| pydantic / pydantic-settings | 2.14.1 / 2.15.0 | MIT |
| SQLAlchemy | 2.1.4 | MIT |
| alembic | 1.20.0 | MIT |
| httpx / httpcore | 0.28.1 / 1.0.9 | BSD-3-Clause |
| uvicorn | 0.54.0 | BSD-3-Clause |
| RapidFuzz | 3.14.6 | MIT |
| PyYAML | 6.0.3 | MIT |
| psycopg | 3.3.6 | **LGPL-3.0-only**: se usa como librería sin modificar, lo que es compatible con distribuir OpenFoot bajo Apache-2.0. Si se redistribuye una imagen con psycopg, hay que incluir su licencia. |
| pytest, ruff, pip-audit (solo desarrollo) | — | MIT / MIT / Apache-2.0 |

### App (Dart/Flutter)
| Paquete | Versión | Licencia |
|---|---|---|
| Flutter SDK | 3.47.7 | BSD-3-Clause |
| http, path, intl | 1.6.0 / 1.9.1 / 0.20.3 | BSD-3-Clause |
| shared_preferences, url_launcher | 2.5.6 / 6.3.3 | BSD-3-Clause |
| sqflite, sqflite_common_ffi (pruebas) | 2.4.4+2 / 2.4.4 | BSD-2-Clause |
| flutter_local_notifications | 22.3.2 | BSD-3-Clause |
| timezone | 0.11.2 | BSD-2-Clause |
| flutter_timezone | 5.1.1 | Apache-2.0 |
| provider | 6.1.5+1 | MIT |
| cupertino_icons | 1.0.9 | MIT |

La app muestra el listado completo de licencias, incluidas las dependencias transitivas, en
**Ajustes → Licencias de terceros** (`showLicensePage`, generado por Flutter).
Para regenerar el inventario del backend:
`pip-licenses` (opcional) o `python -c "import importlib.metadata as m; …"`.
