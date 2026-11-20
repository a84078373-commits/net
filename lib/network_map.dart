import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'l10n/app_localizations.dart';
import 'network/network_api.dart';
import 'network/network_test_screen.dart';
import 'network/speed_test_service.dart';
import 'theme.dart';

const _city = LatLng(27.5219, 41.6907);
const _customTileUrl = String.fromEnvironment('SMARTCARE_TILE_URL');
// Free Esri streets — no API key (OSM.org volunteer tiles return 403 for many apps).
const _osmTiles =
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}';
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

  String _metricLabel(AppLocalizations l10n, String metric) {
    switch (metric) {
      case 'upload':
        return l10n.upload;
      case 'ping':
        return l10n.httpLatency;
      case 'density':
        return l10n.metricDensityOnly;
      default:
        return l10n.download;
    }
  }

  String _connectionLabel(AppLocalizations l10n, String connection) {
    switch (connection) {
      case 'wifi':
        return l10n.connectionWifi;
      case 'cellular':
        return l10n.connectionCellular;
      case 'ethernet':
        return l10n.connectionEthernet;
      case 'unknown':
        return l10n.unknown;
      default:
        return l10n.allConnections;
    }
  }

  String _qualityDescription(AppLocalizations l10n) {
    final quality = configuration?['quality'];
    if (quality == null) return l10n.mapQualityGuidelinesFallback;
    if (l10n.isArabic) {
      return (quality['description_ar'] as String?) ??
          l10n.mapQualityGuidelinesFallback;
    }
    return (quality['description_en'] as String?) ??
        (quality['description_ar'] as String?) ??
        l10n.mapQualityGuidelinesFallback;
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
    final l10n = context.l10n;
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.goToMyLocationTitle),
        content: Text(l10n.goToMyLocationBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.allow),
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
          SnackBar(content: Text(l10n.locationUnavailableSnack)),
        );
      }
    }
  }

  void info(QualityCell? cell) {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                cell == null ? l10n.mapDataTitle : l10n.cellSummaryTitle,
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
                          ? l10n.mapNoDataMessage
                          : l10n.mapCellsAvailable(cells.length)),
                ),
                const SizedBox(height: 12),
                Text(
                  refreshed == null
                      ? l10n.mapNoServerData
                      : l10n.mapLastUpdate('$refreshed'),
                ),
                const SizedBox(height: 12),
                Text(l10n.mapGrayCellsNote),
              ] else ...[
                Text(
                  l10n.cellIdLine(cell.id),
                  style: const TextStyle(
                    color: StcColors.purple,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  cell.status == 'ready'
                      ? l10n.cellStatusReady
                      : cell.status == 'stale'
                      ? l10n.cellStatusStale
                      : l10n.cellStatusInsufficient,
                ),
                Text(
                  l10n.cellValidSamplesLine(
                    '${cell.count ?? l10n.cellSamplesWithheld}',
                  ),
                ),
                if (cell.data['age_hours'] != null)
                  Text(
                    l10n.cellAgeHoursValue(
                      (cell.data['age_hours'] as num).toInt(),
                    ),
                  ),
                if (cell.data['last_measurement'] != null)
                  Text(
                    l10n.cellLastMeasurementValue(
                      DateTime.fromMillisecondsSinceEpoch(
                        ((cell.data['last_measurement'] as num) * 1000)
                            .round(),
                      ).toLocal().toString(),
                    ),
                  ),
                const SizedBox(height: 12),
                for (final m in [
                  ('download_mbps', 'download', 'Mbps'),
                  ('upload_mbps', 'upload', 'Mbps'),
                  ('ping_ms', 'ping', 'ms'),
                ])
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      l10n.cellMetricRow(
                        m.$2 == 'download'
                            ? l10n.download
                            : m.$2 == 'upload'
                            ? l10n.upload
                            : l10n.httpLatency,
                        cell.value(m.$1, 'mean')?.toStringAsFixed(2) ?? '—',
                        cell.value(m.$1, 'median')?.toStringAsFixed(2) ?? '—',
                        m.$3,
                      ),
                    ),
                  ),
                Text(l10n.cellTechnicalDisclaimer),
                const SizedBox(height: 12),
                Text(
                  l10n.cellAnalysisPeriodRange(
                    filters.start.toLocal().toString().substring(0, 16),
                    filters.end.toLocal().toString().substring(0, 16),
                  ),
                ),
              ],
              const SizedBox(height: 18),
              Text(
                l10n.mapColorsDisclaimer,
                style: const TextStyle(color: StcColors.purple),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(c),
                child: Text(l10n.close),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void legend() {
    final l10n = context.l10n;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.mapLegendTitle,
              style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 14),
            if (filters.metric == 'density')
              Text(l10n.legendDensity)
            else
              for (final item in [
                ('good', l10n.qualityGood),
                ('moderate', l10n.qualityModerate),
                ('poor', l10n.qualityPoor),
                ('very_poor', l10n.qualityVeryPoor),
                ('insufficient', l10n.qualityInsufficient),
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
                                ((configuration?['quality']?['colors']?[item.$1] ??
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
            Text(_qualityDescription(l10n)),
            const SizedBox(height: 8),
            Text(l10n.mapLegendMinSamplesNote(filters.minSamples)),
            const SizedBox(height: 15),
          ],
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
        builder: (c, update) {
          final sheetL10n = AppLocalizations.of(c);
          return SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(22),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    sheetL10n.dataFiltersTitle,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: view,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: sheetL10n.viewAreaLabel,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'city',
                        child: Text(sheetL10n.viewCityHail),
                      ),
                      for (final cell in cells)
                        DropdownMenuItem(
                          value: cell.id,
                          child: Text(sheetL10n.cellIdLine(cell.id)),
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
                          label: Text(
                            d == 1
                                ? sheetL10n.filterLast24h
                                : sheetL10n.filterLastDays(d),
                          ),
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
                    label: Text(sheetL10n.customDateRange),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: metric,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: sheetL10n.displayMetric,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'download',
                        child: Text(sheetL10n.metricDownloadQuality),
                      ),
                      DropdownMenuItem(
                        value: 'upload',
                        child: Text(sheetL10n.metricUploadQuality),
                      ),
                      DropdownMenuItem(
                        value: 'ping',
                        child: Text(sheetL10n.metricHttpQuality),
                      ),
                      DropdownMenuItem(
                        value: 'density',
                        child: Text(sheetL10n.metricDensityOnly),
                      ),
                    ],
                    onChanged: (v) => update(() => metric = v!),
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    initialValue: connection,
                    isExpanded: true,
                    decoration: InputDecoration(
                      labelText: sheetL10n.connectionType,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'all',
                        child: Text(sheetL10n.allConnections),
                      ),
                      DropdownMenuItem(
                        value: 'wifi',
                        child: Text(sheetL10n.connectionWifi),
                      ),
                      DropdownMenuItem(
                        value: 'cellular',
                        child: Text(sheetL10n.connectionCellular),
                      ),
                      DropdownMenuItem(
                        value: 'ethernet',
                        child: Text(sheetL10n.connectionEthernet),
                      ),
                      DropdownMenuItem(
                        value: 'unknown',
                        child: Text(sheetL10n.unknown),
                      ),
                    ],
                    onChanged: (v) => update(() => connection = v!),
                  ),
                  const SizedBox(height: 16),
                  Text('${sheetL10n.minSamplesLabel}: $minSamples'),
                  Slider(
                    value: minSamples.toDouble(),
                    min: baseMinimum.toDouble(),
                    max: math.max(50, baseMinimum + 1).toDouble(),
                    divisions: 9,
                    onChanged: (v) => update(() => minSamples = v.round()),
                  ),
                  Text(sheetL10n.filterMinDownloadAtLeast(minDown.toInt())),
                  Slider(
                    value: minDown,
                    min: 0,
                    max: 200,
                    divisions: 20,
                    onChanged: (v) => update(() => minDown = v),
                  ),
                  Text(
                    maxPing == 10000
                        ? sheetL10n.filterPingNoExtraCap
                        : sheetL10n.filterPingAtMost(maxPing.toInt()),
                  ),
                  Slider(
                    value: maxPing == 10000 ? 500 : maxPing,
                    min: 50,
                    max: 500,
                    divisions: 9,
                    onChanged: (v) =>
                        update(() => maxPing = v == 500 ? 10000 : v),
                  ),
                  Text(
                    sheetL10n.mapCarrierFilterUnavailable,
                    style: const TextStyle(
                      color: StcColors.silver,
                      fontSize: 11,
                    ),
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
                    child: Text(sheetL10n.applyFilters),
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
                    child: Text(sheetL10n.resetFilters),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    ).then((changed) {
      if (changed == true && mounted) refresh();
    });
  }

  void compare() {
    final l10n = context.l10n;
    final valid = cells.where((c) => c.status == 'ready').toList()
      ..sort(
        (a, b) => (b.value('download_mbps', 'median') ?? 0).compareTo(
          a.value('download_mbps', 'median') ?? 0,
        ),
      );
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            l10n.compareCellsTitle,
            style: const TextStyle(fontSize: 23, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Text(l10n.compareCellsSubtitle),
          if (valid.length < 2)
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(l10n.compareCellsInsufficient),
            ),
          for (final cell in valid)
            ListTile(
              title: Text(cell.id),
              subtitle: Text(
                l10n.compareCellMetrics(
                  '${cell.value('download_mbps', 'median')}',
                  '${cell.value('upload_mbps', 'median')}',
                  '${cell.value('ping_ms', 'median')}',
                ),
              ),
              trailing: Text(l10n.sampleCount(cell.count ?? 0)),
              onTap: () {
                Navigator.pop(context);
                info(cell);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Stack(
    children: [
      FlutterMap(
        mapController: controller,
        options: MapOptions(
          initialCenter: _city,
          initialZoom: 12.3,
          minZoom: 2,
          maxZoom: 18,
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
          Align(
            alignment: Alignment.bottomLeft,
            child: ColoredBox(
              color: const Color(0xED121725),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Text(
                  l10n.mapAttribution,
                  textDirection: TextDirection.ltr,
                  style: const TextStyle(fontSize: 8, color: Colors.white70),
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
              l10n.zoomIn,
              () => controller.move(
                controller.camera.center,
                math.min(18, controller.camera.zoom + .7),
              ),
            ),
            tool(
              Icons.remove,
              l10n.zoomOut,
              () => controller.move(
                controller.camera.center,
                math.max(2, controller.camera.zoom - .7),
              ),
            ),
            tool(
              Icons.home_outlined,
              l10n.backToHail,
              () {
                controller.move(_city, 12.3);
                refresh();
              },
            ),
            tool(Icons.my_location, l10n.myCurrentLocation, locate),
            tool(
              dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
              l10n.toggleMapTheme,
              () => setState(() {
                dark = !dark;
                tilesFailed = false;
              }),
            ),
            tool(
              heat ? Icons.layers : Icons.layers_clear,
              l10n.toggleHeatmap,
              () => setState(() => heat = !heat),
            ),
            if (!widget.fullScreen)
              tool(
                Icons.fullscreen,
                l10n.fullScreen,
                () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (routeContext) => Scaffold(
                      appBar: AppBar(
                        title: Text(
                          AppLocalizations.of(routeContext)
                              .internetQualityMapTitle,
                        ),
                      ),
                      body: NetworkMap(
                        selectedArea: widget.selectedArea,
                        fullScreen: true,
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
            tool(Icons.tune, l10n.tooltipFilters, editFilters),
            tool(Icons.refresh, l10n.tooltipRefresh, refresh),
            tool(Icons.speed, l10n.tooltipSpeedTest, () async {
              await Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const NetworkTestScreen(),
                ),
              );
              if (mounted) refresh();
            }),
            tool(Icons.compare_arrows, l10n.tooltipCompare, compare),
            tool(Icons.palette_outlined, l10n.tooltipLegend, legend),
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
                        ? l10n.mapBannerError
                        : mine.isNotEmpty
                        ? l10n.mapBannerMine(mine.length, cells.length)
                        : cells.isEmpty
                        ? l10n.mapBannerEmpty
                        : l10n.mapBannerPublic(cells.length),
                    style: TextStyle(
                      fontSize: 12,
                      color: error == null ? _mint : Colors.orangeAccent,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.mapBannerFilterSummary(
                      _metricLabel(l10n, filters.metric),
                      filters.minSamples,
                      _connectionLabel(l10n, filters.connection),
                    ),
                    style: const TextStyle(color: Colors.white54, fontSize: 10),
                  ),
                  if (refreshed != null)
                    Text(
                      l10n.mapBannerUpdated(
                        '${refreshed!.hour.toString().padLeft(2, '0')}:${refreshed!.minute.toString().padLeft(2, '0')}',
                        (filters.end.difference(filters.start).inHours / 24)
                            .ceil(),
                      ),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                      ),
                    ),
                  if (filters.minDownload > 0 || filters.maxPing < 10000)
                    Text(
                      l10n.mapBannerThresholds(
                        filters.minDownload,
                        filters.maxPing,
                      ),
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white54,
                      ),
                    ),
                  if (!heat)
                    Text(
                      l10n.heatmapHidden,
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                      ),
                    ),
                  if (tilesFailed)
                    Text(
                      l10n.mapTilesFailed,
                      style: const TextStyle(
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
}
