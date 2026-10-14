import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/time_format.dart';
import '../../data/models.dart';
import 'state_views.dart';

/// Carga datos con estados de carga, error y caché. `deps` decide cuándo volver a cargar.
class Loader<T> extends StatefulWidget {
  const Loader({
    super.key,
    required this.load,
    required this.deps,
    required this.builder,
    required this.formatter,
    this.autoRefresh,
  });

  final Future<Loaded<T>> Function() load;
  final List<Object?> deps;
  final Widget Function(BuildContext context, T data, Future<void> Function() refresh) builder;
  final TimeFormatter formatter;

  /// Si devuelve un intervalo para los datos actuales, se recarga periódicamente (p. ej. en directo).
  final Duration? Function(T data)? autoRefresh;

  @override
  State<Loader<T>> createState() => _LoaderState<T>();
}

class _LoaderState<T> extends State<Loader<T>> {
  Loaded<T>? _data;
  Object? _error;
  bool _loading = true;
  int _generation = 0;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  @override
  void didUpdateWidget(covariant Loader<T> old) {
    super.didUpdateWidget(old);
    if (!_sameDeps(old.deps, widget.deps)) {
      setState(() {
        _data = null;
        _loading = true;
      });
      _fetch();
    }
  }

  bool _sameDeps(List<Object?> a, List<Object?> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Future<void> _fetch() async {
    final gen = ++_generation;
    try {
      final result = await widget.load();
      if (!mounted || gen != _generation) return;
      setState(() {
        _data = result;
        _error = null;
        _loading = false;
      });
      final every = widget.autoRefresh?.call(result.data);
      _timer?.cancel();
      if (every != null) {
        _timer = Timer(every, () {
          if (mounted && gen == _generation) _fetch();
        });
      }
    } catch (e) {
      if (!mounted || gen != _generation) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _data == null) return const LoadingView();
    if (_data == null) return ErrorView(error: _error ?? 'Error desconocido', onRetry: _fetch);
    final data = _data!;
    return Column(
      children: [
        if (data.fromCache) CacheBanner(cachedAt: data.cachedAt!, formatter: widget.formatter),
        Expanded(child: widget.builder(context, data.data, _fetch)),
      ],
    );
  }
}
