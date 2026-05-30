import 'package:flutter/material.dart';
import '../../../data/models/retailer_model.dart';
import '../../../core/utils/format_utils.dart';

class RetailerSearchDialog extends StatefulWidget {
  const RetailerSearchDialog({super.key, required this.retailers});
  final List<RetailerModel> retailers;

  @override
  State<RetailerSearchDialog> createState() => _RetailerSearchDialogState();
}

class _RetailerSearchDialogState extends State<RetailerSearchDialog> {
  final _controller = TextEditingController();
  late List<RetailerModel> _filtered;

  @override
  void initState() {
    super.initState();
    _filtered = widget.retailers;
    _controller.addListener(() {
      final q = _controller.text.toLowerCase();
      setState(() {
        _filtered = widget.retailers
            .where((r) => r.name.toLowerCase().contains(q))
            .toList();
      });
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 400, maxHeight: 500),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text('Select Retailer',
                  style: Theme.of(context).textTheme.titleLarge),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search retailers...',
                  prefixIcon: Icon(Icons.search),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Flexible(
              child: _filtered.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(24),
                      child: Text('No retailers found'),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: _filtered.length,
                      itemBuilder: (_, i) {
                        final r = _filtered[i];
                        return ListTile(
                          title: Text(r.name),
                          subtitle: Text(
                              'Credit: ${formatCurrency(r.availableCredit)}'),
                          dense: true,
                          onTap: () => Navigator.pop(context, r),
                        );
                      },
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
