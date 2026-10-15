/*
  Robot de mini-sumo RC: ESP32-WROOM-32 + mando Switch (Bluetooth) + TB6612FNG
  PCB CUyLAB V3.1 · LiPo 2S 500 mAh · 2 motores N20 6 V 500 RPM

  Generado por el Simulador Sumo ESP32. La función pasoControl() es la
  misma que mueve el robot del simulador: con los mismos ajustes, el
  robot real responde igual al mando.

  Preparación
   1. Arduino IDE > Preferencias > "Gestor de URLs adicionales de tarjetas":
      https://raw.githubusercontent.com/ricardoquesada/esp32-arduino-lib-builder/master/bluepad32_files/package_esp32_bluepad32_index.json
   2. Gestor de placas > instala "esp32_bluepad32" (trae la librería Bluepad32).
   3. Placa: "ESP32 Arduino (Bluepad32)" > "ESP32 Dev Module".
      Monitor serie a 115200 baudios.
   4. Con SOLO_ESTE_MANDO a 1 solo se acepta el mando de MAC_MANDO.
      Si tu mando no conecta, ponlo a 0 y mira en el monitor serie la
      dirección con la que se presenta.
   5. Completa los 7 GPIO. Si alguno vale -1 o no sirve como salida,
      el programa no activa ninguna salida y lo avisa por el monitor serie.

  Emparejar: enciende el ESP32 y mantén pulsado el botón de sincronización
  del mando (el pequeño junto al USB) hasta que los LED recorran de lado a
  lado. Si el mando estaba emparejado con una Switch, déjala apagada.

  Controles (posición de los botones en el mando de Switch)
   Stick izquierdo vertical    avance y retroceso
   Stick izquierdo horizontal  curva suave para zigzag (GIRO_ZIGZAG)
   Stick derecho horizontal    giro fuerte; sin avanzar, gira sobre sí mismo
   ZR                          ataque: sube el límite de potencia
   ZL                          freno corto (IN1 = IN2 = HIGH)
   B (botón de abajo)          parada inmediata (STBY = LOW)
   X (botón de arriba)         rearmar, con el stick centrado y ZR suelto
   El robot arranca en parada y vuelve a ella si se pierde el mando.
*/

#include <Bluepad32.h>

// ---------- Mando ----------
#define SOLO_ESTE_MANDO 1                 // 1: ignora cualquier otro mando
const char* MAC_MANDO = "98:B6:E9:85:31:E4";

#if SOLO_ESTE_MANDO
#include <uni.h>
#endif

// ---------- GPIO del TB6612FNG (-1 = sin confirmar) ----------
const int PIN_PWMA = -1;
const int PIN_AIN1 = -1;
const int PIN_AIN2 = -1;
const int PIN_STBY = -1;
const int PIN_BIN1 = -1;
const int PIN_BIN2 = -1;
const int PIN_PWMB = -1;

// ---------- Montaje: ajustar con la prueba de giro ----------
const bool MOTOR_IZQ_EN_A = true;  // true: motor izquierdo en AO1/AO2
const bool INVERTIR_IZQ   = false;
const bool INVERTIR_DER   = false;

// ---------- Conducción ----------
// Con la batería llena (8,4 V), un 71 % de PWM equivale a unos 6 V en el motor.
const float LIMITE_NORMAL = 0.7f;  // fracción de PWM sin ZR
const float LIMITE_ATAQUE = 0.85f;  // fracción de PWM con ZR pulsado
const float RAMPA         = 6.0f;  // cambio máximo de PWM por segundo (1 = 100 %)
const float GANANCIA_GIRO = 0.75f;  // stick derecho: giro fuerte
const float GIRO_ZIGZAG   = 0.35f;  // stick izquierdo horizontal: curva suave
const float EXPO          = 0.4f;  // 0 = lineal; cerca de 1 = muy suave en el centro
const float ZONA_MUERTA   = 0.08f;
const float UMBRAL_FRENO  = 0.2f;  // recorrido de ZL que activa el freno

