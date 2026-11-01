import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'app_store.dart';
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
    home: const Directionality(
      textDirection: TextDirection.rtl,
      child: AppRoot(),
    ),
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
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'الرئيسية',
            ),
            NavigationDestination(
              icon: Icon(Icons.shopping_bag_outlined),
              selectedIcon: Icon(Icons.shopping_bag_rounded),
              label: 'المتجر',
            ),
            NavigationDestination(
              icon: Icon(Icons.loyalty_outlined),
              selectedIcon: Icon(Icons.loyalty_rounded),
              label: 'قطاف',
            ),
            NavigationDestination(
              icon: Icon(Icons.menu_rounded),
              selectedIcon: Icon(Icons.menu_rounded),
              label: 'المزيد',
            ),
          ],
        ),
      ),
    );
  }
}
