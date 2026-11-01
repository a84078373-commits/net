import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:geolocator/geolocator.dart';
import 'package:smartcare/network/network_api.dart';
import 'package:smartcare/network/speed_test_service.dart';

class DeniedLocation extends GeolocatorPlatform {
  @override
  Future<bool> isLocationServiceEnabled() async => true;
  @override
  Future<LocationPermission> checkPermission() async =>
      LocationPermission.denied;
  @override
  Future<LocationPermission> requestPermission() async =>
      LocationPermission.denied;
}

Map<String, dynamic> config({bool available = true}) => {
  'test': {
    'server_id': 'https://speed.test.invalid',
    'available': available,
    'mode': 'internet',
    'reason': 'الخدمة غير متاحة',
    'max_seconds': 15,
    'phase_max_bytes': 4194304,
    'target_seconds': 0.01,
    'min_phase_seconds': 1.5,
  },
};
NetworkApi apiForTest({bool available = true}) => NetworkApi(
  baseUrl: 'https://speed.test.invalid',
  client: MockClient((request) async {
    if (request.url.path == '/api/network-config') {
      return http.Response(
        jsonEncode(config(available: available)),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }
    return http.Response(
      jsonEncode({'session_id': 'isolated-test-session-id-12345'}),
      201,
    );
  }),
)..token = 'test-only';
void main() {
  test(
    'Rolling dates refresh for new measurements while custom dates stay fixed',
    () {
      final rolling = MapFilters()..end = DateTime.utc(2020);
      rolling.query([41.6, 27.4, 41.8, 27.6]);
      expect(rolling.end.isAfter(DateTime.utc(2026)), true);
      final custom = MapFilters(
        start: DateTime.utc(2026, 1, 1),
        end: DateTime.utc(2026, 1, 8),
      );
      custom.query([41.6, 27.4, 41.8, 27.6]);
      expect(custom.end, DateTime.utc(2026, 1, 8));
    },
  );
  test('Unavailable service never creates a synthetic result', () async {
    final api = apiForTest(available: false);
    final service = SpeedTestService(
      api,
      clientFactory: () => throw StateError('No transfer permitted'),
    );
    await expectLater(
      service.run(onProgress: (_, __) {}),
      throwsA(isA<NetworkFailure>()),
    );
  });
  test('Throughput uses transferred bytes and measured elapsed time', () async {
    var downBytes = 0, upBytes = 0;
    final api = apiForTest();
    final service = SpeedTestService(
      api,
      clientFactory: () => MockClient((request) async {
        if (request.url.path.endsWith('ping')) return http.Response('{}', 200);
        await Future<void>.delayed(const Duration(milliseconds: 1600));
        if (request.method == 'GET') {
          downBytes += 2097152;
          return http.Response.bytes(Uint8List(2097152), 200);
        }
        upBytes += request.bodyBytes.length;
        return http.Response('{}', 200);
      }),
    );
    final result = await service.run(onProgress: (_, __) {});
    expect(result.downloadBytes, downBytes);
    expect(result.uploadBytes, upBytes);
    expect(
      result.download,
      closeTo(downBytes * 8 / result.downloadSeconds / 1000000, 0.00001),
    );
    expect(result.downloadSeconds, greaterThanOrEqualTo(1.5));
    expect(result.toJson(share: false).containsKey('latitude'), false);
    expect(result.toJson(share: false).containsKey('carrier_name'), false);
    expect(
      result.toJson(share: false).containsKey('packet_loss_percent'),
      false,
    );
  });
  test('Interruption yields an error, never a completed measurement', () async {
    final service = SpeedTestService(
      apiForTest(),
      clientFactory: () =>
          MockClient((request) async => throw http.ClientException('offline')),
    );
    await expectLater(
      service.run(onProgress: (_, __) {}),
      throwsA(isA<NetworkFailure>()),
    );
  });
  test('Cancellation cannot return a successful result', () async {
    late SpeedTestService service;
    service = SpeedTestService(
      apiForTest(),
      clientFactory: () => MockClient((request) async {
        service.cancel();
        throw http.ClientException('cancelled');
      }),
    );
    await expectLater(
      service.run(onProgress: (_, __) {}),
      throwsA(isA<NetworkFailure>()),
    );
  });
  test('Denied location permission yields no approximate location', () async {
    final previous = GeolocatorPlatform.instance;
    GeolocatorPlatform.instance = DeniedLocation();
    addTearDown(() => GeolocatorPlatform.instance = previous);
    await expectLater(
      LocationService().locate(),
      throwsA(isA<NetworkFailure>()),
    );
  });
  test('API filters use selected bounds, dates and actual constraints', () {
    final f =
        MapFilters(
            start: DateTime.utc(2026, 10, 1),
            end: DateTime.utc(2026, 10, 8),
          )
          ..metric = 'ping'
          ..connection = 'wifi'
          ..minSamples = 10
          ..maxPing = 50;
    final q = f.query([41.6, 27.4, 41.8, 27.6]);
    expect(q['metric'], 'ping');
    expect(q['connection'], 'wifi');
    expect(q['min_samples'], '10');
    expect(q['max_ping'], '50.0');
    expect(q['bbox'], '41.6,27.4,41.8,27.6');
  });
}
