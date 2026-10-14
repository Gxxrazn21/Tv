# Fase 1 · Investigación de APIs, derechos, fuentes y viabilidad

Fecha de la investigación: **14 de octubre de 2026**.

## Cómo se hizo y qué grado de confianza tiene

Desde el entorno de desarrollo **no se pudo abrir ninguna página ni API externa**. La política de red
del contenedor bloqueaba football-data.org, OpenLigaDB, TheSportsDB, API-Football, uefa.com, fifa.com
y el registro de skills, y la herramienta de descarga web no resolvía esos dominios. La investigación
se hizo con un **buscador web**. Cada dato se marca así:

| Marca | Significado |
|---|---|
| **[Oficial]** | Fragmento atribuido por el buscador al dominio oficial de la fuente. |
| **[Terceros]** | Aparece en blogs, comparadores o catálogos de APIs; no se ha confirmado en la fuente. |
| **[Conocimiento previo]** | Documentación conocida por el equipo antes de este trabajo; hay que re-verificarla. |
| **[Sin verificar]** | No se encontró información fiable. |

> **Antes de publicar la app hay que revisar las condiciones de uso actuales de cada proveedor
> directamente en su web.** Este documento no sustituye esa revisión. En particular: permiso de uso
> en una app pública, atribución, caché y redistribución.

---

## 1. Fuentes de datos deportivos

### 1.1 football-data.org (elegida como **fuente principal**)

| Aspecto | Hallazgo |
|---|---|
| Competiciones (plan gratuito) | 12: Premier League (PL), LaLiga (PD), Bundesliga (BL1), Serie A (SA), Ligue 1 (FL1), Champions League (CL), Eredivisie (DED), Primeira Liga (PPL), Championship (ELC), Brasileirão Série A (BSA), Mundial (WC) y Eurocopa (EC). **[Terceros]**, que lo atribuyen a la página oficial de precios. |
| Datos disponibles | Calendario, resultados, clasificaciones, goleadores (`/scorers`). Sin estadísticas detalladas de jugadores en el plan gratuito. **[Terceros]** |
| Límite de solicitudes | 10 por minuto (límite de ritmo, no cupo mensual). **[Terceros]** |
| Coste | Gratis con registro. Planes de pago desde unos 29 €/mes según una fuente **[Terceros, cifras no confirmadas]**. |
| Resultados en directo | **Con retraso** en el plan gratuito. **[Terceros]** |
| Histórico | Limitado a la temporada actual en el plan gratuito. **[Terceros]** |
| Autenticación y API | Cabecera `X-Auth-Token`; API v4 en `https://api.football-data.org/v4`; `/matches` admite como máximo 10 días por consulta. **[Conocimiento previo]** |
| Atribución | "Football data provided by the Football-Data.org API". **[Conocimiento previo]** Se muestra en la app y en `NOTICE`. |
| Uso comercial y redistribución | **[Sin verificar]** Revisar sus términos. OpenFoot no es comercial, pero sí público. |
| Caché | Los terceros recomiendan cachear y no llamar a la API en cada visita. OpenFoot usa la base de datos como caché y sincroniza periódicamente. |
| Imágenes y escudos | La API devuelve URL de escudos. Son **marcas de los clubes**: OpenFoot no las sirve por defecto (`OPENFOOT_SERVE_CREST_URLS=false`). |

**Por qué es la principal:** cubre gratis las grandes ligas europeas, la Champions, el Brasileirão y los
torneos de selecciones. Además tiene una API REST estable y un límite de ritmo compatible con la
sincronización programada que hace el servidor.

### 1.2 OpenLigaDB (**fuente secundaria**, integrada)

| Aspecto | Hallazgo |
|---|---|
| Competiciones | Sobre todo fútbol alemán (`bl1`, `bl2`, `bl3`…). Los datos los aporta la comunidad. |
| Datos | Partidos, resultados, goles con minuto y goleador, estadio. **No incluye un campo de estado del partido**: OpenFoot lo deduce y lo documenta (ver `adapters/openligadb.py`). |
| Límites | Una fuente de terceros poco fiable habla de 1000 solicitudes/hora por IP **[Sin verificar]**. OpenFoot se limita a 30/minuto por prudencia. |
| Coste y clave | Gratis y sin clave. **[Terceros]** |
| Licencia de datos | Un catálogo de terceros la describe como ODbL (atribución y compartir igual). **[Terceros, sin verificar]** |
| Endpoint usado | `GET https://api.openligadb.de/getmatchdata/{liga}/{temporada}` **[Conocimiento previo]** |

