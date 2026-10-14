import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/countries.dart';
import '../../core/theme.dart';
import '../../core/time_format.dart';
import '../../data/local_store.dart';
import '../../data/models.dart';
import '../../data/repository.dart';
import '../../services/reminders.dart';
import '../../state/favorites_controller.dart';
import '../../state/settings_controller.dart';
import '../widgets/loader.dart';
import '../widgets/state_views.dart';
import '../widgets/status_chip.dart';
import '../widgets/team_badge.dart';

const kReportUrl = 'https://github.com/gxxrazn21/tv/issues/new';

/// Abre una URL https fuera de OpenFoot. Con [inApp] usa el navegador integrado del sistema
/// (Custom Tabs en Android); si no, la app oficial del proveedor o el navegador.
/// OpenFoot nunca reproduce ni redistribuye la señal por su cuenta.
Future<void> openExternal(BuildContext context, String url, {bool inApp = false}) async {
  final uri = Uri.tryParse(url);
  final messenger = ScaffoldMessenger.of(context);
  if (uri == null || uri.scheme != 'https') {
    messenger.showSnackBar(const SnackBar(content: Text('Enlace no válido')));
    return;
  }
  final ok = await launchUrl(uri, mode: inApp ? LaunchMode.inAppBrowserView : LaunchMode.externalApplication);
  if (!ok) messenger.showSnackBar(const SnackBar(content: Text('No se pudo abrir el enlace')));
}

class MatchScreen extends StatelessWidget {
  const MatchScreen({super.key, required this.matchId, this.initial});

  final int matchId;
  final MatchSummary? initial;

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final repo = context.watch<Repository>();
    final fmt = TimeFormatter(settings.timezone);
    return Scaffold(
      appBar: AppBar(title: Text(initial?.competition.name ?? 'Partido')),
      body: Loader<MatchSummary>(
        formatter: fmt,
        deps: [repo, matchId],
        load: () => repo.match(matchId),
        autoRefresh: (m) => m.phase == MatchPhase.live ? const Duration(seconds: 60) : null,
        builder: (context, m, refresh) => RefreshIndicator(
          onRefresh: refresh,
          child: ListView(
            padding: const EdgeInsets.only(bottom: 32),
            children: [
              _Hero(match: m, formatter: fmt),
              WatchSection(match: m),
              const SizedBox(height: 8),
              _Info(match: m, formatter: fmt),
              if (m.events.isNotEmpty) _Events(match: m),
            ],
          ),
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.match, required this.formatter});

  final MatchSummary match;
  final TimeFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final m = match;
    final favs = context.watch<FavoritesController>();

    Widget team(Team t) {
      final fav = favs.isFavorite('team', '${t.id}');
      return Expanded(
        child: Column(
          children: [
            TeamBadge(t, size: 72),
            const SizedBox(height: 10),
            Text(t.name, textAlign: TextAlign.center, maxLines: 2, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            IconButton(
              tooltip: fav ? 'Quitar ${t.name} de favoritos' : 'Añadir ${t.name} a favoritos',
              icon: Icon(fav ? Icons.star : Icons.star_outline, color: fav ? Colors.amber : null),
              onPressed: () => favs.toggle(Favorite(kind: 'team', id: '${t.id}', label: t.name)),
            ),
          ],
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 8),
      padding: const EdgeInsets.fromLTRB(12, 16, 12, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primaryContainer.withValues(alpha: 0.55), scheme.surfaceContainerHigh],
        ),
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CompetitionLogo(url: m.competition.emblemUrl, name: m.competition.name, size: 20),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  m.competition.name + (m.matchday != null ? ' · Jornada ${m.matchday}' : ''),
                  style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              team(m.home),
              Padding(
                padding: const EdgeInsets.only(top: 14),
                child: Column(
                  children: [
                    Semantics(
                      label: m.hasScore ? 'Resultado ${m.homeScore} a ${m.awayScore}' : 'Hora ${formatter.time(m.utcDate)}',
                      excludeSemantics: true,
                      child: Text(
                        m.hasScore ? '${m.homeScore} - ${m.awayScore}' : formatter.time(m.utcDate),
                        style: text.displaySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          color: m.phase == MatchPhase.live ? AppTheme.live : null,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    StatusChip(m.phase),
                    const SizedBox(height: 6),
                    Text(formatter.date(m.utcDate), style: text.labelSmall),
                  ],
                ),
              ),
              team(m.away),
            ],
          ),
        ],
      ),
    );
  }
}

class _Info extends StatelessWidget {
  const _Info({required this.match, required this.formatter});

