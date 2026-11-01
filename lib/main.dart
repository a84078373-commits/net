import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'network_map.dart';
import 'app_store.dart';
import 'care_screens.dart';
import 'network/network_test_screen.dart';
import 'network/network_api.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await appStore.load();
  runApp(const SmartCare());
}

class SmartCare extends StatelessWidget {
  const SmartCare({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'SmartCare • حائل',
    locale: const Locale('ar', 'SA'),
    supportedLocales: const [Locale('ar', 'SA')],
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    theme: stcTheme(),
    home: const Directionality(textDirection: TextDirection.rtl, child: Home()),
  );
}

class Home extends StatefulWidget {
  const Home({super.key});
  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  int page = 0;
  final complaint = TextEditingController();
  final search = TextEditingController();
  String? diagnosis;
  @override
  void initState() {
    super.initState();
    appStore.addListener(refresh);
    networkApi.addListener(syncAuth);
  }

  void syncAuth() {
    appStore.signedIn = networkApi.token != null;
    appStore.changed();
  }

  void refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appStore.removeListener(refresh);
    networkApi.removeListener(syncAuth);
    complaint.dispose();
    search.dispose();
    super.dispose();
  }

  Widget label(
    String text, {
    double size = 14,
    Color? color,
    FontWeight weight = FontWeight.normal,
  }) => Text(
    text,
    style: TextStyle(
      fontSize: size,
      color: color ?? StcColors.onyx,
      fontWeight: weight,
      height: 1.35,
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, bounds) {
          final wide = bounds.maxWidth > 900;
          return Row(
            children: [
              if (wide) SizedBox(width: 248, child: sidebar()),
              Expanded(
                child: SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    wide ? 28 : 16,
                    12,
                    wide ? 28 : 16,
                    24,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 1100),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          [
                            dashboard,
                            speed,
                            coverage,
                            assistant,
                            tickets,
                          ][page](),
                          const SizedBox(height: 20),
                          label(
                            'البلاغات محلية • قياسات الشبكة من الخدمة الفعلية فقط',
                            size: 11,
                            color: StcColors.silver,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    ),
    bottomNavigationBar: MediaQuery.sizeOf(context).width > 900
        ? null
        : Container(
            decoration: const BoxDecoration(
              color: StcColors.card,
              border: Border(top: BorderSide(color: Color(0xFFE8E2EE))),
            ),
            child: NavigationBar(
              selectedIndex: page,
              onDestinationSelected: (i) => setState(() => page = i),
              destinations: const [
                NavigationDestination(
                  icon: StcNavIcon(Icons.home_outlined),
                  selectedIcon: StcNavIcon(Icons.home_rounded, selected: true),
                  label: 'الرئيسية',
                ),
                NavigationDestination(
                  icon: StcNavIcon(Icons.sim_card_outlined),
                  selectedIcon: StcNavIcon(Icons.sim_card, selected: true),
                  label: 'القياس',
                ),
                NavigationDestination(
                  icon: StcNavIcon(Icons.map_outlined),
                  selectedIcon: StcNavIcon(Icons.map_rounded, selected: true),
                  label: 'الخريطة',
                ),
                NavigationDestination(
                  icon: StcNavIcon(Icons.auto_awesome_outlined),
                  selectedIcon: StcNavIcon(Icons.auto_awesome, selected: true),
                  label: 'المساعد',
                ),
                NavigationDestination(
                  icon: StcNavIcon(Icons.receipt_long_outlined),
                  selectedIcon: StcNavIcon(Icons.receipt_long, selected: true),
                  label: 'بلاغاتي',
                ),
              ],
            ),
          ),
  );

  Widget sidebar() => Container(
    decoration: const BoxDecoration(
      color: StcColors.card,
      border: Border(left: BorderSide(color: Color(0xFFE8E2EE))),
    ),
    padding: const EdgeInsets.fromLTRB(20, 28, 20, 20),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const StcWordmark(color: StcColors.purple, size: 42),
        const SizedBox(height: 6),
        label('SMARTCARE  حائل', size: 11, color: StcColors.coral),
        const SizedBox(height: 36),
        for (final entry in [
          ('الرئيسية', Icons.home_outlined, Icons.home_rounded),
          ('القياس', Icons.sim_card_outlined, Icons.sim_card),
          ('الخريطة', Icons.map_outlined, Icons.map_rounded),
          ('المساعد', Icons.auto_awesome_outlined, Icons.auto_awesome),
          ('بلاغاتي', Icons.receipt_long_outlined, Icons.receipt_long),
        ].asMap().entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              selected: page == entry.key,
              selectedTileColor: StcColors.purpleSoft,
              selectedColor: StcColors.purple,
              leading: Icon(
                page == entry.key ? entry.value.$3 : entry.value.$2,
                color: page == entry.key ? StcColors.purple : StcColors.silver,
              ),
              title: Text(
                entry.value.$1,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              onTap: () => setState(() => page = entry.key),
            ),
          ),
        const Spacer(),
        StcCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.cell_tower_rounded, color: StcColors.purple),
              const SizedBox(height: 10),
              label('اتصالك، نفهمه أكثر', size: 13, weight: FontWeight.w700),
              const SizedBox(height: 4),
              label('رؤية أذكى لشبكة حائل', size: 11, color: StcColors.silver),
            ],
          ),
        ),
      ],
    ),
  );

  Widget welcomeHeader() {
    final first = appStore.name.split(' ').first;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 18, 20, 56),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [StcColors.purple, StcColors.purpleDeep],
          begin: Alignment.topRight,
          end: Alignment.bottomLeft,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(8)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const StcWordmark(size: 28),
              const Spacer(),
              IconButton(
                tooltip: 'الإشعارات',
                onPressed: () => openCare(context, const NoticesScreen()),
                icon: Badge(
                  isLabelVisible: appStore.unread > 0,
                  backgroundColor: StcColors.coral,
                  label: Text('${appStore.unread}'),
                  child: const Icon(
                    Icons.notifications_none_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'حسابي والمزيد',
                onPressed: () => openCare(context, const MoreScreen()),
                icon: const CircleAvatar(
                  radius: 16,
                  backgroundColor: Colors.white24,
                  child: Icon(
                    Icons.person_outline,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 22),
          label(
            'أهلًا $first',
            size: 32,
            weight: FontWeight.w800,
            color: Colors.white,
          ),
          const SizedBox(height: 6),
          label(
            'حائل، المملكة العربية السعودية',
            color: Colors.white70,
            size: 13,
          ),
        ],
      ),
    );
  }

  Widget searchBar() => StcCard(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
    child: TextField(
      controller: search,
      onChanged: (_) => setState(() {}),
      decoration: const InputDecoration(
        hintText: 'ابحث عن خدمة…',
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        filled: false,
        prefixIcon: Icon(Icons.search, color: StcColors.silver),
        contentPadding: EdgeInsets.symmetric(vertical: 14),
      ),
    ),
  );

  List<(IconData, String, VoidCallback)> services() => [
    (Icons.speed_outlined, 'اختبار الشبكة', () => setState(() => page = 1)),
    (Icons.map_outlined, 'خريطة التغطية', () => setState(() => page = 2)),
    (Icons.auto_awesome_outlined, 'المساعد', () => setState(() => page = 3)),
    (
      Icons.add_task_outlined,
      'بلاغ جديد',
      () => openCare(context, const NewReportScreen()),
    ),
    (
      Icons.history_rounded,
      'سجل القياسات',
      () => openCare(context, const HistoryScreen()),
    ),
    (Icons.receipt_long_outlined, 'بلاغاتي', () => setState(() => page = 4)),
    (
      Icons.cloud_sync_outlined,
      'الحفظ والمزامنة',
      () => openCare(context, const SyncScreen()),
    ),
    (
      Icons.tune_rounded,
      'الإعدادات',
      () => openCare(context, const SettingsScreen()),
    ),
  ];

  Widget dashboard() {
    final q = search.text.trim();
    final items = services()
        .where((s) => q.isEmpty || s.$2.contains(q))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: welcomeHeader(),
        ),
        Transform.translate(
          offset: const Offset(0, -36),
          child: Column(
            children: [
              searchBar(),
              const SizedBox(height: 14),
              StcCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: StcColors.purpleSoft,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: const Icon(
                            Icons.sim_card_outlined,
                            color: StcColors.purple,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              label(
                                'شبكتك المفضلة',
                                size: 12,
                                color: StcColors.silver,
                              ),
                              label(
                                'SmartCare • ${appStore.area}',
                                weight: FontWeight.w800,
                                size: 16,
                              ),
                            ],
                          ),
                        ),
                        TextButton(
                          onPressed: () =>
                              openCare(context, const ProfileScreen()),
                          child: const Text('تغيير'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 18),
                    const StcUsageBar(
                      icon: Icons.south_rounded,
                      label: 'التنزيل',
                      value: 'ابدأ قياسًا',
                      progress: 0.12,
                    ),
                    const StcUsageBar(
                      icon: Icons.bolt_outlined,
                      label: 'الاستجابة',
                      value: '— ms',
                      progress: 0.08,
                    ),
                    const StcUsageBar(
                      icon: Icons.signal_cellular_alt,
                      label: 'جودة الشبكة',
                      value: 'غير مقاسة',
                      progress: 0.06,
                    ),
                    Row(
                      children: [
                        Expanded(
                          child: _miniStat(
                            '${appStore.measurements.length}',
                            'قياسات',
                            Icons.analytics_outlined,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _miniStat(
                            '${appStore.reports.length}',
                            'بلاغات',
                            Icons.receipt_long_outlined,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              StcCoralBar(
                title: 'اطمئن على اتصالك الآن',
                action: 'اختبر',
                onTap: () => setState(() => page = 1),
              ),
            ],
          ),
        ),
        label('خدمات سريعة', size: 18, weight: FontWeight.w800),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: MediaQuery.sizeOf(context).width > 650 ? 4 : 3,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1,
          children: [
            for (final item in items)
              StcIconTile(icon: item.$1, label: item.$2, onTap: item.$3),
          ],
        ),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: label('لا توجد خدمة مطابقة لبحثك', color: StcColors.silver),
          ),
        const SizedBox(height: 18),
        StcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: StcColors.purpleSoft,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Icon(
                      Icons.auto_awesome,
                      color: StcColors.purple,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: label(
                      'رؤية من مساعدك الذكي',
                      weight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              label(
                'الجودة تبدأ بقياس موثوق.',
                size: 20,
                weight: FontWeight.w800,
              ),
              const SizedBox(height: 8),
              label(
                'استكشف القياسات المنشورة حسب الخلايا والفترة؛ غياب البيانات لا يعني ضعف الاتصال.',
                color: StcColors.silver,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () => setState(() => page = 2),
                child: const Text('استكشف جودة الشبكة'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _miniStat(String value, String title, IconData icon) => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: StcColors.canvas,
      borderRadius: BorderRadius.circular(16),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: StcColors.purple, size: 18),
        const SizedBox(height: 8),
        label(value, size: 22, weight: FontWeight.w800),
        label(title, size: 12, color: StcColors.silver),
      ],
    ),
  );

  Widget speed() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: RealSpeedPanel(onMapped: () => setState(() => page = 2)),
  );

  Widget coverage() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      label('الخريطة', size: 28, weight: FontWeight.w800),
      const SizedBox(height: 6),
      label(
        'خلايا جغرافية منتظمة • نحو 1 كم • لا تُفترض حدود الأحياء',
        color: StcColors.silver,
        size: 13,
      ),
      const SizedBox(height: 16),
      ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: const SizedBox(height: 650, child: NetworkMap(selectedArea: 0)),
      ),
      const SizedBox(height: 16),
      StcCard(
        child: label(
          'الألوان تستند إلى البيانات المجمعة من الخادم فقط. المناطق بلا عينات كافية تبقى دون تصنيف. تستخدم الفلاتر من زر الأدوات داخل الخريطة.',
          size: 12,
          color: StcColors.silver,
        ),
      ),
    ],
  );

  Widget assistant() => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      const SizedBox(height: 8),
      label('المساعد', size: 28, weight: FontWeight.w800),
      const SizedBox(height: 6),
      label(
        'صف المشكلة بالعربية لتحصل على إرشادات أولية.',
        color: StcColors.silver,
      ),
      const SizedBox(height: 18),
      StcCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.auto_awesome, color: StcColors.purple, size: 42),
            const SizedBox(height: 14),
            label('كيف نقدر نحسّن اتصالك؟', size: 22, weight: FontWeight.w800),
            const SizedBox(height: 8),
            label(
              'تحليل بقواعد محلية توضيحية، يحتاج تأكيدًا بقياسات فعلية.',
              color: StcColors.silver,
              size: 13,
            ),
            const SizedBox(height: 20),
            TextField(
              controller: complaint,
              maxLines: 4,
              decoration: const InputDecoration(
                hintText: 'مثال: الإنترنت بطيء مساءً في حي النقرة…',
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () {
                final t = complaint.text.trim();
                if (t.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('اكتب وصف المشكلة أولًا')),
                  );
                  return;
                }
                setState(
                  () => diagnosis = t.contains('مكالم') || t.contains('اتصال')
                      ? 'قد يرتبط انقطاع الاتصال بضعف التغطية داخل المبنى. جرّب موقعًا مفتوحًا وتحقق من إعدادات الشبكة، ثم أعد تشغيل الجهاز.'
                      : t.contains('إشار') || t.contains('تغطية')
                      ? 'قد تتأثر الإشارة بالعوائق أو موقع الجهاز. اقترب من نافذة وقارن جودة الاتصال في مكان آخر.'
                      : 'قد يرتبط البطء بازدحام الشبكة أو استخدام عدة أجهزة. أعد تشغيل الموجّه، وأوقف التنزيلات الخلفية، ثم قارن الأداء في وقت آخر.',
                );
              },
              icon: const Icon(Icons.auto_awesome),
              label: const Text('حلّل المشكلة'),
            ),
          ],
        ),
      ),
      if (diagnosis != null) ...[
        const SizedBox(height: 16),
        StcCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              label(
                'تشخيص أولي مقترح',
                color: StcColors.purple,
                weight: FontWeight.bold,
              ),
              const SizedBox(height: 12),
              label(diagnosis!, size: 16),
              const SizedBox(height: 12),
              label(
                'تحليل بقواعد محلية توضيحية، يحتاج تأكيدًا بقياسات فعلية.',
                size: 11,
                color: StcColors.silver,
              ),
              const SizedBox(height: 16),
              StcCoralBar(
                title: 'احفظ كبلاغ تجريبي',
                action: 'حفظ',
                onTap: () {
                  setState(() {
                    final text = complaint.text.trim();
                    appStore.addReport(
                      text,
                      category: text.contains('مكالم')
                          ? 'انقطاع المكالمات'
                          : text.contains('إشار') || text.contains('تغطية')
                          ? 'ضعف الإشارة'
                          : 'بطء الإنترنت',
                      recommendation: diagnosis ?? '',
                    );
                    diagnosis = null;
                    complaint.clear();
                    page = 4;
                  });
                },
              ),
            ],
          ),
        ),
      ],
    ],
  );

  Widget tickets() => ReportsPanel(onNew: () => setState(() => page = 3));
}
