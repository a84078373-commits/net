import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_store.dart';
import 'network/server_auth_screen.dart';
import 'network/network_test_screen.dart';
import 'network/network_api.dart';
import 'theme.dart';

const _purple = StcColors.purple, _mint = StcColors.oasis;
void openCare(BuildContext context, Widget screen) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) =>
            Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    );
void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class CarePage extends StatelessWidget {
  final String title, eyebrow;
  final List<Widget> children;
  final List<Widget>? actions;
  const CarePage({
    super.key,
    required this.title,
    this.eyebrow = 'SMARTCARE / حائل',
    required this.children,
    this.actions,
  });
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(title), actions: actions),
    body: SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 920),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  eyebrow,
                  style: const TextStyle(
                    color: StcColors.coral,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 28,
                    fontWeight: FontWeight.w800,
                    color: StcColors.onyx,
                  ),
                ),
                const SizedBox(height: 22),
                ...children,
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

class CareCard extends StatelessWidget {
  final Widget child;
  const CareCard(this.child, {super.key});
  @override
  Widget build(BuildContext context) =>
      StcCard(margin: const EdgeInsets.only(bottom: 16), child: child);
}

Widget titleText(String text) => Text(
  text,
  style: const TextStyle(
    fontSize: 18,
    fontWeight: FontWeight.w800,
    color: StcColors.onyx,
  ),
);
Widget muted(String text) => Text(
  text,
  style: const TextStyle(fontSize: 12, color: StcColors.silver, height: 1.7),
);
Widget actionButton(
  String text,
  VoidCallback action, {
  IconData icon = Icons.arrow_back,
}) => FilledButton.icon(
  onPressed: action,
  icon: Icon(icon, size: 19),
  label: Text(text),
);
Widget metric(String value, String label, IconData icon) => CareCard(
  Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: _mint),
      const SizedBox(height: 12),
      Text(
        value,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      muted(label),
    ],
  ),
);
Widget adaptiveMetrics(List<Widget> items) => LayoutBuilder(
  builder: (_, c) => Wrap(
    spacing: 12,
    children: items
        .map(
          (w) => SizedBox(
            width: c.maxWidth > 600
                ? (c.maxWidth - 12 * (items.length - 1)) / items.length
                : c.maxWidth,
            child: w,
          ),
        )
        .toList(),
  ),
);
Widget emptyState(IconData icon, String title, String text) => CareCard(
  Column(
    children: [
      Icon(icon, color: _purple, size: 58),
      const SizedBox(height: 18),
      titleText(title),
      const SizedBox(height: 8),
      muted(text),
    ],
  ),
);

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) {
      final items = <(IconData, String, Widget)>[
        (Icons.person_outline, 'الملف الشخصي', const ProfileScreen()),
        (Icons.history, 'سجل القياسات', const HistoryScreen()),
        (Icons.notifications_none, 'الإشعارات', const NoticesScreen()),
        (Icons.cloud_sync_outlined, 'الحفظ والمزامنة', const SyncScreen()),
        (Icons.tune, 'الإعدادات', const SettingsScreen()),
        (Icons.analytics_outlined, 'لوحة البلاغات', const AdminScreen()),
        (Icons.help_outline, 'المساعدة', const HelpScreen()),
        (Icons.privacy_tip_outlined, 'الخصوصية', const PrivacyScreen()),
      ];
      return CarePage(
        title: 'المزيد',
        eyebrow: 'APP CENTER',
        children: [
          CareCard(
            Row(
              children: [
                const CircleAvatar(
                  radius: 28,
                  backgroundColor: StcColors.purpleSoft,
                  child: Icon(
                    Icons.person_outline,
                    color: StcColors.purple,
                    size: 28,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleText(appStore.name),
                      muted(
                        appStore.signedIn
                            ? 'حساب SmartCare • الجلسة على الخادم'
                            : 'تصفح كزائر • كل الخدمات في متناولك',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          titleText('مركز التطبيقات'),
          const SizedBox(height: 14),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 0.95,
            children: [
              for (final item in items)
                StcIconTile(
                  icon: item.$1,
                  label: item.$2,
                  onTap: () => openCare(context, item.$3),
                ),
            ],
          ),
          const SizedBox(height: 20),
          if (!appStore.signedIn)
            actionButton(
              'تسجيل الدخول / إنشاء حساب',
              () => openCare(context, const AuthScreen()),
              icon: Icons.login,
            ),
        ],
      );
    },
  );
}

class AuthScreen extends StatelessWidget {
  const AuthScreen({super.key});
  @override
  Widget build(BuildContext context) => const ServerAuthScreen();
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});
  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final name = TextEditingController(text: appStore.name);
  late String area = appStore.area;
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CarePage(
    title: 'ملفي الشخصي',
    children: [
      const Center(
        child: CircleAvatar(
          radius: 46,
          backgroundColor: _purple,
          child: Icon(Icons.person, size: 50, color: Colors.white),
        ),
      ),
      const SizedBox(height: 24),
      CareCard(
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: name,
                decoration: const InputDecoration(labelText: 'الاسم'),
                validator: (v) =>
                    (v ?? '').trim().length < 2 ? 'اكتب اسمك' : null,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: area,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الحي المفضل'),
                items: neighborhoods
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => area = v!,
              ),
              const SizedBox(height: 20),
              muted(
                appStore.phone.isEmpty
                    ? 'تصفح كزائر'
                    : 'رقم الجوال: ${appStore.phone}',
              ),
              const SizedBox(height: 20),
              actionButton('حفظ التعديلات', () {
                if (!form.currentState!.validate()) return;
                appStore.name = name.text.trim();
                appStore.area = area;
                appStore.changed();
                toast(context, 'تم تحديث ملفك الشخصي');
              }, icon: Icons.check),
            ],
          ),
        ),
      ),
      muted('بيانات الملف مرتبطة بهذا المتصفح أو الجهاز في النسخة التجريبية.'),
    ],
  );
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) => CarePage(
      title: 'الإعدادات',
      children: [
        CareCard(
          Column(
            children: [
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('إشعارات داخل التطبيق'),
                subtitle: muted('تحديثات البلاغات والقياسات داخل التطبيق'),
                value: appStore.notifications,
                onChanged: (v) {
                  appStore.notifications = v;
                  appStore.changed();
                },
              ),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('الحفظ التلقائي على الجهاز'),
                subtitle: muted(
                  'احفظ البيانات بعد كل تعديل؛ عند إيقافه استخدم الحفظ اليدوي',
                ),
                value: appStore.autoSave,
                onChanged: (v) async {
                  appStore.autoSave = v;
                  await appStore.save();
                },
              ),
            ],
          ),
        ),
        CareCard(
          Column(
            children: [
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.language, color: _mint),
                title: Text('اللغة'),
                trailing: Text('العربية'),
              ),
              const Divider(),
              const ListTile(
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.light_mode_outlined, color: _mint),
                title: Text('المظهر'),
                trailing: Text('فاتح • هوية stc'),
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.privacy_tip_outlined, color: _mint),
                title: const Text('الخصوصية وبياناتك'),
                trailing: const Icon(Icons.chevron_left),
                onTap: () => openCare(context, const PrivacyScreen()),
              ),
            ],
          ),
        ),
        actionButton(
          'الحفظ والمزامنة',
          () => openCare(context, const SyncScreen()),
          icon: Icons.cloud_sync_outlined,
        ),
        const SizedBox(height: 16),
        if (appStore.signedIn)
          OutlinedButton.icon(
            onPressed: () async {
              await networkApi.signOut();
              if (!context.mounted) return;
              appStore.signOut();
              Navigator.pop(context);
              toast(context, 'تم تسجيل الخروج من هذا الجهاز');
            },
            icon: const Icon(Icons.logout),
            label: const Text('تسجيل الخروج'),
          ),
      ],
    ),
  );
}

