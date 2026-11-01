import 'dart:async';
import 'dart:math' show Random;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'network_api.dart';

class ApproximateLocation {
  final double latitude, longitude, accuracy;
  const ApproximateLocation(this.latitude, this.longitude, this.accuracy);
}

class LocationService {
  ApproximateLocation _cell(Position p) {
    // Match the backend's 0.01 degree grid before transmission, never send GPS.
    final lat = (p.latitude / .01).floor() * .01 + .005;
    final lon = (p.longitude / .01).floor() * .01 + .005;
    return ApproximateLocation(lat, lon, p.accuracy);
  }

  Future<ApproximateLocation> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const NetworkFailure(
        'خدمة الموقع متوقفة؛ يمكنك الاختبار دون مشاركة الموقع',
      );
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw const NetworkFailure(
        'لم يُمنح إذن الموقع. لن يُرسل موقع؛ يمكنك إجراء اختبار خاص',
      );
    }
    try {
      final p = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.lowest,
          timeLimit: Duration(seconds: 12),
        ),
      );
      return _cell(p);
    } on TimeoutException {
      final last = await Geolocator.getLastKnownPosition();
      if (last != null) return _cell(last);
      throw const NetworkFailure(
        'تعذر تحديد الموقع بسرعة؛ أوقف رسم الخريطة مؤقتًا أو فعّل GPS ثم أعد المحاولة',
      );
    }
  }
}

class SpeedResult {
  final double download, upload, ping, downloadSeconds, uploadSeconds;
  final int downloadBytes, uploadBytes;
  final String sessionId, connection, source;
  final DateTime time;
  final ApproximateLocation? location;
  SpeedResult({
    required this.download,
    required this.upload,
    required this.ping,
    required this.downloadSeconds,
    required this.uploadSeconds,
    required this.downloadBytes,
    required this.uploadBytes,
    required this.sessionId,
    required this.connection,
    required this.source,
    required this.time,
    this.location,
  });
  Map<String, dynamic> toJson({required bool share}) => {
    'session_id': sessionId,
    'download_mbps': download,
    'upload_mbps': upload,
    'ping_ms': ping,
    'download_seconds': downloadSeconds,
    'upload_seconds': uploadSeconds,
    'download_bytes': downloadBytes,
    'upload_bytes': uploadBytes,
    'connection_type': connection,
    'connection_source': source,
    'measurement_time': time.millisecondsSinceEpoch / 1000,
    'test_status': 'completed',
    'share_location': share,
    if (share && location != null) ...{
      'latitude': location!.latitude,
      'longitude': location!.longitude,
      'location_accuracy_m': location!.accuracy,
    },
  };
}

class SpeedTestService {
  final NetworkApi api;
  final http.Client Function() clientFactory;
  http.Client? _client;
  Completer<void>? _abort;
  bool _cancelled = false;
  Uri? _transferRoot;
  SpeedTestService(this.api, {http.Client Function()? clientFactory})
    : clientFactory = clientFactory ?? http.Client.new;
  void cancel() {
    _cancelled = true;
    if (_abort != null && !_abort!.isCompleted) _abort!.complete();
    _client?.close();
  }

