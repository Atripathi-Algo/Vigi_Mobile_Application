import 'dart:convert';

/// The service's own error message from a failed response, shortened; the start of the body if it has none.
/// Handles Google (`error.message`), OpenAI-style and Anthropic (`error.message`) and plain `error` strings.
String apiErrorMessage(String body) {
  String msg = body;
  try {
    final dynamic j = jsonDecode(body);
    final dynamic err = j is Map ? j['error'] : null;
    if (err is Map && err['message'] is String) {
      msg = err['message'] as String;
    } else if (err is String) {
      msg = err;
    }
  } catch (_) {}
  msg = msg.replaceAll(RegExp(r'\s+'), ' ').trim();
  return msg.length > 160 ? '${msg.substring(0, 160)}…' : msg;
}