const uint32_t PERIODO_MS    = 10;     // bucle de control a 100 Hz
const uint32_t SIN_SENAL_MS  = 300;    // sin datos del mando durante este tiempo = parada
const uint32_t PWM_FREQ      = 20000;  // 20 kHz, fuera del rango audible
const uint8_t  PWM_BITS      = 8;
const int      PWM_MAX       = (1 << PWM_BITS) - 1;
const bool     DEPURAR       = false;  // true: imprime el estado cada 250 ms

// ---------- Tipos y estado ----------
enum Modo { DESCONECTADO, PARADA, FRENO, NORMAL, ATAQUE };
const char* NOMBRE_MODO[] = { "desconectado", "parada", "freno", "normal", "ataque" };

struct Entrada { bool conectado; float lx, ly, rx, zr, zl; bool parar, rearmar; };
struct Estado  { bool parada; float salIzq, salDer; };
struct Motor   { int pwm, in1, in2, canal; bool invertir; };

Estado estado = { true, 0, 0 };
Motor motorIzq, motorDer;
bool pinesListos = false;
uint32_t ultimoPaso = 0, ultimaTraza = 0;
uint32_t ultimoPaquete = 0;
ControllerPtr mando = nullptr;
int ultimoModo = -1;

float limitar(float v, float lo, float hi) { return v < lo ? lo : (v > hi ? hi : v); }

float zonaMuerta(float v) {
  float a = fabsf(v);
  if (a < ZONA_MUERTA) return 0;
  return copysignf((a - ZONA_MUERTA) / (1 - ZONA_MUERTA), v);
}

float curvaExpo(float v) { return v * (EXPO * v * v + (1 - EXPO)); }

float rampa(float actual, float objetivo, float paso) {
  return actual + limitar(objetivo - actual, -paso, paso);
}

// Lógica de conducción. Es la misma que ejecuta el simulador.
Modo pasoControl(Estado& st, const Entrada& in, float dt) {
  if (!in.conectado) { st.parada = true; st.salIzq = st.salDer = 0; return DESCONECTADO; }
  if (in.parar) st.parada = true;
  bool centrado = zonaMuerta(in.lx) == 0 && zonaMuerta(in.ly) == 0 && zonaMuerta(in.rx) == 0 && in.zr < 0.1f;
  if (st.parada && in.rearmar && centrado) st.parada = false;
  if (st.parada) { st.salIzq = st.salDer = 0; return PARADA; }
  if (in.zl > UMBRAL_FRENO) { st.salIzq = st.salDer = 0; return FRENO; }

  float avance = curvaExpo(zonaMuerta(in.ly));
  float giro = curvaExpo(zonaMuerta(in.lx)) * GIRO_ZIGZAG
             + curvaExpo(zonaMuerta(in.rx)) * GANANCIA_GIRO;
  giro = limitar(giro, -1, 1);
  float izq = avance + giro;
  float der = avance - giro;
  float m = fmaxf(fabsf(izq), fabsf(der));
  if (m > 1) { izq /= m; der /= m; }

  float limite = LIMITE_NORMAL + (LIMITE_ATAQUE - LIMITE_NORMAL) * in.zr;
  float paso = RAMPA * dt;
  st.salIzq = rampa(st.salIzq, izq * limite, paso);
  st.salDer = rampa(st.salDer, der * limite, paso);
  return in.zr > 0.1f ? ATAQUE : NORMAL;
}

// ---------- TB6612FNG ----------
void pwmConfigurar(const Motor& m) {
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcAttach(m.pwm, PWM_FREQ, PWM_BITS);
#else
  ledcSetup(m.canal, PWM_FREQ, PWM_BITS);
  ledcAttachPin(m.pwm, m.canal);
#endif
}

