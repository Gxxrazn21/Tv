import 'package:flutter/material.dart';

import '../../data/models.dart';

/// Monograma del equipo. Los escudos son marcas registradas: solo se muestran si el servidor
/// los sirve expresamente (OPENFOOT_SERVE_CREST_URLS); si no, se usa un monograma propio.
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
    final scheme = Theme.of(context).colorScheme;
    final hue = (team.name.hashCode % 360).abs().toDouble();
    final color = HSLColor.fromAHSL(1, hue, 0.45, Theme.of(context).brightness == Brightness.dark ? 0.35 : 0.55).toColor();
    final monogram = CircleAvatar(
      radius: size / 2,
      backgroundColor: color,
      child: Text(
        _initials,
        style: TextStyle(color: Colors.white, fontSize: size * 0.3, fontWeight: FontWeight.w700),
      ),
    );
    final url = team.crestUrl;
    if (url == null || !url.startsWith('https://')) return ExcludeSemantics(child: monogram);
    return ExcludeSemantics(
      child: SizedBox.square(
        dimension: size,
        child: Image.network(
          url,
          errorBuilder: (_, _, _) => monogram,
          frameBuilder: (_, child, frame, _) => frame == null ? CircleAvatar(radius: size / 2, backgroundColor: scheme.surfaceContainerHighest) : child,
        ),
      ),
    );
  }
}