  Future<SpeedResult> run({
    required void Function(String, double) onProgress,
    ApproximateLocation? location,
  }) async {
    _cancelled = false;
    if (api.token == null) {
      throw const NetworkFailure('سجّل الدخول بالخادم قبل إجراء الاختبار');
    }
    final config = await api.config();
    if (_cancelled) throw const NetworkFailure('أُلغي الاختبار قبل بدء النقل');
    final test = config['test'] as Map;
    final mode = test['mode'] as String? ?? '';
    if (test['available'] != true || (mode != 'internet' && mode != 'local')) {
      throw NetworkFailure(test['reason'] ?? 'اختبار الإنترنت غير متاح');
    }
    final declared = Uri.tryParse(test['server_id'] as String? ?? '');
    if (declared == null || declared.host.isEmpty) {
      throw const NetworkFailure('خادم القياس غير معرّف');
    }
    _transferRoot = declared.scheme == 'https'
        ? declared
        : Uri.parse(api.baseUrl);
    _client = clientFactory();
    _abort = Completer<void>();
    final deadline = Timer(
      Duration(seconds: (test['max_seconds'] as num).toInt().clamp(1, 90)),
      cancel,
    );
    try {
      final session = await api.request('/api/speed/sessions', method: 'POST');
      final sid = session['session_id'] as String;
      final headers = <String, String>{
        'Authorization': 'Bearer ${api.token}',
        'X-Test-Session': sid,
        'Cache-Control': 'no-cache',
      };
      onProgress('التحقق من مسار القياس', 0.02);
      await _send('GET', '/api/speed/ping', headers, seconds: 10);
      final rtts = <double>[];
      for (var i = 0; i < 8; i++) {
        onProgress('قياس زمن الاستجابة HTTP', i / 8 * .15);
        final watch = Stopwatch()..start();
        await _send('GET', '/api/speed/ping', headers, seconds: 10);
        if (i > 0) rtts.add(watch.elapsedMicroseconds / 1000);
      }
      final random = Random.secure();
      final payload = Uint8List.fromList(
        List.generate(2 * 1024 * 1024, (_) => random.nextInt(256)),
      );
      final phaseCap = (test['phase_max_bytes'] as num).toInt().clamp(
        4 * 1024 * 1024,
        32 * 1024 * 1024,
      );
      final target = (test['target_seconds'] as num).toDouble();
      Future<(int, double)> transfer(bool down) async {
        var count = 0;
        final watch = Stopwatch()..start();
        while (count < phaseCap &&
            (watch.elapsedMicroseconds / 1e6 < target ||
                count < 4 * 1024 * 1024)) {
          if (_cancelled) {
            throw const NetworkFailure(
              'أُلغي الاختبار أو انتهت مدته؛ لا توجد نتيجة مكتملة',
            );
          }
          onProgress(
            down
                ? 'قياس التنزيل بنقل بيانات فعلية'
                : 'قياس الرفع بنقل بيانات فعلية',
            (down ? .15 : .55) + .38 * (count / phaseCap),
          );
          final sent = await _send(
            down ? 'GET' : 'POST',
            down ? '/api/speed/download' : '/api/speed/upload',
            headers,
            body: down ? null : payload,
            seconds: 45,
          );
          count += down ? sent : payload.length;
        }
        final seconds = watch.elapsedMicroseconds / 1e6;
        if (count < 4 * 1024 * 1024 || seconds <= 0) {
          throw const NetworkFailure(
            'حجم النقل أقل من الحد الأدنى؛ لن تُقبل النتيجة',
          );
        }
        return (count, seconds);
      }

      final down = await transfer(true), up = await transfer(false);
      var connection = 'unknown';
      if (!kIsWeb) {
        try {
          final types = await Connectivity().checkConnectivity();
          if (types.contains(ConnectivityResult.wifi)) {
            connection = 'wifi';
          } else if (types.contains(ConnectivityResult.mobile)) {
            connection = 'cellular';
          } else if (types.contains(ConnectivityResult.ethernet)) {
            connection = 'ethernet';
          }
        } catch (_) {
          connection = 'unknown';
        }
      }
      rtts.sort();
      if (rtts.isEmpty) {
        throw const NetworkFailure('تعذر قياس زمن الاستجابة');
      }
      onProgress('اكتمل القياس', 1);
      return SpeedResult(
        download: down.$1 * 8 / down.$2 / 1e6,
        upload: up.$1 * 8 / up.$2 / 1e6,
        ping: rtts[rtts.length ~/ 2],
        downloadSeconds: down.$2,
        uploadSeconds: up.$2,
        downloadBytes: down.$1,
        uploadBytes: up.$1,
        sessionId: sid,
        connection: connection,
        source: connection == 'unknown' ? 'unavailable' : 'os_interface',
        time: DateTime.now().toUtc(),
        location: location,
      );
    } on NetworkFailure {
      rethrow;
    } on TimeoutException {
      throw const NetworkFailure(
        'انتهت مهلة الاتصال بخادم القياس؛ لم تُحفظ نتيجة',
      );
    } on http.ClientException {
      throw NetworkFailure(
        _cancelled
            ? 'أُلغي الاختبار أو انتهت مدته'
            : 'انقطع الاتصال بخادم القياس أثناء النقل',
      );
    } catch (_) {
      throw NetworkFailure(
        _cancelled
            ? 'أُلغي الاختبار أو انتهت مدته'
            : 'انقطع الاختبار؛ لم تُنشأ أو تُحفظ نتيجة مكتملة',
      );
    } finally {
      deadline.cancel();
      _client?.close();
      _client = null;
    }
  }

  Future<int> _send(
    String method,
    String path,
    Map<String, String> headers, {
    Uint8List? body,
    int seconds = 45,
  }) async {
    if (_cancelled) throw const NetworkFailure('تم إلغاء الاختبار');
    final root = (_transferRoot ?? Uri.parse(api.baseUrl))
        .toString()
        .replaceAll(RegExp(r'/$'), '');
    final req = http.AbortableRequest(
      method,
      Uri.parse('$root$path'),
      abortTrigger: _abort!.future,
    )..headers.addAll({
        ...headers,
        'bypass-tunnel-reminder': 'true',
      });
    if (body != null) {
      req.headers['Content-Type'] = 'application/octet-stream';
      req.bodyBytes = body;
    }
    final limit = Duration(seconds: seconds);
    final response = await _client!.send(req).timeout(limit);
    if (response.headers['content-encoding'] != null &&
        response.headers['content-encoding'] != 'identity') {
      throw const NetworkFailure(
        'رفض نتيجة نقل مضغوط؛ تحقق من إعداد خادم القياس',
      );
    }
    if (response.statusCode != 200) {
      throw const NetworkFailure('رفض خادم القياس النقل أو انتهت ميزانيته');
    }
    var bytes = 0;
    await for (final chunk in response.stream.timeout(limit)) {
      bytes += chunk.length;
    }
    if (method == 'GET' &&
        path.endsWith('download') &&
        bytes != 2 * 1024 * 1024) {
      throw const NetworkFailure('تنزيل ناقص؛ لن تُقبل النتيجة');
    }
    return bytes;
  }
}
