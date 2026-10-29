import '../app/fmt.dart';
import 'agent.dart';
import 'brain_prompt.dart';
import 'capture_parser.dart';
import 'models.dart';

/// Who decides what K does with an utterance. A 1B model is good at language and poor at being exact about
/// changes (measured on a phone-class run: 7 of 24 sample requests right when it decided everything), so:
///
///  1. **Rules** handle clear commands exactly: water, spend, reminders, events, notes, and "I did X" matched
///     against the user's real objectives and protocols. No model, no battery, same answer every time.
///  2. **The router** answers questions about the user's own data (water, steps, sleep, money, schedule) from the
///     store, so the numbers are always the real ones.
///  3. **The model** handles open language: general questions and chat, and commands the rules did not recognise.
///     Whatever action it proposes is checked against the user's words ([validateModelPlan]) before it runs.

enum DecisionSource { rules, router, model }

/// A decision made without the model.
class Decision {
  const Decision(this.source, this.plan);

  final DecisionSource source;

  /// Set for [DecisionSource.rules]; null for [DecisionSource.router] (the keyword router writes the answer).
  final AgentPlan? plan;
}

const Set<String> _stop = <String>{
  'i', 'my', 'me', 'the', 'a', 'an', 'is', 'was', 'were', 'am', 'are', 'has', 'have', 'had', 'been', 'it', 'its', 'to', 'of', 'on', 'for', 'and', 'with', 'in', 'at',
  'just', 'now', 'today', 'please', 'k', 'that', 'this', 'up', 'out', 'off', 'also', 'already', 'finally', 'tonight', 'tomorrow',
};

/// Words that say something was finished. They are not part of the name of the thing finished.
const Set<String> _doneCue = <String>{'did', 'done', 'finished', 'finish', 'completed', 'complete', 'completing', 'mark', 'marked', 'tick', 'ticked', 'cleared', 'clear', 'crossed', 'handled', 'wrapped'};

const Map<String, String> _irregular = <String, String>{'sent': 'send', 'paid': 'pay', 'bought': 'buy', 'took': 'take', 'made': 'make', 'wrote': 'write', 'ran': 'run', 'did': 'do', 'went': 'go', 'got': 'get', 'met': 'meet'};

/// A crude stem, enough to match "called" with "call" and "reading" with "read".
String _stem(String w) {
  final String x = w.toLowerCase();
  if (_irregular.containsKey(x)) return _irregular[x]!;
  for (final String suf in <String>['ing', 'ed', 'es', 's']) {
    if (x.length > suf.length + 2 && x.endsWith(suf)) return x.substring(0, x.length - suf.length);
  }
  return x;
}

List<String> _tokens(String text, {bool dropCues = false}) => <String>[
      for (final String w in RegExp(r"[a-z0-9']+").allMatches(text.toLowerCase()).map((Match m) => m.group(0)!))
        if (w.length >= 2 && !_stop.contains(w) && !(dropCues && _doneCue.contains(w))) _stem(w),
    ];

String _cap(String s) {
  final String t = s.trim();
  return t.isEmpty ? t : '${t[0].toUpperCase()}${t.substring(1)}';
}

String _hm(int m) => '${(m ~/ 60).toString().padLeft(2, '0')}:${(m % 60).toString().padLeft(2, '0')}';

AgentPlan _plan(String say, List<Map<String, dynamic>> actions) => AgentPlan(say, <AgentAction>[for (final Map<String, dynamic> a in actions) AgentAction(a['type'] as String, a)]);

final RegExp _timeWords = RegExp(r'\b(\d{1,2}(:\d{2})?\s*(am|pm)|\d{1,2}:\d{2}|noon|midnight)\b', caseSensitive: false);

/// "tomorrow" or "today" from the utterance, or null when it names no day (or names a weekday, which the
/// actions do not support, so the model or the user handles it).
String? _day(String lower) {
  if (RegExp(r'\b(mon|tue|tues|wed|thu|thur|thurs|fri|sat|sun|monday|tuesday|wednesday|thursday|friday|saturday|sunday)\b').hasMatch(lower)) return 'weekday';
  if (lower.contains('tomorrow')) return 'tomorrow';
  if (lower.contains('today') || lower.contains('tonight')) return 'today';
  return null;
}

