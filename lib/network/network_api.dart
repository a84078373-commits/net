import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

final networkApi = NetworkApi();

class NetworkFailure implements Exception {
  final String message;
  const NetworkFailure(this.message);
  @override
  String toString() => message;
}

class AuthRegister {
  final String firstName, secondName, familyName, gender;
  const AuthRegister({
    required this.firstName,
    required this.secondName,
    required this.familyName,
    required this.gender,
  });
  Map<String, dynamic> toJson() => {
    'first_name': firstName,
    'second_name': secondName,
    'family_name': familyName,
    'gender': gender,
  };
}

class NetworkApi extends ChangeNotifier {
  final String baseUrl;
  http.Client client;
  String? token;
  Map<String, dynamic>? user, configuration;
  NetworkApi({
    this.baseUrl = const String.fromEnvironment(
      'SMARTCARE_API_URL',
      defaultValue: 'https://net-71nf.onrender.com',
    ),
    http.Client? client,
  }) : client = client ?? http.Client();
  Map<String, String> get headers => {
    'Content-Type': 'application/json',
    if (token != null) 'Authorization': 'Bearer $token',
  };
  Uri uri(String path, [Map<String, String>? query]) {
    final root = Uri.parse(baseUrl);
    if (root.scheme != 'https' &&
        !(root.scheme == 'http' &&
            const [
              'localhost',
              '127.0.0.1',
              '::1',
              '10.0.2.2',
            ].contains(root.host))) {
      throw const NetworkFailure(
        'عنوان الخدمة يحتاج HTTPS؛ HTTP مسموح فقط للتطوير على الجهاز نفسه',
      );
    }
    return Uri.parse(
      '${baseUrl.replaceAll(RegExp(r'/$'), '')}$path',
    ).replace(queryParameters: query);
  }

  Future<Map<String, dynamic>> request(
    String path, {
    String method = 'GET',
    Map<String, dynamic>? body,
    Map<String, String>? query,
  }) async {
    try {
      final target = uri(path, query);
      late final http.Response response;
      if (method == 'POST') {
        response = await client
            .post(target, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 45));
      } else if (method == 'PUT') {
        response = await client
            .put(target, headers: headers, body: jsonEncode(body ?? {}))
            .timeout(const Duration(seconds: 45));
      } else if (method == 'DELETE') {
        response = await client
            .delete(target, headers: headers)
            .timeout(const Duration(seconds: 45));
      } else {
        response = await client
            .get(target, headers: headers)
            .timeout(const Duration(seconds: 45));
      }
      if (response.statusCode == 401) {
        token = null;
        user = null;
        notifyListeners();
      }
      final json = response.body.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
      if (response.statusCode >= 400) {
        throw NetworkFailure(
          json['detail'] is String
              ? json['detail']
              : 'رفض الخادم الطلب؛ تحقق من الحقول والاتصال',
        );
      }
      return json;
    } on NetworkFailure {
      rethrow;
    } on TimeoutException {
      throw const NetworkFailure(
        'انتهت مهلة الخدمة؛ خادم Render قد يكون في إقلاع أول، أعد المحاولة خلال ثوانٍ',
      );
    } catch (_) {
      throw const NetworkFailure(
        'تعذر الاتصال بخدمة الشبكة. تحقق من اتصالك وإعداد عنوان API',
      );
    }
  }

  Future<Map<String, dynamic>> config() async {
    configuration = await request('/api/network-config');
    return configuration!;
  }

  Future<void> authenticate(
    String phone,
    String password, {
    AuthRegister? register,
  }) async {
    final result = await request(
      register == null ? '/api/auth/login' : '/api/auth/register',
      method: 'POST',
      body: {
        'phone': phone,
        'password': password,
        if (register != null) ...register.toJson(),
      },
    );
    token = result['token'];
    user = Map<String, dynamic>.from(result['user']);
    notifyListeners();
  }

  Future<void> signOut() async {
    try {
      if (token != null) await request('/api/auth/session', method: 'DELETE');
    } catch (_) {
      // Local logout must still succeed offline; server sessions expire in 15 minutes.
    } finally {
      token = null;
      user = null;
      notifyListeners();
    }
  }

  bool get isAdmin => user?['is_admin'] == true;
}

class MapFilters {
  DateTime start, end;
  int? rollingDays;
  String metric = 'download', connection = 'all';
  int minSamples = 5;
  double minDownload = 0, maxPing = 10000;
  MapFilters({DateTime? start, DateTime? end})
    : rollingDays = start == null && end == null ? 7 : null,
      start = start ?? DateTime.now().toUtc().subtract(const Duration(days: 7)),
      end = end ?? DateTime.now().toUtc();
  Map<String, String> query(List<double> bounds) {
    if (rollingDays != null) {
      end = DateTime.now().toUtc();
      start = end.subtract(Duration(days: rollingDays!));
    }
    return {
      'start': '${start.millisecondsSinceEpoch / 1000}',
      'end': '${end.millisecondsSinceEpoch / 1000}',
      'bbox': bounds.join(','),
      'metric': metric,
      'connection': connection,
      'min_samples': '$minSamples',
      'min_download': '$minDownload',
      'max_ping': '$maxPing',
    };
  }
}

class QualityCell {
  final Map<String, dynamic> data;
  QualityCell(this.data);
  String get id => data['id'];
  String get status => data['status'];
  List<double> get bounds =>
      (data['bounds'] as List).map((v) => (v as num).toDouble()).toList();
  int? get count => data['sample_count'];
  String quality(String metric) => status == 'insufficient' || status == 'stale'
      ? status
      : (data['quality']?[metric] ?? 'insufficient');
  double? value(String metric, String aggregate) =>
      (data['statistics']?[metric]?[aggregate] as num?)?.toDouble();
}
