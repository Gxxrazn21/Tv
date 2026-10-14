import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/countries.dart';
import '../../data/models.dart';
import '../../data/repository.dart';

class MatchFilters {
  const MatchFilters({this.competition, this.country});

  final String? competition;
  final String? country;

  MatchFilters copyWith({String? competition, String? country, bool clearCompetition = false, bool clearCountry = false}) =>
      MatchFilters(
        competition: clearCompetition ? null : competition ?? this.competition,
        country: clearCountry ? null : country ?? this.country,
      );
}

/// Filtros por competición y país (la fecha la gestiona cada pantalla).
class FilterBar extends StatefulWidget {
  const FilterBar({super.key, required this.filters, required this.onChanged});

  final MatchFilters filters;
  final ValueChanged<MatchFilters> onChanged;

  @override
  State<FilterBar> createState() => _FilterBarState();
}

class _FilterBarState extends State<FilterBar> {
  List<Competition> _competitions = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    context.read<Repository>().competitions().then((r) {
      if (mounted) setState(() => _competitions = r.data.where((c) => c.hasData).toList());
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final f = widget.filters;
    final countries = {
      for (final c in _competitions)
        if (c.areaCode != null) c.areaCode!: c.areaName,
    };
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(
        children: [
          _Dropdown(
            label: 'Competición',
            value: f.competition,
            items: {for (final c in _competitions) c.code: c.name},
            onChanged: (v) => widget.onChanged(v == null ? f.copyWith(clearCompetition: true) : f.copyWith(competition: v)),
          ),
          const SizedBox(width: 8),
          _Dropdown(
            label: 'País',
            value: f.country,
            items: {for (final e in countries.entries) e.key: '${flagEmoji(e.key)} ${e.value}'},
            onChanged: (v) => widget.onChanged(v == null ? f.copyWith(clearCountry: true) : f.copyWith(country: v)),
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({required this.label, required this.value, required this.items, required this.onChanged});

  final String label;
  final String? value;
  final Map<String, String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final selected = value != null ? items[value] ?? value! : null;
    return InputChip(
      label: Text(selected ?? label),
      selected: value != null,
      avatar: const Icon(Icons.filter_list, size: 18),
      onDeleted: value != null ? () => onChanged(null) : null,
      deleteButtonTooltipMessage: 'Quitar filtro',
      onPressed: () async {
        final picked = await showModalBottomSheet<String>(
          context: context,
          showDragHandle: true,
          builder: (ctx) => SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                ListTile(title: Text(label, style: Theme.of(ctx).textTheme.titleMedium)),
                for (final e in items.entries)
                  ListTile(
                    title: Text(e.value),
                    selected: e.key == value,
                    onTap: () => Navigator.pop(ctx, e.key),
                  ),
              ],
            ),
          ),
        );
        if (picked != null) onChanged(picked);
      },
    );
  }
}
