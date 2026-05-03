import 'package:intl/intl.dart';

// Indian grouping: 3 digits rightmost, then groups of 2 → 1,00,000
final _currency = NumberFormat('#,##,##0.00', 'en_IN');
final _number   = NumberFormat('#,##,##0',    'en_IN');
final _dateShort = DateFormat('dd MMM yyyy');
final _dateTime = DateFormat('dd MMM yyyy, hh:mm a');

String formatCurrency(dynamic amount) {
  final val = double.tryParse(amount.toString()) ?? 0;
  return '₹${_currency.format(val)}';
}

String formatNumber(dynamic value) {
  final val = int.tryParse(value.toString()) ?? 0;
  return _number.format(val);
}

String formatDate(String? isoDate) {
  if (isoDate == null) return '—';
  return _dateShort.format(DateTime.parse(isoDate).toLocal());
}

String formatDateTime(String? isoDate) {
  if (isoDate == null) return '—';
  return _dateTime.format(DateTime.parse(isoDate).toLocal());
}

/// Converts 'snake_case' or 'camelCase' to 'Title Case'
String labelify(String key) {
  return key
      .replaceAll('_', ' ')
      .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .split(' ')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}
