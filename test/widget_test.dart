import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smartcare/main.dart';
import 'package:smartcare/network_map.dart';

void main() {
  testWidgets('Geographic heatmap controls work on mobile', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SizedBox(height: 590, child: NetworkMap(selectedArea: 0)),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('HAIL / NETWORK INTELLIGENCE'), findsNothing);
    expect(find.text('خريطة حقيقية • قياسات محاكاة'), findsNothing);
    expect(
      find.text('المنتزه'),
      findsNothing,
    ); // No fabricated geographic samples.
    await tester.tap(find.byTooltip('إظهار أو إخفاء الحرارة'));
    await tester.pump();
    expect(find.text('الحرارة مخفية'), findsOneWidget);
    await tester.tap(find.byTooltip('دليل الألوان'));
    await tester.pumpAndSettle();
    expect(find.text('دليل الخريطة'), findsOneWidget);
    expect(tester.takeException(), isNull);
    Navigator.of(tester.element(find.text('دليل الخريطة'))).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('فلاتر البيانات'));
    await tester.pumpAndSettle();
    expect(find.text('اختيار منطقة العرض'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('تطبيق الفلاتر'));
    await tester.tap(find.text('تطبيق الفلاتر'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('ملء الشاشة'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('خريطة جودة الإنترنت'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('Arabic mobile dashboard and complaint flow', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const SmartCare());
    expect(find.text('كل اتصال يبدأ بتجربة أفضل.'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('المساعد'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'الإنترنت بطيء');
    await tester.ensureVisible(find.text('حلّل المشكلة'));
    await tester.tap(find.text('حلّل المشكلة'));
    await tester.pumpAndSettle();
    expect(find.text('تشخيص أولي مقترح'), findsOneWidget);
    await tester.ensureVisible(find.text('احفظ كبلاغ تجريبي'));
    await tester.tap(find.text('احفظ كبلاغ تجريبي'));
    await tester.pumpAndSettle();
    expect(find.text('الإنترنت بطيء'), findsOneWidget);
    expect(find.text('لم يُرسل إلى STC'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
