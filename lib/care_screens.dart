import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app_store.dart';
import 'l10n/app_localizations.dart';
import 'network/server_auth_screen.dart';
import 'network/network_test_screen.dart';
import 'network/network_api.dart';
import 'theme.dart';
import 'widgets/language_switcher.dart';

const _purple = StcColors.purple, _mint = StcColors.oasis;
const _reportCategoryKeys = ['slow', 'weak', 'dropped', 'unstable'];
const _statusPending = 'بانتظار الربط';
const _statusClosedDemo = 'مغلق تجريبيًا';

void openCare(BuildContext context, Widget screen) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => screen));

String areaLabel(AppLocalizations l10n, String key) {
  switch (normalizeAreaKey(key)) {
    case 'naqrah':
      return l10n.neighborhoodNaqrah;
    case 'jamiin':
      return l10n.neighborhoodJamiin;
    case 'central':
      return l10n.neighborhoodCentralHail;
    default:
      return l10n.neighborhoodMuntazah;
  }
}

String normalizeCategoryKey(String value) {
  const legacy = {
    'بطء الإنترنت': 'slow',
    'Slow internet': 'slow',
    'ضعف الإشارة': 'weak',
    'Weak signal': 'weak',
    'انقطاع المكالمات': 'dropped',
    'Dropped calls': 'dropped',
    'اتصال غير مستقر': 'unstable',
    'Unstable connection': 'unstable',
  };
  if (_reportCategoryKeys.contains(value)) return value;
  return legacy[value] ?? 'slow';
}

String categoryLabel(AppLocalizations l10n, String key) {
  switch (normalizeCategoryKey(key)) {
    case 'weak':
      return l10n.reportCategoryWeakSignal;
    case 'dropped':
      return l10n.reportCategoryDroppedCalls;
    case 'unstable':
      return l10n.reportCategoryUnstable;
    default:
      return l10n.reportCategorySlowInternet;
  }
}

bool isReportClosedStatus(String status) => status == _statusClosedDemo;

String reportStatusLabel(AppLocalizations l10n, String status) {
  if (isReportClosedStatus(status)) return l10n.reportStatusClosedDemo;
  if (status == _statusPending) return l10n.reportStatusPending;
  return status;
}

void toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