class ReportsPanel extends StatefulWidget {
  final VoidCallback onNew;
  const ReportsPanel({super.key, required this.onNew});
  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  String filter = 'الكل';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) {
      final reports = appStore.reports
          .where(
            (r) =>
                filter == 'الكل' ||
                (filter == 'مغلقة'
                    ? r.status == 'مغلق تجريبيًا'
                    : r.status != 'مغلق تجريبيًا'),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'بلاغاتي',
            style: TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: StcColors.onyx,
            ),
          ),
          const SizedBox(height: 8),
          muted('محفوظة على هذا الجهاز • لم تُرسل إلى STC'),
          const SizedBox(height: 18),
          actionButton(
            'إنشاء بلاغ جديد',
            () => openCare(context, const NewReportScreen()),
            icon: Icons.add,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: ['الكل', 'مفتوحة', 'مغلقة']
                .map(
                  (f) => ChoiceChip(
                    label: Text(f),
                    selected: filter == f,
                    onSelected: (_) => setState(() => filter = f),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (reports.isEmpty)
            emptyState(
              Icons.task_alt,
              'لا توجد بلاغات هنا',
              'أضف بلاغًا أو جرّب اختيار حالة أخرى.',
            ),
          for (final r in reports)
            CareCard(
              InkWell(
                onTap: () => openCare(context, ReportDetailScreen(report: r)),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.receipt_long,
                          color: _purple,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            r.category,
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                        const Icon(Icons.chevron_left),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      r.description,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 10),
                    muted('${r.area} • ${dateLabel(r.created)}'),
                    const SizedBox(height: 8),
                    Text(
                      r.status,
                      style: const TextStyle(color: _mint, fontSize: 12),
                    ),
                    muted('لم يُرسل إلى STC'),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: widget.onNew,
            icon: const Icon(Icons.auto_awesome),
            label: const Text('ابدأ بتشخيص المشكلة أولًا'),
          ),
        ],
      );
    },
  );
}

