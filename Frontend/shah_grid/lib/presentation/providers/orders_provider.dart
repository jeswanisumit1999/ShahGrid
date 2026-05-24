import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/order_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/orders_repository.dart';

final ordersProvider =
    StateNotifierProvider.autoDispose<OrdersNotifier, AsyncValue<PaginatedResult<OrderModel>>>(
  (ref) => OrdersNotifier(ref.read(ordersRepositoryProvider)),
);

class OrdersNotifier extends StateNotifier<AsyncValue<PaginatedResult<OrderModel>>> {
  OrdersNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final OrdersRepository _repo;
  String? _cursor;
  String? _salesOfficerId;
  String? _search;
  final List<OrderModel> _items = [];

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final result = await _repo.list(
        cursor: _cursor,
        salesOfficerId: _salesOfficerId,
        search: _search,
      );
      _items.addAll(result.items);
      _cursor = result.nextCursor;
      state = AsyncValue.data(
        PaginatedResult(items: List.unmodifiable(_items), hasMore: result.hasMore),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> loadMore() async {
    if (!(state.valueOrNull?.hasMore ?? false)) return;
    await load();
  }

  Future<void> filterBySalesOfficer(String? salesOfficerId) async {
    _salesOfficerId = salesOfficerId;
    await load(refresh: true);
  }

  Future<void> search(String? query) async {
    _search = (query != null && query.trim().isEmpty) ? null : query?.trim();
    await load(refresh: true);
  }
}

final orderDetailProvider =
    FutureProvider.autoDispose.family<OrderModel, String>((ref, id) {
  return ref.read(ordersRepositoryProvider).getById(id);
});
