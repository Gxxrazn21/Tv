# Política de privacidad de OpenFoot

Última actualización: 14 de octubre de 2026.

OpenFoot está pensado para recopilar **lo mínimo posible**. No afirmamos que sea «totalmente
privado»: para mostrarte partidos, la app tiene que hacer peticiones a un servidor, y ese servidor
recibe ciertos metadatos. Esta política explica exactamente cuáles.

## Lo que NO hacemos
- No hay cuentas ni registro.
- No hay publicidad, banners ni contenido patrocinado.
- No hay rastreadores publicitarios, SDK de analítica ni identificadores publicitarios.
- No vendemos ni cedemos datos.
- No pedimos ubicación, contactos, cámara, micrófono ni almacenamiento externo.

## Lo que se guarda en tu dispositivo (y solo ahí)
| Dato | Dónde | Para qué |
|---|---|---|
| Equipos y competiciones favoritos | SQLite local | Personalizar Inicio y Favoritos |
| Recordatorios | SQLite local + sistema de notificaciones del dispositivo | Avisarte antes de un partido |
| Caché de respuestas (máximo 14 días) | SQLite local | Ver datos sin conexión |
| Preferencias (tema, zona horaria, país, servidor, secciones) | `shared_preferences` | Recordar tus ajustes |

Puedes borrar la caché desde Ajustes. Al desinstalar la app se borra todo. En Android la copia de
seguridad automática está desactivada (`allowBackup="false"`).

## Lo que recibe el servidor de OpenFoot
Cada petición de la app al servidor configurado (el de OpenFoot o uno autoalojado) envía:
- tu **dirección IP** (inevitable en cualquier conexión de red);
- la **ruta y los parámetros** de la consulta: fechas, zona horaria, competición, equipo, texto de
  búsqueda y el **país elegido** para «Dónde ver»;
- cabeceras técnicas estándar (por ejemplo, el agente de usuario de la librería HTTP).

El servidor oficial se ejecuta **sin registro de accesos** (`--no-access-log`). Solo registra errores
internos (tipo de error y ruta, sin cabeceras ni parámetros) y, durante un minuto, la IP en memoria
para aplicar el límite de solicitudes. No se guarda en disco. Quien autoaloje el servidor es
responsable de su propia configuración y de la de su proxy inverso.

## Servicios de terceros
- **Proveedores de datos deportivos** (football-data.org, OpenLigaDB): los consulta **el servidor**,
  nunca tu móvil. Reciben la IP del servidor y las consultas de sincronización, que no contienen
  datos de usuarios.
- **Proveedores audiovisuales:** al pulsar «Abrir», sales de OpenFoot a la web o app del proveedor,
  que aplica **su propia política de privacidad**. OpenFoot no les envía ningún identificador tuyo.
- **Imágenes de escudos:** desactivadas por defecto. Si un servidor las activa, tu dispositivo
  descargaría las imágenes desde el dominio que las aloje, que vería tu IP.

## Notificaciones
Los recordatorios son **notificaciones locales** programadas en tu dispositivo. No se usan
notificaciones push ni servicios de mensajería.

## Contacto y cambios
Puedes abrir una incidencia en https://github.com/gxxrazn21/tv/issues. Los cambios en esta política
quedan registrados en el historial del repositorio.