String _stripWhen(String s) {
  String t = s;
  t = t.replaceAll(RegExp(r'\b(by|at|before|around|for)\s+(\d{1,2}(:\d{2})?\s*(am|pm)|\d{1,2}:\d{2}|noon|midnight)', caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r'\b\d{1,2}(:\d{2})?\s*(am|pm)\b|\b\d{1,2}:\d{2}\b', caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r'\b(tomorrow|tonight|today|this (morning|afternoon|evening)|(in the )?(morning|afternoon|evening))\b', caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r',?\s*(it is|it\x27s|its)\s+(critical|urgent|important|high priority)\b', caseSensitive: false), ' ');
  t = t.replaceAll(RegExp(r'\b(critical|urgent|asap)\b', caseSensitive: false), ' ');
  // A trailing priority word is a priority, not part of the title ("report, important").
  t = t.replaceAll(RegExp(r',?\s*\b(important|high priority)\s*$', caseSensitive: false), ' ');
  return t.replaceAll(RegExp(r'\s+'), ' ').replaceAll(RegExp(r'^[\s,.\-]+|[\s,.\-]+$'), '').trim();
}

// ----------------------------------------------------------------------------------------------- water

AgentPlan? _water(String q, String lower) {
  if (!lower.contains('water')) return null;
  final RegExpMatch? ml = RegExp(r'\b(\d{2,4})\s*(ml|millilit(?:re|er)s?)\b').firstMatch(lower);
  final RegExpMatch? l = RegExp(r'\b(\d+(?:\.\d+)?)\s*(l|litres?|liters?)\b').firstMatch(lower);
  int? amount;
  if (ml != null) {
    amount = int.parse(ml.group(1)!);
  } else if (l != null) {
    amount = (double.parse(l.group(1)!) * 1000).round();
  } else {
    final RegExpMatch? unit = RegExp(r'\b(a|an|one|two|three|four|\d)?\s*(glass(?:es)?|bottles?|cups?)\b').firstMatch(lower);
    if (unit == null) return null;
    const Map<String, int> n = <String, int>{'a': 1, 'an': 1, 'one': 1, 'two': 2, 'three': 3, 'four': 4};
    final String g = unit.group(1) ?? 'a';
    final int count = n[g] ?? int.tryParse(g) ?? 1;
    final String u = unit.group(2)!;
    amount = count * (u.startsWith('glass') ? 250 : (u.startsWith('bottle') ? 500 : 200));
  }
  if (amount < 50 || amount > 2000) return null;
  return _plan('Logged $amount ml of water.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'log_water', 'ml': amount},
  ]);
}

// ----------------------------------------------------------------------------------------------- spend

const Map<String, String> _spendCategory = <String, String>{
  'lunch': 'FOOD', 'dinner': 'FOOD', 'breakfast': 'FOOD', 'coffee': 'FOOD', 'tea': 'FOOD', 'snack': 'FOOD', 'snacks': 'FOOD', 'groceries': 'FOOD', 'vegetables': 'FOOD',
  'swiggy': 'FOOD', 'zomato': 'FOOD', 'restaurant': 'FOOD', 'food': 'FOOD', 'meal': 'FOOD',
  'uber': 'TRANSPORT', 'ola': 'TRANSPORT', 'cab': 'TRANSPORT', 'taxi': 'TRANSPORT', 'auto': 'TRANSPORT', 'metro': 'TRANSPORT', 'bus': 'TRANSPORT', 'train': 'TRANSPORT',
  'fuel': 'TRANSPORT', 'petrol': 'TRANSPORT', 'diesel': 'TRANSPORT', 'flight': 'TRANSPORT', 'parking': 'TRANSPORT', 'toll': 'TRANSPORT',
  'bill': 'BILLS', 'electricity': 'BILLS', 'broadband': 'BILLS', 'wifi': 'BILLS', 'recharge': 'BILLS', 'rent': 'BILLS', 'emi': 'BILLS', 'insurance': 'BILLS',
  'amazon': 'SHOPPING', 'flipkart': 'SHOPPING', 'shopping': 'SHOPPING', 'clothes': 'SHOPPING', 'shoes': 'SHOPPING',
};

