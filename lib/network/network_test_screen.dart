import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';
import 'network_api.dart';
import 'server_auth_screen.dart';
import 'speed_test_service.dart';

class NetworkTestScreen extends StatelessWidget {
  const NetworkTestScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.internetQualityTestTitle)),
      body: const SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.all(22),
          child: RealSpeedPanel(),
        ),
      ),
    );
  }
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
  String phase = '';
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

  String _connectionLabel(SpeedResult r, AppLocalizations l10n) {
    if (r.connection == 'cellular') return l10n.connectionMobileNetwork;
    if (r.connection == 'wifi') return l10n.connectionWifi;
    return l10n.connectionUncertain;
  }

  Future<void> run() async {
    if (busy) return;
    final l10n = context.l10n;
    await load();
    if (!mounted) return;
    if (config?['test']?['available'] != true) return;
    if (networkApi.token == null) {
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => const ServerAuthScreen(),
        ),
      );
      if (!mounted || networkApi.token == null) return;
    }
    final consent = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(l10n.testConsentTitle),
        content: Text(
          share ? l10n.testConsentBodyShare : l10n.testConsentBodyNoShare,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.agreeAndStart),
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
      phase = l10n.phaseReady;
    });
    try {
      ApproximateLocation? location;
      var shareThisRun = share;
      if (shareThisRun) {
        setState(() => phase = l10n.phaseLocating);
        try {
          location = await LocationService().locate();
          if (location.accuracy > LocationService.maxShareAccuracyM) {
            shareThisRun = false;
            location = null;
            if (mounted) {
              setState(() => error = l10n.locationAccuracyInsufficient);
            }
          }
        } on NetworkFailure catch (e) {
          shareThisRun = false;
          location = null;
          if (mounted) setState(() => error = e.message);
        }
      }
      if (!mounted || cancelled) {
        throw NetworkFailure(l10n.testCancelledBeforeTransfer);
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
    final l10n = context.l10n;
    setState(() {
      analyzing = true;
      aiAnalysis = null;
    });
    try {
      final prompt = l10n.aiSpeedPrompt(
        download: r.download.toStringAsFixed(1),
        upload: r.upload.toStringAsFixed(1),
        ping: r.ping.toStringAsFixed(0),
        connection: _connectionLabel(r, l10n),
        cellId: mappedCellId,
      );
      final res = await networkApi.request(
        '/api/ai/analyze',
        method: 'POST',
        body: {'text': prompt},
      );
      if (mounted) {
        setState(
          () => aiAnalysis = res['analysis']?.toString() ?? l10n.aiNoResult,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => aiAnalysis = l10n.aiAnalysisFailed(e.toString()));
      }
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Widget block(Widget child) =>
      StcCard(margin: const EdgeInsets.only(bottom: 16), child: child);
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
            Text(
              l10n.measurementSectionTitle,
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w800,
                color: StcColors.onyx,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              l10n.speedTestIntro,
              style: const TextStyle(color: StcColors.silver, height: 1.7),
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
                    Text(
                      l10n.testUnavailableTitle,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      config?['test']?['reason']?.toString() ??
                          l10n.testUnavailableDefault,
                      style: const TextStyle(
                        color: StcColors.silver,
                        height: 1.7,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: load,
                      icon: const Icon(Icons.refresh),
                      label: Text(l10n.retryCheck),
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
                    title: Text(l10n.shareOnMapSwitch),
                    subtitle: Text(
                      l10n.shareOnMapSubtitle,
                      style: const TextStyle(
                        fontSize: 11,
                        color: StcColors.silver,
                      ),
                    ),
                    value: share,
                    onChanged: busy || saving || saved
                        ? null
                        : (v) => setState(() => share = v),
                  ),
                  if (busy) ...[
                    const SizedBox(height: 20),
                    Text(phase.isEmpty ? l10n.phaseReady : phase),
                    const SizedBox(height: 12),
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () {
                        cancelled = true;
                        service.cancel();
                      },
                      child: Text(l10n.cancelTest),
                    ),
                  ] else if (available)
                    StcCoralBar(
                      title: result == null
                          ? l10n.startSpeedTest
                          : l10n.newTest,
                      action: l10n.startAction,
                      onTap: run,
                    ),
                  const SizedBox(height: 12),
                  Text(
                    l10n.jitterDisclaimer,
                    style: const TextStyle(
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
                        Expanded(
                          child: Text(
                            l10n.yourResultTitle,
                            style: const TextStyle(
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
                      label: l10n.download,
                      value: '${result!.download.toStringAsFixed(2)} Mbps',
                      progress: (result!.download / 300).clamp(0.08, 1),
                    ),
                    StcUsageBar(
                      icon: Icons.north_rounded,
                      label: l10n.upload,
                      value: '${result!.upload.toStringAsFixed(2)} Mbps',
                      progress: (result!.upload / 100).clamp(0.08, 1),
                    ),
                    StcUsageBar(
                      icon: Icons.bolt_outlined,
                      label: l10n.httpLatency,
                      value: '${result!.ping.toStringAsFixed(1)} ms',
                      progress: (1 - (result!.ping / 200)).clamp(0.08, 1),
                    ),
                    Text(
                      '${_connectionLabel(result!, l10n)} • ${((result!.downloadBytes + result!.uploadBytes) / 1048576).toStringAsFixed(1)} MiB',
                      style: const TextStyle(color: StcColors.silver),
                    ),
                    const SizedBox(height: 8),
                    if (share && result!.location == null)
                      Text(
                        l10n.noLocationForTest,
                        style: const TextStyle(color: Colors.orangeAccent),
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
                            ? l10n.savedToDatabase
                            : saving
                            ? l10n.saving
                            : share
                            ? l10n.saveResultShare
                            : l10n.saveResultPrivate,
                      ),
                    ),
                    if (mappedCellId != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        l10n.mappedCellLine(mappedCellId!),
                        style: const TextStyle(
                          color: StcColors.purple,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                    if (analyzing) ...[
                      const SizedBox(height: 16),
                      Text(l10n.analyzing),
                      const SizedBox(height: 8),
                      const LinearProgressIndicator(),
                    ],
                    if (aiAnalysis != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        l10n.aiAnalysisTitle,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(aiAnalysis!, style: const TextStyle(height: 1.7)),
                    ],
                    const SizedBox(height: 12),
                    Text(
                      l10n.mapLayerNote,
                      style: const TextStyle(
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
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.realHistoryTitle),
        actions: [
          IconButton(
            tooltip: l10n.refresh,
            onPressed: () => load(reset: true),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(22),
        children: [
          Text(
            l10n.realHistorySubtitle,
            style: const TextStyle(
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
                    builder: (_) => const ServerAuthScreen(),
                  ),
                );
                if (mounted && networkApi.token != null) load(reset: true);
              },
              child: Text(l10n.signInToViewHistory),
            ),
          if (loading) const LinearProgressIndicator(),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.orangeAccent)),
          if (!loading && rows.isEmpty)
            Padding(
              padding: const EdgeInsets.all(30),
              child: Text(l10n.realHistoryEmpty),
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
                    Text(
                      l10n.httpTestCompleted,
                      style: const TextStyle(
                        color: StcColors.silver,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (more && rows.isNotEmpty)
            TextButton(
              onPressed: loading ? null : load,
              child: Text(l10n.loadMore),
            ),
          if (rows.isNotEmpty)
            TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: Text(l10n.deleteMyMeasurementsFromServer),
              onPressed: () async {
                final yes = await showDialog<bool>(
                  context: context,
                  builder: (c) => AlertDialog(
                    title: Text(l10n.deleteAllMeasurementsTitle),
                    content: Text(l10n.deleteAllMeasurementsBody),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(c, false),
                        child: Text(l10n.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(c, true),
                        child: Text(l10n.deleteMyMeasurements),
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
}
