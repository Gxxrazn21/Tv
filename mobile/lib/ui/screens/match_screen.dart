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

/// Abre una URL https en una aplicación externa (navegador o app del proveedor).
/// OpenFoot nunca reproduce la señal dentro de la app.
Future<void> openExternal(BuildContext context, String url) async {
  final uri = Uri.tryParse(url);
  final messenger = ScaffoldMessenger.of(context);
  if (uri == null || uri.scheme != 'https') {
    messenger.showSnackBar(const SnackBar(content: Text('Enlace no válido')));
    return;
  }
  final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
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
              _Header(match: m, formatter: fmt),
              _Info(match: m, formatter: fmt),
              if (m.events.isNotEmpty) _Events(match: m),
              const Divider(height: 32),
              WatchSection(match: m),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.match, required this.formatter});

  final MatchSummary match;
  final TimeFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final m = match;
    final favs = context.watch<FavoritesController>();
    Widget team(Team t) {
      final fav = favs.isFavorite('team', '${t.id}');
      return Expanded(
        child: Column(
          children: [
            TeamBadge(t, size: 56),
            const SizedBox(height: 8),
            Text(t.name, textAlign: TextAlign.center, style: text.titleSmall),
            IconButton(
              tooltip: fav ? 'Quitar ${t.name} de favoritos' : 'Añadir ${t.name} a favoritos',
              icon: Icon(fav ? Icons.star : Icons.star_outline),
              onPressed: () => favs.toggle(Favorite(kind: 'team', id: '${t.id}', label: t.name)),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          StatusChip(m.phase),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              team(m.home),
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Semantics(
                  label: m.hasScore ? 'Resultado ${m.homeScore} a ${m.awayScore}' : 'Hora ${formatter.time(m.utcDate)}',
                  excludeSemantics: true,
                  child: Text(
                    m.hasScore ? '${m.homeScore} - ${m.awayScore}' : formatter.time(m.utcDate),
                    style: text.displaySmall?.copyWith(fontWeight: FontWeight.w800),
                  ),
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
        ListTile(
          leading: const Icon(Icons.schedule),
          title: Text(formatter.full(m.utcDate)),
          subtitle: Text('Zona horaria: ${formatter.location.name}'
              '${m.wasRescheduled ? '\nHorario anterior: ${formatter.full(m.previousUtcDate!)}' : ''}'),
        ),
        ListTile(
          leading: const Icon(Icons.emoji_events_outlined),
          title: Text(m.competition.name),
          subtitle: Text([
            if (m.matchday != null) 'Jornada ${m.matchday}',
            if (m.stage != null && m.stage != 'REGULAR_SEASON') m.stage!,
          ].join(' · ').ifEmpty(m.competition.areaName)),
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Datos: ${m.source} · actualizado ${formatter.full(m.fetchedAt)}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      ],
    );
  }
}

extension on String {
  String ifEmpty(String other) => isEmpty ? other : this;
}

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

/// "Dónde ver": solo proveedores verificados para el país elegido.
class WatchSection extends StatelessWidget {
  const WatchSection({super.key, required this.match});

  final MatchSummary match;

  Future<void> _pickCountry(BuildContext context) async {
    final settings = context.read<SettingsController>();
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
    final fmt = TimeFormatter(settings.timezone);
    final country = settings.country;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          'Dónde ver',
          trailing: TextButton.icon(
            onPressed: () => _pickCountry(context),
            icon: Text(country != null ? flagEmoji(country) : '🌐'),
            label: Text(country != null ? countryName(country) : 'Elegir país'),
          ),
        ),
        if (country == null)
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('Elige tu país para ver los proveedores oficiales verificados en tu región.'),
          )
        else
          _WatchContent(
            key: ValueKey('$country-${match.id}-${repo.api.baseUrl}'),
            load: () => repo.watch(match.id, country),
            formatter: fmt,
          ),
      ],
    );
  }
}

class _WatchContent extends StatefulWidget {
  const _WatchContent({super.key, required this.load, required this.formatter});

  final Future<Loaded<WatchInfo>> Function() load;
  final TimeFormatter formatter;

  @override
  State<_WatchContent> createState() => _WatchContentState();
}

class _WatchContentState extends State<_WatchContent> {
  late Future<Loaded<WatchInfo>> _future = widget.load();

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
        final fmt = widget.formatter;
        final text = Theme.of(context).textTheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (snap.data!.fromCache) CacheBanner(cachedAt: snap.data!.cachedAt!, formatter: fmt),
            for (final o in info.options) _OptionCard(option: o, formatter: fmt),
            if (info.message != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.search_off),
                  title: Text(info.message!),
                  subtitle: const Text('No mostramos enlaces que no hayamos podido verificar.'),
                ),
              ),
            if (info.directory != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.list_alt),
                  title: Text('Directorio oficial de emisoras (${info.directory!.organizer})'),
                  subtitle: Text('Verificado el ${fmt.date(info.directory!.verifiedAt)}'),
                  trailing: const Icon(Icons.open_in_new),
                  onTap: () => openExternal(context, info.directory!.url),
                ),
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

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option, required this.formatter});

  final WatchOption option;
  final TimeFormatter formatter;

  @override
  Widget build(BuildContext context) {
    final o = option;
    final text = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(o.broadcasterName, style: text.titleMedium)),
                AccessBadge(o.accessType),
              ],
            ),
            if (o.priceNote != null) Text(o.priceNote!, style: text.bodyMedium),
            if (o.coverageNote != null) Text(o.coverageNote!, style: text.bodySmall),
            if (o.territorialNotes != null) Text(o.territorialNotes!, style: text.bodySmall),
            const SizedBox(height: 6),
            Text(
              'Verificado el ${formatter.date(o.verifiedAt)} · fuente: ${Uri.tryParse(o.sourceUrl)?.host ?? o.sourceUrl}'
              '${o.lastCheck != null ? ' · enlace comprobado el ${formatter.date(o.lastCheck!.checkedAt)}' : ''}',
              style: text.labelSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: () => openExternal(context, o.watchUrl),
                  icon: const Icon(Icons.open_in_new),
                  label: Text('Abrir ${o.broadcasterName}'),
                ),
                TextButton(onPressed: () => openExternal(context, o.sourceUrl), child: const Text('Ver fuente')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