class CarePage extends StatelessWidget {
  final String title;
  final String? eyebrow;
  final List<Widget> children;
  final List<Widget>? actions;
  const CarePage({
    super.key,
    required this.title,
    this.eyebrow,
    required this.children,
    this.actions,
  });
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
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
                  eyebrow ?? l10n.eyebrowSmartcareHail,
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
      final l10n = context.l10n;
      final items = <(IconData, String, Widget)>[
        (Icons.person_outline, l10n.profile, const ProfileScreen()),
        (Icons.history, l10n.measurementHistory, const HistoryScreen()),
        (Icons.notifications_none, l10n.notifications, const NoticesScreen()),
        (Icons.cloud_sync_outlined, l10n.saveAndSync, const SyncScreen()),
        (Icons.tune, l10n.settings, const SettingsScreen()),
        if (networkApi.isAdmin)
          (
            Icons.admin_panel_settings_outlined,
            l10n.adminPanel,
            const AdminScreen(),
          ),
        (Icons.help_outline, l10n.help, const HelpScreen()),
        (Icons.privacy_tip_outlined, l10n.privacy, const PrivacyScreen()),
      ];
      return CarePage(
        title: l10n.navMore,
        eyebrow: l10n.eyebrowAppCenter,
        children: [
          CareCard(
            Row(
              children: [
                const StcProfileAvatar(
                  radius: 28,
                  backgroundColor: StcColors.purpleSoft,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      titleText(appStore.name),
                      muted(
                        appStore.signedIn
                            ? l10n.accountServerSession
                            : l10n.guestBrowseBlurb,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          titleText(l10n.appCenter),
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
              l10n.signInOrRegister,
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
  late String area = normalizeAreaKey(appStore.area);
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CarePage(
      title: l10n.myProfile,
      children: [
        const Center(
          child: StcProfileAvatar(radius: 46, backgroundColor: Colors.white),
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
                  decoration: InputDecoration(labelText: l10n.nameLabel),
                  validator: (v) => (v ?? '').trim().length < 2
                      ? l10n.nameValidationMin
                      : null,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: area,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: l10n.preferredNeighborhood,
                  ),
                  items: neighborhoodKeys
                      .map(
                        (key) => DropdownMenuItem(
                          value: key,
                          child: Text(areaLabel(l10n, key)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => area = v!,
                ),
                const SizedBox(height: 20),
                muted(
                  appStore.phone.isEmpty
                      ? l10n.browsingAsGuest
                      : l10n.mobileNumberLine(appStore.phone),
                ),
                const SizedBox(height: 20),
                actionButton(l10n.saveChanges, () {
                  if (!form.currentState!.validate()) return;
                  appStore.name = name.text.trim();
                  appStore.area = area;
                  appStore.changed();
                  toast(context, l10n.profileUpdatedToast);
                }, icon: Icons.check),
              ],
            ),
          ),
        ),
        muted(l10n.profileLocalBetaNote),
      ],
    );
  }
}

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) {
      final l10n = context.l10n;
      return CarePage(
        title: l10n.settings,
        children: [
          CareCard(
            Column(
              children: [
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.inAppNotifications),
                  subtitle: muted(l10n.inAppNotificationsSubtitle),
                  value: appStore.notifications,
                  onChanged: (v) {
                    appStore.notifications = v;
                    appStore.changed();
                  },
                ),
                const Divider(),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(l10n.autoSaveOnDevice),
                  subtitle: muted(l10n.autoSaveSubtitle),
                  value: appStore.autoSave,
                  onChanged: (v) async {
                    appStore.autoSave = v;
                    await appStore.save();
                  },
                ),
              ],
            ),
          ),
          const CareCard(LanguageSwitcher()),
          CareCard(
            Column(
              children: [
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.light_mode_outlined, color: _mint),
                  title: Text(l10n.appearance),
                  trailing: Text(l10n.appearanceLightStc),
                ),
                const Divider(),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.privacy_tip_outlined, color: _mint),
                  title: Text(l10n.privacyAndData),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () => openCare(context, const PrivacyScreen()),
                ),
              ],
            ),
          ),
          actionButton(
            l10n.saveAndSync,
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
                toast(context, l10n.signedOutToast);
              },
              icon: const Icon(Icons.logout),
              label: Text(l10n.signOut),
            ),
        ],
      );
    },
  );
}

class ReportsPanel extends StatefulWidget {
  final VoidCallback onNew;
  const ReportsPanel({super.key, required this.onNew});
  @override
  State<ReportsPanel> createState() => _ReportsPanelState();
}

