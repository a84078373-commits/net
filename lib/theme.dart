import 'package:flutter/material.dart';

/// Official stc brand tokens from the public brand booklet,
/// applied in the visual language of the 2026 mystc SA app.
class StcBrand {
  static const profileAsset = 'assets/brand/stc_profile.png';
}

class StcProfileAvatar extends StatelessWidget {
  final double radius;
  final Color backgroundColor;
  const StcProfileAvatar({
    super.key,
    this.radius = 16,
    this.backgroundColor = Colors.white,
  });
  @override
  Widget build(BuildContext context) => CircleAvatar(
    radius: radius,
    backgroundColor: backgroundColor,
    backgroundImage: const AssetImage(StcBrand.profileAsset),
  );
}

class StcColors {
  static const purple = Color(0xFF4F008C);
  static const purpleDeep = Color(0xFF3A0068);
  static const purpleSoft = Color(0xFFF3ECF8);
  static const coral = Color(0xFFFF375E);
  static const sunset = Color(0xFFFF6A39);
  static const oasis = Color(0xFF00C48C);
  static const sea = Color(0xFF1BCED8);
  static const moon = Color(0xFFA54EE1);
  static const sun = Color(0xFFFFDD40);
  static const silver = Color(0xFF8E9AA0);
  static const onyx = Color(0xFF1D252D);
  static const canvas = Color(0xFFF6F3F8);
  static const card = Color(0xFFFFFFFF);
}

class StcRadii {
  static const tile = 18.0;
  static const card = 22.0;
  static const pill = 28.0;
}

ThemeData stcTheme() {
  const text = TextTheme(
    bodyMedium: TextStyle(color: StcColors.onyx, height: 1.45),
    titleLarge: TextStyle(
      color: StcColors.onyx,
      fontWeight: FontWeight.w700,
      fontSize: 22,
    ),
  );
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.light,
    fontFamily: 'Segoe UI',
    scaffoldBackgroundColor: Colors.white,
    colorScheme: const ColorScheme.light(
      primary: StcColors.purple,
      secondary: StcColors.coral,
      tertiary: StcColors.oasis,
      surface: StcColors.card,
      onPrimary: Colors.white,
      onSecondary: Colors.white,
      onSurface: StcColors.onyx,
    ),
    textTheme: text,
    appBarTheme: const AppBarTheme(
      backgroundColor: StcColors.canvas,
      foregroundColor: StcColors.onyx,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: StcColors.onyx,
        fontSize: 22,
        fontWeight: FontWeight.w700,
      ),
      iconTheme: IconThemeData(color: StcColors.onyx),
    ),
    cardTheme: CardThemeData(
      color: StcColors.card,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(StcRadii.card),
        side: const BorderSide(color: Color(0xFFE8E2EE)),
      ),
    ),
    dividerColor: const Color(0xFFE8E2EE),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: StcColors.card,
      hintStyle: const TextStyle(color: StcColors.silver),
      labelStyle: const TextStyle(color: StcColors.silver),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE8E2EE)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: Color(0xFFE8E2EE)),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: const BorderSide(color: StcColors.purple, width: 1.4),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: StcColors.purpleSoft,
      selectedColor: StcColors.purple,
      checkmarkColor: Colors.white,
      labelStyle: const TextStyle(color: StcColors.onyx, fontSize: 12),
      secondaryLabelStyle: const TextStyle(color: Colors.white, fontSize: 12),
      side: BorderSide.none,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: StcColors.coral,
        foregroundColor: Colors.white,
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 16),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: StcColors.purple,
        side: const BorderSide(color: Color(0xFFE0D6EA)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: StcColors.coral),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: StcColors.card,
      elevation: 0,
      height: 72,
      indicatorColor: Colors.transparent,
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 11,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? StcColors.purple : StcColors.silver,
        );
      }),
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final selected = states.contains(WidgetState.selected);
        return IconThemeData(
          size: 24,
          color: selected ? StcColors.purple : StcColors.silver,
        );
      }),
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: StcColors.purple,
      linearTrackColor: Color(0xFFE8E2EE),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: StcColors.onyx,
      contentTextStyle: const TextStyle(color: Colors.white),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: StcColors.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: StcColors.card,
      showDragHandle: true,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? StcColors.purple
            : StcColors.silver,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected)
            ? StcColors.purple.withValues(alpha: .35)
            : const Color(0xFFE8E2EE),
      ),
    ),
  );
}

class StcWordmark extends StatelessWidget {
  final Color color;
  final double size;
  const StcWordmark({super.key, this.color = Colors.white, this.size = 36});
  @override
  Widget build(BuildContext context) {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Text(
          'stc',
          style: TextStyle(
            color: color,
            fontSize: size,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.6,
            height: 1,
          ),
        ),
        Positioned(
          top: size * 0.02,
          left: size * 0.72,
          child: Row(
            children: [
              _dot(),
              SizedBox(width: size * 0.06),
              _dot(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _dot() => Container(
    width: size * 0.11,
    height: size * 0.11,
    decoration: BoxDecoration(color: color, shape: BoxShape.circle),
  );
}

class StcCard extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  final EdgeInsets margin;
  final Color? color;
  const StcCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.margin = EdgeInsets.zero,
    this.color,
  });
  @override
  Widget build(BuildContext context) => Container(
    margin: margin,
    padding: padding,
    decoration: BoxDecoration(
      color: color ?? StcColors.card,
      borderRadius: BorderRadius.circular(StcRadii.card),
      border: Border.all(color: const Color(0xFFE8E2EE)),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F4F008C),
          blurRadius: 18,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );
}

class StcIconTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const StcIconTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: StcColors.purpleSoft,
    borderRadius: BorderRadius.circular(StcRadii.tile),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(StcRadii.tile),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: StcColors.purple, size: 28),
            const SizedBox(height: 10),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: StcColors.onyx,
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

class StcUsageBar extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final double progress;
  const StcUsageBar({
    super.key,
    required this.icon,
    required this.label,
    required this.value,
    required this.progress,
  });
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      children: [
        Row(
          children: [
            Icon(icon, size: 18, color: StcColors.onyx),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              value,
              style: const TextStyle(color: StcColors.silver, fontSize: 13),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: LinearProgressIndicator(
            value: progress.clamp(0, 1),
            minHeight: 3,
            color: StcColors.purple,
            backgroundColor: const Color(0xFFE8E2EE),
          ),
        ),
      ],
    ),
  );
}

class StcNavIcon extends StatelessWidget {
  final IconData icon;
  final bool selected;
  const StcNavIcon(this.icon, {super.key, this.selected = false});
  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return IconTheme(
        data: const IconThemeData(color: StcColors.silver, size: 24),
        child: Icon(icon),
      );
    }
    return Container(
      width: 42,
      height: 32,
      decoration: BoxDecoration(
        color: StcColors.purple,
        borderRadius: BorderRadius.circular(10),
      ),
      child: IconTheme(
        data: const IconThemeData(color: Colors.white, size: 20),
        child: Icon(icon),
      ),
    );
  }
}

class StcCoralBar extends StatelessWidget {
  final String title;
  final String action;
  final VoidCallback onTap;
  const StcCoralBar({
    super.key,
    required this.title,
    required this.action,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: StcColors.coral,
    borderRadius: BorderRadius.circular(16),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              action,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