class NewReportScreen extends StatefulWidget {
  const NewReportScreen({super.key});
  @override
  State<NewReportScreen> createState() => _NewReportScreenState();
}

class _NewReportScreenState extends State<NewReportScreen> {
  final text = TextEditingController();
  final form = GlobalKey<FormState>();
  String area = appStore.area, category = 'بطء الإنترنت';
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => CarePage(
    title: 'بلاغ جديد',
    children: [
      CareCard(
        Form(
          key: form,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleText('صف المشكلة، وخلّنا نتابعها'),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: category,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'نوع المشكلة'),
                items:
                    [
                          'بطء الإنترنت',
                          'ضعف الإشارة',
                          'انقطاع المكالمات',
                          'اتصال غير مستقر',
                        ]
                        .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                        .toList(),
                onChanged: (v) => category = v!,
              ),
              const SizedBox(height: 20),
              DropdownButtonFormField<String>(
                initialValue: area,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'الحي'),
                items: neighborhoods
                    .map((a) => DropdownMenuItem(value: a, child: Text(a)))
                    .toList(),
                onChanged: (v) => area = v!,
              ),
              const SizedBox(height: 20),
              TextFormField(
                controller: text,
                minLines: 4,
                maxLines: 6,
                maxLength: 1000,
                decoration: const InputDecoration(
                  labelText: 'وصف المشكلة',
                  hintText: 'متى بدأت المشكلة؟ وهل تحدث داخل المنزل أو خارجه؟',
                  alignLabelWithHint: true,
                ),
                validator: (v) => (v ?? '').trim().length < 10
                    ? 'اكتب وصفًا من 10 أحرف على الأقل'
                    : null,
              ),
              const SizedBox(height: 20),
              actionButton('حفظ البلاغ على الجهاز', () {
                if (!form.currentState!.validate()) return;
                final r = appStore.addReport(
                  text.text.trim(),
                  selectedArea: area,
                  category: category,
                );
                Navigator.of(context).pushReplacement(
                  MaterialPageRoute<void>(
                    builder: (_) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: ReportDetailScreen(report: r),
                    ),
                  ),
                );
              }, icon: Icons.add_task),
              const SizedBox(height: 12),
              muted(
                'لن يُرسل البلاغ إلى مزود الخدمة. يمكنك استعراضه وتتبع حالته محليًا.',
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class ReportDetailScreen extends StatelessWidget {
  final CareReport report;
  const ReportDetailScreen({super.key, required this.report});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) => CarePage(
      title: 'تفاصيل البلاغ',
      children: [
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.receipt_long, color: _purple, size: 36),
              const SizedBox(height: 16),
              titleText(report.category),
              const SizedBox(height: 8),
              SelectableText(
                report.id,
                style: const TextStyle(color: _mint, fontSize: 11),
              ),
              const SizedBox(height: 16),
              Text(report.description, style: const TextStyle(height: 1.8)),
              const Divider(height: 30),
              muted('الحي: ${report.area}'),
              muted('تاريخ الإنشاء: ${dateLabel(report.created)}'),
              const SizedBox(height: 8),
              Text(report.status, style: const TextStyle(color: _mint)),
            ],
          ),
        ),
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText('مسار المتابعة'),
              const SizedBox(height: 20),
              for (final step in <(String, String, bool)>[
                ('إنشاء البلاغ', 'أُضيف على هذا الجهاز', true),
                (
                  'الحفظ المحلي',
                  appStore.storageFailed
                      ? 'تعذر الحفظ الدائم'
                      : appStore.autoSave
                      ? 'الحفظ التلقائي مفعّل'
                      : 'استخدم الحفظ اليدوي',
                  !appStore.storageFailed && appStore.autoSave,
                ),
                ('الربط بالدعم', 'غير متصل • لم يُرسل البلاغ إلى STC', false),
                (
                  'حالة المتابعة المحلية',
                  report.status,
                  report.status == 'مغلق تجريبيًا',
                ),
              ])
                Padding(
                  padding: const EdgeInsets.only(bottom: 18),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        step.$3
                            ? Icons.check_circle
                            : Icons.radio_button_unchecked,
                        color: step.$3 ? _mint : const Color(0xFFD5CDDD),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text(step.$1), muted(step.$2)],
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
        if (report.recommendation.isNotEmpty)
          CareCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText('التوصية الأولية'),
                const SizedBox(height: 12),
                Text(report.recommendation),
                const SizedBox(height: 8),
                muted('توصية توضيحية بقواعد محلية وليست تشخيصًا مؤكدًا.'),
              ],
            ),
          ),
        actionButton(
          report.status == 'مغلق تجريبيًا'
              ? 'إعادة فتح محليًا'
              : 'إغلاق البلاغ محليًا',
          () => appStore.updateStatus(
            report,
            report.status == 'مغلق تجريبيًا'
                ? 'بانتظار الربط'
                : 'مغلق تجريبيًا',
          ),
          icon: Icons.check_circle_outline,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: () async {
            await Clipboard.setData(
              ClipboardData(
                text:
                    '${report.id}\n${report.description}\n${report.area}\n${report.status}\nبلاغ تجريبي محلي، لم يُرسل إلى STC',
              ),
            );
            if (context.mounted) toast(context, 'تم نسخ ملخص البلاغ');
          },
          icon: const Icon(Icons.copy),
          label: const Text('نسخ ملخص البلاغ'),
        ),
      ],
    ),
  );
}

