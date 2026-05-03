import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/retailer_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/retailers_repository.dart';

/// Paginated list of retailers with optional search filter.
final retailersProvider =
    StateNotifierProvider.autoDispose<RetailersNotifier, AsyncValue<PaginatedResult<RetailerModel>>>(
  (ref) => RetailersNotifier(ref.read(retailersRepositoryProvider)),
);

class RetailersNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<RetailerModel>>> {
  RetailersNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final RetailersRepository _repo;
  String? _cursor;
  String _search = '';
  final List<RetailerModel> _items = [];

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
      state = AsyncValue.data(
        PaginatedResult(items: List.unmodifiable(_items), hasMore: result.hasMore),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> search(String query) async {
    _search = query;
    await load(refresh: true);
  }

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