### 1.3 TheSportsDB (evaluada, no integrada)

- La clave gratuita de prueba aparece como `3` o `123`, según la fuente **[Terceros, contradictorio]**.
- Límite gratuito de unas 30 solicitudes/minuto y plan premium de unos 9 $/mes **[Terceros]**.
- Los resultados en directo son una función premium de la v2, actualizada cada 2 minutos **[Terceros]**.
- Una fuente indica que la API gratuita es **solo para uso no comercial** **[Terceros, sin verificar]**.
- **Motivo para no integrarla:** las condiciones no están claras y no aporta cobertura gratuita
  crítica que no tengan ya las otras fuentes. Se puede añadir como adaptador (ver `docs/arquitectura.md`).

### 1.4 API-Football (api-sports.io) (evaluada, no integrada)

- Plan gratuito: **100 solicitudes/día** (se reinicia a las 00:00 UTC, sin acumular) y 10/minuto **[Terceros]**.
- Incluye todos los endpoints y competiciones, pero solo temporadas recientes **[Terceros]**.
- Planes de pago de unos 15–19 $/mes **[Terceros, cifras contradictorias]**.
- **Es la candidata para cubrir lo que falta gratis** (Liga Profesional Argentina, Libertadores,
  Sudamericana, copas nacionales, Europa League, Conference League). Pero 100 solicitudes al día no
  alcanzan para una app pública si no se cachea con mucha disciplina. **No está integrada**: esas
  competiciones aparecen en el catálogo como «sin fuente gratuita integrada», no con datos inventados.

### 1.5 Fuentes oficiales (UEFA, FIFA, ligas)

- Ni UEFA, ni FIFA, ni las ligas consultadas publican una **API abierta y documentada** de calendario
  para terceros que se haya podido localizar **[Sin verificar]**. Extraer datos de sus webs (*scraping*)
  sin permiso queda descartado.
- Sí publican **directorios de emisoras oficiales**, que OpenFoot usa como fuente de «Dónde ver» (ver §2).

### Resumen de cobertura

| Competición | Fuente integrada | Estado en OpenFoot |
|---|---|---|
| Champions League, Premier, LaLiga, Serie A, Bundesliga, Ligue 1, Eredivisie, Primeira Liga, Championship | football-data.org | Disponible (con retraso en directo) |
| Bundesliga y 2. Bundesliga | OpenLigaDB | Disponible (estado deducido) |
| Brasileirão Série A, Mundial, Eurocopa | football-data.org | Disponible |
| Europa League, Conference League, Copa del Rey, FA Cup | — | Sin fuente gratuita integrada |
| Liga Profesional Argentina, Série B, Libertadores, Sudamericana, Copa Argentina, Copa do Brasil | — | Sin fuente gratuita integrada |
| Eliminatorias, Copa América, Nations League, amistosos, Mundial femenino | — | Sin fuente gratuita integrada |

---

## 2. Derechos audiovisuales y «Dónde ver»

### Hallazgos