class _ReportsPanelState extends State<ReportsPanel> {
  String filter = 'all';
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) {
      final l10n = context.l10n;
      final reports = appStore.reports
          .where(
            (r) =>
                filter == 'all' ||
                (filter == 'closed'
                    ? isReportClosedStatus(r.status)
                    : !isReportClosedStatus(r.status)),
          )
          .toList();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            l10n.myReports,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w800,
              color: StcColors.onyx,
            ),
          ),
          const SizedBox(height: 8),
          muted(l10n.reportsLocalNotStc),
          const SizedBox(height: 18),
          actionButton(
            l10n.createNewReport,
            () => openCare(context, const NewReportScreen()),
            icon: Icons.add,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            children: [
              ('all', l10n.filterAll),
              ('open', l10n.filterOpen),
              ('closed', l10n.filterClosed),
            ]
                .map(
                  (f) => ChoiceChip(
                    label: Text(f.$2),
                    selected: filter == f.$1,
                    onSelected: (_) => setState(() => filter = f.$1),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 16),
          if (reports.isEmpty)
            emptyState(
              Icons.task_alt,
              l10n.reportsEmptyTitle,
              l10n.reportsEmptyBody,
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
                            categoryLabel(l10n, r.category),
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
                    muted(
                      '${areaLabel(l10n, r.area)} • ${dateLabel(r.created)}',
                    ),
                    const SizedBox(height: 8),
                    Text(
                      reportStatusLabel(l10n, r.status),
                      style: const TextStyle(color: _mint, fontSize: 12),
                    ),
                    muted(l10n.notSentToStc),
                  ],
                ),
              ),
            ),
          TextButton.icon(
            onPressed: widget.onNew,
            icon: const Icon(Icons.auto_awesome),
            label: Text(l10n.diagnoseFirst),
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
  String area = normalizeAreaKey(appStore.area);
  String category = _reportCategoryKeys.first;
  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CarePage(
      title: l10n.newReport,
      children: [
        CareCard(
          Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                titleText(l10n.newReportIntro),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: category,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.issueType),
                  items: _reportCategoryKeys
                      .map(
                        (key) => DropdownMenuItem(
                          value: key,
                          child: Text(categoryLabel(l10n, key)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => category = v!,
                ),
                const SizedBox(height: 20),
                DropdownButtonFormField<String>(
                  initialValue: area,
                  isExpanded: true,
                  decoration: InputDecoration(labelText: l10n.neighborhood),
                  items: neighborhoodKeys
                      .map(
                        (key) => DropdownMenuItem(
                          value: key,
                          child: Text(areaLabel(l10n, key)),
                        ),
                      )
                      .toList(),
                  onChanged: (v) => area = v!,
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: text,
                  minLines: 4,
                  maxLines: 6,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: l10n.problemDescription,
                    hintText: l10n.problemDescriptionHint,
                    alignLabelWithHint: true,
                  ),
                  validator: (v) => (v ?? '').trim().length < 10
                      ? l10n.descriptionMinLength
                      : null,
                ),
                const SizedBox(height: 20),
                actionButton(l10n.saveReportLocally, () {
                  if (!form.currentState!.validate()) return;
                  final r = appStore.addReport(
                    text.text.trim(),
                    selectedArea: area,
                    category: category,
                  );
                  Navigator.of(context).pushReplacement(
                    MaterialPageRoute<void>(
                      builder: (_) => ReportDetailScreen(report: r),
                    ),
                  );
                }, icon: Icons.add_task),
                const SizedBox(height: 12),
                muted(l10n.reportLocalOnlyNote),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class ReportDetailScreen extends StatelessWidget {
  final CareReport report;
  const ReportDetailScreen({super.key, required this.report});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (_, __) {
      final l10n = context.l10n;
      final closed = isReportClosedStatus(report.status);
      final localSaveDone = !appStore.storageFailed && appStore.autoSave;
      return CarePage(
        title: l10n.reportDetails,
        children: [
          CareCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.receipt_long, color: _purple, size: 36),
                const SizedBox(height: 16),
                titleText(categoryLabel(l10n, report.category)),
                const SizedBox(height: 8),
                SelectableText(
                  report.id,
                  style: const TextStyle(color: _mint, fontSize: 11),
                ),
                const SizedBox(height: 16),
                Text(report.description, style: const TextStyle(height: 1.8)),
                const Divider(height: 30),
                muted(l10n.reportAreaLine(areaLabel(l10n, report.area))),
                muted(l10n.reportCreatedLine(dateLabel(report.created))),
                const SizedBox(height: 8),
                Text(
                  reportStatusLabel(l10n, report.status),
                  style: const TextStyle(color: _mint),
                ),
              ],
            ),
          ),
          CareCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText(l10n.followUpPath),
                const SizedBox(height: 20),
                for (final step in <(String, String, bool)>[
                  (l10n.stepReportCreated, l10n.stepAddedLocally, true),
                  (
                    l10n.stepLocalSave,
                    appStore.storageFailed
                        ? l10n.stepSaveFailed
                        : appStore.autoSave
                        ? l10n.stepAutoSaveOn
                        : l10n.stepManualSave,
                    localSaveDone,
                  ),
                  (l10n.stepSupportLink, l10n.stepNotLinkedStc, false),
                  (
                    l10n.stepLocalStatus,
                    reportStatusLabel(l10n, report.status),
                    closed,
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
                  titleText(l10n.initialRecommendation),
                  const SizedBox(height: 12),
                  Text(report.recommendation),
                  const SizedBox(height: 8),
                  muted(l10n.recommendationDisclaimer),
                ],
              ),
            ),
          actionButton(
            closed ? l10n.reopenLocally : l10n.closeLocally,
            () => appStore.updateStatus(
              report,
              closed ? _statusPending : _statusClosedDemo,
            ),
            icon: Icons.check_circle_outline,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(
                ClipboardData(
                  text:
                      '${report.id}\n${report.description}\n${areaLabel(l10n, report.area)}\n${reportStatusLabel(l10n, report.status)}\n${l10n.clipboardReportFooter}',
                ),
              );
              if (context.mounted) toast(context, l10n.reportCopiedToast);
            },
            icon: const Icon(Icons.copy),
            label: Text(l10n.copyReportSummary),
          ),
        ],
      );
    },
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
    builder: (_, __) {
      final l10n = context.l10n;
      return CarePage(
        title: l10n.notifications,
        actions: [
          IconButton(
            tooltip: l10n.markAllRead,
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
            CareCard(Text(l10n.notificationsDisabled)),
          if (appStore.notices.isEmpty)
            emptyState(
              Icons.notifications_none,
              l10n.noticesEmptyTitle,
              l10n.noticesEmptyBody,
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
      );
    },
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
    builder: (_, __) {
      final l10n = context.l10n;
      final localCount = appStore.reports.length + appStore.measurements.length;
      return CarePage(
        title: l10n.saveAndSync,
        children: [
          const Center(
            child: Icon(Icons.cloud_off_outlined, size: 80, color: _purple),
          ),
          const SizedBox(height: 20),
          CareCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleText(l10n.syncHeroTitle),
                const SizedBox(height: 12),
                muted(l10n.syncOfflineBlurb),
                const SizedBox(height: 18),
                Text(
                  appStore.storageFailed
                      ? l10n.storageFailed
                      : l10n.storageAvailable,
                  style: TextStyle(
                    color: appStore.storageFailed
                        ? Colors.orangeAccent
                        : _mint,
                  ),
                ),
                const SizedBox(height: 8),
                muted(
                  appStore.lastSaved == null
                      ? l10n.noSaveYet
                      : l10n.lastSavedLine(dateLabel(appStore.lastSaved!)),
                ),
                const Divider(height: 28),
                muted(l10n.syncDataSplitNote),
                muted(l10n.reportsSentToStcCount),
                muted(l10n.localItemsCount(localCount)),
              ],
            ),
          ),
          actionButton(saving ? l10n.saving : l10n.saveDataNow, () async {
            if (saving) return;
            setState(() => saving = true);
            await appStore.save();
            if (!mounted) return;
            setState(() => saving = false);
            if (context.mounted) {
              toast(
                context,
                appStore.storageFailed
                    ? l10n.saveFailedToast
                    : l10n.saveSuccessToast,
              );
            }
          }, icon: Icons.save_outlined),
          const SizedBox(height: 16),
          CareCard(
            Text(
              l10n.syncLongDisclaimer,
              style: const TextStyle(
                color: StcColors.silver,
                height: 1.8,
                fontSize: 12,
              ),
            ),
          ),
        ],
      );
    },
  );
}

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});
  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen>
    with SingleTickerProviderStateMixin {
  late final TabController tabs;
  Map<String, dynamic>? overview;
  List<Map<String, dynamic>> users = [], measurements = [];
  final gemini = TextEditingController();
  final analyze = TextEditingController();
  final userQuery = TextEditingController();
  String? geminiMasked, analysis, error;
  bool loading = true, savingKey = false, analyzing = false;

  @override
  void initState() {
    super.initState();
    tabs = TabController(length: 4, vsync: this);
    networkApi.addListener(_onAuth);
    reload();
  }

  void _onAuth() {
    if (mounted) setState(() {});
    if (networkApi.isAdmin) reload();
  }

  @override
  void dispose() {
    networkApi.removeListener(_onAuth);
    tabs.dispose();
    gemini.dispose();
    analyze.dispose();
    userQuery.dispose();
    super.dispose();
  }

  String _n(num? v, [int digits = 1]) =>
      v == null ? '—' : v.toStringAsFixed(digits);

  Future<void> reload() async {
    if (networkApi.token == null || !networkApi.isAdmin) {
      setState(() {
        loading = false;
        error = AppLocalizations(appStore.locale).adminSignInRequired;
      });
      return;
    }
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final o = await networkApi.request('/api/admin/overview');
      final u = await networkApi.request('/api/admin/users');
      final m = await networkApi.request(
        '/api/admin/measurements',
        query: {'limit': '100'},
      );
      final s = await networkApi.request('/api/admin/settings');
      if (!mounted) return;
      setState(() {
        overview = o;
        users = (u['items'] as List)
            .cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        measurements = (m['items'] as List)
            .cast<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        geminiMasked = s['gemini_api_key_masked'] as String?;
        loading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          loading = false;
        });
      }
    }
  }

  Future<void> saveGemini() async {
    if (savingKey) return;
    setState(() => savingKey = true);
    try {
      await networkApi.request(
        '/api/admin/settings',
        method: 'PUT',
        body: {'gemini_api_key': gemini.text.trim()},
      );
      gemini.clear();
      await reload();
      if (mounted) toast(context, context.l10n.geminiSavedToast);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => savingKey = false);
    }
  }

  Future<void> runAnalyze() async {
    if (analyzing || analyze.text.trim().length < 3) return;
    setState(() {
      analyzing = true;
      analysis = null;
    });
    try {
      final r = await networkApi.request(
        '/api/ai/analyze',
        method: 'POST',
        body: {'text': analyze.text.trim()},
      );
      if (mounted) setState(() => analysis = r['analysis'] as String?);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => analyzing = false);
    }
  }

  Future<void> deleteUser(Map<String, dynamic> u) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.deleteUserConfirmTitle),
        content: Text(l10n.deleteUserConfirmBody('${u['phone']}')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await networkApi.request('/api/admin/users/${u['id']}', method: 'DELETE');
      await reload();
      if (mounted) toast(context, context.l10n.userDeletedToast);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  Future<void> deleteMeasurement(Map<String, dynamic> m) async {
    try {
      await networkApi.request(
        '/api/admin/measurements/${m['id']}',
        method: 'DELETE',
      );
      await reload();
      if (mounted) toast(context, context.l10n.measurementDeletedToast);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    }
  }

  List<Map<String, dynamic>> get filteredUsers {
    final q = userQuery.text.trim();
    if (q.isEmpty) return users;
    return users
        .where(
          (u) =>
              '${u['phone']}'.contains(q) ||
              '${u['name']}'.contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (!networkApi.isAdmin) {
      return CarePage(
        title: l10n.adminDashboard,
        eyebrow: l10n.eyebrowAdminControl,
        children: [
          emptyState(
            Icons.admin_panel_settings_outlined,
            l10n.adminAccessRequiredTitle,
            l10n.adminAccessRequiredBody,
          ),
          actionButton(
            l10n.adminSignIn,
            () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AuthScreen(),
                ),
              );
              if (mounted) reload();
            },
            icon: Icons.login,
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F7),
      appBar: AppBar(
        title: Text(l10n.adminDashboard),
        actions: [
          IconButton(
            onPressed: loading ? null : reload,
            icon: const Icon(Icons.refresh),
            tooltip: l10n.refresh,
          ),
        ],
        bottom: TabBar(
          controller: tabs,
          isScrollable: true,
          tabs: [
            Tab(
              text: l10n.tabOverview,
              icon: const Icon(Icons.dashboard_outlined, size: 18),
            ),
            Tab(
              text: l10n.tabUsers,
              icon: const Icon(Icons.people_outline, size: 18),
            ),
            Tab(
              text: l10n.tabMeasurements,
              icon: const Icon(Icons.speed, size: 18),
            ),
            Tab(
              text: l10n.tabAiSettings,
              icon: const Icon(Icons.tune, size: 18),
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          if (loading) const LinearProgressIndicator(minHeight: 2),
          if (error != null)
            Material(
              color: const Color(0xFFFFF3E0),
              child: ListTile(
                leading: const Icon(Icons.warning_amber, color: Colors.orange),
                title: Text(error!, style: const TextStyle(fontSize: 13)),
                trailing: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => setState(() => error = null),
                ),
              ),
            ),
          Expanded(
            child: TabBarView(
              controller: tabs,
              children: [
                _overviewTab(),
                _usersTab(),
                _measurementsTab(),
                _settingsTab(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _overviewTab() {
    final l10n = context.l10n;
    final o = overview;
    if (o == null && loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final byConn = ((o?['by_connection'] as List?) ?? const [])
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final top = ((o?['top_users'] as List?) ?? const [])
        .cast<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
    final adminName =
        networkApi.user?['name']?.toString() ?? l10n.adminDefaultName;
    final phone = networkApi.user?['phone']?.toString() ?? '';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText(l10n.adminWelcome(adminName)),
              const SizedBox(height: 6),
              muted(l10n.adminFullAccessSubtitle(phone)),
            ],
          ),
        ),
        adaptiveMetrics([
          metric('${o?['users'] ?? 0}', l10n.metricUsers, Icons.people_outline),
          metric(
            '${o?['admins'] ?? 0}',
            l10n.metricAdmins,
            Icons.verified_user_outlined,
          ),
          metric('${o?['measurements'] ?? 0}', l10n.metricMeasurements, Icons.speed),
          metric(
            '${o?['shared_measurements'] ?? 0}',
            l10n.metricOnMap,
            Icons.map_outlined,
          ),
        ]),
        adaptiveMetrics([
          metric(
            _n((o?['avg_download_mbps'] as num?)),
            l10n.metricAvgDownload,
            Icons.download_outlined,
          ),
          metric(
            _n((o?['avg_upload_mbps'] as num?)),
            l10n.metricAvgUpload,
            Icons.upload_outlined,
          ),
          metric(
            _n((o?['avg_ping_ms'] as num?), 0),
            l10n.metricAvgPing,
            Icons.timer_outlined,
          ),
        ]),
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleText(l10n.serverStatus),
              const SizedBox(height: 10),
              muted(
                'Origin: ${o?['public_origin'] == null || '${o?['public_origin']}'.isEmpty ? networkApi.baseUrl : o?['public_origin']}',
              ),
              muted(
                'Speed API: ${o?['speed_enabled'] == true ? l10n.enabled : l10n.stopped}',
              ),
              muted(
                'Gemini: ${o?['gemini_configured'] == true ? l10n.configured : l10n.notConfigured}',
              ),
              muted(
                '${l10n.databaseLabel}: ${o?['db_path'] ?? '—'} • ${o?['db_persistent'] == true ? l10n.persistent : l10n.temporary}',
              ),
              if (o?['persistence_hint'] != null)
                Text(
                  '${o!['persistence_hint']}',
                  style: const TextStyle(color: Colors.orangeAccent, height: 1.5),
                ),
            ],
          ),
        ),
        if (byConn.isNotEmpty) ...[
          titleText(l10n.byConnectionType),
          const SizedBox(height: 12),
          for (final c in byConn)
            CareCard(
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.wifi_tethering, color: _purple),
                title: Text('${c['type'] ?? l10n.unknown}'),
                subtitle: muted(
                  '${l10n.sampleCount(c['count'] as int? ?? 0)} • ↓ ${_n(c['avg_download'] as num?)} • ${_n(c['avg_ping'] as num?, 0)} ms',
                ),
              ),
            ),
        ],
        if (top.isNotEmpty) ...[
          titleText(l10n.topActiveUsers),
          const SizedBox(height: 12),
          for (final u in top)
            CareCard(
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text('${u['name'] ?? ''}'),
                subtitle: muted('${u['phone']}'),
                trailing: Text(
                  '${u['tests']}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: _purple,
                    fontSize: 18,
                  ),
                ),
              ),
            ),
        ],
        Row(
          children: [
            Expanded(
              child: actionButton(
                l10n.tabUsers,
                () => tabs.animateTo(1),
                icon: Icons.people,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: actionButton(
                l10n.tabMeasurements,
                () => tabs.animateTo(2),
                icon: Icons.speed,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _usersTab() {
    final l10n = context.l10n;
    final list = filteredUsers;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: userQuery,
          onChanged: (_) => setState(() {}),
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: l10n.userSearchHint,
          ),
        ),
        const SizedBox(height: 12),
        muted(l10n.userCountLine(list.length, users.length)),
        const SizedBox(height: 12),
        for (final u in list)
          CareCard(
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: CircleAvatar(
                backgroundColor: u['is_admin'] == true
                    ? StcColors.purple
                    : StcColors.purpleSoft,
                child: Icon(
                  u['is_admin'] == true ? Icons.shield : Icons.person_outline,
                  color: u['is_admin'] == true ? Colors.white : _purple,
                ),
              ),
              title: Text(u['name']?.toString() ?? ''),
              subtitle: muted(
                '${u['phone']}${u['gender_label'] != null && '${u['gender_label']}'.isNotEmpty ? ' • ${u['gender_label']}' : ''} • ${u['tests']}${u['is_admin'] == true ? ' • ${l10n.systemAdmin}' : ''}${u['created_at_iso'] != null ? '\n${u['created_at_iso']}' : ''}',
              ),
              isThreeLine: u['created_at_iso'] != null,
              trailing: u['is_admin'] == true
                  ? const Icon(Icons.verified, color: _purple)
                  : IconButton(
                      tooltip: l10n.deleteUser,
                      onPressed: () => deleteUser(u),
                      icon: const Icon(Icons.delete_outline, color: Colors.orangeAccent),
                    ),
            ),
          ),
      ],
    );
  }

  Widget _measurementsTab() {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        muted(l10n.recentMeasurementsHeader(measurements.length)),
        const SizedBox(height: 12),
        if (measurements.isEmpty)
          emptyState(
            Icons.speed,
            l10n.measurementsEmptyTitle,
            l10n.measurementsEmptyBody,
          ),
        for (final m in measurements)
          CareCard(
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(m['phone']?.toString() ?? ''),
              subtitle: muted(
                '↓ ${_n(m['download_mbps'] as num?)} • ↑ ${_n(m['upload_mbps'] as num?)} • ${_n(m['ping_ms'] as num?, 0)} ms\n'
                '${m['connection_type'] ?? '-'} • ${m['test_status'] ?? '-'}'
                '${m['cell_y'] != null ? ' • ${l10n.cellIdLine('${m['cell_y']},${m['cell_x']}')}' : ''}',
              ),
              isThreeLine: true,
              trailing: IconButton(
                tooltip: l10n.deleteMeasurement,
                onPressed: () => deleteMeasurement(m),
                icon: const Icon(Icons.delete_outline, color: Colors.orangeAccent),
              ),
            ),
          ),
      ],
    );
  }

  Widget _settingsTab() {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleText(l10n.geminiServerKeyTitle),
              const SizedBox(height: 8),
              muted(l10n.geminiServerKeyBlurb),
              const SizedBox(height: 8),
              muted(
                geminiMasked == null || geminiMasked!.isEmpty
                    ? l10n.geminiNoKeyYet
                    : l10n.geminiKeyMasked(geminiMasked!),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: gemini,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.geminiApiKeyLabel,
                  hintText: l10n.geminiApiKeyHint,
                ),
              ),
              const SizedBox(height: 12),
              actionButton(
                savingKey ? l10n.saving : l10n.saveToDatabase,
                saveGemini,
                icon: Icons.key,
              ),
            ],
          ),
        ),
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              titleText(l10n.tryAnalysis),
              const SizedBox(height: 12),
              TextField(
                controller: analyze,
                maxLines: 5,
                decoration: InputDecoration(hintText: l10n.analyzeInputHint),
              ),
              const SizedBox(height: 12),
              actionButton(
                analyzing ? l10n.analyzing : l10n.analyzeNow,
                runAnalyze,
                icon: Icons.auto_awesome,
              ),
              if (analysis != null) ...[
                const SizedBox(height: 14),
                Text(analysis!, style: const TextStyle(height: 1.6)),
              ],
            ],
          ),
        ),
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText(l10n.loginDetails),
              const SizedBox(height: 8),
              muted(l10n.adminPhoneLine),
              muted('API: ${networkApi.baseUrl}'),
              muted(l10n.geminiKeyPersistNote),
            ],
          ),
        ),
      ],
    );
  }
}