class HistoryScreen extends StatelessWidget {
  const HistoryScreen({super.key});
  @override
  Widget build(BuildContext context) => const RealHistoryScreen();
}

class NoticesScreen extends StatelessWidget {
  const NoticesScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) => CarePage(
      title: 'الإشعارات',
      actions: [
        IconButton(
          tooltip: 'قراءة الكل',
          onPressed: () {
            for (final n in appStore.notices) {
              n.read = true;
            }
            appStore.changed();
          },
          icon: const Icon(Icons.done_all),
        ),
      ],
      children: [
        if (!appStore.notifications)
          const CareCard(Text('الإشعارات الجديدة متوقفة من الإعدادات.')),
        if (appStore.notices.isEmpty)
          emptyState(
            Icons.notifications_none,
            'كل شيء هادئ هنا',
            'ستظهر تحديثات البلاغات ونتائج الاختبارات هنا.',
          ),
        for (final n in appStore.notices)
          CareCard(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                n.read ? Icons.notifications_none : Icons.notifications_active,
                color: n.read ? StcColors.silver : _purple,
              ),
              title: Text(n.title),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 8),
                  Text(
                    n.body,
                    style: const TextStyle(
                      fontSize: 12,
                      color: StcColors.silver,
                    ),
                  ),
                  muted(dateLabel(n.created)),
                ],
              ),
              onTap: () {
                n.read = true;
                appStore.changed();
              },
            ),
          ),
      ],
    ),
  );
}

