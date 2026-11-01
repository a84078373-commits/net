import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'network/network_api.dart';
import 'network/network_test_screen.dart';
import 'network/speed_test_service.dart';
import 'theme.dart';

const _city = LatLng(27.5219, 41.6907);
const _customTileUrl = String.fromEnvironment('SMARTCARE_TILE_URL');
// Free OSM tiles — no API key (Carto CDN now requires a key).
const _osmTiles = 'https://tile.openstreetmap.org/{z}/{x}/{y}.png';
const _views = [
  LatLng(27.549, 41.697),
  LatLng(27.485, 41.704),
  LatLng(27.535, 41.674),
  LatLng(27.511, 41.720),
];
const _mint = StcColors.oasis;

class NetworkMap extends StatefulWidget {
  final int selectedArea;
  final bool fullScreen;
  const NetworkMap({
    super.key,
    required this.selectedArea,
    this.fullScreen = false,
  });
  @override
  State<NetworkMap> createState() => _NetworkMapState();
}

class _NetworkMapState extends State<NetworkMap> {
  final controller = MapController();
  final filters = MapFilters();
  List<QualityCell> cells = [];
  List<QualityCell> mine = [];
  Map<String, dynamic>? configuration;
  DateTime? refreshed;
  bool dark = false,
      heat = true,
      ready = false,
      loading = false,
      tilesFailed = false;
  String? error;
  int sequence = 0;
  Timer? debounce;
  @override
  void initState() {
    super.initState();
    loadConfig();
  }

  Future<void> loadConfig() async {
    try {
      final c = await networkApi.config();
      if (!mounted) return;
      setState(() {
        configuration = c;
        filters.minSamples = (c['quality']['min_samples'] as num).toInt();
      });
      if (ready) await refresh();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  @override
  void didUpdateWidget(covariant NetworkMap old) {
    super.didUpdateWidget(old);
    if (ready && old.selectedArea != widget.selectedArea) {
      controller.move(_views[widget.selectedArea], 13);
      refresh();
    }
  }

  @override
  void dispose() {
    debounce?.cancel();
    sequence++;
    controller.dispose();
    super.dispose();
  }

  Future<void> refresh() async {
    if (!ready) return;
    final current = ++sequence;
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final b = controller.camera.visibleBounds;
      final data = await networkApi.request(
        '/api/network-heatmap',
        query: filters.query([b.west, b.south, b.east, b.north]),
      );
      var own = <QualityCell>[];
      if (networkApi.token != null) {
        try {
          final mineData = await networkApi.request(
            '/api/network-heatmap/mine',
          );
          own = (mineData['cells'] as List)
              .map((c) => QualityCell(Map<String, dynamic>.from(c)))
              .toList();
        } catch (_) {
          own = [];
        }
      }
      if (!mounted || sequence != current) return;
      setState(() {
        cells = (data['cells'] as List)
            .map((c) => QualityCell(Map<String, dynamic>.from(c)))
            .toList();
        mine = own;
        refreshed = DateTime.fromMillisecondsSinceEpoch(
          ((data['generated_at'] as num) * 1000).round(),
          isUtc: true,
        ).toLocal();
      });
    } catch (e) {
      if (mounted && sequence == current) {
        setState(() {
          error = e.toString();
          cells = [];
        });
      }
    } finally {
      if (mounted && sequence == current) setState(() => loading = false);
    }
  }

  Color color(QualityCell cell) {
    if (filters.metric == 'density' &&
        (cell.status == 'ready' || cell.status == 'personal')) {
      return Color.lerp(
        const Color(0xFF7F90E8),
        const Color(0xFFB542F5),
        ((cell.count ?? 5) / 30).clamp(0, 1),
      )!;
    }
    final name = cell.quality(filters.metric);
    final hex =
        (configuration?['quality']?['colors']?[name] ?? '#7B8193') as String;
    return Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);
  }