void pwmEscribir(const Motor& m, int duty) {
#if defined(ESP_ARDUINO_VERSION_MAJOR) && ESP_ARDUINO_VERSION_MAJOR >= 3
  ledcWrite(m.pwm, duty);
#else
  ledcWrite(m.canal, duty);
#endif
}

// v entre -1 y 1. Con 0 el motor queda libre (IN1 = IN2 = LOW).
void moverMotor(const Motor& m, float v) {
  if (m.invertir) v = -v;
  int duty = (int)lroundf(fabsf(v) * PWM_MAX);
  if (duty == 0) {
    digitalWrite(m.in1, LOW);
    digitalWrite(m.in2, LOW);
    pwmEscribir(m, 0);
    return;
  }
  digitalWrite(m.in1, v > 0 ? HIGH : LOW);
  digitalWrite(m.in2, v > 0 ? LOW : HIGH);
  pwmEscribir(m, duty);
}

// Freno corto: los dos terminales del motor unidos a GND.
void frenarMotor(const Motor& m) {
  digitalWrite(m.in1, HIGH);
  digitalWrite(m.in2, HIGH);
  pwmEscribir(m, PWM_MAX);
}

bool pinValido(int p) {
  if (p < 0 || p > 33) return false;              // 34-39 son solo de entrada
  if (p >= 6 && p <= 11) return false;            // memoria flash
  if (p == 20 || p == 24 || (p >= 28 && p <= 31)) return false;  // no existen
  return true;
}

bool pinesValidos() {
  const int pines[] = { PIN_PWMA, PIN_AIN1, PIN_AIN2, PIN_STBY, PIN_BIN1, PIN_BIN2, PIN_PWMB };
  for (int i = 0; i < 7; i++) {
    if (!pinValido(pines[i])) return false;
    for (int j = i + 1; j < 7; j++) if (pines[i] == pines[j]) return false;
  }
  return true;
}

// ---------- Mando ----------
void alConectar(ControllerPtr ctl) {
  if (mando == nullptr) {
    mando = ctl;
    ultimoPaquete = millis();
    ultimoModo = -1;
    Serial.printf("Mando conectado: %s\n", ctl->getModelName().c_str());
  } else {
    Serial.println("Ya hay un mando conectado; se ignora el segundo.");
    ctl->disconnect();
  }
}

void alDesconectar(ControllerPtr ctl) {
  if (ctl == mando) {
    mando = nullptr;
    Serial.println("Mando desconectado.");
  }
}

// Los 4 LED de jugador indican el modo: 1 = normal, 4 = ataque,
// extremos = parada, centrales = freno. Al armar vibra un instante.
void ledsMando(Modo modo) {
  if (modo == ultimoModo || mando == nullptr) return;
  if (ultimoModo == PARADA && (modo == NORMAL || modo == ATAQUE))
    mando->playDualRumble(0, 120, 0x60, 0x60);
  ultimoModo = modo;
  switch (modo) {
    case PARADA: mando->setPlayerLEDs(0x09); break;
    case FRENO:  mando->setPlayerLEDs(0x06); break;
    case ATAQUE: mando->setPlayerLEDs(0x0F); break;
    default:     mando->setPlayerLEDs(0x01); break;
  }
}

#if SOLO_ESTE_MANDO
void soloEsteMando() {
  unsigned int b[6];
  if (sscanf(MAC_MANDO, "%x:%x:%x:%x:%x:%x", &b[0], &b[1], &b[2], &b[3], &b[4], &b[5]) != 6) {
    Serial.println("MAC_MANDO no tiene el formato XX:XX:XX:XX:XX:XX; se acepta cualquier mando.");
    uni_bt_allowlist_set_enabled(false);
    return;
  }
  bd_addr_t addr;
  for (int i = 0; i < 6; i++) addr[i] = (uint8_t)b[i];
  uni_bt_allowlist_remove_all();
  uni_bt_allowlist_add_addr(addr);
  uni_bt_allowlist_set_enabled(true);
}
#endif

