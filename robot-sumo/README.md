# Robot de mini-sumo RC: simulador 3D y firmware

Robot de sumo con ESP32-WROOM-32, controlador TB6612FNG (PCB CUyLAB V3.1), dos motores N20 de 6 V y
500 RPM, batería LiPo 2S y mando genérico de Switch por Bluetooth (MAC 98:B6:E9:85:31:E4).

```
robot-sumo/
├── simulador/index.html        Dohyo 3D: conduces el robot con teclado, mando o pantalla táctil
└── firmware/sumo_switch/
    └── sumo_switch.ino         Sketch para el ESP32 con Bluepad32 (GPIO en -1 hasta que los confirmes)
```

## Simulador

Abre `simulador/index.html` en Chrome o Edge (necesita internet para cargar three.js).

| Teclado | Mando Switch | Acción |
|---|---|---|
| W / S | Stick izquierdo vertical | Avance y retroceso |
| A / D | Stick izquierdo horizontal | Curva suave para hacer zigzag |
| ← / → | Stick derecho horizontal | Giro fuerte; sin avanzar, gira sobre sí mismo |
| Shift | ZR | Ataque: sube el límite de PWM |
| Espacio | ZL | Freno corto |
| X | B (botón de abajo) | Parada inmediata (STBY a LOW) |
| T | X (botón de arriba) | Rearmar con el stick centrado |
| R | − | Nueva ronda (solo en el simulador) |

El mando conectado al ordenador por USB o Bluetooth también controla el simulador.

El simulador ejecuta la misma función `pasoControl()` que el firmware, cada 10 ms, y escribe los
mismos niveles en los pines del TB6612FNG (STBY, AIN1/AIN2/PWMA, BIN1/BIN2/PWMB). Esos niveles
alimentan un modelo de motor de corriente continua (par y corriente de bloqueo, RPM sin carga),
tracción limitada por el agarre de las ruedas y una cuña que levanta al rival. El panel muestra:

- **Control:** stick, gatillos, LED de jugador del mando, estado de cada pin y tensión, RPM,
  corriente y tracción de cada motor, con las marcas de 1,2 A continuos y 3,2 A de pico del TB6612FNG.
- **Ajustes:** los 7 GPIO (con validación de pines de flash, solo entrada y arranque), límites de
  potencia, rampa, giro, expo y zona muerta, y un «cableado físico simulado» para ensayar la prueba
  de giro cruzando motores.
- **Código:** el sketch generado con tus GPIO y ajustes, listo para copiar.
- **Montaje:** conexiones de alimentación y motores, tabla de verdad y prueba de giro.

## Firmware

El mando es de Switch, así que el sketch usa **Bluepad32** (PS4Controller solo sirve para DualShock 4).

1. Arduino IDE → Preferencias → «Gestor de URLs adicionales de tarjetas»:
   `https://raw.githubusercontent.com/ricardoquesada/esp32-arduino-lib-builder/master/bluepad32_files/package_esp32_bluepad32_index.json`
2. Gestor de placas → instala **esp32_bluepad32** (incluye la librería Bluepad32).
3. Placa **ESP32 Arduino (Bluepad32) → ESP32 Dev Module**, monitor serie a 115200.
4. `MAC_MANDO` ya tiene tu mando (`98:B6:E9:85:31:E4`). Con `SOLO_ESTE_MANDO 1` se ignora
   cualquier otro mando cercano. Si el tuyo no conecta, ponlo a `0` y mira en el monitor serie la
   dirección con la que se presenta.
5. Completa los 7 GPIO en `sumo_switch.ino` (o en el simulador y copia el código generado).
   Con algún GPIO en `-1`, el programa no activa ninguna salida e imprime el estado del mando por el
   monitor serie, útil para probar el emparejado.
6. Emparejar: con el ESP32 encendido, mantén pulsado el botón de sincronización del mando hasta que
   conecte. Si estaba emparejado con una Switch, déjala apagada.
7. Primera prueba con las ruedas en el aire. Ajusta `MOTOR_IZQ_EN_A`, `INVERTIR_IZQ` e
   `INVERTIR_DER` hasta que ambas ruedas avancen con el stick hacia delante.

Los gatillos ZL/ZR del mando de Switch son digitales: ZR pasa directamente del límite normal al de
ataque.

Seguridad incluida: arranca en parada, B corta STBY, y sin datos del mando durante 300 ms el
robot se detiene y exige rearmar con X. Los LED de jugador indican el modo (extremos = parada,
1 = normal, 4 = ataque, centrales = freno) y el mando vibra al armar.

Los N20 son de 6 V: con la batería llena (8,4 V), un PWM por encima del 71 % les da más tensión de la
nominal. Los límites por defecto son 70 % (normal) y 85 % (ataque); sube el de ataque solo después de
medir la corriente con las ruedas bloqueadas y comprobar la temperatura de motores y driver.
