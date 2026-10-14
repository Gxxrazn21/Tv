# Retirada de contenido y corrección de enlaces

OpenFoot no aloja ni emite contenido audiovisual: solo enlaza a páginas oficiales. Aun así, nos
tomamos en serio cualquier error o reclamación.

## Quién puede pedir algo
- **Titulares de derechos** (ligas, federaciones, emisoras, clubes) que detecten un enlace incorrecto,
  una atribución errónea o un uso indebido de sus marcas.
- **Usuarios** que encuentren un enlace roto, caducado, que lleve a una web no oficial o con un tipo
  de acceso (gratis o de pago) equivocado.

## Cómo
1. Abre una incidencia en https://github.com/gxxrazn21/tv/issues/new (desde la app: ficha del
   partido → «Informar de un enlace incorrecto»).
2. Indica la competición, el país, el proveedor y la URL afectada y, si eres titular de derechos, la
   relación con el contenido. **No incluyas datos personales ni credenciales.**
3. Para solicitudes confidenciales, pide en la incidencia un canal privado.

## Qué hacemos
| Caso | Acción | Plazo orientativo |
|---|---|---|
| Enlace que no es oficial o que infringe derechos | Se marca `rejected` con `openfoot review reject` y se elimina del catálogo | En cuanto se confirme; prioridad máxima |
| Enlace roto o caducado | Se marca `rejected` o se actualiza tras verificar la nueva URL | Siguiente revisión |
| Tipo de acceso o territorio incorrecto | Se corrige en `catalog.yaml` mediante un pull request con la fuente | Siguiente revisión |
| Petición de un titular para no aparecer | Se retiran sus entradas y se documenta en el historial | En cuanto se confirme |

Todas las correcciones quedan registradas en el historial de git del catálogo.
