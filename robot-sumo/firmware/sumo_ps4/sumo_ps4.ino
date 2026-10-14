/*
  Robot de mini-sumo RC: ESP32-WROOM-32 + DualShock 4 + TB6612FNG
  PCB CUyLAB V3.1 · LiPo 2S 500 mAh · 2 motores N20 6 V 500 RPM

  Generado por el Simulador Sumo ESP32. La función pasoControl() es la
  misma que mueve el robot del simulador: con los mismos ajustes, el
  robot real responde igual al mando.

  Preparación
   1. Arduino IDE > Gestor de placas > "esp32" de Espressif, versión 2.0.17
      (la librería PS4Controller no funciona con el núcleo 3.x).
   2. Librería "PS4Controller" (github.com/aed3/PS4-esp32).
   3. Placa "ESP32 Dev Module". Monitor serie a 115200 baudios.
   4. El mando solo se conecta a la MAC maestra que tiene guardada.
      Léela o cámbiala con SixaxisPairTool (mando por USB al PC) y
      escríbela en PS4_MAC.
   5. Completa los 7 GPIO. Si alguno vale -1 o no sirve como salida,
      el programa no activa ninguna salida y lo avisa por el monitor serie.

  Controles
   Stick izquierdo vertical    avance y retroceso
   Stick izquierdo horizontal  giro diferencial
   R2 (analógico)              ataque: sube el límite de potencia
   L2                          freno corto (IN1 = IN2 = HIGH)
   X                           parada inmediata (STBY = LOW)
   Triángulo u OPTIONS         rearmar, con el stick centrado y R2 suelto
   El robot arranca en parada y vuelve a ella si se pierde el mando.
*/

#include <PS4Controller.h>

// ---------- Mando ----------
const char* PS4_MAC = "01:02:03:04:05:06";

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
const float LIMITE_NORMAL = 0.7f;  // fracción de PWM sin R2
const float LIMITE_ATAQUE = 0.85f;  // fracción de PWM con R2 a fondo
const float RAMPA         = 6.0f;  // cambio máximo de PWM por segundo (1 = 100 %)
const float GANANCIA_GIRO = 0.75f;
const float EXPO          = 0.4f;  // 0 = lineal; cerca de 1 = muy suave en el centro
const float ZONA_MUERTA   = 0.08f;
const float UMBRAL_FRENO  = 0.2f;  // recorrido de L2 que activa el freno

const uint32_t PERIODO_MS    = 10;     // bucle de control a 100 Hz
const uint32_t SIN_SENAL_MS  = 300;    // sin paquetes del mando durante este tiempo = parada
const uint32_t PWM_FREQ      = 20000;  // 20 kHz, fuera del rango audible
const uint8_t  PWM_BITS      = 8;
const int      PWM_MAX       = (1 << PWM_BITS) - 1;
const bool     DEPURAR       = false;  // true: imprime el estado cada 250 ms

// ---------- Tipos y estado ----------
enum Modo { DESCONECTADO, PARADA, FRENO, NORMAL, ATAQUE };
const char* NOMBRE_MODO[] = { "desconectado", "parada", "freno", "normal", "ataque" };

struct Entrada { bool conectado; float lx, ly, r2, l2; bool cruz, rearmar; };
struct Estado  { bool parada; float salIzq, salDer; };
struct Motor   { int pwm, in1, in2, canal; bool invertir; };

Estado estado = { true, 0, 0 };
Motor motorIzq, motorDer;
bool pinesListos = false;
uint32_t ultimoPaso = 0, ultimaTraza = 0;
volatile uint32_t ultimoPaquete = 0;
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
  if (in.cruz) st.parada = true;
  bool centrado = zonaMuerta(in.lx) == 0 && zonaMuerta(in.ly) == 0 && in.r2 < 0.1f;
  if (st.parada && in.rearmar && centrado) st.parada = false;
  if (st.parada) { st.salIzq = st.salDer = 0; return PARADA; }
  if (in.l2 > UMBRAL_FRENO) { st.salIzq = st.salDer = 0; return FRENO; }

  float avance = curvaExpo(zonaMuerta(in.ly));
  float giro = curvaExpo(zonaMuerta(in.lx)) * GANANCIA_GIRO;
  float izq = avance + giro;
  float der = avance - giro;
  float m = fmaxf(fabsf(izq), fabsf(der));
  if (m > 1) { izq /= m; der /= m; }

  float limite = LIMITE_NORMAL + (LIMITE_ATAQUE - LIMITE_NORMAL) * in.r2;
  float paso = RAMPA * dt;
  st.salIzq = rampa(st.salIzq, izq * limite, paso);
  st.salDer = rampa(st.salDer, der * limite, paso);
  return in.r2 > 0.1f ? ATAQUE : NORMAL;
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
void alRecibirPaquete() { ultimoPaquete = millis(); }

void colorMando(Modo modo) {
  if (modo == ultimoModo) return;
  ultimoModo = modo;
  switch (modo) {
    case PARADA: PS4.setLed(255, 0, 0); break;
    case FRENO:  PS4.setLed(255, 255, 255); break;
    case ATAQUE: PS4.setLed(255, 80, 0); break;
    default:     PS4.setLed(0, 60, 255); break;
  }
  PS4.sendToController();
}

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

  PS4.attach(alRecibirPaquete);
  PS4.begin(PS4_MAC);
  Serial.printf("Esperando al DualShock 4 (MAC %s). Pulsa PS en el mando.\n", PS4_MAC);
}

void loop() {
  uint32_t ahora = millis();
  if (ahora - ultimoPaso < PERIODO_MS) return;
  float dt = limitar((ahora - ultimoPaso) / 1000.0f, 0, 0.05f);
  ultimoPaso = ahora;

  Entrada in = { false, 0, 0, 0, 0, false, false };
  in.conectado = PS4.isConnected() && (ahora - ultimoPaquete) < SIN_SENAL_MS;
  if (in.conectado) {
    in.lx = limitar(PS4.LStickX() / 127.0f, -1, 1);
    in.ly = limitar(PS4.LStickY() / 127.0f, -1, 1);
    in.r2 = PS4.R2Value() / 255.0f;
    in.l2 = PS4.L2Value() / 255.0f;
    in.cruz = PS4.Cross();
    in.rearmar = PS4.Triangle() || PS4.Options();
  }

  Modo modo = pasoControl(estado, in, dt);
  if (in.conectado) colorMando(modo); else ultimoModo = -1;

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
    Serial.printf("%-12s lx=%+.2f ly=%+.2f r2=%.2f l2=%.2f  izq=%+.2f der=%+.2f\n",
                  NOMBRE_MODO[modo], in.lx, in.ly, in.r2, in.l2, estado.salIzq, estado.salDer);
  }
}
