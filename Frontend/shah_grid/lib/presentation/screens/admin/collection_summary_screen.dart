import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../core/constants/api_constants.dart';
import '../../../core/network/dio_client.dart';
import '../../../core/utils/format_utils.dart';

// ── Models ────────────────────────────────────────────────────────────────────

class _RetailerRow {
  const _RetailerRow({required this.id, required this.name, required this.phone, required this.pendingCollection});
  final String id;
  final String name;
  final String phone;
  final double pendingCollection;

  factory _RetailerRow.fromJson(Map<String, dynamic> j) => _RetailerRow(
        id: j['id'] as String,
        name: j['name'] as String,
        phone: j['phone'] as String? ?? '',
        pendingCollection: (j['pendingCollection'] as num).toDouble(),
      );
}

class _OfficerSummary {
  const _OfficerSummary({
    required this.id,
    required this.name,
    required this.email,
    this.avatarUrl,
    required this.totalPending,
    required this.retailers,
  });
  final String id;
  final String name;
  final String email;
  final String? avatarUrl;
  final double totalPending;
  final List<_RetailerRow> retailers;

  factory _OfficerSummary.fromJson(Map<String, dynamic> j) {
    final so = j['salesOfficer'] as Map<String, dynamic>;
    return _OfficerSummary(
      id: so['id'] as String,
      name: so['name'] as String,
      email: so['email'] as String,
      avatarUrl: so['avatarUrl'] as String?,
      totalPending: (j['totalPending'] as num).toDouble(),
      retailers: (j['retailers'] as List)
          .map((r) => _RetailerRow.fromJson(r as Map<String, dynamic>))
          .toList(),
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

final _summaryProvider = FutureProvider.autoDispose<List<_OfficerSummary>>((ref) async {
  final dio = ref.read(dioProvider);
  final res = await dio.get(ApiConstants.collectionSummary);
  final data = (res.data['data'] as List);
  return data.map((e) => _OfficerSummary.fromJson(e as Map<String, dynamic>)).toList();
});

// ── Screen ────────────────────────────────────────────────────────────────────

class CollectionSummaryScreen extends ConsumerWidget {
  const CollectionSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(_summaryProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Collection Summary')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (summaries) {
          if (summaries.isEmpty) {
            return const Center(child: Text('No Sales Officers found.'));
          }

          final grandTotal = summaries.fold<double>(0, (s, o) => s + o.totalPending);

          return Column(
            children: [
              _GrandTotalBanner(total: grandTotal),
              Expanded(
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: summaries.length,
                  itemBuilder: (context, i) => _OfficerCard(summary: summaries[i]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

// ── Grand total banner ────────────────────────────────────────────────────────

class _GrandTotalBanner extends StatelessWidget {
  const _GrandTotalBanner({required this.total});
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      color: theme.colorScheme.primaryContainer,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      child: Row(
        children: [
          const Icon(Icons.account_balance_wallet_outlined, size: 20),
          const SizedBox(width: 10),
          Text('Total Outstanding', style: theme.textTheme.titleSmall),
          const Spacer(),
          Text(
            formatCurrency(total),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }
}

// ── Per-officer expandable card ───────────────────────────────────────────────

class _OfficerCard extends StatefulWidget {
  const _OfficerCard({required this.summary});
  final _OfficerSummary summary;

  @override
  State<_OfficerCard> createState() => _OfficerCardState();
}

class _OfficerCardState extends State<_OfficerCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = widget.summary;
    final isPositive = s.totalPending > 0;
    final amountColor = isPositive ? Colors.red.shade700 : Colors.green.shade700;

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          // ── Header row ──────────────────────────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    radius: 22,
                    backgroundImage: s.avatarUrl != null ? NetworkImage(s.avatarUrl!) : null,
                    child: s.avatarUrl == null
                        ? Text(s.name[0].toUpperCase(),
                            style: const TextStyle(fontWeight: FontWeight.bold))
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(s.email, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
                        const SizedBox(height: 2),
                        Text(
                          '${s.retailers.length} retailer${s.retailers.length == 1 ? '' : 's'}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        formatCurrency(s.totalPending.abs()),
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: amountColor,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        isPositive ? 'to collect' : 'credit',
                        style: theme.textTheme.labelSmall?.copyWith(color: amountColor),
                      ),
                    ],
                  ),
                  const SizedBox(width: 8),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more,
                      color: theme.colorScheme.outline),
                ],
              ),
            ),
          ),

          // ── Retailer list ────────────────────────────────────────────────
          if (_expanded) ...[
            const Divider(height: 1),
            if (s.retailers.isEmpty)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text('No retailers assigned.',
                    style: TextStyle(color: theme.colorScheme.outline)),
              )
            else
              ...s.retailers.map((r) => _RetailerTile(retailer: r)),
          ],
        ],
      ),
    );
  }
}

// ── Single retailer row inside expanded card ──────────────────────────────────

class _RetailerTile extends StatelessWidget {
  const _RetailerTile({required this.retailer});
  final _RetailerRow retailer;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = retailer.pendingCollection;
    final color = pending > 0 ? Colors.red.shade700 : pending < 0 ? Colors.green.shade700 : null;

    return InkWell(
      onTap: () => context.go('/retailers/${retailer.id}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
        child: Row(
          children: [
            const Icon(Icons.storefront_outlined, size: 18),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(retailer.name, style: theme.textTheme.bodyMedium),
                  if (retailer.phone.isNotEmpty)
                    Text(retailer.phone,
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            ),
            Text(
              formatCurrency(pending.abs()),
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
