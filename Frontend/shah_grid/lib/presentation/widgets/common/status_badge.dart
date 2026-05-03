import 'package:flutter/material.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.status, {super.key, this.small = false});
  final String status;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final (color, textColor) = _palette(status, context);
    return Container(
      padding: EdgeInsets.symmetric(
          horizontal: small ? 6 : 10, vertical: small ? 2 : 4),
      decoration:
          BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
      child: Text(
        status,
        style: TextStyle(
            color: textColor,
            fontSize: small ? 10 : 12,
            fontWeight: FontWeight.w600),
      ),
    );
  }

  (Color, Color) _palette(String s, BuildContext ctx) {
    final cs = Theme.of(ctx).colorScheme;
    return switch (s) {
      'Delivered' || 'delivered' => (cs.primaryContainer, cs.onPrimaryContainer),
      'Ready for Dispatch' => (cs.tertiaryContainer, cs.onTertiaryContainer),
      'Returned' || 'returned' => (cs.secondaryContainer, cs.onSecondaryContainer),
      'Cancelled' || 'cancelled' => (cs.errorContainer, cs.onErrorContainer),
      'Pending Stock Verification' || 'Pending Stock Availability' =>
        (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      _ => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };
  }
}
