import 'models.dart';

/// Rules-based quick-capture parser (spec section 5). Pure function: text in,
/// structured draft out. Runs on every keystroke.
abstract final class CaptureParser {
  /// A trailing amount, optionally prefixed by a currency marker. Allows
  /// thousands separators and decimals: `1,250`, `12.50`, `Rs. 1,250`, `₹ 12,000`.
  static final RegExp _amountTail = RegExp(r'(?:₹|rs\.?|inr)?\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)\s*$', caseSensitive: false);
  static final RegExp _rupee = RegExp(r'₹\s*(\d{1,3}(?:,\d{2,3})+(?:\.\d{1,2})?|\d+(?:\.\d{1,2})?)');
  static final RegExp _clockAmPm = RegExp(r'\b(\d{1,2})(?::(\d{2}))?\s*(am|pm)\b', caseSensitive: false);
  static final RegExp _clock24 = RegExp(r'\b([01]?\d|2[0-3]):([0-5]\d)\b');
  static final RegExp _quantity = RegExp(r'\b(pages?|mins?|minutes?|hours?|hrs?|km|kg|reps?)\b', caseSensitive: false);

  /// Whole words only, and `tomorrow` is checked before the weekdays.
  static final List<(RegExp, String)> _dayWords = <(RegExp, String)>[
    (RegExp(r'\btomorrow\b'), 'TOMORROW'),
    (RegExp(r'\btonight\b'), 'TONIGHT'),
    (RegExp(r'\btoday\b'), 'TODAY'),
    (RegExp(r'\b(mon|monday)\b'), 'MON'),
    (RegExp(r'\b(tue|tues|tuesday)\b'), 'TUE'),
    (RegExp(r'\b(wed|weds|wednesday)\b'), 'WED'),
    (RegExp(r'\b(thu|thur|thurs|thursday)\b'), 'THU'),
    (RegExp(r'\b(fri|friday)\b'), 'FRI'),
    (RegExp(r'\b(sat|saturday)\b'), 'SAT'),
    (RegExp(r'\b(sun|sunday)\b'), 'SUN'),
  ];

  static const List<String> _spendWords = <String>['lunch', 'dinner', 'breakfast', 'coffee', 'uber', 'ola', 'cab', 'fuel', 'petrol', 'groceries', 'bought', 'paid', 'spent', 'bill', 'recharge', 'rent'];
  static const Map<String, String> _category = <String, String>{
    'lunch': 'FOOD', 'dinner': 'FOOD', 'breakfast': 'FOOD', 'coffee': 'FOOD', 'groceries': 'FOOD',
    'uber': 'TRANSPORT', 'ola': 'TRANSPORT', 'cab': 'TRANSPORT', 'fuel': 'TRANSPORT', 'petrol': 'TRANSPORT',
    'bill': 'BILLS', 'recharge': 'BILLS', 'rent': 'BILLS',
  };

  static int? _paise(String digits) {
    final String clean = digits.replaceAll(',', '');
    if (clean.replaceAll('.', '').length > 9) return null; // would overflow: ignore
    final double? v = double.tryParse(clean);
    return v == null ? null : (v * 100).round();
  }

  static bool _hasWord(String lower, String w) => RegExp('\\b${RegExp.escape(w)}\\b').hasMatch(lower);

  static CaptureDraft parse(String raw) {
    final String text = raw.trim();
    final String lower = text.toLowerCase();
    final CaptureDraft d = CaptureDraft(raw: text, title: text);
    if (text.isEmpty) return d;

    // When
    int? when;
    final Match? ap = _clockAmPm.firstMatch(lower);
    if (ap != null) {
      final int h12 = int.parse(ap.group(1)!);
      if (h12 >= 1 && h12 <= 12) {
        int h = h12 % 12;
        if (ap.group(3)!.toLowerCase() == 'pm') h += 12;
        when = h * 60 + int.parse(ap.group(2) ?? '0');
      }
    }
    if (when == null) {
      final Match? h = _clock24.firstMatch(lower);
      if (h != null) when = int.parse(h.group(1)!) * 60 + int.parse(h.group(2)!);
    }
    d.when = when;
    for (final (RegExp, String) e in _dayWords) {
      if (e.$1.hasMatch(lower)) {
        d.whenLabel = e.$2;
        break;
      }
    }

    // Money
    final Match? r = _rupee.firstMatch(text);
    final Match? a = _amountTail.firstMatch(text);
    final bool qty = _quantity.hasMatch(lower);
    int? paise;
    if (r != null) {
      paise = _paise(r.group(1)!);
    } else if (a != null && when == null && !qty) {
      paise = _paise(a.group(1)!);
    }
    d.paise = paise;

    // Type
    final bool spendy = _spendWords.any((String w) => _hasWord(lower, w));
    if (paise != null && (spendy || r != null || a != null)) {
      d.type = CaptureType.spend;
      d.uncertainType = !spendy && r == null;
      d.tag = _spendWords.where((String w) => _hasWord(lower, w)).map((String w) => _category[w]).whereType<String>().firstOrNull ?? 'OTHER';
      final String stripped = text.replaceAll(RegExp(r'(?:₹|rs\.?|inr)?\s*(?:\d{1,3}(?:,\d{2,3})+|\d+)(?:\.\d{1,2})?\s*$', caseSensitive: false), '').trim();
      d.title = stripped.isEmpty ? text : stripped;
    } else if (RegExp(r'\b(daily|every day|each day|weekly)\b').hasMatch(lower)) {
      d.type = CaptureType.habit;
      d.uncertainType = false;
    } else if (RegExp(r'\b(meeting|call|sync|standup|catch ?up|interview|review)\b').hasMatch(lower) && when != null) {
      d.type = CaptureType.event;
      d.uncertainType = false;
    } else if (lower.startsWith('note') || lower.startsWith('idea') || lower.startsWith('remember')) {
      d.type = CaptureType.note;
      d.uncertainType = false;
    } else {
      d.type = CaptureType.obj;
      d.uncertainType = when == null && d.whenLabel == null;
      d.tag = RegExp(r'\b(home|mom|dad|dentist|gym|groceries)\b').hasMatch(lower) ? 'HOME' : 'WORK';
    }
    return d;
  }

  static String typeLabel(CaptureType t) => switch (t) {
        CaptureType.obj => 'TASK',
        CaptureType.event => 'EVENT',
        CaptureType.note => 'NOTE',
        CaptureType.spend => 'SPEND',
        CaptureType.habit => 'HABIT',
      };
}
