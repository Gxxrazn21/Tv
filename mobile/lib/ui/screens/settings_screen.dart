import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:timezone/timezone.dart' as tz;

import '../../core/countries.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../state/settings_controller.dart';
import '../widgets/state_views.dart';
import 'match_screen.dart' show openExternal;

const kPrivacyUrl = 'https://github.com/gxxrazn21/tv/blob/main/docs/privacidad.md';
const kSourceUrl = 'https://github.com/gxxrazn21/tv';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  static const _sectionNames = {
    'live': 'En directo',
    'upcoming': 'Próximos',
    'finished': 'Finalizados',
    'favorites': 'Tus favoritos',
    'featured': 'Competiciones destacadas',
  };

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsController>();
    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          const SectionHeader('Apariencia'),
          RadioGroup<ThemeMode>(
            groupValue: s.themeMode,
            onChanged: (v) => s.setThemeMode(v!),
            child: const Column(children: [
              RadioListTile(value: ThemeMode.dark, title: Text('Oscuro')),
              RadioListTile(value: ThemeMode.light, title: Text('Claro')),
              RadioListTile(value: ThemeMode.system, title: Text('Según el sistema')),
            ]),
          ),
          const SectionHeader('Región y hora'),
          ListTile(
            leading: const Icon(Icons.schedule),
            title: const Text('Zona horaria'),
            subtitle: Text(s.timezoneOverride ?? 'Automática (${s.deviceTimezone})'),
            onTap: () => _pickTimezone(context, s),
          ),
          ListTile(
            leading: Text(s.country != null ? flagEmoji(s.country!) : '🌐', style: const TextStyle(fontSize: 22)),
            title: const Text('País para "Dónde ver"'),
            subtitle: Text(s.country != null ? countryName(s.country!) : 'Sin elegir'),
            onTap: () => _pickCountry(context, s),
          ),
          const SectionHeader('Pantalla de inicio'),
          for (final e in _sectionNames.entries)
            SwitchListTile(
              title: Text(e.value),
              value: s.sectionVisible(e.key),
              onChanged: (v) => s.setSectionVisible(e.key, v),
            ),
          const SectionHeader('Recordatorios'),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Avisar antes del inicio'),
            trailing: DropdownButton<int>(
              value: s.reminderMinutes,
              items: const [5, 15, 30, 60].map((m) => DropdownMenuItem(value: m, child: Text('$m min'))).toList(),
              onChanged: (v) => s.setReminderMinutes(v!),
            ),
          ),
          const SectionHeader('Servidor'),
          ListTile(
            leading: const Icon(Icons.dns_outlined),
            title: const Text('Servidor de OpenFoot'),
            subtitle: Text(s.apiUrl),
            onTap: () => _editServer(context, s),
          ),
          ListTile(
            leading: const Icon(Icons.delete_sweep_outlined),
            title: const Text('Borrar datos guardados sin conexión'),
            onTap: () async {
              final messenger = ScaffoldMessenger.of(context);
              await context.read<Repository>().store.clearCache();
              messenger.showSnackBar(const SnackBar(content: Text('Caché borrada')));
            },
          ),
          const SectionHeader('Privacidad y fuentes'),
          const ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Privacidad'),
            subtitle: Text(
              'Sin cuentas, anuncios ni rastreadores. Favoritos, preferencias y recordatorios se guardan '
              'solo en este dispositivo. La app consulta únicamente el servidor configurado arriba, que '
              'recibe tu dirección IP y las consultas (fechas, competición, país elegido). Al abrir un '
              'proveedor, sales a su web o app y se aplica su propia política.',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.description_outlined),
            title: const Text('Política de privacidad completa'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openExternal(context, kPrivacyUrl),
          ),
          const _SourcesTile(),
          ListTile(
            leading: const Icon(Icons.code),
            title: const Text('Código fuente (Apache-2.0)'),
            subtitle: const Text('La licencia del código no concede derechos sobre partidos, emisiones, escudos ni datos de terceros.'),
            trailing: const Icon(Icons.open_in_new),
            onTap: () => openExternal(context, kSourceUrl),
          ),
          ListTile(
            leading: const Icon(Icons.gavel_outlined),
            title: const Text('Licencias de terceros'),
            onTap: () => showLicensePage(context: context, applicationName: 'OpenFoot'),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<void> _pickCountry(BuildContext context, SettingsController s) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            for (final e in kCountries.entries)
              ListTile(
                leading: Text(flagEmoji(e.key), style: const TextStyle(fontSize: 22)),
                title: Text(e.value),
                selected: e.key == s.country,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await s.setCountry(picked);
  }

  Future<void> _pickTimezone(BuildContext context, SettingsController s) async {
    final zones = tz.timeZoneDatabase.locations.keys.where((z) => z.contains('/')).toList()..sort();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _TimezonePicker(zones: zones),
    );
    if (picked == null) return;
    await s.setTimezone(picked == 'auto' ? null : picked);
  }

  Future<void> _editServer(BuildContext context, SettingsController s) async {
    final controller = TextEditingController(text: s.apiUrl);
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('Servidor de OpenFoot'),
          content: TextField(
            controller: controller,
            keyboardType: TextInputType.url,
            decoration: InputDecoration(errorText: error, helperText: 'Usa tu propio servidor (autoalojado).'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            TextButton(onPressed: () => Navigator.pop(ctx, s.defaultApiUrl), child: const Text('Restablecer')),
            FilledButton(
              onPressed: () {
                final e = SettingsController.validateApiUrl(controller.text);
                if (e != null) {
                  setState(() => error = e);
                } else {
                  Navigator.pop(ctx, controller.text.trim());
                }
              },
              child: const Text('Guardar'),
            ),
          ],
        ),
      ),
    );
    if (result != null) await s.setApiUrl(result);
  }
}

