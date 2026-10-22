import 'package:intl/intl.dart';

/// Formatting rules from the handoff (section 2.8).
abstract final class Fmt {
  /// Minutes after midnight -> `HH:mm` (wraps past 24 h).
  static String hm(int minutes) {
    final int m = ((minutes % 1440) + 1440) % 1440;
    return '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';
  }

  static String time(DateTime d) => DateFormat('HH:mm').format(d);

  static String dayStamp(DateTime d) => DateFormat('EEE dd MMM').format(d).toUpperCase();

  /// `7h 12m`
  static String dur(int minutes) {
    final int a = minutes.abs();
    return '${a ~/ 60}h ${(a % 60).toString().padLeft(2, '0')}m';
  }

  /// `7h12`
  static String durCompact(int minutes) => '${minutes ~/ 60}h${(minutes % 60).toString().padLeft(2, '0')}';

  static final NumberFormat _inr = NumberFormat.currency(locale: 'en_IN', symbol: '₹', decimalDigits: 0);

  /// Paise -> `₹24,860`
  static String money(int paise) => _inr.format(paise / 100);

  /// Debit in lists with a true minus sign (U+2212).
  static String debit(int paise) => '−${money(paise)}';

  static String mmss(int seconds) {
    final int s = seconds < 0 ? 0 : seconds;
    return '${(s ~/ 60).toString().padLeft(2, '0')}:${(s % 60).toString().padLeft(2, '0')}';
  }

  static String greeting(DateTime d) => d.hour < 12
      ? 'Morning'
      : d.hour < 17
          ? 'Afternoon'
          : 'Evening';

  static String litres(int ml) => (ml / 1000).toStringAsFixed(1);
}