class SyncScreen extends StatefulWidget {
  const SyncScreen({super.key});
  @override
  State<SyncScreen> createState() => _SyncScreenState();
}

class _SyncScreenState extends State<SyncScreen> {
  bool saving = false;
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) => CarePage(
      title: 'الحفظ والمزامنة',
      children: [
        const Center(
          child: Icon(Icons.cloud_off_outlined, size: 80, color: _purple),
        ),
        const SizedBox(height: 20),
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText('بياناتك معك على جهازك'),
              const SizedBox(height: 12),
              muted(
                'يمكن إنشاء البلاغات واستعراض السجل دون اتصال بعد تحميل التطبيق. الخريطة تحتاج الإنترنت لتحميل الطرق.',
              ),
              const SizedBox(height: 18),
              Text(
                appStore.storageFailed
                    ? 'تعذر الحفظ على الجهاز'
                    : 'التخزين المحلي متاح',
                style: TextStyle(
                  color: appStore.storageFailed ? Colors.orangeAccent : _mint,
                ),
              ),
              const SizedBox(height: 8),
              muted(
                appStore.lastSaved == null
                    ? 'لم تُحفظ تغييرات بعد'
                    : 'آخر حفظ: ${dateLabel(appStore.lastSaved!)}',
              ),
              const Divider(height: 28),
              muted('البلاغات: محلية • قياسات الشبكة: عبر خدمة API المستقلة'),
              muted('البلاغات المرسلة إلى STC: 0'),
              muted(
                'عناصر محلية: ${appStore.reports.length + appStore.measurements.length}',
              ),
            ],
          ),
        ),
        actionButton(saving ? 'جارٍ الحفظ…' : 'حفظ البيانات الآن', () async {
          if (saving) return;
          setState(() => saving = true);
          await appStore.save();
          if (!mounted) return;
          setState(() => saving = false);
          if (context.mounted) {
            toast(
              context,
              appStore.storageFailed
                  ? 'تعذر الحفظ؛ تحقق من إتاحة تخزين المتصفح'
                  : 'تم حفظ البيانات على هذا الجهاز',
            );
          }
        }, icon: Icons.save_outlined),
        const SizedBox(height: 16),
        const CareCard(
          Text(
            'لا تُزامن البلاغات المحلية مع STC. تُحفظ قياسات الشبكة على خادم SmartCare فقط عند اكتمال اختبار فعلي والضغط على الحفظ. لا تُعاد محاولة إرسال الموقع في الخلفية.',
            style: TextStyle(
              color: StcColors.silver,
              height: 1.8,
              fontSize: 12,
            ),
          ),
        ),
      ],
    ),
  );
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  String area = 'الكل';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) {
      final reports = appStore.reports
          .where((r) => area == 'الكل' || r.area == area)
          .toList();
      final measurements = appStore.measurements
          .where((m) => area == 'الكل' || m.area == area)
          .toList();
      final total = reports.length;
      return CarePage(
        title: 'لوحة الإدارة',
        eyebrow: 'OPERATIONS / عرض تجريبي محلي',
        children: [
          const CareCard(
            Text(
              'تعرض هذه اللوحة بيانات هذا الجهاز فقط. الدخول الإداري وصلاحيات الموظفين غير متصلين بخادم.',
              style: TextStyle(
                fontSize: 12,
                color: StcColors.silver,
                height: 1.7,
              ),
            ),
          ),
          DropdownButtonFormField<String>(
            initialValue: area,
            decoration: const InputDecoration(labelText: 'نطاق التحليل'),
            items: [
              'الكل',
              ...neighborhoods,
            ].map((a) => DropdownMenuItem(value: a, child: Text(a))).toList(),
            onChanged: (v) => setState(() => area = v!),
          ),
          const SizedBox(height: 20),
          adaptiveMetrics([
            metric('$total', 'إجمالي البلاغات المحلية', Icons.receipt_long),
            metric(
              '${reports.where((r) => r.status != 'مغلق تجريبيًا').length}',
              'بلاغ مفتوح',
              Icons.pending_actions,
            ),
            metric('${measurements.length}', 'قياس تجريبي', Icons.speed),
          ]),
          CareCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText('المشكلات الأكثر شيوعًا'),
                const SizedBox(height: 20),
                if (total == 0) muted('أنشئ بلاغات لعرض توزيع المشكلات.'),
                for (final type in [
                  'بطء الإنترنت',
                  'ضعف الإشارة',
                  'انقطاع المكالمات',
                  'اتصال غير مستقر',
                ]) ...[
                  Row(
                    children: [
                      Expanded(
                        child: Text(type, style: const TextStyle(fontSize: 12)),
                      ),
                      Text(
                        '${reports.where((r) => r.category == type).length}',
                        style: const TextStyle(color: _mint),
                      ),
                    ],
                  ),
                  const SizedBox(height: 7),
                  LinearProgressIndicator(
                    value: total == 0
                        ? 0
                        : reports.where((r) => r.category == type).length /
                              total,
                    color: _purple,
                    backgroundColor: const Color(0xFFE8E2EE),
                    minHeight: 7,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
          CareCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText('أولوية مراجعة الأحياء'),
                const SizedBox(height: 15),
                for (final a in (area == 'الكل' ? neighborhoods : [area]))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(
                      Icons.location_on_outlined,
                      color: _mint,
                    ),
                    title: Text(a),
                    subtitle: muted(
                      '${reports.where((r) => r.area == a).length} بلاغ محلي • ${measurements.where((m) => m.area == a).length} قياس تجريبي',
                    ),
                  ),
                muted(
                  'الأعداد من بيانات الجهاز؛ لا تكفي لاستنتاج جودة الشبكة الفعلية.',
                ),
              ],
            ),
          ),
          titleText('متابعة البلاغات'),
          const SizedBox(height: 16),
          if (reports.isEmpty)
            emptyState(
              Icons.inbox_outlined,
              'لا توجد بلاغات للتحليل',
              'ستظهر البلاغات الجديدة هنا تلقائيًا.',
            ),
          for (final r in reports)
            CareCard(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    r.description,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 8),
                  muted('${r.area} • ${r.category}'),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('${r.id}-${r.status}'),
                    initialValue: r.status,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'حالة المتابعة المحلية',
                    ),
                    items:
                        [
                              'بانتظار الربط',
                              'قيد المراجعة التجريبية',
                              'مغلق تجريبيًا',
                            ]
                            .map(
                              (s) => DropdownMenuItem(
                                value: s,
                                child: Text(
                                  s,
                                  style: const TextStyle(fontSize: 12),
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (v) => appStore.updateStatus(r, v!),
                  ),
                  TextButton(
                    onPressed: () =>
                        openCare(context, ReportDetailScreen(report: r)),
                    child: const Text('عرض تفاصيل البلاغ'),
                  ),
                ],
              ),
            ),
        ],
      );
    },
  );
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) => CarePage(
    title: 'نحن هنا لمساعدتك',
    children: [
      const Icon(Icons.support_agent, size: 80, color: _purple),
      const SizedBox(height: 20),
      for (final item in <(String, String)>[
        (
          'كيف أضيف بلاغًا؟',
          'من بلاغاتي اختر إنشاء بلاغ جديد، أو ابدأ بتشخيص المشكلة عبر المساعد ثم احفظ النتيجة.',
        ),
        (
          'هل القياسات حقيقية؟',
          'خدمة القياس تنقل بيانات فعلية عند إعداد خادم عام. دون الخدمة لا يظهر قياس. الخريطة تعرض خلايا مجمعة فقط، والطرق من CARTO اعتمادًا على بيانات OpenStreetMap.',
        ),
        (
          'هل يصل البلاغ إلى STC؟',
          'لا، البلاغات محفوظة على جهازك فقط. الربط بمزود الخدمة يحتاج خدمة خلفية وصلاحيات مناسبة.',
        ),
        (
          'ماذا يحدث عند انقطاع الإنترنت؟',
          'بعد تحميل التطبيق، يمكن استخدام الواجهات وحفظ البلاغات محليًا. تحميل أجزاء جديدة من الخريطة يتطلب اتصالًا.',
        ),
        (
          'هل الحساب آمن للإنتاج؟',
          'الدخول يستخدم حسابًا وكلمة مرور على خادم SmartCare. ملكية رقم الجوال غير متحققة برسائل SMS، ولا يرتبط الحساب بشركة STC.',
        ),
      ])
        CareCard(
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Text(item.$1, style: const TextStyle(fontSize: 15)),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: muted(item.$2),
              ),
            ],
          ),
        ),
      CareCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleText('STC SmartCare AI'),
            const SizedBox(height: 10),
            muted(
              'مشروع تصوري لتحليل بلاغات الاتصالات ومراقبة جودة الشبكة في مدينة حائل. ليس تطبيقًا رسميًا لشركة STC.',
            ),
            muted('الإصدار 1.0 • نموذج واجهات تفاعلي'),
          ],
        ),
      ),
      TextButton(
        onPressed: () => openCare(context, const PrivacyScreen()),
        child: const Text('الخصوصية وبياناتك'),
      ),
    ],
  );
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) => CarePage(
    title: 'الخصوصية وبياناتك',
    children: [
      CareCard(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            titleText('أنت تعرف أين تُحفظ بياناتك'),
            const SizedBox(height: 16),
            muted(
              'يحفظ هذا النموذج الاسم ورقم الجوال التجريبي والبلاغات والقياسات والإعدادات في التخزين المحلي للتطبيق أو المتصفح. هذا التخزين غير مشفر ولا يمثل حسابًا سحابيًا.',
            ),
            const SizedBox(height: 16),
            muted(
              'لا يُطلب الموقع إلا بموافقتك لتحريك الخريطة أو مشاركة خلية تقريبية. يمكن الاختبار دون مشاركة الموقع. تُحمّل صور الطرق من CARTO (بيانات OpenStreetMap)؛ يتلقى مزود الخرائط طلبات أجزاء الخريطة وعنوان الإنترنت، ولا يتلقى رقم حسابك من التطبيق.',
            ),
            const SizedBox(height: 16),
            muted(
              'البلاغات لا تُرسل إلى STC. القياسات المكتملة التي توافق على حفظها تُرسل إلى خادم SmartCare. الموقع اختياري، ويُقرب إلى خلية بنحو 1 كم قبل الإرسال. لا تُخزّن إحداثيات GPS الدقيقة ولا تُنشر هويات المساهمين. تُحتفظ القياسات 90 يومًا وتُحذف من شاشة السجل. الجلسة في الذاكرة فقط. مسح بيانات المتصفح لا يحذف قياسات الخادم.',
            ),
          ],
        ),
      ),
    ],
  );
}
