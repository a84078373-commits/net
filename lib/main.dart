import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_store.dart';
import 'l10n/app_localizations.dart';
import 'mystc_pages.dart';
import 'network/network_api.dart';
import 'theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
    ),
  );
  await appStore.load();
  await networkApi.restoreSession();
  appStore.signedIn = networkApi.token != null;
  if (networkApi.user != null) {
    appStore.name = networkApi.user!['name']?.toString() ?? appStore.name;
    appStore.phone = networkApi.user!['phone']?.toString() ?? appStore.phone;
  }
  runApp(const SmartCare());
}

class SmartCare extends StatelessWidget {
  const SmartCare({super.key});
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: appStore,
    builder: (context, _) {
      final locale = appStore.locale;
      final isAr = locale.languageCode != 'en';
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        title: isAr ? 'SmartCare • حائل' : 'SmartCare • Hail',
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        localeResolutionCallback: (device, supported) {
          if (device == null) return locale;
          for (final s in supported) {
            if (s.languageCode == device.languageCode) return s;
          }
          return locale;
        },
        theme: stcTheme(locale: locale),
        builder: (context, child) {
          final l10n = AppLocalizations.of(context);
          return Directionality(
            textDirection: l10n.textDirection,
            child: child ?? const SizedBox.shrink(),
          );
        },
        home: const AppRoot(),
      );
    },
  );
}

class AppRoot extends StatefulWidget {
  const AppRoot({super.key});
  @override
  State<AppRoot> createState() => _AppRootState();
}

class _AppRootState extends State<AppRoot> {
  bool splash = true;
  int page = 0;

  @override
  void initState() {
    super.initState();
    appStore.addListener(_refresh);
    networkApi.addListener(_syncAuth);
  }

  void _syncAuth() {
    appStore.signedIn = networkApi.token != null;
    appStore.changed();
  }

  void _refresh() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    appStore.removeListener(_refresh);
    networkApi.removeListener(_syncAuth);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (splash) {
      return MystcSplash(onDone: () {
        if (mounted) setState(() => splash = false);
      });
    }
    return Scaffold(
      backgroundColor: Colors.white,
      body: IndexedStack(
        index: page,
        children: [
          MystcHomeTab(
            onSpeed: () => setState(() => page = 1),
            onMap: () => setState(() => page = 2),
            onMore: () => setState(() => page = 3),
          ),
          const SafeArea(bottom: false, child: MystcStoreTab()),
          const SafeArea(bottom: false, child: MystcQitafTab()),
          const SafeArea(bottom: false, child: MystcMoreTab()),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(top: BorderSide(color: Color(0xFFE6E6E6))),
        ),
        child: NavigationBar(
          selectedIndex: page,
          onDestinationSelected: (i) => setState(() => page = i),
          destinations: [
            NavigationDestination(
              icon: const Icon(Icons.home_outlined),
              selectedIcon: const Icon(Icons.home_rounded),
              label: l10n.navHome,
            ),
            NavigationDestination(
              icon: const Icon(Icons.shopping_bag_outlined),
              selectedIcon: const Icon(Icons.shopping_bag_rounded),
              label: l10n.navStore,
            ),
            NavigationDestination(
              icon: const Icon(Icons.loyalty_outlined),
              selectedIcon: const Icon(Icons.loyalty_rounded),
              label: l10n.navQitaf,
            ),
            NavigationDestination(
              icon: const Icon(Icons.menu_rounded),
              selectedIcon: const Icon(Icons.menu_rounded),
              label: l10n.navMore,
            ),
          ],
        ),
      ),
    );
  }
}