AgentPlan? _spend(String q, String lower) {
  if (!RegExp(r'\b(spent|spend|paid|pay|cost|costs|bought|buy|purchased|rs|rupees|inr)\b|₹').hasMatch(lower) && !RegExp(r'\b(lunch|dinner|breakfast|coffee|uber|ola|cab)\b').hasMatch(lower)) return null;
  // The amount: a number that is not part of a time.
  final String noTimes = lower.replaceAll(_timeWords, ' ');
  final Iterable<RegExpMatch> nums = RegExp(r'(?:₹|rs\.?\s*|inr\s*)?(\d[\d,]*(?:\.\d{1,2})?)').allMatches(noTimes);
  if (nums.isEmpty) return null;
  final double? amount = double.tryParse(nums.last.group(1)!.replaceAll(',', ''));
  if (amount == null || amount <= 0 || amount > 10000000) return null;
  // Quantities ("30 min", "20 pages") are not money.
  if (RegExp('${RegExp.escape(nums.last.group(1)!)}\\s*(min|mins|minutes?|hours?|hrs?|pages?|km|kg|reps?|ml|l|litres?)\\b').hasMatch(noTimes)) return null;
  String category = 'OTHER';
  for (final String w in RegExp(r'[a-z]+').allMatches(lower).map((Match m) => m.group(0)!)) {
    if (_spendCategory.containsKey(w)) {
      category = _spendCategory[w]!;
      break;
    }
  }
  String title = q
      .replaceAll(RegExp(r'(?:₹|rs\.?\s*|inr\s*)?\d[\d,]*(?:\.\d{1,2})?\s*(?:rupees|rs|inr)?', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(spent|spend|paid|pay|cost|costs|bought|buy|purchased|i|just|rupees|rs|inr)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  title = title.replaceAll(RegExp(r'^(on|for|to|at|the|a|an)\s+', caseSensitive: false), '').replaceAll(RegExp(r'^(on|for|to|at|the|a|an)\s+', caseSensitive: false), '').trim();
  if (title.isEmpty) title = 'Spend';
  return _plan('Logged ${Fmt.money((amount * 100).round())} for ${title.toLowerCase()}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'log_expense', 'title': _cap(title), 'amount': amount, 'category': category},
  ]);
}

// ----------------------------------------------------------------------------------------------- finished something

({String name, bool protocol, int score})? _bestMatch(List<String> candidates, List<String> words, bool protocol) {
  ({String name, bool protocol, int score})? best;
  for (final String c in candidates) {
    final String name = c.split(' · ').first.replaceAll(RegExp(r' \(done\)$'), '');
    final Set<String> have = _tokens(name).toSet();
    final int score = words.where(have.contains).length;
    if (score > 0 && (best == null || score > best.score)) best = (name: name, protocol: protocol, score: score);
  }
  return best;
}

AgentPlan? _completion(String q, String lower, BrainFacts f) {
  final bool cue = RegExp(r'\b(did|done|finished|completed|complete|called|sent|submitted|paid|booked|bought|cleared|ticked|tick|mark|marked|crossed|handled|wrapped|had|took|went|ran|met|wrote)\b').hasMatch(lower);
  if (!cue) return null;
  final List<String> words = _tokens(q, dropCues: true).where((String w) => w != 'tick').toList();
  if (words.isEmpty) return null;
  final ({String name, bool protocol, int score})? obj = _bestMatch(f.objectives, words, false);
  final ({String name, bool protocol, int score})? pro = _bestMatch(f.protocols, words, true);
  ({String name, bool protocol, int score})? pick;
  if (obj != null && (pro == null || obj.score > pro.score)) pick = obj;
  if (pro != null && (obj == null || pro.score > obj.score)) pick = pro;
  if (pick == null) return null; // nothing matched, or an exact tie: leave it to the model or the user
  return pick.protocol
      ? _plan('Checked ${pick.name}.', <Map<String, dynamic>>[
          <String, dynamic>{'type': 'check_protocol', 'name': pick.name},
        ])
      : _plan('Marked ${pick.name} as done.', <Map<String, dynamic>>[
          <String, dynamic>{'type': 'complete_objective', 'title': pick.name},
        ]);
}

// ----------------------------------------------------------------------------------------------- event

AgentPlan? _event(String q, String lower) {
  final bool verb = RegExp(r'\b(schedule|put|add|book|set up|create|block)\b').hasMatch(lower);
  final bool thing = RegExp(r'\b(meeting|appointment|event|calendar|call|lunch|dinner|catch ?up|interview|sync|standup|review|session)\b').hasMatch(lower);
  if (!verb || !thing) return null;
  final CaptureDraft d = CaptureParser.parse(q);
  final int? start = d.when;
  if (start == null) return null;
  final String? day = _day(lower);
  if (day == 'weekday') return null;
  int minutes = 30;
  final RegExpMatch? dur = RegExp(r'\bfor\s+(an?|one|\d+(?:\.\d+)?)\s*(hour|hr|hours|hrs|minute|min|minutes|mins)\b').firstMatch(lower);
  if (dur != null) {
    final String n = dur.group(1)!;
    final double v = (n == 'a' || n == 'an' || n == 'one') ? 1 : double.parse(n);
    minutes = (dur.group(2)!.startsWith('h') ? v * 60 : v).round();
  }
  final int end = (start + minutes).clamp(start + 5, 24 * 60);
  String title = q
      .replaceAll(RegExp(r'\b(schedule|put|add|book|set up|create|block)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\b(on|in|to)\s+my\s+(calendar|diary|schedule)\b', caseSensitive: false), ' ')
      .replaceAll(RegExp(r'\bfor\s+(an?|one|\d+(?:\.\d+)?)\s*(hour|hr|hours|hrs|minute|min|minutes|mins)\b', caseSensitive: false), ' ');
  title = _stripWhen(title).replaceAll(RegExp(r'^(a|an|the|my)\s+', caseSensitive: false), '').trim();
  if (title.isEmpty) return null;
  return _plan('Added ${title.toLowerCase()} at ${_hm(start)}${day == 'tomorrow' ? ' tomorrow' : ''}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'add_event', 'title': _cap(title), 'start': _hm(start), 'end': _hm(end), if (day != null) 'day': day},
  ]);
}

