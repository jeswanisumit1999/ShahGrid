import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/retailers_provider.dart';
import '../../providers/auth_provider.dart';
import '../../../core/utils/format_utils.dart';
import '../../widgets/common/app_error_widget.dart';
import '../../widgets/common/pagination_list_view.dart';

class RetailersListScreen extends ConsumerWidget {
  const RetailersListScreen({super.key});

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
        data: (result) => PaginationListView(
          items: result.items,
          hasMore: result.hasMore,
          onLoadMore: notifier.loadMore,
          onRefresh: () => notifier.load(refresh: true),
          itemBuilder: (ctx, retailer) => ListTile(
            leading: const CircleAvatar(child: Icon(Icons.storefront)),
            title: Text(retailer.name),
            subtitle: Text(retailer.phone),
            trailing: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(formatCurrency(retailer.pendingCollection),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
                Text('pending', style: Theme.of(ctx).textTheme.labelSmall),
              ],
            ),
            onTap: () => ctx.go('/retailers/${retailer.id}'),
          ),
        ),
      ),
    );
  }
}
