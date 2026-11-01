import 'package:flutter/material.dart';
import '../theme.dart';
import 'network_api.dart';
import 'server_auth_screen.dart';
import 'speed_test_service.dart';
class NetworkTestScreen extends StatelessWidget {
  const NetworkTestScreen({super.key});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('اختبار جودة الإنترنت')),
    body: const SafeArea(
      child: SingleChildScrollView(
        padding: EdgeInsets.all(22),
        child: RealSpeedPanel(),
      ),
    ),
  );
}

class RealSpeedPanel extends StatefulWidget {
  final VoidCallback? onMapped;
  const RealSpeedPanel({super.key, this.onMapped});
  @override
  State<RealSpeedPanel> createState() => _RealSpeedPanelState();
}

class _RealSpeedPanelState extends State<RealSpeedPanel> {
  late final service = SpeedTestService(networkApi);
  Map<String, dynamic>? config;
  SpeedResult? result;
  bool busy = false,
      loading = true,
      share = true,
      saving = false,
      saved = false,
      analyzing = false;
  bool cancelled = false;
  String? error;
  String? aiAnalysis;
  String? mappedCellId;
  String phase = 'جاهز للبدء';
  double progress = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    service.cancel();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final c = await networkApi.config();
      if (mounted) {
        setState(() {
          config = c;
          loading = false;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> run() async {
    if (busy) return;
    await load();
    if (!mounted) return;
    if (config?['test']?['available'] != true) return;
    if (networkApi.token == null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const Directionality(
            textDirection: TextDirection.rtl,
            child: ServerAuthScreen(),
          ),
        ),
      );
      if (!mounted || networkApi.token == null) return;
    }
    final consent = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('السماح ببدء الاختبار؟'),
        content: Text(
          'سيُقاس الاتصال الحالي (واي فاي أو شبكة الجوال) بنقل بيانات فعلية حتى 64 ميبيبايت خلال 90 ثانية، ثم تُحفظ النتيجة تلقائيًا.\n\n${share ? 'سيُطلب الموقع لرسم خلية تقريبية (~1 كم) على الخريطة، دون حفظ إحداثياتك الدقيقة.' : 'لن يُرسم القياس على الخريطة دون مشاركة الموقع.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('أوافق وأبدأ'),
          ),
        ],
      ),
    );
    if (consent != true || !mounted) return;
    setState(() {
      busy = true;
      cancelled = false;
      error = null;
      result = null;
      saved = false;
      analyzing = false;
      aiAnalysis = null;
      mappedCellId = null;
      progress = 0;
    });
    try {
      ApproximateLocation? location;
      var shareThisRun = share;
      if (shareThisRun) {
        setState(() => phase = 'تحديد موقع أدق للخريطة…');
        try {
          location = await LocationService().locate();
          if (location.accuracy > LocationService.maxShareAccuracyM) {
            shareThisRun = false;
            location = null;
            if (mounted) {
              setState(
                () => error =
                    'دقة الموقع غير كافية للمشاركة • سيُحفظ القياس دون رسم على الخريطة',
              );
            }
          }
        } on NetworkFailure catch (e) {
          // Speed measurement must still run; map share is optional.
          shareThisRun = false;
          location = null;
          if (mounted) {
            setState(() => error = '${e.message} • سيُحفظ القياس دون رسم على الخريطة');
          }
        }
      }
      if (!mounted || cancelled) {
        throw const NetworkFailure('أُلغي الاختبار قبل نقل البيانات');
      }
      final value = await service.run(
        location: location,
        onProgress: (p, v) {
          if (mounted) {
            setState(() {
              phase = p;
              progress = v;
            });
          }
        },
      );
      if (mounted) setState(() => result = value);
      if (mounted && !(shareThisRun && value.location == null)) {
        final previous = share;
        share = shareThisRun;
        try {
          await save();
        } finally {
          share = previous;
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e is NetworkFailure ? e.message : e.toString());
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    if (result == null || saving) return;
    setState(() {
      saving = true;
      error = null;
    });
    try {
      final savedRow = await networkApi.request(
        '/api/network-tests',
        method: 'POST',
        body: result!.toJson(share: share),
      );
      if (mounted) {
        setState(() {
          saved = true;
          mappedCellId = savedRow['shared'] == true
              ? savedRow['cell_id']?.toString()
              : null;
        });
        if (share) widget.onMapped?.call();
      }
      await analyzeResult();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  Future<void> analyzeResult() async {
    final r = result;
    if (r == null || analyzing) return;
    setState(() {
      analyzing = true;
      aiAnalysis = null;
    });
    try {
      final prompt = StringBuffer()
        ..writeln('حلّل نتيجة فحص سرعة شبكة للمستخدم:')
        ..writeln('- التحميل: ${r.download.toStringAsFixed(1)} Mbps')
        ..writeln('- الرفع: ${r.upload.toStringAsFixed(1)} Mbps')
        ..writeln('- البنق: ${r.ping.toStringAsFixed(0)} ms')
        ..writeln(
          '- نوع الاتصال: ${r.connection == 'cellular'
              ? 'شبكة الجوال'
              : r.connection == 'wifi'
              ? 'واي فاي'
              : 'غير مؤكد'}',
        );
      if (mappedCellId != null) {
        prompt.writeln('- رُسم على خلية: $mappedCellId');
      } else {
        prompt.writeln('- لم تُشارك إحداثيات على الخريطة');
      }
      prompt.writeln(
        'اذكر تقييمًا مختصرًا وجودة الاستخدام اليومي ونصيحة واحدة عملية.',
      );
      final res = await networkApi.request(
        '/api/ai/analyze',
        method: 'POST',
        body: {'text': prompt.toString()},
      );
      if (mounted) {
        setState(() => aiAnalysis = res['analysis']?.toString() ?? 'لا توجد نتيجة');
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => aiAnalysis =
              'تعذر التحليل الذكي: $e\n(تأكد أن المدير حفظ مفتاح Gemini في لوحة الإدارة)',
        );
      }
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Widget block(Widget child) =>
      StcCard(margin: const EdgeInsets.only(bottom: 16), child: child);
  @override
  Widget build(BuildContext context) {
    final mode = config?['test']?['mode'];
    final available =
        config?['test']?['available'] == true &&
        (mode == 'internet' || mode == 'local');
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'القياس',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: StcColors.onyx,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'فحص السرعة مسموح على الواي فاي أو شبكة الجوال. بعد الحفظ تُرسم على الخريطة (طبقة قياساتك) ويُحلَّل بالذكاء الاصطناعي تلقائيًا.',
              style: TextStyle(color: StcColors.silver, height: 1.7),
            ),
            const SizedBox(height: 20),
            if (loading) const LinearProgressIndicator(),
            if (!loading && !available)
              block(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.wifi_off,
                      color: Colors.orangeAccent,
                      size: 42,
                    ),
                    const SizedBox(height: 16),
                    const Text(
                      'اختبار الإنترنت غير متاح',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      config?['test']?['reason'] ??
                          'تعذر الوصول إلى خدمة القياس',
                      style: const TextStyle(
                        color: StcColors.silver,
                        height: 1.7,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: load,
                      icon: const Icon(Icons.refresh),
                      label: const Text('إعادة التحقق'),
                    ),
                  ],
                ),
              ),
            if (error != null)
              block(
                Text(
                  error!,
                  style: const TextStyle(
                    color: Colors.orangeAccent,
                    height: 1.6,
                  ),
                ),
              ),
            block(
              Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('ارسم النتيجة على الخريطة'),
                    subtitle: const Text(
                      'يُحفظ القياس مع نوع الشبكة (واي فاي أو خلوي) في خلية تقريبية نحو 1 كم',
                      style: TextStyle(fontSize: 11, color: StcColors.silver),
                    ),
                    value: share,
                    onChanged: busy || saving || saved
                        ? null
                        : (v) => setState(() => share = v),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 20),
                    Text(phase),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        cancelled = true;
                        service.cancel();
                      },
                      child: const Text('إلغاء الاختبار'),
                    ),
                  ] else if (available)
                    StcCoralBar(
                      title: result == null
                          ? 'ابدأ فحص السرعة'
                          : 'اختبار جديد',
                      action: 'ابدأ',
                      onTap: run,
                    ),
                  const SizedBox(height: 12),
                  const Text(
                    'Jitter وفقد الحزم غير متاحين؛ HTTP لا يقيس فقد حزم الشبكة. شركة الاتصالات غير معروفة دون مصدر موثوق.',
                    style: TextStyle(
                      fontSize: 11,
                      color: StcColors.silver,
                      height: 1.7,
                    ),
                  ),
                ],
              ),
            ),
            if (result != null)
              block(
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
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
                        const Expanded(
                          child: Text(
                            'نتيجتك الفعلية',
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    StcUsageBar(
                      icon: Icons.south_rounded,
                      label: 'التنزيل',
                      value: '${result!.download.toStringAsFixed(2)} Mbps',
                      progress: (result!.download / 300).clamp(0.08, 1),
                    ),
                    StcUsageBar(
                      icon: Icons.north_rounded,
                      label: 'الرفع',
                      value: '${result!.upload.toStringAsFixed(2)} Mbps',
                      progress: (result!.upload / 100).clamp(0.08, 1),
                    ),
                    StcUsageBar(
                      icon: Icons.bolt_outlined,
                      label: 'استجابة HTTP',
                      value: '${result!.ping.toStringAsFixed(1)} ms',
                      progress: (1 - (result!.ping / 200)).clamp(0.08, 1),
                    ),
                    Text(
                      '${result!.connection == 'cellular'
                          ? 'شبكة الجوال'
                          : result!.connection == 'wifi'
                          ? 'واي فاي'
                          : 'نوع الاتصال غير مؤكد'} • ${((result!.downloadBytes + result!.uploadBytes) / 1048576).toStringAsFixed(1)} MiB',
                      style: const TextStyle(color: StcColors.silver),
                    ),
                    const SizedBox(height: 8),
                    if (share && result!.location == null)
                      const Text(
                        'لم يُجمع موقع لهذا الاختبار؛ أوقف المساهمة لحفظ نتيجة خاصة.',
                        style: TextStyle(color: Colors.orangeAccent),
                      ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed:
                          saved || saving || share && result!.location == null
                          ? null
                          : save,
                      icon: Icon(
                        saved ? Icons.check : Icons.cloud_upload_outlined,
                      ),
                      label: Text(
                        saved
                            ? 'تم الحفظ في قاعدة البيانات'
                            : saving
                            ? 'جارٍ الحفظ…'
                            : share
                            ? 'حفظ النتيجة والمساهمة بالخريطة'
                            : 'حفظ نتيجة خاصة على الخادم',
                      ),
                    ),
                    if (mappedCellId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'رُسم على الخريطة — خلية $mappedCellId (طبقة قياساتك بالأحمر)',
                        style: const TextStyle(
                          color: StcColors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (analyzing) ...[
                      const SizedBox(height: 16),
                      const Text('جارٍ التحليل الذكي…'),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    if (aiAnalysis != null) ...[
                      const SizedBox(height: 16),
                      const Text(
                        'تحليل الذكاء الاصطناعي',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(aiAnalysis!, style: const TextStyle(height: 1.7)),
                    ],
                    const SizedBox(height: 12),
                    const Text(
                      'قياساتك تظهر فورًا في طبقة «قياساتك» على الخريطة. الطبقة العامة تحتاج عينات من عدة مساهمين.',
                      style: TextStyle(
                        fontSize: 11,
                        color: StcColors.silver,
                        height: 1.7,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class RealHistoryScreen extends StatefulWidget {
  const RealHistoryScreen({super.key});
  @override
  State<RealHistoryScreen> createState() => _RealHistoryScreenState();
}

class _RealHistoryScreenState extends State<RealHistoryScreen> {
  final rows = <Map<String, dynamic>>[];
  bool loading = false, more = true;
  String? error;
  @override
  void initState() {
    super.initState();
    if (networkApi.token != null) load();
  }

  Future<void> load({bool reset = false}) async {
    if (loading) return;
    setState(() {
      loading = true;
      error = null;
      if (reset) rows.clear();
    });
    try {
      final data = await networkApi.request(
        '/api/network-tests/mine',
        query: {'limit': '30', 'offset': '${rows.length}'},
      );
      final items = (data['items'] as List)
          .map((r) => Map<String, dynamic>.from(r))
          .toList();
      if (mounted) {
        setState(() {
          rows.addAll(items);
          more = items.length == 30;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('سجل القياسات الفعلية'),
      actions: [
        IconButton(
          tooltip: 'تحديث',
          onPressed: () => load(reset: true),
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: ListView(
      padding: const EdgeInsets.all(22),
      children: [
        const Text(
          'من قاعدة البيانات • نتائج مكتملة فقط',
          style: TextStyle(
            color: StcColors.purple,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 20),
        if (networkApi.token == null)
          FilledButton(
            onPressed: () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const Directionality(
                    textDirection: TextDirection.rtl,
                    child: ServerAuthScreen(),
                  ),
                ),
              );
              if (mounted && networkApi.token != null) load(reset: true);
            },
            child: const Text('تسجيل الدخول لاستعراض سجلي'),
          ),
        if (loading) const LinearProgressIndicator(),
        if (error != null)
          Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
        if (!loading && rows.isEmpty)
          const Padding(
            padding: EdgeInsets.all(30),
            child: Text(
              'لا توجد قياسات فعلية معروضة. نتائج المحاكاة القديمة لا تدخل هذا السجل.',
            ),
          ),
        for (final row in rows)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    DateTime.fromMillisecondsSinceEpoch(
                      ((row['measurement_time'] as num) * 1000).round(),
                      isUtc: true,
                    ).toLocal().toString().substring(0, 16),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 18,
                    runSpacing: 10,
                    children: [
                      Text(
                        '↓ ${(row['download_mbps'] as num).toStringAsFixed(2)} Mbps',
                      ),
                      Text(
                        '↑ ${(row['upload_mbps'] as num).toStringAsFixed(2)} Mbps',
                      ),
                      Text(
                        'HTTP ${(row['ping_ms'] as num).toStringAsFixed(1)} ms',
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'قياس نقل HTTP مكتمل',
                    style: TextStyle(color: StcColors.silver, fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        if (more && rows.isNotEmpty)
          TextButton(
            onPressed: loading ? null : load,
            child: const Text('تحميل المزيد'),
          ),
        if (rows.isNotEmpty)
          TextButton.icon(
            icon: const Icon(Icons.delete_outline),
            label: const Text('حذف قياساتي من الخادم'),
            onPressed: () async {
              final yes = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('حذف جميع قياساتك؟'),
                  content: const Text(
                    'سيُحذف سجلك ومساهماتك من الخريطة. لا يمكن التراجع.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('إلغاء'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('حذف قياساتي'),
                    ),
                  ],
                ),
              );
              if (yes == true) {
                try {
                  await networkApi.request(
                    '/api/network-tests/mine',
                    method: 'DELETE',
                  );
                  if (mounted) load(reset: true);
                } catch (e) {
                  if (mounted) setState(() => error = e.toString());
                }
              }
            },
          ),
      ],
    ),
  );
}
