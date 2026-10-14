# Seguridad

## Secretos
- Las claves (por ejemplo `OPENFOOT_FOOTBALL_DATA_TOKEN`) se leen de variables de entorno o de
  `backend/.env`, que git ignora, y se guardan como `SecretStr`, que no aparece en logs ni en
  representaciones del objeto.
- **La app móvil no contiene ninguna clave**: solo habla con el backend.
- `.env.example` documenta las variables sin valores reales.

## API pública
- Solo lectura. **No hay endpoints de administración**: la administración se hace por CLI con acceso
  al servidor.
- Validación estricta de entradas: zonas horarias IANA, códigos de país ISO alfa-2, listas de códigos
  alfanuméricos, rangos de fechas de 31 días como máximo y paginación acotada (`limit` ≤ 500).
- Todas las consultas usan el ORM con parámetros enlazados (sin SQL concatenado) y se prueban con
  entradas como `PL;DROP TABLE`.
- Límite por cliente (ventana deslizante en memoria, `OPENFOOT_RATE_LIMIT_PER_MINUTE`).
  `X-Forwarded-For` solo se tiene en cuenta si `OPENFOOT_TRUST_FORWARDED_FOR=true`, es decir, detrás
  de un proxy de confianza.
- Cabeceras `X-Content-Type-Options: nosniff`, `Referrer-Policy: no-referrer`,
  `X-Frame-Options: DENY` y `Cache-Control: no-store`.
- Los errores no controlados devuelven un 500 genérico. Se registran el tipo de excepción y la ruta,
  nunca el detalle ni los datos del cliente.

## Verificador de enlaces y SSRF (`services/linkcheck.py`)
- Solo `https`, puerto 443, sin credenciales en la URL y **sin IP literales**.
- El dominio debe pertenecer a los `official_domains` registrados del proveedor.
- El host se resuelve y **todas** sus direcciones deben ser públicas. Se rechazan:
  - redes privadas (10/8, 172.16/12, 192.168/16) y loopback;
  - link-local, incluido `169.254.169.254` (metadatos de nube);
  - CGNAT (100.64/10), 0.0.0.0, multicast y rangos reservados;
  - en IPv6: `::1`, ULA (`fd00::/8`), link-local y direcciones IPv4 mapeadas (`::ffff:127.0.0.1`).
- **La conexión se fija a la IP ya validada**, lo que evita el *DNS rebinding*, pero se mantienen el
  SNI y la cabecera `Host`, así que el certificado TLS se valida contra el dominio.
- Las redirecciones se siguen **a mano**, cinco como máximo. En cada salto se vuelven a normalizar y
  validar el esquema, el dominio registrado y las IP. Un salto a http, a una IP privada o a un dominio
  ajeno detiene la comprobación.
- No se usan los proxies del entorno (`trust_env=False`), ni cookies, ni credenciales, y no se
  descarga el cuerpo de la respuesta.
- Las pruebas cubren todos estos casos (`tests/test_linkcheck.py`).

## App móvil
- `network_security_config`: solo HTTPS, con excepción para `10.0.2.2`, `localhost` y `127.0.0.1`
  (desarrollo).
- La URL del servidor configurable se valida: https, o http solo para equipos locales, y sin
  credenciales.
- Los enlaces externos solo se abren si son `https://` y siempre en una aplicación externa.
- Permisos de Android mínimos: `INTERNET`, `POST_NOTIFICATIONS` (opcional, se pide al activar el
  primer recordatorio) y `RECEIVE_BOOT_COMPLETED` (para reprogramar recordatorios tras reiniciar).

## Dependencias y versiones
- `pip-audit` en la CI (backend): «No known vulnerabilities found» el 14/10/2026.
- Dart: `flutter pub outdated` en el mantenimiento periódico. `pubspec.lock` está versionado.
- La base de datos se versiona con migraciones de Alembic, y la CI comprueba que el modelo y las
  migraciones no divergen.

## Cómo informar de una vulnerabilidad
Abre una incidencia **sin detalles explotables** en https://github.com/gxxrazn21/tv/issues pidiendo
un canal privado, o usa los avisos de seguridad privados de GitHub en el repositorio.
