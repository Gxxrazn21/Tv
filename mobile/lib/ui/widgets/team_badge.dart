import 'package:flutter/material.dart';

import '../../data/models.dart';
import 'net_logo.dart';

/// Escudo del equipo; si el servidor no lo sirve o falla, un monograma propio.
class TeamBadge extends StatelessWidget {
  const TeamBadge(this.team, {super.key, this.size = 32});

  final Team team;
  final double size;

  String get _initials {
    if (team.tla != null && team.tla!.isNotEmpty) return team.tla!;
    final words = team.name.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    return words.take(3).map((w) => w[0]).join().toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final hue = (team.name.hashCode % 360).abs().toDouble();
    final dark = Theme.of(context).brightness == Brightness.dark;
    final color = HSLColor.fromAHSL(1, hue, 0.45, dark ? 0.35 : 0.5).toColor();
    final monogram = CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(
        _initials,
        style: TextStyle(color: Colors.white, fontSize: size * 0.3, fontWeight: FontWeight.w700),
      ),
    );
    return NetLogo(url: team.crestUrl, size: size, fallback: ExcludeSemantics(child: monogram));
  }
}

/// Logo de la competición; si no hay, un trofeo con las iniciales.
class CompetitionLogo extends StatelessWidget {
  const CompetitionLogo({super.key, required this.url, required this.name, this.size = 22});

  final String? url;
  final String name;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return NetLogo(
      url: url,
      size: size,
      fallback: Icon(Icons.emoji_events, size: size * 0.9, color: scheme.primary),
    );
  }
}
