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

void _lookOnly(BuildContext context) {
  ScaffoldMessenger.of(context).clearSnackBars();
  ScaffoldMessenger.of(context).showSnackBar(
    const SnackBar(
      content: Text('هذا العنصر للعرض فقط • الخدمات الفعلية: فحص السرعة وخريطة الجودة'),
      behavior: SnackBarBehavior.floating,
      duration: Duration(seconds: 2),
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
    const searchH = 48.0;
    const overlap = 24.0;
    return CustomScrollView(
      clipBehavior: Clip.none,
      slivers: [
        SliverToBoxAdapter(
          child: Column(
            children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: double.infinity,
                    color: StcColors.purple,
                    padding: EdgeInsets.fromLTRB(
                      20,
                      MediaQuery.paddingOf(context).top + 18,
                      20,
                      overlap + 16,
                    ),
                    child: const Text(
                      'مرحبا بكم في stc',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: -overlap,
                    child: Material(
                      color: Colors.white,
                      elevation: 4,
                      shadowColor: const Color(0x40000000),
                      borderRadius: BorderRadius.circular(8),
                      child: SizedBox(
                        height: searchH,
                        child: Row(
                          children: [
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'ما الذي تبحث عنه؟',
                                style: TextStyle(
                                  color: Color(0xFF9AA0A6),
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            Material(
                              color: StcColors.coral,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(8),
                              ),
                              child: InkWell(
                                onTap: onSpeed,
                                child: const SizedBox(
                                  width: 52,
                                  height: searchH,
                                  child: Icon(
                                    Icons.search,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: overlap + 12),
            ],
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 28),
          sliver: SliverList.list(
            children: [
              const _SectionTitle('استكشف منتجاتنا'),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: _ProductShot(
                      title: 'حول رقمك إلى stc',
                      image: 'assets/brand/product_transfer.jpg',
                      onTap: () => _lookOnly(context),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _ProductShot(
                      title: 'شريحة جوال وإنترنت',
                      image: 'assets/brand/product_sim.jpg',
                      onTap: () => _lookOnly(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 22),
              const _SectionTitle('انضم إلى stc'),
              const SizedBox(height: 12),
              Material(
                color: const Color(0xFF1BCED8),
                borderRadius: BorderRadius.circular(10),
                child: InkWell(
                  onTap: () => _lookOnly(context),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 20,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .2),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.home_outlined,
                            color: Colors.white,
                            size: 26,
                          ),
                        ),
                        const SizedBox(width: 14),
                        const Expanded(
                          child: Text(
                            'الإنترنت المنزلي',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 20,
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
                      label: 'إعادة شحن الرقم',
                      onTap: () => _lookOnly(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.description_outlined,
                      label: 'ترقية إلى مفوتر',
                      onTap: () => _lookOnly(context),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _QuickAction(
                      icon: Icons.view_in_ar_outlined,
                      label: 'طلباتي',
                      color: const Color(0xFF2ECC71),
                      onTap: () => _lookOnly(context),
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
                    onPressed: () => _lookOnly(context),
                    child: const Text('إظهار الكل'),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 86,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    _PayLogo('App Store', Icons.apple, () => _lookOnly(context)),
                    _PayLogo(
                      'Blacknut',
                      Icons.sports_esports_outlined,
                      () => _lookOnly(context),
                    ),
                    _PayLogo(
                      'OSN+',
                      Icons.live_tv_outlined,
                      () => _lookOnly(context),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Material(
                color: StcColors.purpleSoft,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: onSpeed,
                          icon: const Icon(Icons.speed),
                          label: const Text('فحص السرعة'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: onMap,
                          icon: const Icon(Icons.map_outlined),
                          label: const Text('الخريطة'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ProductShot extends StatelessWidget {
  final String title;
  final String image;
  final VoidCallback onTap;
  const _ProductShot({
    required this.title,
    required this.image,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    borderRadius: BorderRadius.circular(12),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 178,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Image.asset(
              image,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => const ColoredBox(
                color: StcColors.purpleDeep,
              ),
            ),
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0x22000000),
                    Color(0xCC1A1028),
                  ],
                ),
              ),
            ),
            Positioned(
              right: 12,
              bottom: 14,
              left: 12,
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 15,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _PayLogo extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  const _PayLogo(this.label, this.icon, this.onTap);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 10),
    child: Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(12),
      elevation: 1,
      shadowColor: const Color(0x14000000),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: SizedBox(
          width: 118,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, color: StcColors.purple, size: 28),
              const SizedBox(height: 8),
              Text(
                label,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    ),
  );
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
    return AnimatedBuilder(
      animation: networkApi,
      builder: (context, _) {
        final signedIn = networkApi.token != null;
        final admin = networkApi.isAdmin;
        final items = <(IconData, String, VoidCallback)>[
          (
            Icons.admin_panel_settings_outlined,
            admin ? 'لوحة تحكم المدير' : 'لوحة الإدارة (دخول المدير)',
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
                  decoration: BoxDecoration(
                    color: admin ? StcColors.purple : StcColors.purple,
                    shape: BoxShape.circle,
                    border: admin
                        ? Border.all(color: StcColors.coral, width: 3)
                        : null,
                  ),
                  child: Icon(
                    admin ? Icons.shield_outlined : Icons.person_outline,
                    color: Colors.white,
                    size: 44,
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                admin
                    ? (networkApi.user?['name']?.toString() ?? 'مدير النظام')
                    : 'مرحبا بكم في stc',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              if (admin) ...[
                const SizedBox(height: 6),
                Text(
                  '${networkApi.user?['phone'] ?? ''} • صلاحية مدير كاملة',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: StcColors.silver, fontSize: 13),
                ),
              ],
              const SizedBox(height: 16),
              if (admin)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Material(
                    color: StcColors.purple,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => openCare(context, const AdminScreen()),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 18,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.dashboard_customize_outlined,
                              color: Colors.white,
                              size: 28,
                            ),
                            SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'افتح لوحة التحكم الكاملة',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 16,
                                    ),
                                  ),
                                  SizedBox(height: 4),
                                  Text(
                                    'مستخدمون • قياسات • Gemini • حالة الخادم',
                                    style: TextStyle(
                                      color: Color(0xFFD4B8F0),
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 16),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
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
                              signedIn
                                  ? Icons.check_rounded
                                  : Icons.login_rounded,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              signedIn
                                  ? (admin
                                      ? 'جلسة مدير نشطة • اضغط لإدارة الحساب'
                                      : 'أنت متصل بحساب القياس')
                                  : 'سجّل دخول المدير: 0552515874',
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
      },
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
