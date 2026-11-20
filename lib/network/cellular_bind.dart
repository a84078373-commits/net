import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import '../app_store.dart';
import '../l10n/app_localizations.dart';

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
            AppLocalizations(appStore.locale).cellularDataUnavailable,
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