// ----------------------------------------------------------------------------------------------- task

AgentPlan? _task(String q, String lower) {
  final RegExpMatch? m = RegExp(
          r"^(?:please\s+)?(?:remind me to|remind me|remember to|add (?:a |an )?(?:task|todo|reminder|to-?do)(?: to| for| about)?|todo:?|to-?do:?|i need to|i have to|i must|i should|don't forget to|dont forget to)\s+(.+)$",
          caseSensitive: false)
      .firstMatch(q.trim());
  if (m == null) return null;
  final String body = m.group(1)!;
  final String bl = body.toLowerCase();
  final CaptureDraft d = CaptureParser.parse(body);
  final String? day = _day(bl);
  if (day == 'weekday') return null;
  final String title = _cap(_stripWhen(body));
  if (title.isEmpty) return null;
  final String threat = RegExp(r'\b(critical|urgent|asap)\b').hasMatch(bl) ? 'crit' : (RegExp(r'\b(important|high priority)\b').hasMatch(bl) ? 'high' : 'routine');
  final int? due = d.when;
  return _plan('Done. $title${due != null ? ', ${day == 'tomorrow' ? 'tomorrow ' : ''}at ${_hm(due)}' : (day == 'tomorrow' ? ', tomorrow' : '')}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'add_objective', 'title': title, if (due != null) 'due': _hm(due), if (day != null) 'day': day, if (threat != 'routine') 'threat': threat},
  ]);
}

// ----------------------------------------------------------------------------------------------- fuel

AgentPlan? _fuel(String q, String lower, BrainFacts f) {
  if (f.bikes.isEmpty) return null;
  if (!RegExp(r'\b(fill(?:ed)?|fuell?ed|refuell?ed|tank(?:ed)?|petrol|fuel|diesel|top(?:ped)?\s*up|poured|put)\b').hasMatch(lower)) return null;
  final RegExpMatch? lit = RegExp(r'(\d+(?:\.\d+)?)\s*(?:l|ltr|ltrs|litres?|liters?)\b').firstMatch(lower);
  if (lit == null) return null;
  final double litres = double.parse(lit.group(1)!);
  // The odometer reading: "at 9,412" or "9412 km".
  final RegExpMatch? odo = RegExp(r'\b(?:at|odometer|odo|reading|on)\s*(\d[\d,]*)\s*(?:km|kms)?\b|\b(\d[\d,]*)\s*(?:km|kms)\b').firstMatch(lower);
  final int? odometer = odo == null ? null : int.tryParse((odo.group(1) ?? odo.group(2))!.replaceAll(',', ''));
  // The amount: after "for", "rs", "₹" or "rupees".
  final String noOdo = odo == null ? lower : lower.replaceFirst(odo.group(0)!, ' ');
  final RegExpMatch? amt = RegExp(r'(?:₹|rs\.?\s*|inr\s*|rupees?\s*|for\s+)(\d[\d,]*(?:\.\d{1,2})?)').firstMatch(noOdo);
  if (amt == null) return null;
  final double amount = double.parse(amt.group(1)!.replaceAll(',', ''));
  if (amount <= 0 || litres <= 0) return null;
  String? bike;
  final Set<String> words = RegExp(r'[a-z0-9]+').allMatches(lower).map((Match m) => m.group(0)!).toSet();
  for (final String name in f.bikes) {
    if (RegExp(r'[a-z0-9]+').allMatches(name.toLowerCase()).any((Match m) => m.group(0)!.length >= 3 && words.contains(m.group(0)!))) {
      bike = name;
      break;
    }
  }
  final bool partial = RegExp(r'\b(partial|half|top(?:ped)?\s*up)\b').hasMatch(lower);
  final String lt = litres == litres.roundToDouble() ? litres.round().toString() : litres.toString();
  final String rs = amount == amount.roundToDouble() ? amount.round().toString() : amount.toStringAsFixed(2);
  return _plan('Logged $lt litres for ₹$rs${bike == null ? '' : ' on the ${bike.toLowerCase()}'}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'log_fill_up', if (bike != null) 'bike': bike, 'litres': litres, 'amount': amount, if (odometer != null) 'odometer': odometer, if (partial) 'full': false},
  ]);
}

