# Compilar el APK de Android

## Opción A · GitHub Actions (recomendada, sin instalar nada)
Cada push ejecuta `.github/workflows/ci.yml`, que compila
`mobile/build/app/outputs/flutter-apk/app-release.apk` y lo publica como artefacto **openfoot-apk**
en la pestaña *Actions* del repositorio.

- Para que el APK apunte a tu servidor, define la variable de repositorio `OPENFOOT_API_URL`
  (*Settings → Secrets and variables → Actions → Variables*), por ejemplo `https://openfoot.tu-dominio.org`.
  Sin ella, el APK usa el despliegue de Vercel del proyecto (`https://tv-backend-five.vercel.app`).
  En cualquier caso, la URL se puede cambiar en la app desde Ajustes → Servidor.
- El APK de la CI va firmado con la **clave de depuración**: sirve para instalarlo y probarlo, no
  para publicarlo en una tienda.

## Opción B · En tu equipo
Requisitos: Flutter 3.47.x (canal estable), JDK 17 y el Android SDK (Android Studio o
*command-line tools*).

```bash
cd mobile
flutter pub get
flutter analyze && flutter test
flutter build apk --release --dart-define=OPENFOOT_API_URL=https://openfoot.tu-dominio.org
# Resultado: build/app/outputs/flutter-apk/app-release.apk
```

Para instalarlo en un dispositivo con la depuración USB activada:
`flutter install` o `adb install build/app/outputs/flutter-apk/app-release.apk`.

## Firma para publicación
1. Crea una clave (guárdala fuera del repositorio):
   `keytool -genkey -v -keystore ~/openfoot-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias openfoot`
2. Crea `mobile/android/key.properties`, que git ignora:
   ```properties
   storeFile=/ruta/absoluta/openfoot-release.jks
   storePassword=…
   keyAlias=openfoot
   keyPassword=…
   ```
3. `flutter build apk --release` (o `flutter build appbundle` para Google Play) firmará con esa clave.
   Si `key.properties` no existe, se usa la clave de depuración.

## Probar con el backend local
```bash
# Terminal 1: backend
cd backend && python -m venv .venv && . .venv/bin/activate && pip install -e ".[dev]"
openfoot init-db && openfoot load-catalog data/catalog.yaml
uvicorn --factory openfoot.main:app_factory --host 0.0.0.0 --port 8000
# Terminal 2: app en el emulador (10.0.2.2 es el equipo anfitrión visto desde el emulador)
cd mobile && flutter run --dart-define=OPENFOOT_API_URL=http://10.0.2.2:8000
```
En un móvil físico, usa la IP del equipo en la red local **con https** (por ejemplo, con un proxy
inverso). La app solo admite http para localhost y el emulador.

## iOS
El proyecto incluye la plataforma iOS (`mobile/ios`), pero **no se ha compilado ni probado**: hace
falta macOS con Xcode y una cuenta de desarrollador de Apple para firmar.
