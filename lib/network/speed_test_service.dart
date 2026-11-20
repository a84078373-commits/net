import 'dart:async';
import 'dart:math' show Random;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import '../app_store.dart';
import '../l10n/app_localizations.dart';
import 'network_api.dart';

AppLocalizations get _l10n => AppLocalizations(appStore.locale);

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

  /// Max horizontal accuracy (meters) accepted for ~1 km map cells.
  static const maxShareAccuracyM = 2000.0;

  Future<ApproximateLocation> locate() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw NetworkFailure(_l10n.locationServiceDisabled);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      throw NetworkFailure(_l10n.locationPermissionDenied);
    }
    Position? best;
    try {
      // Prefer a real GPS/network fix — LocationAccuracy.lowest often returns
      // city-level estimates (>2 km) that the server rejects for cell mapping.
      best = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 20),
          distanceFilter: 0,
        ),
      );
    } on TimeoutException {
      best = await Geolocator.getLastKnownPosition();
    } catch (_) {
      best = await Geolocator.getLastKnownPosition();
    }
    if (best == null) {
      throw NetworkFailure(_l10n.locationUnavailable);
    }
    if (best.accuracy > maxShareAccuracyM) {
      throw NetworkFailure(
        _l10n.locationAccuracyPoor(best.accuracy.round()),
      );
    }
    return _cell(best);
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
      throw NetworkFailure(_l10n.signInBeforeTest);
    }
    final config = await api.config();
    if (_cancelled) {
      throw NetworkFailure(_l10n.testCancelledBeforeTransfer);
    }
    final test = config['test'] as Map;
    final mode = test['mode'] as String? ?? '';
    if (test['available'] != true || (mode != 'internet' && mode != 'local')) {
      throw NetworkFailure(
        test['reason']?.toString() ?? _l10n.testUnavailableDefault,
      );
    }
    final declared = Uri.tryParse(test['server_id'] as String? ?? '');
    if (declared == null || declared.host.isEmpty) {
      throw NetworkFailure(_l10n.measurementServerUndefined);
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
      onProgress(_l10n.phaseVerifyPath, 0.02);
      await _send('GET', '/api/speed/ping', headers, seconds: 10);
      final rtts = <double>[];
      for (var i = 0; i < 8; i++) {
        onProgress(_l10n.phaseHttpLatency, i / 8 * .15);
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
            throw NetworkFailure(_l10n.testIncompleteCancelled);
          }
          onProgress(
            down ? _l10n.phaseDownload : _l10n.phaseUpload,
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
          throw NetworkFailure(_l10n.transferTooSmall);
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
        throw NetworkFailure(_l10n.latencyMeasureFailed);
      }
      onProgress(_l10n.phaseComplete, 1);
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
      throw NetworkFailure(_l10n.measurementServerTimeout);
    } on http.ClientException {
      throw NetworkFailure(
        _cancelled
            ? _l10n.testIncompleteCancelled
            : _l10n.measurementServerDisconnected,
      );
    } catch (_) {
      throw NetworkFailure(
        _cancelled ? _l10n.testIncompleteCancelled : _l10n.testInterrupted,
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
    if (_cancelled) throw NetworkFailure(_l10n.testCancelled);
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
      throw NetworkFailure(_l10n.compressedTransferRejected);
    }
    if (response.statusCode != 200) {
      throw NetworkFailure(_l10n.transferRejected);
    }
    var bytes = 0;
    await for (final chunk in response.stream.timeout(limit)) {
      bytes += chunk.length;
    }
    if (method == 'GET' &&
        path.endsWith('download') &&
        bytes != 2 * 1024 * 1024) {
      throw NetworkFailure(_l10n.downloadIncomplete);
    }
    return bytes;
  }
}
