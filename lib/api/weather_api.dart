import 'dart:convert';

import 'package:http/http.dart' as http;

import '../app/env.dart';

class Weather {
  const Weather(this.tempC, this.code);

  final double tempC;
  final int code;

  String get summary => switch (code) {
        0 => 'CLEAR',
        1 || 2 || 3 => 'CLOUDY',
        45 || 48 => 'FOG',
        >= 51 && <= 67 => 'RAIN',
        >= 71 && <= 77 => 'SNOW',
        >= 80 && <= 82 => 'SHOWERS',
        >= 95 => 'STORM',
        _ => 'MIXED',
      };
}

/// Open-Meteo current conditions (no API key). Base URL comes from `.env`.
/// Returns null on any failure so the Briefing falls back to the SLEEP tile.
Future<Weather?> fetchWeather() async {
  try {
    final Uri uri = Uri.parse(Env.weatherBaseUrl).replace(queryParameters: <String, String>{
      'latitude': '${Env.weatherLat}',
      'longitude': '${Env.weatherLon}',
      'current': 'temperature_2m,weather_code',
    });
    final http.Response r = await http.get(uri).timeout(const Duration(seconds: 6));
    if (r.statusCode != 200) return null;
    final Map<String, dynamic> cur = (jsonDecode(r.body) as Map<String, dynamic>)['current'] as Map<String, dynamic>;
    return Weather((cur['temperature_2m'] as num).toDouble(), (cur['weather_code'] as num).toInt());
  } catch (_) {
    return null;
  }
}