class _TimezonePicker extends StatefulWidget {
  const _TimezonePicker({required this.zones});

  final List<String> zones;

  @override
  State<_TimezonePicker> createState() => _TimezonePickerState();
}

class _TimezonePickerState extends State<_TimezonePicker> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final filtered = widget.zones.where((z) => z.toLowerCase().contains(_q.toLowerCase())).toList();
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.8,
      builder: (_, controller) => Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar (p. ej. Madrid, Buenos_Aires)'),
              onChanged: (v) => setState(() => _q = v),
            ),
          ),
          Expanded(
            child: ListView.builder(
              controller: controller,
              itemCount: filtered.length + 1,
              itemBuilder: (_, i) => i == 0
                  ? ListTile(title: const Text('Automática (la del dispositivo)'), onTap: () => Navigator.pop(context, 'auto'))
                  : ListTile(title: Text(filtered[i - 1]), onTap: () => Navigator.pop(context, filtered[i - 1])),
            ),
          ),
        ],
      ),
    );
  }
}

class _SourcesTile extends StatefulWidget {
  const _SourcesTile();

  @override
  State<_SourcesTile> createState() => _SourcesTileState();
}

class _SourcesTileState extends State<_SourcesTile> {
  late final Future<List<SourceStatus>> _future = context.read<Repository>().sources();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SourceStatus>>(
      future: _future,
      builder: (context, snap) {
        final sources = snap.data ?? const [];
        return ListTile(
          leading: const Icon(Icons.dataset_outlined),
          title: const Text('Fuentes de datos y atribuciones'),
          subtitle: Text(
            snap.hasError
                ? 'No disponible sin conexión con el servidor.'
                : sources.isEmpty
                    ? 'Cargando…'
                    : sources
                        .map((s) => '${s.attribution}${s.configured ? '' : ' (no configurada en este servidor)'}')
                        .join('\n'),
          ),
        );
      },
    );
  }
}