  final MatchSummary match;
  final TimeFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final m = match;
    final reminders = context.watch<RemindersController>();
    final settings = context.read<SettingsController>();
    return Column(
      children: [
        const SectionHeader('Información'),
        ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(formatter.full(m.utcDate)),
          subtitle: Text('Zona horaria: ${formatter.location.name}'
              '${m.wasRescheduled ? '\nHorario anterior: ${formatter.full(m.previousUtcDate!)}' : ''}'),
        ),
        if (m.stage != null && m.stage != 'REGULAR_SEASON')
          ListTile(leading: const Icon(Icons.flag_outlined), title: Text(_stageLabel(m.stage!))),
        if (m.venue != null) ListTile(leading: const Icon(Icons.stadium_outlined), title: Text(m.venue!)),
        if (m.phase == MatchPhase.upcoming)
          SwitchListTile(
            secondary: const Icon(Icons.notifications_active_outlined),
            title: const Text('Recordatorio'),
            subtitle: Text('Aviso local ${settings.reminderMinutes} minutos antes'),
            value: reminders.has(m.id),
            onChanged: (_) async {
              final messenger = ScaffoldMessenger.of(context);
              final msg = await reminders.toggle(m, minutesBefore: settings.reminderMinutes);
              messenger.showSnackBar(SnackBar(content: Text(msg)));
            },
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text(
            'Datos: ${m.source} · actualizado ${formatter.full(m.fetchedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

String _stageLabel(String raw) => switch (raw) {
      'LEAGUE_STAGE' => 'Fase de liga',
      'GROUP_STAGE' => 'Fase de grupos',
      'LAST_16' => 'Octavos de final',
      'QUARTER_FINALS' => 'Cuartos de final',
      'SEMI_FINALS' => 'Semifinales',
      'FINAL' => 'Final',
      'PLAYOFFS' => 'Eliminatoria previa',
      _ => raw.replaceAll('_', ' ').toLowerCase(),
    };

class _Events extends StatelessWidget {
  const _Events({required this.match});

  final MatchSummary match;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionHeader('Goles'),
        for (final e in match.events)
          ListTile(
            dense: true,
            leading: Text(e.minute != null ? "${e.minute}'" : '—'),
            title: Text(e.playerName ?? 'Gol'),
            subtitle: Text([
              if (e.teamSide == 'home') match.home.displayName,
              if (e.teamSide == 'away') match.away.displayName,
              if (e.kind == 'penalty_goal') 'penalti',
              if (e.kind == 'own_goal') 'en propia puerta',
            ].join(' · ')),
          ),
      ],
    );
  }
}

String accessLabel(AccessType a) => switch (a) {
      AccessType.free => 'Gratis',
      AccessType.subscription => 'Suscripción',
      AccessType.ppv => 'Pago por evento',
      AccessType.unknown => 'Acceso no especificado',
    };

class AccessBadge extends StatelessWidget {
  const AccessBadge(this.access, {super.key});

  final AccessType access;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (color, icon) = switch (access) {
      AccessType.free => (AppTheme.free, Icons.lock_open),
      AccessType.subscription => (AppTheme.subscription, Icons.lock_outline),
      AccessType.ppv => (AppTheme.ppv, Icons.confirmation_number_outlined),
      AccessType.unknown => (scheme.outline, Icons.help_outline),
    };
    return Chip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(accessLabel(access)),
      side: BorderSide(color: color),
      visualDensity: VisualDensity.compact,
    );
  }
}

/// ¿Conviene abrir las opciones de visionado automáticamente al entrar?
/// Sí si el partido está en directo o empieza en menos de 30 minutos.
bool shouldAutoOpenWatch(MatchSummary m, DateTime nowUtc) {
  if (m.phase == MatchPhase.live) return true;
  if (m.phase != MatchPhase.upcoming) return false;
  final diff = m.utcDate.difference(nowUtc);
  return diff <= const Duration(minutes: 30) && diff >= const Duration(minutes: -5);
}

/// "Dónde ver": botón principal de reproducción y opciones verificadas para el país elegido.
class WatchSection extends StatelessWidget {
  const WatchSection({super.key, required this.match, this.now});

  final MatchSummary match;

  /// Para pruebas: instante actual en UTC.
  final DateTime? now;

  static Future<void> pickCountry(BuildContext context) async {
    final settings = context.read<SettingsController>();
    final picked = await showModalBottomSheet<String>(
      context: context,
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
                selected: e.key == settings.country,
                onTap: () => Navigator.pop(ctx, e.key),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await settings.setCountry(picked);
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsController>();
    final repo = context.watch<Repository>();
    final country = settings.country;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Dónde ver',
          trailing: TextButton.icon(
            onPressed: () => pickCountry(context),
            icon: Text(country != null ? flagEmoji(country) : '🌐'),
            label: Text(country != null ? countryName(country) : 'Elegir país'),
          ),
        ),
        if (country == null)
          Card(
            child: ListTile(
              leading: const Icon(Icons.public),
              title: const Text('Elige tu país para ver dónde se emite'),
              subtitle: const Text('Solo mostramos proveedores oficiales verificados en tu región.'),
              onTap: () => pickCountry(context),
            ),
          )
        else
          _WatchPanel(
            key: ValueKey('$country-${match.id}-${repo.api.baseUrl}'),
            match: match,
            load: () => repo.watch(match.id, country),
            onlyFree: settings.onlyFree,
            now: now,
          ),
      ],
    );
  }
}

class _WatchPanel extends StatefulWidget {
  const _WatchPanel({super.key, required this.match, required this.load, required this.onlyFree, this.now});

