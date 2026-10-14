# Catálogo de proveedores y verificación de enlaces

## Principios
1. **Solo fuentes permitidas**, por orden de preferencia: (1) directorios oficiales de emisoras de
   los organizadores, (2) APIs documentadas y autorizadas, (3) páginas oficiales de los titulares de
   derechos, (4) enlaces facilitados por proveedores autorizados, (5) otras fuentes con legitimidad
   comprobada.
2. **Nunca**: webs piratas, agregadores de streams, extracción de URL HLS/DASH, descifrado, evasión de
   DRM o de bloqueos geográficos, ni reutilización de cookies, tokens o credenciales.
3. **Un HTTP 200 no prueba nada legal.** La comprobación técnica solo sirve para detectar enlaces
   rotos o redirecciones sospechosas.
4. **Que un dominio parezca legítimo no basta.** `official_domains` lo fija una persona tras revisar
   la fuente.
5. Si algo no se puede validar, **no se publica**. La app muestra: «No se encontró una transmisión
   oficial verificada para esta región».

## Ciclo de vida de una entrada
```
pending_review ──(revisión humana: openfoot review approve right N --by "nombre")──▶ verified
      │                                                                                 │
      └──(openfoot review reject … --note "motivo")──▶ rejected        caduca a los 30 días┘
                                                                     (OPENFOOT_VERIFICATION_TTL_DAYS)
```
Un derecho se muestra solo si se cumplen **todas** estas condiciones:
- su estado es `verified`;
- la verificación tiene menos de N días;
- su periodo de validez cubre la fecha del partido;
- el último chequeo técnico no fue `broken`, `offsite_redirect` ni `blocked`.

## Campos del catálogo (`backend/data/catalog.yaml`)
- **Proveedor:** `slug`, `name`, `website_url`, `official_domains`, `countries`.
- **Derecho:** proveedor, competición, país ISO-3166 alfa-2, temporada, `valid_from` y `valid_to`,
  `access_type` (`free`, `subscription`, `ppv`, `unknown`), `price_note`, `territorial_notes`,
  `coverage_note`, `watch_url`, `embed_allowed` (por defecto false; la app no integra reproductores),
  `source_type`, `source_url`, `status`, `verified_at`, `verified_by`, `review_note`.
- **Directorio oficial:** competición, organizador, `url`, `official_domains` y estado.

El cargador **rechaza** (no corrige) estas entradas:
- `watch_url` fuera de los dominios del proveedor;
- URL que no sean https, con credenciales o con puertos no estándar;
- entradas verificadas sin fuente, fecha o responsable;
- códigos de país o tipos de acceso no válidos.

## Comprobación técnica (`openfoot check-links`)
- **Normalización:** esquema y host en minúsculas, IDNA, sin fragmento ni parámetros de seguimiento
  (`utm_*`, `fbclid`, `gclid`…) y con la consulta ordenada. Esto también sirve para detectar duplicados.
- **Resultados:** `ok` (2xx); `restricted` (401/403/429/451, posible bloqueo geográfico o de
  suscripción, sin conclusión); `broken` (404/410/otros 4xx); `error` (5xx, red o DNS);
  `blocked` (política de seguridad); `offsite_redirect` (redirección fuera de los dominios del
  proveedor).
- Se registran la **cadena de redirecciones**, la URL final, el código y la fecha (`link_checks`).
- Las protecciones frente a SSRF se describen en `docs/seguridad.md`.

## Revisión manual de proveedores nuevos o dudosos
1. Abre un pull request añadiendo la entrada con `status: pending_review` y `source_url`.
2. La persona revisora comprueba en la **fuente oficial** la competición, el territorio, la temporada
   y el tipo de acceso, y luego cambia la entrada a `verified` con `verified_at` y `verified_by`
   (o la aprueba con `openfoot review approve`).
3. Ejecuta `openfoot check-links` antes de desplegar.

## Estado del catálogo inicial (14/10/2026)
- **Verificados:** 8 derechos del Mundial 2026 en los países nórdicos (comunicado oficial de FIFA) y
  3 directorios oficiales (Champions League y Europa League en uefa.com, Premier League en
  premierleague.com).
- **Pendientes (no publicados):** Premier League en Reino Unido (Sky Sports, TNT Sports) y en EE. UU.
  (Peacock), y Europa League en Reino Unido, España y EE. UU. Falta confirmarlos para 2026/27.
- **Comprobación HTTP:** no se pudo ejecutar desde el entorno de desarrollo, que no tenía acceso a
  esos dominios. Es obligatoria antes del despliegue.
