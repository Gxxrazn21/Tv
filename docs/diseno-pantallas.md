# Diseño de pantallas

Identidad propia: verde césped (`#1B8A5A`) como color semilla de Material 3, rojo solo para
**EN DIRECTO** y colores distintos para cada tipo de acceso. **Tema oscuro por defecto**; el claro
y el del sistema se eligen en Ajustes. No se imitan interfaces, logotipos ni identidades de otras
apps deportivas.

## Navegación

Barra inferior con **Inicio · Partidos · Competiciones · Favoritos**. La búsqueda (🔍) y los
ajustes (⚙) están en la barra superior de las pantallas principales.

## Inicio
```
┌─────────────────────────────────────┐
│ OpenFoot                      🔍  ⚙ │
│ [Ayer] [■Hoy■] [Mañana] [📅 Otra fecha]│
│ [⏷ Competición] [⏷ País]             │
│ Competiciones destacadas             │
│ (Champions) (Premier) (LaLiga) …     │
│ Tus favoritos (1)                    │
│ En directo (1)                       │
│ ┌ Premier League · J8   ● EN DIRECTO┐│
│ │ (ROV) Rovers  1   21:00   0 Atlético (ATM)│
│ └───────────────────────────────────┘│
│ Próximos (3) · Finalizados (5)       │
│ Aplazados, cancelados o sin confirmar│
└─────────────────────────────────────┘
```
- Se refresca solo cada 60 s mientras hay partidos en directo, y al deslizar hacia abajo.
- Las secciones se pueden ocultar desde Ajustes (personalización).

## Partidos (calendario)
Franja horizontal de ±14 días más un selector de fecha (hasta ±1 año). Filtros por competición, país
y equipo favorito. Los partidos se agrupan por competición. Los cambios de horario se marcan con
«Horario cambiado».

## Competiciones
Agrupadas por **Europa / Sudamérica / Internacional**. Las competiciones sin fuente de datos se
muestran con ⓘ y explican por qué no hay datos, en lugar de aparecer vacías o con datos inventados.
Cada una tiene una estrella para marcarla como favorita.

## Ficha del partido
```
            ● EN DIRECTO
   (ROV)                     (ATM)
   Rovers       1 - 0        Atlético
     ☆                          ☆
🕘 miércoles 14 de octubre de 2026, 21:00 (Europe/Madrid)
🏆 Premier League · Jornada 8
🏟 Estadio (si la fuente lo da)
🔔 Recordatorio [  ]  (solo próximos)
Datos: football-data.org · actualizado …
Goles: 12' Jugador (Rovers)
──────────────────────────────────────
Dónde ver                    🇪🇸 España ▸
┌ Proveedor X            [🔓 Gratis] ┐
│ Verificado el … · fuente: …         │
│ [↗ Abrir Proveedor X]  Ver fuente   │
└─────────────────────────────────────┘
┌ Proveedor Y         [🔒 Suscripción]┐ …
– o, si no hay nada verificado –
🔍 No se encontró una transmisión oficial verificada para esta región
📋 Directorio oficial de emisoras (UEFA) ↗
Aviso: OpenFoot no emite ni redistribuye señales…
⚑ Informar de un enlace incorrecto
```
- Insignias de acceso: **Gratis** (verde, candado abierto), **Suscripción** (azul, candado),
  **Pago por evento** (ámbar, entrada) y **Acceso no especificado** (gris). El texto siempre
  acompaña al color.
- «Abrir» lanza el navegador o la app oficial (`LaunchMode.externalApplication`). La app **nunca**
  reproduce señales.

## Favoritos
Próximos partidos de los equipos favoritos (unidos y ordenados), lista de equipos y lista de
competiciones. Todo se guarda solo en el dispositivo.

## Búsqueda
Se busca a medida que se escribe (con 350 ms de espera). Encuentra equipos, jugadores (goleadores
sincronizados), competiciones y países, y también partidos por fecha (`14/10/2026`). Tolera errores
ortográficos («Ejmplo Rovers» → «Ejemplo Rovers»; «atletico» → «Atlético»).

## Ajustes
Tema · zona horaria (automática o cualquier zona IANA, con buscador) · país para «Dónde ver» ·
secciones de Inicio · minutos de aviso · servidor (autoalojable) · borrar caché · privacidad ·
fuentes y atribuciones · código fuente · licencias de terceros.

## Estados y accesibilidad
- Estados de **carga**, **error con «Reintentar»**, **lista vacía con explicación** y **sin conexión**
  (banner con la fecha de los datos guardados).
- Cada tarjeta de partido tiene una etiqueta completa para lectores de pantalla, por ejemplo:
  «Rovers contra Atlético, en directo, 1 a 0, Premier League, miércoles 14 de octubre…». Los
  encabezados están marcados como `header` y todos los botones de icono tienen *tooltip*.
- Los estados no dependen solo del color. El diseño se adapta con `Expanded` y `Flexible`, y las
  listas se desplazan.
