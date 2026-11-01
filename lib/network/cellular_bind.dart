import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CellularBind {
  static const _channel = MethodChannel('smartcare/cellular');
  static Future<bool> request() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    try {
      await _channel.invokeMethod('bind').timeout(const Duration(seconds: 12));
      return true;
    } on PlatformException catch (e) {
      throw NetworkBindFailure(
        e.message ??
            'بيانات الجوال غير متاحة. فعّل شبكة الجوال ثم أعد المحاولة',
      );
    } on MissingPluginException {
      return false;
    }
  }

  static Future<void> release() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    try {
      await _channel.invokeMethod('unbind');
    } catch (_) {}
  }
}

class NetworkBindFailure implements Exception {
  final String message;
  const NetworkBindFailure(this.message);
  @override
  String toString() => message;
}
