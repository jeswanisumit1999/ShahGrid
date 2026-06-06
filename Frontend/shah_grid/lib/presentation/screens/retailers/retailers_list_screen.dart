import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import '../../providers/retailers_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../data/models/retailer_model.dart';
import '../../../data/repositories/retailers_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../../core/network/dio_client.dart';
import '../../widgets/common/pagination_list_view.dart';

class RetailersListScreen extends ConsumerWidget {
  const RetailersListScreen({super.key});

  Future<({Uint8List bytes, String name})?> _pickFile() {
    final completer = Completer<({Uint8List bytes, String name})?>();
    final input = html.FileUploadInputElement()
      ..accept = '.xls,.xlsx';
    input.onChange.listen((_) {
      final file = input.files?.first;
      if (file == null) { completer.complete(null); return; }
      final reader = html.FileReader();
      reader.onLoad.listen((_) {
        final bytes = reader.result as Uint8List;
        completer.complete((bytes: bytes, name: file.name));
      });
      reader.onError.listen((_) => completer.complete(null));
      reader.readAsArrayBuffer(file);
    });
    input.click();
    return completer.future;
  }

  Future<void> _importXls(BuildContext context, WidgetRef ref) async {
    final picked = await _pickFile();
    if (picked == null || !context.mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const AlertDialog(
        content: Row(children: [
          CircularProgressIndicator(),
          SizedBox(width: 16),
          Text('Importing…'),
        ]),
      ),
    );

    try {
      final repo = ref.read(retailersRepositoryProvider);
      final res = await repo.importFromXls(picked.bytes, picked.name);
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (!context.mounted) return;

      ref.read(retailersProvider.notifier).load(refresh: true);

      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Import Complete'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ImportResultRow(Icons.check_circle, Colors.green, '${res.created} retailers created'),
              _ImportResultRow(Icons.skip_next, Colors.orange, '${res.skipped} already existed (skipped)'),
              if (res.errors.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('${res.errors.length} error(s):', style: const TextStyle(fontWeight: FontWeight.w600)),
                ...res.errors.take(5).map((e) => Text('• $e', style: const TextStyle(fontSize: 12))),
                if (res.errors.length > 5)
                  Text('… and ${res.errors.length - 5} more', style: const TextStyle(fontSize: 12)),
              ],
            ],
          ),
          actions: [
            FilledButton(onPressed: () => Navigator.pop(ctx), child: const Text('Done')),
          ],
        ),
      );
    } catch (e) {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _confirmDelete(BuildContext context, WidgetRef ref, RetailerModel retailer, RetailersNotifier notifier) {
    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Delete Retailer'),
        content: Text('Delete "${retailer.name}"? This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogCtx), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              Navigator.pop(dialogCtx);
              try {
                await ref.read(retailersRepositoryProvider).deleteRetailer(retailer.id);
                notifier.load(refresh: true);
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
                  );
                }
              }
            },
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(retailersProvider);
    final notifier = ref.read(retailersProvider.notifier);
    final user = ref.watch(authStateProvider).valueOrNull;
    final canCreate = user?.hasPermission('retailers', 'manage') ?? false;

    return Scaffold(
      floatingActionButton: canCreate
          ? FloatingActionButton.extended(
              onPressed: () => context.go('/retailers/new'),
              icon: const Icon(Icons.add),
              label: const Text('Add Retailer'),
            )
          : null,
      appBar: AppBar(
        title: const Text('Retailers'),
        actions: [
          if (canCreate)
            IconButton(
              icon: const Icon(Icons.upload_file_outlined),
              tooltip: 'Import from XLS',
              onPressed: () => _importXls(context, ref),
            ),
          PopupMenuButton<RetailerSort>(
            icon: const Icon(Icons.sort),
            tooltip: 'Sort',
            onSelected: notifier.sortBy,
            itemBuilder: (_) => const [
              PopupMenuItem(value: RetailerSort.nameAsc, child: Text('Name A→Z')),
              PopupMenuItem(value: RetailerSort.nameDesc, child: Text('Name Z→A')),
              PopupMenuItem(value: RetailerSort.pendingDesc, child: Text('Pending ↑ High')),
              PopupMenuItem(value: RetailerSort.pendingAsc, child: Text('Pending ↓ Low')),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SearchBar(
              hintText: 'Search by name or phone…',
              leading: const Icon(Icons.search),
              onChanged: (q) => notifier.search(q),
            ),
          ),
        ),
      ),
      body: state.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e, onRetry: () => notifier.load(refresh: true)),
        data: (result) => PaginationListView<RetailerModel>(
          items: result.items,
          hasMore: result.hasMore,
          onLoadMore: notifier.loadMore,
          onRefresh: () => notifier.load(refresh: true),
          emptyWidget: const Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.storefront_outlined, size: 48),
              SizedBox(height: 12),
              Text('No retailers found'),
            ],
          ),
          itemBuilder: (ctx, retailer) => ListTile(
            leading: const CircleAvatar(child: Icon(Icons.storefront)),
            title: Text(retailer.name),
            subtitle: Text(retailer.phone),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(formatCurrency(retailer.pendingCollection),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    Text('pending', style: Theme.of(ctx).textTheme.labelSmall),
                  ],
                ),
                const SizedBox(width: 4),
                IconButton(
                  icon: const Icon(Icons.call_outlined, size: 20),
                  tooltip: 'Call',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      launchUrl(Uri(scheme: 'tel', path: retailer.phone)),
                ),
                if (canCreate) ...[
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert),
                    onSelected: (v) {
                      if (v == 'delete') _confirmDelete(ctx, ref, retailer, notifier);
                    },
                    itemBuilder: (_) => [
                      PopupMenuItem(
                        value: 'delete',
                        child: const ListTile(
                          leading: Icon(Icons.delete_outline, color: Colors.red),
                          title: Text('Delete', style: TextStyle(color: Colors.red)),
                          contentPadding: EdgeInsets.zero,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            onTap: () => ctx.go('/retailers/${retailer.id}'),
          ),
        ),
      ),
    );
  }
}

class _ImportResultRow extends StatelessWidget {
  const _ImportResultRow(this.icon, this.color, this.label);
  final IconData icon;
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Icon(icon, color: color, size: 18),
            const SizedBox(width: 8),
            Text(label),
          ],
        ),
      );
}