// ----------------------------------------------------------------------------------------------- move an event

AgentPlan? _move(String q, String lower, BrainFacts f) {
  final RegExpMatch? m = RegExp(r'^(?:please\s+)?(?:move|reschedule|shift)\s+(.+?)\s+(?:to|till|until|at|for)\s+(.+)$', caseSensitive: false).firstMatch(q.trim());
  if (m == null) return null;
  final CaptureDraft d = CaptureParser.parse(m.group(2)!);
  final int? start = d.when;
  if (start == null) return null;
  final String? day = _day(m.group(2)!.toLowerCase());
  if (day == 'weekday') return null;
  final List<String> words = _tokens(m.group(1)!);
  if (words.isEmpty) return null;
  final ({String name, bool protocol, int score})? best = _bestMatch(<String>[for (final String e in f.events) e.replaceFirst(RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}\s+'), '')], words, false);
  if (best == null) return null;
  return _plan('Moved ${best.name.toLowerCase()} to ${_hm(start)}${day == 'tomorrow' ? ' tomorrow' : ''}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'move_event', 'title': best.name, 'start': _hm(start), if (day != null) 'day': day},
  ]);
}

/// Two changes in one sentence ("move gym to 9 and add a note"): K does one at a time.
AgentPlan? _oneAtATime(String lower) {
  const String verbs = r'(?:move|reschedule|add|log|remind|schedule|delete|remove|cancel|mark|set|book|put)';
  if (!RegExp('^(?:please\\s+)?$verbs\\b').hasMatch(lower)) return null;
  if (!RegExp('\\band\\s+(?:then\\s+)?$verbs\\b').hasMatch(lower)) return null;
  return _plan('I change one thing at a time. Which one first?', const <Map<String, dynamic>>[]);
}

// ----------------------------------------------------------------------------------------------- note

AgentPlan? _note(String q) {
  final RegExpMatch? m = RegExp(r'^(?:note|notes|jot down|write down|remember|idea)\s*(?:that|:|-)?\s*(.+)$', caseSensitive: false).firstMatch(q.trim());
  if (m == null) return null;
  final String text = m.group(1)!.trim();
  if (text.isEmpty) return null;
  return _plan('Noted.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'add_note', 'text': _cap(text)},
  ]);
}

// ----------------------------------------------------------------------------------------------- control of the rest of the app

const Map<String, String> _screenWords = <String, String>{
  'garage': 'garage', 'bikes': 'garage', 'my bike': 'garage', 'bike': 'garage',
  'objectives': 'objectives', 'tasks': 'objectives', 'ops': 'objectives', 'to-dos': 'objectives', 'todos': 'objectives',
  'timeline': 'timeline', 'calendar': 'timeline', 'schedule': 'timeline',
  'protocols': 'protocols', 'habits': 'protocols',
  'vitals': 'vitals', 'sleep': 'sleep',
  'ledger': 'ledger', 'money': 'ledger', 'spending': 'ledger', 'vault': 'ledger', 'expenses': 'ledger',
  'notes': 'notes', 'field log': 'notes',
  'loadout': 'loadout', 'settings': 'loadout',
  'notifications': 'inbox', 'inbox': 'inbox', 'alerts': 'inbox',
  'briefing': 'briefing', 'dawn briefing': 'briefing', 'morning briefing': 'briefing',
  'debrief': 'debrief', 'night debrief': 'debrief',
  'brain': 'brain', 'k brain': 'brain',
};

AgentPlan? _open(String q) {
  final RegExpMatch? m = RegExp(r'^(?:please\s+)?(?:open|go to|take me to|show me|show|switch to)\s+(?:the\s+|my\s+)?(.+?)(?:\s+(?:screen|page|tab|section))?\s*$', caseSensitive: false).firstMatch(q.trim());
  if (m == null) return null;
  final String key = _screenWords[m.group(1)!.toLowerCase().trim()] ?? '';
  final (String, String)? target = kScreens[key];
  if (target == null) return null;
  return _plan('Opening ${target.$2}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'open_screen', 'screen': key},
  ]);
}

