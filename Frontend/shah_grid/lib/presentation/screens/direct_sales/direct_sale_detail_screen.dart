import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../data/models/direct_sale_model.dart';
import '../../../data/repositories/direct_sales_repository.dart';
import '../../../core/utils/format_utils.dart';
import '../../../core/utils/pdf_preview.dart';
import '../../../core/network/dio_client.dart';
import '../../providers/auth_provider.dart';
import '../../widgets/common/app_error_widget.dart';

final _directSaleDetailProvider =
    FutureProvider.autoDispose.family<DirectSaleModel, String>((ref, id) {
  return ref.read(directSalesRepositoryProvider).getById(id);
});

class DirectSaleDetailScreen extends ConsumerStatefulWidget {
  const DirectSaleDetailScreen({super.key, required this.id});
  final String id;

  @override
  ConsumerState<DirectSaleDetailScreen> createState() =>
      _DirectSaleDetailScreenState();
}

class _DirectSaleDetailScreenState
    extends ConsumerState<DirectSaleDetailScreen> {
  bool _generatingChallan = false;

  Future<void> _generateChallan(DirectSaleModel sale) async {
    setState(() => _generatingChallan = true);
    try {
      final bytes =
          await ref.read(directSalesRepositoryProvider).downloadChallan(sale.id);
      final shortId = sale.id.split('-').first.toUpperCase();
      final filename = 'challan_${sale.challanNumber ?? shortId}.pdf';
      final handle = createPdfPreview(bytes);
      if (!mounted) { handle.dispose(); return; }
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ChallanPreviewDialog(handle: handle, filename: filename),
      );
      handle.dispose();
      // Refresh to pick up assigned challan number
      ref.invalidate(_directSaleDetailProvider(widget.id));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(friendlyError(e)), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _generatingChallan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_directSaleDetailProvider(widget.id));
    final user = ref.watch(authStateProvider).valueOrNull;
    final canChallan = user?.hasPermission('challans', 'generate') ?? false;

    return Scaffold(
      appBar: AppBar(title: const Text('Direct Sale')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => AppErrorWidget(error: e),
        data: (sale) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Summary card
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('Customer', style: Theme.of(context).textTheme.labelMedium),
                  Text(sale.customerName,
                      style: Theme.of(context).textTheme.titleMedium),
                  const Divider(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('Sales Officer',
                          style: Theme.of(context).textTheme.labelSmall),
                      Text(sale.salesOfficerName ?? '—'),
                    ]),
                    Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                      Text('Date', style: Theme.of(context).textTheme.labelSmall),
                      Text(formatDate(sale.createdAt)),
                    ]),
                  ]),
                  const Divider(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('Total'),
                    Text(formatCurrency(sale.totalAmount),
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 18)),
                  ]),
                  if (sale.amountPaid != null) ...[
                    const SizedBox(height: 8),
                    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text('Amount Paid',
                          style: Theme.of(context).textTheme.bodyMedium),
                      Text(formatCurrency(sale.amountPaid!),
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ]),
                    if (sale.balance > 0) ...[
                      const SizedBox(height: 4),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('Balance Due',
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)),
                        Text(formatCurrency(sale.balance),
                            style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: Theme.of(context).colorScheme.error)),
                      ]),
                    ] else ...[
                      const SizedBox(height: 4),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        const Text('Balance Due'),
                        Text('Fully paid',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.w600)),
                      ]),
                    ],
                  ],
                  if (sale.challanNumber != null) ...[
                    const SizedBox(height: 8),
                    Text('Challan #${sale.challanNumber}',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary)),
                  ],
                ]),
              ),
            ),
            const SizedBox(height: 16),

            // Items
            Text('Items', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...sale.items.map((item) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(item.productName ?? item.productId),
                    subtitle: Text(
                        '${formatNumber(item.quantity)} × ${formatCurrency(item.unitPrice)}'),
                    trailing: Text(formatCurrency(item.lineTotal),
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                )),

            if (sale.notes != null && sale.notes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text('Notes', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 4),
              Text(sale.notes!),
            ],

            if (canChallan) ...[
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _generatingChallan ? null : () => _generateChallan(sale),
                icon: _generatingChallan
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.picture_as_pdf_outlined),
                label: const Text('Generate Challan'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChallanPreviewDialog extends StatelessWidget {
  const _ChallanPreviewDialog({required this.handle, required this.filename});
  final PdfPreviewHandle handle;
  final String filename;

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Column(children: [
        AppBar(
          automaticallyImplyLeading: false,
          title: Text(filename),
          actions: [
            TextButton.icon(
              onPressed: () => handle.download(filename),
              icon: const Icon(Icons.download_outlined),
              label: const Text('Download'),
            ),
            TextButton.icon(
              onPressed: handle.print,
              icon: const Icon(Icons.print_outlined),
              label: const Text('Print'),
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        Expanded(child: HtmlElementView(viewType: handle.viewType)),
      ]),
    );
  }
}