- **UEFA** publica en uefa.com guías «Where to watch» por país para la Champions League
  ([guía](https://www.uefa.com/uefachampionsleague/news/newsid=2398198.html)) y para la Europa League
  ([guía](https://www.uefa.com/uefaeuropaleague/news/newsid=2398210.html)). **[Oficial]** Según los
  fragmentos, el asterisco marca emisoras en abierto o solo resúmenes, y las listas cambian durante la
  temporada.
- **Premier League**: su
  [FAQ de emisiones](https://www.premierleague.com/en/about/faq/broadcast) confirma Sky Sports y
  TNT Sports en Reino Unido **para 2025/26** y remite a un listado internacional completo. **[Oficial]**
  Para 2026/27 no se encontró confirmación oficial.
- **FIFA**: un [comunicado oficial](https://inside.fifa.com/media-releases/fifa-world-cup-2026-media-rights-awarded-in-the-nordic-territories)
  adjudica el Mundial 2026 a DR y TV 2 (Dinamarca), Yle y MTV (Finlandia), NRK y TV 2 (Noruega), y
  SVT y TV4 (Suecia). **[Oficial]** No se localizó una lista oficial completa por territorios.
- **LaLiga, Bundesliga y CONMEBOL**: solo aparecieron anuncios sueltos y medios de terceros, a menudo
  contradictorios (por ejemplo, sobre las emisiones en abierto de la Libertadores en Chile).
  **[Terceros]**
- Fuentes como LiveSoccerTV o los agregadores de «dónde ver» **no son fuentes oficiales**: no se usan.

### Decisiones

1. Se publican dos niveles de información:
   - **Directorio oficial del organizador**: un enlace a la guía oficial de emisoras. Siempre es
     legítimo y es la opción de reserva cuando no hay un derecho concreto verificado.
   - **Derecho verificado** (proveedor × competición × país × temporada): solo con fuente, fecha y
     responsable de la verificación, y con caducidad.
2. El catálogo inicial publica los 8 derechos nórdicos del Mundial 2026 (comunicado oficial de FIFA) y
   3 directorios oficiales (Champions, Europa League y Premier League). Todo lo demás queda **pendiente
   de revisión** con su evidencia documentada (`backend/data/catalog.yaml`).
3. El tipo de acceso (gratis, suscripción, PPV) solo se indica si la fuente lo respalda. Si no, se marca
   «Acceso no especificado». Por ejemplo, el comunicado de FIFA no dice si las emisoras nórdicas son
   en abierto.

---

## 3. Imágenes, escudos y banderas

- Los escudos de clubes y federaciones son **marcas registradas**, y a menudo obras protegidas. En
  Wikimedia Commons la mayoría de los escudos actuales están marcados como no libres o con avisos de
  marca. **[Terceros]**
- **Decisión:** la app usa por defecto **monogramas propios** (iniciales o código de tres letras)
  generados en el dispositivo. Las URL de escudos solo se sirven si el operador del servidor activa
  `OPENFOOT_SERVE_CREST_URLS` y asume la responsabilidad de tener permiso.
- **Banderas:** se usan **emojis de bandera Unicode**, que dibuja la fuente del sistema. No hay
  imágenes con licencia en el repositorio.

---

## 4. Viabilidad económica

| Partida | Opción gratuita | Límite | Coste si se supera |
|---|---|---|---|
| Datos deportivos | football-data.org gratis + OpenLigaDB | 12 competiciones, retraso en directo, 10 solicitudes/min | Planes de pago de football-data.org o API-Football |
| Servidor | Autoalojado (un PC o una Raspberry Pi) o VPS pequeño | Depende del tráfico | VPS de 4–6 €/mes aprox. **[Estimación]** |
| Base de datos | PostgreSQL autoalojado o SQLite | — | Incluido en el VPS |
| Dominio y TLS | Let's Encrypt (TLS gratis) | — | El dominio cuesta unos 10 €/año **[Estimación]** |
| Compilación del APK | GitHub Actions (gratis en repos públicos, con cuotas) | Minutos de CI | — |
| Publicar en Google Play | — | — | Cuota única de registro de desarrollador **[Sin verificar el importe actual]** |

Más detalle en `docs/sostenibilidad.md`.

## 5. Fuentes consultadas (vía buscador)

- football-data.org (límites y cobertura, según terceros): thestatsapi.com, sportmonks.com, highlightly.net, freeapihub.com
- OpenLigaDB: openligadb.readthedocs.io, freeapihub.com, publicapi.dev
- TheSportsDB: freeapihub.com, apievangelist.com, mintlify.com (teamarr)
- API-Football: api-football.com (guía de inicio), thestatsapi.com
- UEFA: uefa.com (guías «Where to watch» de Champions y Europa League)
- Premier League: premierleague.com/en/about/faq/broadcast; tomsguide.com y techradar.com (terceros)
- Bundesliga: bundesliga.com (noticias), insideworldfootball.com, broadbandtvnews.com
- FIFA: inside.fifa.com (comunicado de derechos nórdicos del Mundial 2026)
- CONMEBOL: insidersport.com, espndeportes.espn.com, redgol.cl (terceros)
- Escudos: páginas de Wikimedia Commons y worldipreview.com
