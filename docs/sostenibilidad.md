# Sostenibilidad y costes

OpenFoot **no tiene publicidad, suscripciones, compras ni funciones de pago**. Para que sea
sostenible:

## Cómo funciona sin ingresos
- **Software libre** (Apache-2.0): cualquiera puede ejecutar su propio servidor.
- **Autoalojamiento:** un servidor pequeño basta para un uso personal o comunitario. La app permite
  apuntar a otro servidor desde Ajustes.
- **APIs gratuitas dentro de sus condiciones:** el servidor sincroniza cada 15 minutos por defecto y
  sirve a todos los usuarios desde su base de datos. El número de llamadas a la API de datos **no
  crece con el número de usuarios**.
- **Caché responsable:** en el servidor, la base de datos hace de caché. En el móvil, la caché local
  dura hasta 14 días.
- **Contribuciones voluntarias opcionales** (por ejemplo, patrocinio en GitHub), siempre que **no
  desbloqueen funciones, no cambien la experiencia y no introduzcan publicidad**.
- **Colaboración comunitaria** en el catálogo: pull requests revisados con su fuente.

## Costes inevitables (estimaciones orientativas, sin verificar precios actuales)
| Concepto | Opción mínima | Coste aproximado |
|---|---|---|
| Servidor | Equipo propio o VPS de 1 vCPU y 1–2 GB | 0 € (propio) o unos 4–6 €/mes (VPS) |
| Dominio | Opcional para uso local; necesario para TLS público | Unos 10 €/año |
| Certificado TLS | Let's Encrypt | 0 € |
| Tráfico | Respuestas JSON pequeñas (unos KB por consulta) | Normalmente incluido en el VPS |
| Datos deportivos | football-data.org gratuito (12 competiciones, retraso en directo) | 0 €; ampliar cobertura o tener directo real cuesta dinero |
| Publicar en Google Play | Cuota única de registro de desarrollador | Revisar el importe vigente |
| CI | GitHub Actions en repositorio público | 0 € dentro de las cuotas |

## Límites que hay que conocer
- El plan gratuito de football-data.org (10 solicitudes/min según terceros) limita la frecuencia de
  sincronización y no ofrece resultados en directo sin retraso.
- Las competiciones sudamericanas y las copas no tienen fuente gratuita integrada. Cubrirlas implica
  integrar API-Football (100 solicitudes/día gratis) o pagar un plan.
- Un servidor público con mucho tráfico necesitará más recursos y, quizá, un proxy con caché delante.
  **No prometemos funcionamiento ilimitado sin coste.**
