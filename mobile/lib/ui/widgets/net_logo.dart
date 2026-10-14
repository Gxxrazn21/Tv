import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Imagen remota (PNG o SVG) con un respaldo propio si no hay URL o falla la descarga.
/// Solo se cargan URL https; los logos son decorativos y se excluyen de los lectores de pantalla.
class NetLogo extends StatelessWidget {
  const NetLogo({super.key, required this.url, required this.size, required this.fallback});

  final String? url;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final u = url;
    if (u == null || !u.startsWith('https://')) return SizedBox.square(dimension: size, child: fallback);
    final isSvg = Uri.tryParse(u)?.path.toLowerCase().endsWith('.svg') ?? false;
    final Widget image = isSvg
        ? SvgPicture.network(
            u,
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            placeholderBuilder: (_) => SizedBox.square(dimension: size),
            errorBuilder: (_, _, _) => fallback,
          )
        : Image.network(
            u,
            width: size,
            height: size,
            fit: BoxFit.contain,
            excludeFromSemantics: true,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, _, _) => fallback,
            frameBuilder: (_, child, frame, sync) =>
                sync || frame != null ? child : SizedBox.square(dimension: size),
          );
    return SizedBox.square(dimension: size, child: ExcludeSemantics(child: image));
  }
}
