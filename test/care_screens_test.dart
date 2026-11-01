import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smartcare/app_store.dart';
import 'package:smartcare/care_screens.dart';
import 'package:smartcare/main.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:smartcare/network/network_api.dart';

void main() {
  testWidgets('Create a report and close it from its detail screen', (
    tester,
  ) async {
    appStore.autoSave = false;
    appStore.reports.clear();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Directionality(
          textDirection: TextDirection.rtl,
          child: NewReportScreen(),
        ),
      ),
    );
    await tester.enterText(
      find.byType(TextFormField),
      'انقطاع متكرر في الإنترنت مساءً في المنزل',
    );
    await tester.ensureVisible(find.text('حفظ البلاغ على الجهاز'));
    await tester.tap(find.text('حفظ البلاغ على الجهاز'));
    await tester.pumpAndSettle();
    expect(appStore.reports, hasLength(1));
    expect(find.byType(ReportDetailScreen), findsOneWidget);
    await tester.ensureVisible(find.text('إغلاق البلاغ محليًا'));
    await tester.tap(find.text('إغلاق البلاغ محليًا'));
    await tester.pumpAndSettle();
    expect(appStore.reports.single.status, 'مغلق تجريبيًا');
    expect(find.text('إعادة فتح محليًا'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  test('Reports, profile, status and measurements survive reopening', () async {
    SharedPreferences.setMockInitialValues({});
    final first = AppStore();
    await first.load();
    first.autoSave = false;
    first.name = 'أحمد';
    first.area = 'النقرة';
    final report = first.addReport(
      'ضعف مستمر في الإشارة داخل المنزل',
      selectedArea: 'النقرة',
      category: 'ضعف الإشارة',
    );
    first.updateStatus(report, 'قيد المراجعة التجريبية');
    first.addMeasurement('النقرة');
    await first.save();
    final reopened = AppStore();
    await reopened.load();
    expect(reopened.name, 'أحمد');
    expect(reopened.reports.single.id, report.id);
    expect(reopened.reports.single.status, 'قيد المراجعة التجريبية');
    expect(reopened.measurements.single.area, 'النقرة');
    expect(reopened.storageFailed, false);
  });

  for (final width in [320.0, 1440.0]) {
    testWidgets('All new screens lay out at width $width', (tester) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      appStore.autoSave = false;
      appStore.reports.clear();
      appStore.measurements.clear();
      appStore.notices.clear();
      final report = appStore.addReport(
        'انقطاع متكرر في الشبكة مساءً داخل المنزل',
        category: 'اتصال غير مستقر',
      );
      appStore.addMeasurement('المنتزه');
      for (final screen in <Widget>[
        const MoreScreen(),
        const AuthScreen(),
        const ProfileScreen(),
        const SettingsScreen(),
        const NewReportScreen(),
        ReportDetailScreen(report: report),
        const HistoryScreen(),
        const NoticesScreen(),
        const SyncScreen(),
        const AdminScreen(),
        const HelpScreen(),
        const PrivacyScreen(),
      ]) {
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark(useMaterial3: true),
            home: Directionality(
              textDirection: TextDirection.rtl,
              child: screen,
            ),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: '$screen at $width');
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('Server login uses password and API session', (tester) async {
    final previousClient = networkApi.client;
    networkApi.client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'token': 'test-only-session',
          'user': {
            'name': 'مستخدم اختبار',
            'phone': '0512345678',
            'id': 'test',
          },
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    addTearDown(() {
      networkApi.client = previousClient;
      networkApi.token = null;
      networkApi.user = null;
    });
    await tester.pumpWidget(const SmartCare());
    await tester.tap(find.byTooltip('حسابي والمزيد'));
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(MoreScreen));
    openCare(context, const AuthScreen());
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).at(0), '0512345678');
    await tester.enterText(
      find.byType(TextFormField).at(1),
      'test-only-password',
    );
    await tester.ensureVisible(find.text('دخول'));
    await tester.tap(find.text('دخول'));
    await tester.pumpAndSettle();
    expect(appStore.signedIn, true);
    expect(appStore.phone, '0512345678');
    expect(networkApi.token, 'test-only-session');
    expect(find.byType(MoreScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
