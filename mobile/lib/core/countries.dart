/// Países seleccionables para "Dónde ver" (ISO 3166-1 alfa-2). La lista es ampliable:
/// incluir un país aquí no implica que existan derechos verificados para él.
const Map<String, String> kCountries = {
  'AR': 'Argentina',
  'BO': 'Bolivia',
  'BR': 'Brasil',
  'CA': 'Canadá',
  'CL': 'Chile',
  'CO': 'Colombia',
  'CR': 'Costa Rica',
  'DE': 'Alemania',
  'DK': 'Dinamarca',
  'EC': 'Ecuador',
  'ES': 'España',
  'FI': 'Finlandia',
  'FR': 'Francia',
  'GB': 'Reino Unido',
  'GT': 'Guatemala',
  'HN': 'Honduras',
  'IT': 'Italia',
  'MX': 'México',
  'NL': 'Países Bajos',
  'NO': 'Noruega',
  'PA': 'Panamá',
  'PE': 'Perú',
  'PT': 'Portugal',
  'PY': 'Paraguay',
  'SE': 'Suecia',
  'SV': 'El Salvador',
  'US': 'Estados Unidos',
  'UY': 'Uruguay',
  'VE': 'Venezuela',
};

/// Bandera como emoji (indicadores regionales Unicode): no requiere imágenes con licencia.
String flagEmoji(String countryCode) {
  final cc = countryCode.toUpperCase();
  if (cc.length != 2 || !RegExp(r'^[A-Z]{2}$').hasMatch(cc)) return '🏳';
  return String.fromCharCodes(cc.codeUnits.map((c) => 0x1F1E6 + c - 0x41));
}

String countryName(String code) => kCountries[code.toUpperCase()] ?? code.toUpperCase();