class AiAssistScreen extends StatefulWidget {
  const AiAssistScreen({super.key});
  @override
  State<AiAssistScreen> createState() => _AiAssistScreenState();
}

class _AiAssistScreenState extends State<AiAssistScreen> {
  final text = TextEditingController();
  String? result, error;
  bool loading = false, available = false, checking = true;

  @override
  void initState() {
    super.initState();
    _status();
  }

  @override
  void dispose() {
    text.dispose();
    super.dispose();
  }

  Future<void> _status() async {
    if (networkApi.token == null) {
      setState(() {
        checking = false;
        available = false;
        error = AppLocalizations(appStore.locale).aiSignInRequired;
      });
      return;
    }
    try {
      final s = await networkApi.request('/api/ai/status');
      if (!mounted) return;
      setState(() {
        available = s['available'] == true;
        checking = false;
        error = available ? null : (s['reason']?.toString());
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        checking = false;
        error = e.toString();
      });
    }
  }

  Future<void> _run() async {
    final body = text.text.trim();
    if (body.length < 3 || loading) return;
    setState(() {
      loading = true;
      error = null;
      result = null;
    });
    try {
      final r = await networkApi.request(
        '/api/ai/analyze',
        method: 'POST',
        body: {'text': body},
      );
      if (!mounted) return;
      setState(() => result = r['analysis']?.toString());
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CarePage(
      title: l10n.aiAssistTitle,
      eyebrow: l10n.eyebrowGemini,
      children: [
        CareCard(muted(l10n.aiAssistIntro)),
        if (checking) const LinearProgressIndicator(),
        if (error != null)
          CareCard(Text(error!, style: const TextStyle(color: Colors.orangeAccent))),
        if (!checking && networkApi.token == null)
          actionButton(
            l10n.signIn,
            () => openCare(context, const AuthScreen()),
            icon: Icons.login,
          ),
        if (available) ...[
          CareCard(
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: text,
                  maxLines: 5,
                  decoration: InputDecoration(hintText: l10n.aiInputHint),
                ),
                const SizedBox(height: 12),
                actionButton(
                  loading ? l10n.analyzing : l10n.analyzeNow,
                  _run,
                  icon: Icons.auto_awesome,
                ),
              ],
            ),
          ),
          if (result != null) CareCard(Text(result!, style: const TextStyle(height: 1.6))),
        ],
      ],
    );
  }
}