  final MatchSummary match;
  final Future<Loaded<WatchInfo>> Function() load;
  final bool onlyFree;
  final DateTime? now;

  @override
  State<_WatchPanel> createState() => _WatchPanelState();
}

class _WatchPanelState extends State<_WatchPanel> {
  late Future<Loaded<WatchInfo>> _future = widget.load();
  bool _showPaid = false;
  bool _autoOpened = false;

  List<WatchOption> _visible(WatchInfo info) =>
      widget.onlyFree && !_showPaid ? info.options.where((o) => o.accessType == AccessType.free).toList() : info.options;

  void _maybeAutoOpen(WatchInfo info) {
    if (_autoOpened) return;
    _autoOpened = true;
    final options = _visible(info);
    if (options.isEmpty || !shouldAutoOpenWatch(widget.match, widget.now ?? DateTime.now().toUtc())) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) showWatchOptions(context, widget.match, options);
    });
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Loaded<WatchInfo>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) return const LoadingView();
        if (snap.hasError) {
          return ErrorView(error: snap.error!, onRetry: () => setState(() => _future = widget.load()));
        }
        final info = snap.data!.data;
        _maybeAutoOpen(info);
        final options = _visible(info);
        final hiddenPaid = info.options.length - options.length;
        final text = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (options.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
                  onPressed: () => showWatchOptions(context, widget.match, options),
                  icon: const Icon(Icons.play_circle_fill, size: 28),
                  label: Text(options.length == 1
                      ? 'Ver ahora en ${options.first.broadcasterName}'
                      : 'Ver ahora · ${options.length} opciones'),
                ),
              ),
            if (options.isEmpty)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.tv_off_outlined),
                  title: Text(hiddenPaid > 0
                      ? 'No hay opciones gratuitas verificadas para esta región'
                      : (info.message ?? 'No se encontró una transmisión oficial verificada para esta región')),
                  subtitle: const Text('No mostramos enlaces que no hayamos podido verificar.'),
                ),
              ),
            if (hiddenPaid > 0)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: TextButton.icon(
                  onPressed: () => setState(() => _showPaid = true),
                  icon: const Icon(Icons.lock_outline),
                  label: Text(hiddenPaid == 1
                      ? 'Hay 1 opción de pago oculta · Mostrar'
                      : 'Hay $hiddenPaid opciones de pago ocultas · Mostrar'),
                ),
              ),
            if (info.directory != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: Text('Directorio oficial de emisoras (${info.directory!.organizer})'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openExternal(context, info.directory!.url),
                ),
              ),
            if (snap.data!.fromCache)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 0),
                child: Text('Sin conexión: datos de visionado guardados anteriormente.'),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Text(info.disclaimer, style: text.bodySmall),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: TextButton.icon(
                onPressed: () => openExternal(context, kReportUrl),
                icon: const Icon(Icons.flag_outlined),
                label: const Text('Informar de un enlace incorrecto'),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Hoja con las opciones de visionado: abrir la app oficial o verlo en el navegador integrado.
Future<void> showWatchOptions(BuildContext context, MatchSummary match, List<WatchOption> options) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(
                '${match.home.displayName} - ${match.away.displayName}',
                style: Theme.of(ctx).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Elige cómo verlo. La reproducción la ofrece cada proveedor oficial.'),
            ),
            for (final o in options) WatchOptionCard(option: o),
          ],
        ),
      ),
    ),
  );
}

class WatchOptionCard extends StatelessWidget {
  const WatchOptionCard({super.key, required this.option});

  final WatchOption option;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: scheme.primaryContainer,
                  child: Text(o.broadcasterName.characters.first, style: TextStyle(color: scheme.onPrimaryContainer)),
                ),
                const SizedBox(width: 12),
                Expanded(child: Text(o.broadcasterName, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
                AccessBadge(o.accessType),
              ],
            ),
            if (o.coverageNote != null) ...[const SizedBox(height: 6), Text(o.coverageNote!, style: text.bodyMedium)],
            if (o.priceNote != null) Text(o.priceNote!, style: text.bodySmall),
            if (o.territorialNotes != null) Text(o.territorialNotes!, style: text.bodySmall),
            const SizedBox(height: 6),
            Text(
              'Verificado el ${o.verifiedAt.toLocal().day}/${o.verifiedAt.toLocal().month}/${o.verifiedAt.toLocal().year}'
              ' · fuente: ${Uri.tryParse(o.sourceUrl)?.host ?? o.sourceUrl}',
              style: text.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () => openExternal(context, o.watchUrl),
                    icon: const Icon(Icons.play_arrow),
                    label: Text('Abrir ${o.broadcasterName}', overflow: TextOverflow.ellipsis),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(minimumSize: const Size(48, 48)),
                  onPressed: () => openExternal(context, o.watchUrl, inApp: true),
                  icon: const Icon(Icons.open_in_browser),
                  label: const Text('Ver aquí'),
                ),
              ],
            ),
            TextButton(onPressed: () => openExternal(context, o.sourceUrl), child: const Text('Ver fuente')),
          ],
        ),
      ),
    );
  }
}
