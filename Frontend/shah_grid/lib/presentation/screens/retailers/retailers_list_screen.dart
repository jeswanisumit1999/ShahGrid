import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';
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