void setup() {
  Serial.begin(115200);
  delay(200);

  if (pinesValidos()) {
    Motor a = { PIN_PWMA, PIN_AIN1, PIN_AIN2, 0, false };
    Motor b = { PIN_PWMB, PIN_BIN1, PIN_BIN2, 1, false };
    motorIzq = MOTOR_IZQ_EN_A ? a : b;
    motorDer = MOTOR_IZQ_EN_A ? b : a;
    motorIzq.invertir = INVERTIR_IZQ;
    motorDer.invertir = INVERTIR_DER;

    pinMode(PIN_STBY, OUTPUT);
    digitalWrite(PIN_STBY, LOW);
    const int salidas[] = { PIN_AIN1, PIN_AIN2, PIN_BIN1, PIN_BIN2 };
    for (int p : salidas) { pinMode(p, OUTPUT); digitalWrite(p, LOW); }
    pwmConfigurar(motorIzq);
    pwmConfigurar(motorDer);
    moverMotor(motorIzq, 0);
    moverMotor(motorDer, 0);
    pinesListos = true;
  } else {
    Serial.println("GPIO del TB6612FNG sin completar, repetidos o no válidos como salida.");
    Serial.println("No se activa ninguna salida. Puedes probar el mando: se imprimirá su estado.");
  }

#if SOLO_ESTE_MANDO
  soloEsteMando();
  Serial.printf("Solo se acepta el mando %s.\n", MAC_MANDO);
#else
  uni_bt_allowlist_set_enabled(false);
#endif
  BP32.setup(&alConectar, &alDesconectar);
  BP32.enableVirtualDevice(false);
  Serial.println("Esperando al mando: mantén pulsado su botón de sincronización.");
}

void loop() {
  uint32_t ahora = millis();
  if (ahora - ultimoPaso < PERIODO_MS) return;
  float dt = limitar((ahora - ultimoPaso) / 1000.0f, 0, 0.05f);
  ultimoPaso = ahora;

  if (BP32.update() && mando && mando->hasData()) ultimoPaquete = ahora;

  Entrada in = { false, 0, 0, 0, 0, 0, false, false };
  in.conectado = mando && mando->isConnected() && (ahora - ultimoPaquete) < SIN_SENAL_MS;
  if (in.conectado) {
    in.lx = limitar(mando->axisX() / 512.0f, -1, 1);
    in.ly = limitar(-mando->axisY() / 512.0f, -1, 1);   // arriba = negativo en Bluepad32
    in.rx = limitar(mando->axisRX() / 512.0f, -1, 1);
    in.zr = mando->throttle() / 1023.0f;
    in.zl = mando->brake() / 1023.0f;
    in.parar = mando->a();      // botón de abajo (B en Switch)
    in.rearmar = mando->y();    // botón de arriba (X en Switch)
  }

  Modo modo = pasoControl(estado, in, dt);
  if (in.conectado) ledsMando(modo); else ultimoModo = -1;

  if (pinesListos) {
    if (modo == DESCONECTADO || modo == PARADA) {
      moverMotor(motorIzq, 0);
      moverMotor(motorDer, 0);
      digitalWrite(PIN_STBY, LOW);
    } else if (modo == FRENO) {
      digitalWrite(PIN_STBY, HIGH);
      frenarMotor(motorIzq);
      frenarMotor(motorDer);
    } else {
      digitalWrite(PIN_STBY, HIGH);
      moverMotor(motorIzq, estado.salIzq);
      moverMotor(motorDer, estado.salDer);
    }
  }

  if ((DEPURAR || !pinesListos) && ahora - ultimaTraza >= 250) {
    ultimaTraza = ahora;
    Serial.printf("%-12s lx=%+.2f ly=%+.2f rx=%+.2f zr=%.2f zl=%.2f  izq=%+.2f der=%+.2f\n",
                  NOMBRE_MODO[modo], in.lx, in.ly, in.rx, in.zr, in.zl, estado.salIzq, estado.salDer);
  }
}
