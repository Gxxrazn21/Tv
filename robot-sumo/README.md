# Robot de mini-sumo RC: simulador 3D y firmware

Robot de sumo con ESP32-WROOM-32, controlador TB6612FNG (PCB CUyLAB V3.1), dos motores N20 de 6 V y
500 RPM, batería LiPo 2S y mando DualShock 4 por Bluetooth.

```
robot-sumo/
├── simulador/index.html        Dohyo 3D: conduces el robot con teclado, mando PS4 o pantalla táctil
└── firmware/sumo_ps4/
    └── sumo_ps4.ino            Sketch para el ESP32 (GPIO en -1 hasta que los confirmes)
```

## Simulador

Abre `simulador/index.html` en Chrome o Edge (necesita internet para cargar three.js).

| Teclado | Mando DS4 | Acción |
|---|---|---|
| W / S | Stick izquierdo vertical | Avance y retroceso |
| A / D | Stick izquierdo horizontal | Giro diferencial |
| Shift | R2 | Ataque: sube el límite de PWM |
| Espacio | L2 | Freno corto |
| X | ✕ | Parada inmediata (STBY a LOW) |
| T | △ / OPTIONS | Rearmar con el stick centrado |
| R | SHARE | Nueva ronda |

Un DualShock 4 conectado al ordenador por USB o Bluetooth también controla el simulador.

El simulador ejecuta la misma función `pasoControl()` que el firmware, cada 10 ms, y escribe los
mismos niveles en los pines del TB6612FNG (STBY, AIN1/AIN2/PWMA, BIN1/BIN2/PWMB). Esos niveles
alimentan un modelo de motor de corriente continua (par y corriente de bloqueo, RPM sin carga),
tracción limitada por el agarre de las ruedas y una cuña que levanta al rival. El panel muestra:

- **Control:** stick, gatillos, barra de luz del mando, estado de cada pin y tensión, RPM, corriente
  y tracción de cada motor, con las marcas de 1,2 A continuos y 3,2 A de pico del TB6612FNG.
- **Ajustes:** los 7 GPIO (con validación de pines de flash, solo entrada y arranque), límites de
  potencia, rampa, giro, expo y zona muerta, y un «cableado físico simulado» para ensayar la prueba
  de giro cruzando motores.
- **Código:** el sketch generado con tus GPIO y ajustes, listo para copiar.
- **Montaje:** conexiones de alimentación y motores, tabla de verdad y prueba de giro.

## Firmware

1. Arduino IDE → Gestor de placas → **esp32** de Espressif **2.0.17** (PS4Controller no funciona con 3.x).
2. Librería **PS4Controller** ([aed3/PS4-esp32](https://github.com/aed3/PS4-esp32)).
3. Placa **ESP32 Dev Module**, monitor serie a 115200.
4. Con SixaxisPairTool, lee o cambia la MAC maestra del mando y escríbela en `PS4_MAC`.
5. Completa los 7 GPIO en `sumo_ps4.ino` (o en el simulador y copia el código generado).
   Con algún GPIO en `-1`, el programa no activa ninguna salida e imprime el estado del mando por el
   monitor serie, útil para probar el emparejado.
6. Primera prueba con las ruedas en el aire. Ajusta `MOTOR_IZQ_EN_A`, `INVERTIR_IZQ` e
   `INVERTIR_DER` hasta que ambas ruedas avancen con el stick hacia delante.

Seguridad incluida: arranca en parada, ✕ corta STBY, y sin paquetes del mando durante 300 ms el
robot se detiene y exige rearmar con △.

Los N20 son de 6 V: con la batería llena (8,4 V), un PWM por encima del 71 % les da más tensión de la
nominal. Los límites por defecto son 70 % (normal) y 85 % (ataque); sube el de ataque solo después de
medir la corriente con las ruedas bloqueadas y comprobar la temperatura de motores y driver.