class HelpScreen extends StatelessWidget {
  const HelpScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final faqs = <(String, String)>[
      (l10n.faqAddReportQ, l10n.faqAddReportA),
      (l10n.faqRealMeasurementsQ, l10n.faqRealMeasurementsA),
      (l10n.faqStcReportsQ, l10n.faqStcReportsA),
      (l10n.faqOfflineQ, l10n.faqOfflineA),
      (l10n.faqAccountSafeQ, l10n.faqAccountSafeA),
    ];
    return CarePage(
      title: l10n.helpTitle,
      children: [
        const Icon(Icons.support_agent, size: 80, color: _purple),
        const SizedBox(height: 20),
        for (final item in faqs)
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
              titleText(l10n.aboutProductTitle),
              const SizedBox(height: 10),
              muted(l10n.aboutBlurb),
              muted(l10n.aboutVersion),
            ],
          ),
        ),
        TextButton(
          onPressed: () => openCare(context, const PrivacyScreen()),
          child: Text(l10n.privacyAndData),
        ),
      ],
    );
  }
}

class PrivacyScreen extends StatelessWidget {
  const PrivacyScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return CarePage(
      title: l10n.privacyAndData,
      children: [
        CareCard(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              titleText(l10n.privacyHero),
              const SizedBox(height: 16),
              muted(l10n.privacyLocalStorage),
              const SizedBox(height: 16),
              muted(l10n.privacyLocationMaps),
              const SizedBox(height: 16),
              muted(l10n.privacyReportsMeasurements),
            ],
          ),
        ),
      ],
    );
  }
}
