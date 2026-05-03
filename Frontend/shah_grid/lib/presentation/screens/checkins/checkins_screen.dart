import 'dart:async';
import 'dart:js_interop';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web/web.dart' as web;
import '../../../data/models/checkin_model.dart';
import '../../../data/repositories/checkins_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_error_widget.dart';

class CheckInsScreen extends ConsumerStatefulWidget {
  const CheckInsScreen({super.key});

  @override
  ConsumerState<CheckInsScreen> createState() => _CheckInsScreenState();
}

class _CheckInsScreenState extends ConsumerState<CheckInsScreen> {
  List<CheckInModel> _items = [];
  bool _loading = true;
  bool _hasMore = false;
  String? _nextCursor;
  Object? _error;
  bool _checkingIn = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool refresh = false}) async {
    if (refresh) setState(() { _loading = true; _error = null; _items = []; _nextCursor = null; });
    try {
      final result = await ref.read(checkInsRepositoryProvider).list(limit: 20);
      if (mounted) {
        setState(() {
          _items = result.items;
          _hasMore = result.hasMore;
          _nextCursor = result.nextCursor;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() { _error = e; _loading = false; });
    }
  }

  Future<void> _loadMore() async {
    if (!_hasMore || _nextCursor == null) return;
    try {
      final result = await ref.read(checkInsRepositoryProvider).list(cursor: _nextCursor, limit: 20);
      if (mounted) {
        setState(() {
          _items = [..._items, ...result.items];
          _hasMore = result.hasMore;
          _nextCursor = result.nextCursor;
        });
      }
    } catch (_) {}
  }

  Future<void> _checkIn() async {
    setState(() => _checkingIn = true);
    try {
      final position = await _getCurrentPosition();
      await ref.read(checkInsRepositoryProvider).create(
        latitude: position.$1,
        longitude: position.$2,
      );
      await _load(refresh: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Checked in successfully'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Check-in failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingIn = false);
    }
  }

  Future<(double, double)> _getCurrentPosition() {
    final completer = Completer<(double, double)>();
    web.window.navigator.geolocation.getCurrentPosition(
      ((web.GeolocationPosition pos) {
        completer.complete((pos.coords.latitude, pos.coords.longitude));
      }).toJS,
      ((web.GeolocationPositionError error) {
        completer.completeError(error.message);
      }).toJS,
    );
    return completer.future;
  }

  void _openOnMap(double lat, double lng) {
    web.window.open(
      'https://www.google.com/maps?q=$lat,$lng',
      '_blank',
    );
  }

  @override
  Widget build(BuildContext context) {
    final canCheckIn = ref.watch(authStateProvider).valueOrNull
            ?.hasPermission('checkins', 'create') ??
        false;
    final canViewAll = ref.watch(authStateProvider).valueOrNull
            ?.hasRole('Admin') ??
        false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Check-Ins'),
        actions: [
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _load(refresh: true)),
        ],
      ),
      floatingActionButton: canCheckIn
          ? FloatingActionButton.extended(
              onPressed: _checkingIn ? null : _checkIn,
              icon: _checkingIn
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.my_location),
              label: const Text('Check In'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
              ? AppErrorWidget(error: _error!, onRetry: () => _load(refresh: true))
              : _items.isEmpty
                  ? const Center(child: Text('No check-ins yet'))
                  : RefreshIndicator(
                      onRefresh: () => _load(refresh: true),
                      child: NotificationListener<ScrollNotification>(
                        onNotification: (n) {
                          if (n.metrics.pixels >= n.metrics.maxScrollExtent - 200) _loadMore();
                          return false;
                        },
                        child: ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                          itemCount: _items.length + (_hasMore ? 1 : 0),
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, i) {
                            if (i == _items.length) {
                              return const Center(child: Padding(
                                padding: EdgeInsets.all(16),
                                child: CircularProgressIndicator(),
                              ));
                            }
                            final item = _items[i];
                            return _CheckInCard(
                              checkIn: item,
                              showUser: canViewAll,
                              onViewMap: () => _openOnMap(item.latitude, item.longitude),
                            );
                          },
                        ),
                      ),
                    ),
    );
  }
}

class _CheckInCard extends StatelessWidget {
  const _CheckInCard({
    required this.checkIn,
    required this.showUser,
    required this.onViewMap,
  });

  final CheckInModel checkIn;
  final bool showUser;
  final VoidCallback onViewMap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.location_on, color: scheme.primary, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showUser && checkIn.userName != null)
                    Text(
                      checkIn.userName!,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  Text(
                    formatDateTime(checkIn.checkedInAt),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${checkIn.latitude.toStringAsFixed(6)}, ${checkIn.longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                  ),
                  if (checkIn.notes != null) ...[
                    const SizedBox(height: 4),
                    Text(checkIn.notes!, style: Theme.of(context).textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.map_outlined),
              tooltip: 'View on Map',
              onPressed: onViewMap,
            ),
          ],
        ),
      ),
    );
  }
}
