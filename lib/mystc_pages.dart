import 'package:flutter/material.dart';
import 'care_screens.dart';
import 'network/network_api.dart';
import 'network/network_test_screen.dart';
import 'network_map.dart';
import 'theme.dart';

/// Splash matching official mystc purple + centered stc mark.
class MystcSplash extends StatefulWidget {
  final VoidCallback onDone;
  const MystcSplash({super.key, required this.onDone});
  @override
  State<MystcSplash> createState() => _MystcSplashState();
}

class _MystcSplashState extends State<MystcSplash> {
  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 1600), widget.onDone);
  }

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: StcColors.purple,
    body: Center(
      child: StcWordmark(color: Color(0xFFD4B8F0), size: 78),
    ),
  );
}

class MystcHomeTab extends StatelessWidget {
  final VoidCallback onSpeed;
  final VoidCallback onMap;
  final VoidCallback onMore;
  const MystcHomeTab({
    super.key,
    required this.onSpeed,
    required this.onMap,
    required this.onMore,
  });

  @override
  Widget build(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Container(
            width: double.infinity,
            color: StcColors.purple,
            padding: EdgeInsets.fromLTRB(
              20,
              MediaQuery.paddingOf(context).top + 16,
              20,
              22,
            ),
            child: const Text(
              'مرحبا بكم في stc',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 22,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Transform.translate(
            offset: const Offset(0, -14),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Material(
                elevation: 2,
                shadowColor: const Color(0x22000000),
                borderRadius: BorderRadius.circular(10),
                child: TextField(
                  readOnly: true,
                  onTap: onSpeed,
                  decoration: InputDecoration(
                    hintText: 'ما الذي تبحث عنه؟',
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 14,
                    ),
                    suffixIcon: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Material(
                        color: StcColors.coral,
                        borderRadius: BorderRadius.circular(8),
                        child: const SizedBox(
                          width: 40,
                          height: 40,
                          child: Icon(Icons.search, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          sliver: SliverList.list(
            children: [
              const _SectionTitle('استكشف منتجاتنا'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _PhotoCard(
                      title: 'شريحة جوال وإنترنت',
                      color: const Color(0xFF5B2A8A),
                      icon: Icons.sim_card_outlined,
                      onTap: onSpeed,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _PhotoCard(
                      title: 'حول رقمك إلى stc',
                      color: const Color(0xFF2F2A44),
                      icon: Icons.swap_horiz_rounded,
                      onTap: onMore,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle('انضم إلى stc'),
              const SizedBox(height: 12),
              Material(
                color: StcColors.sea,
                borderRadius: BorderRadius.circular(12),
                child: InkWell(
                  onTap: onMap,
                  borderRadius: BorderRadius.circular(12),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                    child: Row(
                      children: [
                        Icon(Icons.home_outlined, color: Colors.white, size: 28),
                        SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            'الإنترنت المنزلي',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const _SectionTitle('إجراءات سريعة'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.credit_card_outlined,
                      label: 'فحص السرعة',
                      onTap: onSpeed,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.description_outlined,
                      label: 'خريطة الجودة',
                      onTap: onMap,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.inventory_2_outlined,
                      label: 'بلاغاتي',
                      color: StcColors.oasis,
                      onTap: () => openCare(context, const _ReportsPage()),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: _SectionTitle('ادفع برقمك', pad: false),
                  ),
                  TextButton(
                    onPressed: onMore,
                    child: const Text('إظهار الكل'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 72,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: const [
                    _PayChip('App Store', Icons.apple),
                    _PayChip('Blacknut', Icons.sports_esports_outlined),
                    _PayChip('OSN+', Icons.live_tv_outlined),
                    _PayChip('قياس الشبكة', Icons.speed_outlined),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'واجهة مستوحاة من mystc • ليست تطبيق stc الرسمي',
                textAlign: TextAlign.center,
                style: TextStyle(color: StcColors.silver, fontSize: 11),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ReportsPage extends StatelessWidget {
  const _ReportsPage();
  @override
  Widget build(BuildContext context) => CarePage(
    title: 'بلاغاتي',
    children: [
      ReportsPanel(onNew: () => openCare(context, const NewReportScreen())),
    ],
  );
}

class MystcStoreTab extends StatelessWidget {
  const MystcStoreTab({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        color: StcColors.purple,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: const Row(
          children: [
            Expanded(
              child: Text(
                'المتجر',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.search, color: Colors.white),
          ],
        ),
      ),
      const Expanded(
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: RealSpeedPanel(),
        ),
      ),
    ],
  );
}

class MystcQitafTab extends StatelessWidget {
  const MystcQitafTab({super.key});
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Container(
        width: double.infinity,
        color: StcColors.purple,
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: const Row(
          children: [
            Expanded(
              child: Text(
                'قطاف_qitaf',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Icon(Icons.search, color: Colors.white),
          ],
        ),
      ),
      Expanded(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            Container(
              height: 148,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: const LinearGradient(
                  colors: [StcColors.purple, Color(0xFF6B2BB0)],
                ),
              ),
              padding: const EdgeInsets.all(18),
              child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StcWordmark(size: 22),
                  Spacer(),
                  Text(
                    'قيس شبكتك وارسم الجودة على خريطة حائل',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _Dot(true),
                _Dot(false),
                _Dot(false),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'عروض قطاف',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: () {},
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
            SizedBox(
              height: 150,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: const [
                  _OfferCard('فحص السرعة', 'قياس فعلي', 'مجاني'),
                  _OfferCard('خريطة الجودة', 'خلايا حائل', 'مباشر'),
                  _OfferCard('سجل القياسات', 'نتائجك', 'خاص'),
                ],
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              'خريطة التغطية',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: const SizedBox(
                height: 420,
                child: NetworkMap(selectedArea: 0),
              ),
            ),
          ],
        ),
      ),
    ],
  );
}

class MystcMoreTab extends StatelessWidget {
  const MystcMoreTab({super.key});
  @override
  Widget build(BuildContext context) {
    final signedIn = networkApi.token != null;
    final items = <(IconData, String, VoidCallback)>[
      if (networkApi.isAdmin)
        (
          Icons.admin_panel_settings_outlined,
          'لوحة الإدارة',
          () => openCare(context, const AdminScreen()),
        ),
      (
        Icons.sim_card_outlined,
        'فحص سرعة الشبكة',
        () => openCare(context, const NetworkTestScreen()),
      ),
      (
        Icons.map_outlined,
        'خريطة الجودة',
        () => openCare(
          context,
          const Scaffold(body: SafeArea(child: NetworkMap(selectedArea: 0))),
        ),
      ),
      (
        Icons.history_rounded,
        'سجل القياسات',
        () => openCare(context, const HistoryScreen()),
      ),
      (
        Icons.receipt_long_outlined,
        'بلاغاتي',
        () => openCare(context, const _ReportsPage()),
      ),
      (
        Icons.headset_mic_outlined,
        'تواصل معنا',
        () => openCare(context, const HelpScreen()),
      ),
      (
        Icons.badge_outlined,
        'ملفي الشخصي',
        () => openCare(context, const ProfileScreen()),
      ),
      (
        Icons.info_outline,
        'عن SmartCare',
        () => openCare(context, const PrivacyScreen()),
      ),
      (
        Icons.tune_rounded,
        'الإعدادات',
        () => openCare(context, const SettingsScreen()),
      ),
    ];
    return ColoredBox(
      color: const Color(0xFFF2F2F2),
      child: ListView(
        children: [
          const SizedBox(height: 28),
          Center(
            child: Container(
              width: 88,
              height: 88,
              decoration: const BoxDecoration(
                color: StcColors.purple,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.person_outline,
                color: Colors.white,
                size: 44,
              ),
            ),
          ),
          const SizedBox(height: 14),
          const Text(
            'مرحبا بكم في stc',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              child: InkWell(
                onTap: () => openCare(context, const AuthScreen()),
                borderRadius: BorderRadius.circular(10),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Row(
                    children: [
                      Container(
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          color: StcColors.coral,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(
                          signedIn ? Icons.check_rounded : Icons.login_rounded,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          signedIn
                              ? 'أنت متصل بحساب القياس'
                              : 'قم بتسجيل الدخول للوصول إلى حساب mystc',
                          style: const TextStyle(
                            color: StcColors.coral,
                            fontWeight: FontWeight.w700,
                            height: 1.35,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 18),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Icon(Icons.search, color: StcColors.silver),
                SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'ما الذي تبحث عنه؟',
                    style: TextStyle(color: StcColors.silver, fontSize: 15),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 28),
          ColoredBox(
            color: Colors.white,
            child: Column(
              children: [
                for (final item in items)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 4,
                    ),
                    leading: Icon(item.$1, color: StcColors.purple, size: 26),
                    title: Text(
                      item.$2,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    onTap: item.$3,
                  ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  final bool pad;
  const _SectionTitle(this.text, {this.pad = true});
  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(right: pad ? 0 : 0),
    child: Text(
      text,
      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
    ),
  );
}

class _PhotoCard extends StatelessWidget {
  final String title;
  final Color color;
  final IconData icon;
  final VoidCallback onTap;
  const _PhotoCard({
    required this.title,
    required this.color,
    required this.icon,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color,
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 150,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: Colors.white70, size: 28),
              const Spacer(),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color color;
  const _QuickAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.color = StcColors.purple,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    elevation: 1,
    shadowColor: const Color(0x14000000),
    borderRadius: BorderRadius.circular(12),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PayChip extends StatelessWidget {
  final String label;
  final IconData icon;
  const _PayChip(this.label, this.icon);
  @override
  Widget build(BuildContext context) => Container(
    width: 110,
    margin: const EdgeInsets.only(left: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFE8E2EE)),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: StcColors.purple),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 11)),
      ],
    ),
  );
}

class _OfferCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String badge;
  const _OfferCard(this.title, this.subtitle, this.badge);
  @override
  Widget build(BuildContext context) => Container(
    width: 132,
    margin: const EdgeInsets.only(left: 10),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      boxShadow: const [
        BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 4)),
      ],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Align(
          alignment: Alignment.topLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            color: StcColors.coral,
            child: Text(
              badge,
              style: const TextStyle(color: Colors.white, fontSize: 10),
            ),
          ),
        ),
        const Spacer(),
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        Text(
          subtitle,
          style: const TextStyle(color: StcColors.silver, fontSize: 11),
        ),
      ],
    ),
  );
}

class _Dot extends StatelessWidget {
  final bool on;
  const _Dot(this.on);
  @override
  Widget build(BuildContext context) => Container(
    width: on ? 16 : 7,
    height: 7,
    margin: const EdgeInsets.symmetric(horizontal: 3),
    decoration: BoxDecoration(
      color: on ? StcColors.purple : const Color(0xFFD0D0D0),
      borderRadius: BorderRadius.circular(8),
    ),
  );
}