const Map<String, String> _toggleWords = <String, String>{
  'sound effects': 'sfx', 'sound': 'sfx', 'sounds': 'sfx', 'sfx': 'sfx',
  'haptics': 'haptics', 'haptic': 'haptics', 'vibration': 'haptics', 'vibrations': 'haptics',
  'thunder effects': 'effects', 'effects': 'effects', 'lightning': 'effects', 'animations': 'effects',
  'spoken replies': 'spoken', 'voice replies': 'spoken', 'spoken': 'spoken', 'voice': 'spoken',
  'dawn briefing': 'dawn', 'morning briefing': 'dawn', 'briefing': 'dawn',
  'night debrief': 'debrief', 'evening debrief': 'debrief', 'debrief': 'debrief',
  'ops alerts': 'notifyOps', 'task alerts': 'notifyOps', 'objective alerts': 'notifyOps', 'ops notifications': 'notifyOps',
  'protocol alerts': 'notifyProtocols', 'habit alerts': 'notifyProtocols', 'habit reminders': 'notifyProtocols', 'protocol notifications': 'notifyProtocols',
};

AgentPlan? _toggle(String q) {
  final String t = q.trim();
  final RegExp a = RegExp(r'^(?:please\s+)?(?:turn|switch)\s+(on|off)\s+(?:the\s+|my\s+)?(.+)$', caseSensitive: false);
  final RegExp b = RegExp(r'^(?:please\s+)?(?:turn|switch)\s+(?:the\s+|my\s+)?(.+?)\s+(on|off)$', caseSensitive: false);
  final RegExp c = RegExp(r'^(?:please\s+)?(enable|disable|mute|unmute)\s+(?:the\s+|my\s+)?(.+)$', caseSensitive: false);
  String? name;
  bool? on;
  final RegExpMatch? ma = a.firstMatch(t);
  final RegExpMatch? mb = ma == null ? b.firstMatch(t) : null;
  final RegExpMatch? mc = ma == null && mb == null ? c.firstMatch(t) : null;
  if (ma != null) {
    on = ma.group(1)!.toLowerCase() == 'on';
    name = ma.group(2);
  } else if (mb != null) {
    on = mb.group(2)!.toLowerCase() == 'on';
    name = mb.group(1);
  } else if (mc != null) {
    final String v = mc.group(1)!.toLowerCase();
    on = v == 'enable' || v == 'unmute';
    name = mc.group(2);
  }
  if (name == null || on == null) return null;
  final String n = name.toLowerCase().trim();
  final String? key = _toggleWords[n];
  if (key == null) {
    if (RegExp(r'\b(vault|cloud|drive|backup|lock|key|password|biometric|fingerprint)\b').hasMatch(n)) {
      return _plan('That is a security or data setting, so it stays in Settings, in your hands.', const <Map<String, dynamic>>[]);
    }
    return null;
  }
  return _plan('${kToggleLabels[key]} ${on ? 'on' : 'off'}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'set_toggle', 'key': key, 'on': on},
  ]);
}

AgentPlan? _snooze(String q, BrainFacts f) {
  final RegExpMatch? m = RegExp(r'^(?:please\s+)?(?:snooze|postpone|delay)\s+(.+?)(?:\s+(?:for|by)\s+(half an?|an?|one|\d+)\s*(min\w*|hours?|hrs?))?\s*$', caseSensitive: false).firstMatch(q.trim());
  if (m == null) return null;
  int minutes = 60;
  final String? n = m.group(2)?.toLowerCase();
  if (n != null) {
    final bool hours = m.group(3)!.toLowerCase().startsWith('h');
    final double v = n.startsWith('half') ? 0.5 : (n == 'a' || n == 'an' || n == 'one' ? 1 : double.parse(n));
    minutes = (hours ? v * 60 : v).round();
  }
  if (minutes < 5 || minutes > 720) return _plan('I can snooze between 5 minutes and 12 hours.', const <Map<String, dynamic>>[]);
  final List<String> words = _tokens(m.group(1)!);
  final ({String name, bool protocol, int score})? best = words.isEmpty ? null : _bestMatch(f.objectives, words, false);
  if (best == null) return _plan('Which objective? Say its name as it is in Ops.', const <Map<String, dynamic>>[]);
  return _plan('Snoozed ${best.name.toLowerCase()} by $minutes minutes.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'snooze_objective', 'title': best.name, 'minutes': minutes},
  ]);
}

typedef _Hit = ({String name, bool protocol, int score});

