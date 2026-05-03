import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/shipment_model.dart';
import '../../data/models/user_model.dart';
import '../../data/repositories/shipments_repository.dart';

final shipmentsProvider =
    StateNotifierProvider.autoDispose<ShipmentsNotifier, AsyncValue<PaginatedResult<ShipmentModel>>>(
  (ref) => ShipmentsNotifier(ref.read(shipmentsRepositoryProvider)),
);

class ShipmentsNotifier
    extends StateNotifier<AsyncValue<PaginatedResult<ShipmentModel>>> {
  ShipmentsNotifier(this._repo) : super(const AsyncValue.loading()) {
    load();
  }

  final ShipmentsRepository _repo;
  String? _cursor;
  String? _statusFilter;
  final List<ShipmentModel> _items = [];

  Future<void> load({bool refresh = false}) async {
    if (refresh) {
      _cursor = null;
      _items.clear();
    }
    try {
      if (_items.isEmpty) state = const AsyncValue.loading();
      final result = await _repo.list(cursor: _cursor, status: _statusFilter);
      _items.addAll(result.items);
      _cursor = result.nextCursor;
      state = AsyncValue.data(
        PaginatedResult(items: List.unmodifiable(_items), hasMore: result.hasMore),
      );
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> filterByStatus(String? status) async {
    _statusFilter = status;
    await load(refresh: true);
  }

  Future<void> loadMore() async {
    if (!(state.valueOrNull?.hasMore ?? false)) return;
    await load();
  }
}

final shipmentDetailProvider =
    FutureProvider.autoDispose.family<ShipmentModel, String>((ref, id) {
  return ref.read(shipmentsRepositoryProvider).getById(id);
});
