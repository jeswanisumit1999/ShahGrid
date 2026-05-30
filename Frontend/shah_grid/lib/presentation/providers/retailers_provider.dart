import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/retailer_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/retailers_repository.dart';

/// Paginated list of retailers with optional search filter.
final retailersProvider =
    StateNotifierProvider.autoDispose<RetailersNotifier, AsyncValue<PaginatedResult<RetailerModel>>>(
  (ref) => RetailersNotifier(ref.read(retailersRepositoryProvider)),
);

enum RetailerSort { nameAsc, nameDesc, pendingDesc, pendingAsc }

class RetailersNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<RetailerModel>>> {
  RetailersNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final RetailersRepository _repo;
  String? _cursor;
  String _search = '';
  RetailerSort _sort = RetailerSort.nameAsc;
  final List<RetailerModel> _items = [];

  void _emit() {
    final sorted = [..._items];
    switch (_sort) {
      case RetailerSort.nameAsc:
        sorted.sort((a, b) => a.name.compareTo(b.name));
      case RetailerSort.nameDesc:
        sorted.sort((a, b) => b.name.compareTo(a.name));
      case RetailerSort.pendingDesc:
        sorted.sort((a, b) => b.pendingCollection.compareTo(a.pendingCollection));
      case RetailerSort.pendingAsc:
        sorted.sort((a, b) => a.pendingCollection.compareTo(b.pendingCollection));
    }
    state = AsyncValue.data(
      PaginatedResult(items: List.unmodifiable(sorted), hasMore: _cursor != null),
    );
  }

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final result = await _repo.list(cursor: _cursor, search: _search);
      _items.addAll(result.items);
      _cursor = result.nextCursor;
      _emit();
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> search(String query) async {
    _search = query;
    await load(refresh: true);
  }

  void sortBy(RetailerSort sort) {
    _sort = sort;
    if (state.hasValue) _emit();
  }

  RetailerSort get currentSort => _sort;

  Future<void> loadMore() async {
    if (!(state.valueOrNull?.hasMore ?? false)) return;
    await load();
  }
}

/// Single retailer detail.
final retailerDetailProvider =
    FutureProvider.autoDispose.family<RetailerModel, String>((ref, id) {
  return ref.read(retailersRepositoryProvider).getById(id);
});