AgentPlan? _delete(String q, BrainFacts f) {
  final RegExpMatch? m = RegExp(r'^(?:please\s+)?(?:delete|remove|cancel|scrap|drop)\s+(?:my\s+|the\s+)?(?:(task|objective|event|meeting|protocol|habit)\s+)?(.+)$', caseSensitive: false).firstMatch(q.trim());
  if (m == null) return null;
  final String noun = (m.group(1) ?? '').toLowerCase();
  final List<String> words = _tokens(m.group(2)!);
  if (words.isEmpty) return null;
  final bool any = noun.isEmpty;
  final _Hit? obj = any || noun == 'task' || noun == 'objective' ? _bestMatch(f.objectives, words, false) : null;
  final _Hit? ev = any || noun == 'event' || noun == 'meeting'
      ? _bestMatch(<String>[for (final String e in f.events) e.replaceFirst(RegExp(r'^\d{2}:\d{2}-\d{2}:\d{2}\s+'), '')], words, false)
      : null;
  final _Hit? pro = any || noun == 'protocol' || noun == 'habit' ? _bestMatch(f.protocols, words, true) : null;
  final List<(String, _Hit)> hits = <(String, _Hit)>[
    if (obj != null) ('delete_objective', obj),
    if (ev != null) ('delete_event', ev),
    if (pro != null) ('delete_protocol', pro),
  ];
  if (hits.isEmpty) return _plan('I could not find that to delete. Say its name as it appears in the app.', const <Map<String, dynamic>>[]);
  final int top = hits.map(((String, _Hit) h) => h.$2.score).reduce((int a, int b) => a > b ? a : b);
  final List<(String, _Hit)> best = hits.where(((String, _Hit) h) => h.$2.score == top).toList();
  if (best.length > 1) return _plan('That matches more than one thing. Say which: the task, the event or the protocol.', const <Map<String, dynamic>>[]);
  final String type = best.first.$1;
  final String name = best.first.$2.name;
  final String kind = type == 'delete_objective' ? 'task' : (type == 'delete_event' ? 'event' : 'protocol');
  return _plan('Deleted $name.', <Map<String, dynamic>>[
    <String, dynamic>{'type': type, (type == 'delete_protocol' ? 'name' : 'title'): name, 'ask': 'Delete the $kind "$name"? Say yes to confirm.'},
  ]);
}

AgentPlan? _budget(String q) {
  final RegExpMatch? m = RegExp(r'^(?:please\s+)?(?:set|change|update|make)\s+(?:my\s+|the\s+)?(?:monthly\s+)?budget\s+(?:to|at|as|of)?\s*(?:₹|rs\.?\s*|inr\s*)?(\d[\d,]*(?:\.\d+)?)\s*(k)?\b', caseSensitive: false).firstMatch(q.trim());
  if (m == null) return null;
  double v = double.parse(m.group(1)!.replaceAll(',', ''));
  if (m.group(2) != null) v *= 1000;
  if (v <= 0 || v > 10000000) return _plan('A budget has to be above zero.', const <Map<String, dynamic>>[]);
  return _plan('Monthly budget set to ${Fmt.money((v * 100).round())}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'set_budget', 'amount': v},
  ]);
}

AgentPlan? _addProtocol(String q) {
  final RegExpMatch? m = RegExp(r'^(?:please\s+)?(?:add|create|start|new)\s+(?:a\s+|an\s+)?(?:new\s+)?(?:protocol|habit)(?:\s+(?:called|named|for|to))?\s+(.+)$', caseSensitive: false).firstMatch(q.trim());
  if (m == null) return null;
  final String body = m.group(1)!;
  final CaptureDraft d = CaptureParser.parse(body);
  final String name = _cap(_stripWhen(body));
  if (name.isEmpty) return null;
  return _plan('Added the protocol $name${d.when != null ? ', reminder at ${_hm(d.when!)}' : ''}.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'add_protocol', 'name': name, if (d.when != null) 'remind': _hm(d.when!)},
  ]);
}

AgentPlan? _odometer(String q, String lower, BrainFacts f) {
  if (f.bikes.isEmpty || !RegExp(r'\b(odometer|odo)\b').hasMatch(lower)) return null;
  if (RegExp(r'\b(?:l|ltr|ltrs|litres?|liters?)\b').hasMatch(lower)) return null; // a fill-up
  final RegExpMatch? m = RegExp(r'\b(?:set|update|change|is|at|reads?|to)\s*(?:to|at)?\s*(\d[\d,]*)\s*(?:km|kms)?\s*$').firstMatch(lower);
  if (m == null) return null;
  final int km = int.parse(m.group(1)!.replaceAll(',', ''));
  String? bike;
  final Set<String> words = RegExp(r'[a-z0-9]+').allMatches(lower).map((Match x) => x.group(0)!).toSet();
  for (final String name in f.bikes) {
    if (RegExp(r'[a-z0-9]+').allMatches(name.toLowerCase()).any((Match x) => x.group(0)!.length >= 3 && words.contains(x.group(0)!))) {
      bike = name;
      break;
    }
  }
  return _plan('Odometer set to $km km.', <Map<String, dynamic>>[
    <String, dynamic>{'type': 'set_odometer', if (bike != null) 'bike': bike, 'km': km},
  ]);
}

