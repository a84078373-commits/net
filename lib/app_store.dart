import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appStore = AppStore();
const neighborhoods = ['المنتزه', 'النقرة', 'الجامعيين', 'وسط حائل'];
String dateLabel(DateTime date) =>
    '${date.day}/${date.month}/${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';

class CareReport {
  final String id, description, area, category, recommendation;
  final DateTime created;
  String status;
  CareReport({
    required this.id,
    required this.description,
    required this.area,
    required this.category,
    required this.recommendation,
    required this.created,
    this.status = 'بانتظار الربط',
  });
  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'area': area,
    'category': category,
    'recommendation': recommendation,
    'created': created.toIso8601String(),
    'status': status,
  };
  factory CareReport.fromJson(Map<String, dynamic> j) => CareReport(
    id: j['id'],
    description: j['description'],
    area: j['area'],
    category: j['category'],
    recommendation: j['recommendation'],
    created: DateTime.parse(j['created']),
    status: j['status'],
  );
}

class Measurement {
  final DateTime created;
  final String area;
  final double download, upload;
  final int latency;
  Measurement({
    required this.created,
    required this.area,
    this.download = 248.6,
    this.upload = 42.8,
    this.latency = 18,
  });
  Map<String, dynamic> toJson() => {
    'created': created.toIso8601String(),
    'area': area,
    'download': download,
    'upload': upload,
    'latency': latency,
  };
  factory Measurement.fromJson(Map<String, dynamic> j) => Measurement(
    created: DateTime.parse(j['created']),
    area: j['area'],
    download: (j['download'] as num).toDouble(),
    upload: (j['upload'] as num).toDouble(),
    latency: j['latency'],
  );
}

class CareNotice {
  final String title, body;
  final DateTime created;
  bool read;
  CareNotice(this.title, this.body, {DateTime? created, this.read = false})
    : created = created ?? DateTime.now();
  Map<String, dynamic> toJson() => {
    'title': title,
    'body': body,
    'created': created.toIso8601String(),
    'read': read,
  };
  factory CareNotice.fromJson(Map<String, dynamic> j) => CareNotice(
    j['title'],
    j['body'],
    created: DateTime.parse(j['created']),
    read: j['read'],
  );
}

class AppStore extends ChangeNotifier {
  SharedPreferences? _prefs;
  final reports = <CareReport>[];
  final measurements = <Measurement>[];
  final notices = <CareNotice>[];
  String name = 'زائر SmartCare', phone = '', area = neighborhoods.first;
  bool signedIn = false, notifications = true, autoSave = true;
  bool storageFailed = false;
  DateTime? lastSaved;
  int get unread => notices.where((n) => !n.read).length;
  Future<void> load() async {
    try {
      _prefs = await SharedPreferences.getInstance();
      final text = _prefs!.getString('smartcare.v1');
      if (text != null) {
        final j = jsonDecode(text) as Map<String, dynamic>;
        name = j['name'];
        phone = j['phone'];
        area = j['area'];
        signedIn = j['signedIn'] == true;
        notifications = j['notifications'];
        autoSave = j['autoSave'];
        reports.addAll(
          (j['reports'] as List).map((r) => CareReport.fromJson(r)),
        );
        measurements.addAll(
          (j['measurements'] as List).map((m) => Measurement.fromJson(m)),
        );
        notices.addAll(
          (j['notices'] as List).map((n) => CareNotice.fromJson(n)),
        );
        lastSaved = DateTime.tryParse(j['saved'] ?? '');
      }
    } catch (_) {
      storageFailed = true;
    }
    notifyListeners();
  }

  Future<void> save() async {
    try {
      if (_prefs != null) {
        final now = DateTime.now();
        final ok = await _prefs!.setString(
          'smartcare.v1',
          jsonEncode({
            'name': name,
            'phone': phone,
            'area': area,
            'signedIn': signedIn,
            'notifications': notifications,
            'autoSave': autoSave,
            'reports': reports.map((r) => r.toJson()).toList(),
            'measurements': measurements.map((m) => m.toJson()).toList(),
            'notices': notices.map((n) => n.toJson()).toList(),
            'saved': now.toIso8601String(),
          }),
        );
        if (!ok) throw StateError('Storage unavailable');
        lastSaved = now;
        storageFailed = false;
      }
    } catch (_) {
      storageFailed = true;
    }
    notifyListeners();
  }

  void changed() {
    notifyListeners();
    if (autoSave) save();
  }

  void addNotice(String title, String body) {
    if (notifications) notices.insert(0, CareNotice(title, body));
  }

  CareReport addReport(
    String text, {
    String? selectedArea,
    String category = 'بطء الإنترنت',
    String recommendation = '',
  }) {
    final r = CareReport(
      id: 'SC-${DateTime.now().microsecondsSinceEpoch}',
      description: text,
      area: selectedArea ?? area,
      category: category,
      recommendation: recommendation,
      created: DateTime.now(),
    );
    reports.insert(0, r);
    addNotice(
      'تم حفظ بلاغك',
      'البلاغ محفوظ على جهازك بانتظار الربط بخدمة الدعم.',
    );
    changed();
    return r;
  }

  void addMeasurement(String selectedArea) {
    measurements.insert(
      0,
      Measurement(created: DateTime.now(), area: selectedArea),
    );
    addNotice('اكتمل الاختبار التجريبي', 'أضفنا النتيجة إلى سجل القياسات.');
    changed();
  }

  void updateStatus(CareReport r, String status) {
    r.status = status;
    addNotice('تحديث حالة البلاغ', 'حالة البلاغ المحلية: $status');
    changed();
  }

  void signOut() {
    signedIn = false;
    changed();
  }
}