  Widget tool(IconData icon, String text, VoidCallback action) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: IconButton(
      tooltip: text,
      onPressed: action,
      style: IconButton.styleFrom(
        backgroundColor: const Color(0xED121725),
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      icon: Icon(icon, size: 20),
    ),
  );
  Future<void> locate() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('العودة إلى موقعي'),
        content: const Text(
          'سيُطلب إذن الموقع لتحريك الخريطة إلى خلية تقريبية. طلب الخريطة يرسل حدود العرض إلى API، لكنه لا يحفظ قياسًا أو إحداثيات GPS دقيقة.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('السماح'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final p = await LocationService().locate();
      if (!mounted) return;
      controller.move(LatLng(p.latitude, p.longitude), 13);
      refresh();
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'الموقع غير متاح أو لم يُمنح الإذن؛ يمكنك استكشاف الخريطة يدويًا',
            ),
          ),
        );
      }
    }
  }

  void info(QualityCell? cell) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  cell == null ? 'بيانات الخريطة' : 'ملخص الخلية الجغرافية',
                  style: const TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 14),
                if (cell == null) ...[
                  Text(
                    error ??
                        (cells.isEmpty
                            ? 'لا توجد بيانات منشورة كافية ضمن الحدود والفلاتر الحالية. هذا لا يعني أن الشبكة ضعيفة.'
                            : '${cells.length} خلية متاحة؛ اضغط منطقة ملونة لاستعراض مؤشرات منفصلة.'),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    refreshed == null
                        ? 'لم تصل بيانات من الخادم'
                        : 'آخر تحديث: $refreshed',
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'الرمادي: عينة غير كافية أو بيانات قديمة. تُخفى الخلايا التي يقل عدد مساهميها عن الحد المسموح.',
                  ),
                ] else ...[
                  Text(
                    'خلية ${cell.id}',
                    style: const TextStyle(
                      color: StcColors.purple,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    cell.status == 'ready'
                        ? 'العينة مستوفية للحد الأدنى، وليست ضمانًا للأداء'
                        : cell.status == 'stale'
                        ? 'بيانات قديمة؛ لا يصدر تصنيف حديث'
                        : 'بيانات غير كافية؛ لا يصدر حكم على جودة المنطقة',
                  ),
                  Text(
                    'العينات الصالحة: ${cell.count ?? 'غير منشور لحماية الخصوصية'}',
                  ),
                  if (cell.data['age_hours'] != null)
                    Text('عمر أحدث قياس: ${cell.data['age_hours']} ساعة'),
                  if (cell.data['last_measurement'] != null)
                    Text(
                      'آخر قياس: ${DateTime.fromMillisecondsSinceEpoch(((cell.data['last_measurement'] as num) * 1000).round()).toLocal()}',
                    ),
                  const SizedBox(height: 12),
                  for (final m in [
                    ('download_mbps', 'التنزيل', 'Mbps'),
                    ('upload_mbps', 'الرفع', 'Mbps'),
                    ('ping_ms', 'استجابة HTTP', 'ms'),
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Text(
                        '${m.$2}: المتوسط ${cell.value(m.$1, 'mean')?.toStringAsFixed(2) ?? '—'} • الوسيط ${cell.value(m.$1, 'median')?.toStringAsFixed(2) ?? '—'} ${m.$3}',
                      ),
                    ),
                  const Text(
                    'Jitter وفقد الحزم: غير متاحين. شركة الاتصالات: غير معلومة. لا تُعرض مواقع أفراد أو هوياتهم.',
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'فترة التحليل: ${filters.start.toLocal().toString().substring(0, 16)} — ${filters.end.toLocal().toString().substring(0, 16)}',
                  ),
                ],
                const SizedBox(height: 18),
                const Text(
                  'الألوان تمثل المؤشر المختار فقط؛ كثافة القياسات لا تعني جودة أفضل.',
                  style: TextStyle(color: StcColors.purple),
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => Navigator.pop(c),
                  child: const Text('إغلاق'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void legend() {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'دليل الخريطة',
                style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 14),
              if (filters.metric == 'density')
                const Text(
                  'البنفسجي الأغمق: قياسات منشورة أكثر. لا يمثل جودة الاتصال.',
                )
              else
                for (final item in [
                  ('good', 'جيدة'),
                  ('moderate', 'متوسطة'),
                  ('poor', 'ضعيفة'),
                  ('very_poor', 'ضعيفة جدًا'),
                  ('insufficient', 'عينة غير كافية أو بيانات قديمة'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      children: [
                        Container(
                          width: 15,
                          height: 15,
                          color: Color(
                            int.parse(
                                  ((configuration?['quality']?['colors']?[item
                                                  .$1] ??
                                              '#7B8193')
                                          as String)
                                      .substring(1),
                                  radix: 16,
                                ) |
                                0xFF000000,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(child: Text(item.$2)),
                      ],
                    ),
                  ),
              const SizedBox(height: 10),
              Text(
                configuration?['quality']?['description_ar'] ??
                    'حدود إرشادية للمشروع، وليست معيارًا رسميًا.',
              ),
              const SizedBox(height: 8),
              Text(
                'الحد الأدنى: ${filters.minSamples} قياسات و3 مساهمين مختلفين على الأقل. الأسماء الإدارية غير مستنتجة من الخلايا.',
              ),
              const SizedBox(height: 15),
            ],
          ),
        ),
      ),
    );
  }

  void editFilters() {
    var days = filters.rollingDays ?? 0,
        metric = filters.metric,
        connection = filters.connection,
        minSamples = filters.minSamples;
    double minDown = filters.minDownload, maxPing = filters.maxPing;
    var start = filters.start, end = filters.end;
    final baseMinimum =
        (configuration?['quality']?['min_samples'] as num?)?.toInt() ?? 5;
    String view = 'city';
    showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => StatefulBuilder(
        builder: (c, update) => Directionality(
          textDirection: TextDirection.rtl,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'فلاتر البيانات',
                    style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: view,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'اختيار منطقة العرض',
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: 'city',
                        child: Text('حائل • عرض المدينة'),
                      ),
                      for (final cell in cells)
                        DropdownMenuItem(
                          value: cell.id,
                          child: Text('خلية ${cell.id}'),
                        ),
                    ],
                    onChanged: (v) => update(() => view = v!),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final d in [1, 7, 30])
                        ChoiceChip(
                          label: Text(d == 1 ? 'آخر 24 ساعة' : 'آخر $d يومًا'),
                          selected: days == d,
                          onSelected: (_) => update(() {
                            days = d;
                            end = DateTime.now().toUtc();
                            start = end.subtract(Duration(days: d));
                          }),
                        ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final r = await showDateRangePicker(
                        context: c,
                        firstDate: DateTime.now().subtract(
                          const Duration(days: 89),
                        ),
                        lastDate: DateTime.now(),
                      );
                      if (r != null) {
                        update(() {
                          days = 0;
                          start = r.start.toUtc();
                          end = r.end.add(const Duration(days: 1)).toUtc();
                          if (end.isAfter(DateTime.now().toUtc())) {
                            end = DateTime.now().toUtc();
                          }
                        });
                      }
                    },
                    icon: const Icon(Icons.date_range),
                    label: const Text('نطاق تاريخ مخصص'),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: metric,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'المؤشر المعروض',
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'download',
                        child: Text('جودة التنزيل'),
                      ),
                      DropdownMenuItem(
                        value: 'upload',
                        child: Text('جودة الرفع'),
                      ),
                      DropdownMenuItem(
                        value: 'ping',
                        child: Text('جودة الاستجابة HTTP'),
                      ),
                      DropdownMenuItem(
                        value: 'density',
                        child: Text('كثافة القياسات فقط'),
                      ),
                    ],
                    onChanged: (v) => update(() => metric = v!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: connection,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'نوع الاتصال'),
                    items: const [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text('جميع الاتصالات'),
                      ),
                      DropdownMenuItem(value: 'wifi', child: Text('واي فاي')),
                      DropdownMenuItem(value: 'cellular', child: Text('خلوي')),
                      DropdownMenuItem(value: 'ethernet', child: Text('سلكي')),
                      DropdownMenuItem(
                        value: 'unknown',
                        child: Text('غير معروف'),
                      ),
                    ],
                    onChanged: (v) => update(() => connection = v!),
                  ),
                  const SizedBox(height: 16),
                  Text('الحد الأدنى للعينات: $minSamples'),
                  Slider(
                    value: minSamples.toDouble(),
                    min: baseMinimum.toDouble(),
                    max: math.max(50, baseMinimum + 1).toDouble(),
                    divisions: 9,
                    onChanged: (v) => update(() => minSamples = v.round()),
                  ),
                  Text('تنزيل لا يقل عن ${minDown.toInt()} Mbps'),
                  Slider(
                    value: minDown,
                    min: 0,
                    max: 200,
                    divisions: 20,
                    onChanged: (v) => update(() => minDown = v),
                  ),
                  Text(
                    maxPing == 10000
                        ? 'الاستجابة: دون حد إضافي'
                        : 'الاستجابة لا تتجاوز ${maxPing.toInt()} ms',
                  ),
                  Slider(
                    value: maxPing == 10000 ? 500 : maxPing,
                    min: 50,
                    max: 500,
                    divisions: 9,
                    onChanged: (v) =>
                        update(() => maxPing = v == 500 ? 10000 : v),
                  ),
                  const Text(
                    'شركة الاتصالات غير متاحة من مصدر موثوق؛ فلترها غير مفعّل.',
                    style: TextStyle(color: StcColors.silver, fontSize: 11),
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () {
                      filters.start = start;
                      filters.end = end;
                      filters.rollingDays = days == 0 ? null : days;
                      filters.metric = metric;
                      filters.connection = connection;
                      filters.minSamples = minSamples;
                      filters.minDownload = minDown;
                      filters.maxPing = maxPing;
                      if (view == 'city') {
                        controller.move(_city, 12.3);
                      } else {
                        final selected = cells.firstWhere((c) => c.id == view);
                        final b = selected.bounds;
                        controller.move(
                          LatLng((b[1] + b[3]) / 2, (b[0] + b[2]) / 2),
                          14,
                        );
                      }
                      Navigator.pop(c, true);
                    },
                    child: const Text('تطبيق الفلاتر'),
                  ),
                  TextButton(
                    onPressed: () {
                      final reset = MapFilters();
                      filters.start = reset.start;
                      filters.end = reset.end;
                      filters.rollingDays = 7;
                      filters.metric = 'download';
                      filters.connection = 'all';
                      filters.minSamples = baseMinimum;
                      filters.minDownload = 0;
                      filters.maxPing = 10000;
                      Navigator.pop(c, true);
                    },
                    child: const Text('إعادة ضبط الفلاتر'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ).then((changed) {
      if (changed == true && mounted) refresh();
    });
  }

  void compare() {
    final valid = cells.where((c) => c.status == 'ready').toList()
      ..sort(
        (a, b) => (b.value('download_mbps', 'median') ?? 0).compareTo(
          a.value('download_mbps', 'median') ?? 0,
        ),
      );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => Directionality(
        textDirection: TextDirection.rtl,
        child: ListView(
          padding: const EdgeInsets.all(22),
          children: [
            const Text(
              'مقارنة الخلايا',
              style: TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('نفس الفترة والفلاتر • ترتيب حسب وسيط التنزيل'),
            if (valid.length < 2)
              const Padding(
                padding: EdgeInsets.all(20),
                child: Text('لا توجد خليتان حديثتان بعينة كافية للمقارنة.'),
              ),
            for (final cell in valid)
              ListTile(
                title: Text(cell.id),
                subtitle: Text(
                  'تنزيل ${cell.value('download_mbps', 'median')} Mbps • رفع ${cell.value('upload_mbps', 'median')} Mbps • HTTP ${cell.value('ping_ms', 'median')} ms',
                ),
                trailing: Text('${cell.count} عينة'),
                onTap: () {
                  Navigator.pop(context);
                  info(cell);
                },
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Stack(
    children: [
      FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: _city,
          initialZoom: 12.3,
          minZoom: 7,
          maxZoom: 17,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onMapReady: () {
            ready = true;
            refresh();
          },
          onPositionChanged: (_, gesture) {
            if (gesture) {
              debounce?.cancel();
              debounce = Timer(const Duration(milliseconds: 650), refresh);
            }
          },
          onTap: (_, p) {
            QualityCell? found;
            for (final cell in [...mine, ...cells]) {
              final b = cell.bounds;
              if (p.latitude >= b[1] &&
                  p.latitude <= b[3] &&
                  p.longitude >= b[0] &&
                  p.longitude <= b[2]) {
                found = cell;
                break;
              }
            }
            info(found);
          },
        ),
        children: [
          TileLayer(
            key: ValueKey(dark ? 'dark' : 'light'),
            urlTemplate: _customTileUrl.isNotEmpty ? _customTileUrl : _osmTiles,
            tileBuilder: (context, tile, _) =>
                dark ? darkModeTilesContainerBuilder(context, tile) : tile,
            userAgentPackageName: 'sa.hail.smartcare.networkmap',
            maxNativeZoom: 19,
            panBuffer: 0,
            keepBuffer: 2,
            errorTileCallback: (_, __, ___) {
              if (!tilesFailed && mounted) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) setState(() => tilesFailed = true);
                });
              }
            },
          ),
          if (heat)
            PolygonLayer(
              polygons: [
                for (final c in cells)
                  Polygon(
                    points: [
                      LatLng(c.bounds[1], c.bounds[0]),
                      LatLng(c.bounds[1], c.bounds[2]),
                      LatLng(c.bounds[3], c.bounds[2]),
                      LatLng(c.bounds[3], c.bounds[0]),
                    ],
                    color: color(
                      c,
                    ).withValues(alpha: c.status == 'ready' ? 0.48 : 0.25),
                    borderColor: color(c).withValues(alpha: .7),
                    borderStrokeWidth: 1,
                  ),
                for (final c in mine)
                  Polygon(
                    points: [
                      LatLng(c.bounds[1], c.bounds[0]),
                      LatLng(c.bounds[1], c.bounds[2]),
                      LatLng(c.bounds[3], c.bounds[2]),
                      LatLng(c.bounds[3], c.bounds[0]),
                    ],
                    color: color(c).withValues(alpha: 0.55),
                    borderColor: StcColors.coral,
                    borderStrokeWidth: 3,
                  ),
              ],
            ),
          const Align(
            alignment: Alignment.bottomLeft,
            child: ColoredBox(
              color: Color(0xED121725),
              child: Padding(
                padding: EdgeInsets.all(4),
                child: Text(
                  '© OpenStreetMap © CARTO',
                  textDirection: TextDirection.ltr,
                  style: TextStyle(fontSize: 8, color: Colors.white70),
                ),
              ),
            ),
          ),
        ],
      ),
      Positioned(
        left: 10,
        top: 12,
        child: Column(
          children: [
            tool(
              Icons.add,
              'تكبير',
              () => controller.move(
                controller.camera.center,
                math.min(17, controller.camera.zoom + .7),
              ),
            ),
            tool(
              Icons.remove,
              'تصغير',
              () => controller.move(
                controller.camera.center,
                math.max(7, controller.camera.zoom - .7),
              ),
            ),
            tool(Icons.my_location, 'العودة إلى موقعي', locate),
            tool(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              'تبديل مظهر الخريطة',
              () => setState(() {
                dark = !dark;
                tilesFailed = false;
              }),
            ),
            tool(
              heat ? Icons.layers : Icons.layers_clear,
              'إظهار أو إخفاء الحرارة',
              () => setState(() => heat = !heat),
            ),
            if (!widget.fullScreen)
              tool(
                Icons.fullscreen,
                'ملء الشاشة',
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => Directionality(
                      textDirection: TextDirection.rtl,
                      child: Scaffold(
                        appBar: AppBar(
                          title: const Text('خريطة جودة الإنترنت'),
                        ),
                        body: NetworkMap(
                          selectedArea: widget.selectedArea,
                          fullScreen: true,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
      Positioned(
        right: 10,
        top: 12,
        child: Column(
          children: [
            tool(Icons.tune, 'فلاتر البيانات', editFilters),
            tool(Icons.refresh, 'تحديث البيانات', refresh),
            tool(Icons.speed, 'اختبار الإنترنت', () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const Directionality(
                    textDirection: TextDirection.rtl,
                    child: NetworkTestScreen(),
                  ),
                ),
              );
              if (mounted) refresh();
            }),
            tool(Icons.compare_arrows, 'مقارنة المناطق', compare),
            tool(Icons.palette_outlined, 'دليل الألوان', legend),
          ],
        ),
      ),
      if (loading)
        const Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: LinearProgressIndicator(minHeight: 3),
        ),
      Positioned(
        bottom: 26,
        left: 12,
        right: 12,
        child: Material(
          color: const Color(0xEE121725),
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            onTap: () => info(null),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    error != null
                        ? 'الخدمة غير متاحة'
                        : mine.isNotEmpty
                        ? '${mine.length} قياس لك على الخريطة${cells.isEmpty ? '' : ' • ${cells.length} خلية منشورة'}'
                        : cells.isEmpty
                        ? 'لا توجد بيانات منشورة كافية'
                        : '${cells.length} خلية مجمّعة',
                    style: TextStyle(
                      fontSize: 12,
                      color: error == null ? _mint : Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${{'download': 'التنزيل', 'upload': 'الرفع', 'ping': 'استجابة HTTP', 'density': 'كثافة القياسات'}[filters.metric]} • ${filters.minSamples}+ عينات • ${filters.connection == 'all' ? 'كل الاتصالات' : {'wifi': 'واي فاي', 'cellular': 'خلوي', 'ethernet': 'سلكي', 'unknown': 'غير معروف'}[filters.connection]}',
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                  if (refreshed != null)
                    Text(
                      'تحديث ${refreshed!.hour.toString().padLeft(2, '0')}:${refreshed!.minute.toString().padLeft(2, '0')} • ${(filters.end.difference(filters.start).inHours / 24).ceil()} يوم',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                      ),
                    ),
                  if (filters.minDownload > 0 || filters.maxPing < 10000)
                    Text(
                      'تنزيل ≥ ${filters.minDownload} Mbps • استجابة ≤ ${filters.maxPing} ms',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white54,
                      ),
                    ),
                  if (!heat)
                    const Text(
                      'الحرارة مخفية',
                      style: TextStyle(fontSize: 10, color: Colors.white38),
                    ),
                  if (tilesFailed)
                    const Text(
                      'تعذر تحميل بعض أجزاء الخريطة',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.orangeAccent,
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    ],
  );
}