// ----------------------------------------------------------------------------------------------- public

/// A question about the user's own data, which the router answers from the store with exact numbers.
bool isFactsQuestion(String utterance) {
  if (!isQuestionOnly(utterance)) return false;
  return RegExp(r'\b(water|hydrat\w*|steps?|walk\w*|sleep|slept|bed|bedtime|wake|spend|spent|spending|money|budget|ledger|expenses?|overdue|late|behind|plan|schedule|calendar|meetings?|events?|agenda|objectives?|tasks?|protocols?|habits?|bikes?|mileage|odometer|garage|fuel|petrol|insurance|puc)\b|\bmy day\b|\btoday\b|\btomorrow\b', caseSensitive: false).hasMatch(utterance);
}

/// Decides without the model when it can: [DecisionSource.rules] with a ready plan, [DecisionSource.router] for
/// questions about the user's data, or null to hand the utterance to the model.
Decision? decideWithoutModel(String utterance, BrainFacts facts) {
  final String q = utterance.trim();
  if (q.isEmpty) return null;
  final String lower = q.toLowerCase();
  if (isFactsQuestion(q)) return const Decision(DecisionSource.router, null);
  if (isQuestionOnly(q)) return null;
  final AgentPlan? plan = _oneAtATime(lower) ?? _open(q) ?? _toggle(q) ?? _snooze(q, facts) ?? _delete(q, facts) ?? _budget(q) ?? _addProtocol(q) ?? _odometer(q, lower, facts) ?? _move(q, lower, facts) ?? _water(q, lower) ?? _note(q) ?? _task(q, lower) ?? _event(q, lower) ?? _fuel(q, lower, facts) ?? _spend(q, lower) ?? _completion(q, lower, facts);
  return plan == null ? null : Decision(DecisionSource.rules, plan);
}

/// Keeps only what the user's own words support in a plan the model proposed: at most one action, and only if
/// its key words or numbers appear in the utterance. Returns the plan with the unsupported actions removed, and
/// [dropped] says whether anything was.
({AgentPlan plan, bool dropped}) validateModelPlan(AgentPlan plan, String utterance, BrainFacts facts) {
  final String lower = utterance.toLowerCase();
  if (isQuestionOnly(utterance)) return (plan: AgentPlan(plan.say, const <AgentAction>[]), dropped: plan.actions.isNotEmpty);
  bool grounded(AgentAction a) {
    final Map<String, dynamic> g = a.args;
    switch (a.type) {
      case 'log_water':
        return RegExp(r'\b(water|drank|drink|glass|bottle|ml|millilit\w*|litres?|hydrat\w*)\b').hasMatch(lower);
      case 'log_expense':
        final num? amt = g['amount'] is num ? g['amount'] as num : null;
        if (amt == null) return false;
        final String shown = amt == amt.roundToDouble() ? amt.round().toString() : amt.toString();
        return lower.replaceAll(',', '').contains(shown);
      case 'add_event':
        return _timeWords.hasMatch(lower) && RegExp(r'\b(meeting|appointment|event|calendar|call|lunch|dinner|schedule|book|put|add)\b').hasMatch(lower);
      case 'add_objective':
        return RegExp(r"\b(remind|task|todo|to-do|need to|have to|must|should|forget|going to|plan to|add|put|create|schedule|buy|book)\b").hasMatch(lower);
      case 'move_event':
        return _timeWords.hasMatch(lower) && RegExp(r'\b(move|reschedule|shift|push|change)\b').hasMatch(lower);
      case 'add_note':
        return RegExp(r'\b(note|remember|idea|jot|write down|memo)\b').hasMatch(lower);
      case 'complete_objective':
      case 'check_protocol':
        final String? name = (g['title'] ?? g['name']) as String?;
        if (name == null) return false;
        final Set<String> asked = _tokens(utterance, dropCues: true).toSet();
        return _tokens(name).any(asked.contains);
      default:
        return false;
    }
  }

  final List<AgentAction> ok = plan.actions.where(grounded).take(1).toList();
  return (plan: AgentPlan(plan.say, ok), dropped: ok.length != plan.actions.length);
}
