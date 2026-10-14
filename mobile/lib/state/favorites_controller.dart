import 'package:flutter/foundation.dart';

import '../data/local_store.dart';

class FavoritesController extends ChangeNotifier {
  FavoritesController(this._store);

  final LocalStore _store;
  List<Favorite> _items = const [];

  List<Favorite> get items => _items;
  List<Favorite> get teams => _items.where((f) => f.kind == 'team').toList();
  List<Favorite> get competitions => _items.where((f) => f.kind == 'competition').toList();

  Future<void> load() async {
    _items = await _store.favorites();
    notifyListeners();
  }

  bool isFavorite(String kind, String id) => _items.any((f) => f.kind == kind && f.id == id);

  Future<void> toggle(Favorite f) async {
    if (isFavorite(f.kind, f.id)) {
      await _store.removeFavorite(f.kind, f.id);
    } else {
      await _store.addFavorite(f);
    }
    await load();
  }
}
