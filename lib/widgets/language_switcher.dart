import 'package:flutter/material.dart';
import '../app_store.dart';
import '../l10n/app_localizations.dart';
import '../theme.dart';

/// Segmented Arabic / English language control.
class LanguageSwitcher extends StatelessWidget {
  final bool compact;
  const LanguageSwitcher({super.key, this.compact = false});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final selected = appStore.localeCode == 'en' ? 'en' : 'ar';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!compact) ...[
          Text(
            l10n.language,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.languageSwitcherHint,
            style: const TextStyle(color: StcColors.silver, height: 1.5),
          ),
          const SizedBox(height: 12),
        ],
        SegmentedButton<String>(
          segments: [
            ButtonSegment(
              value: 'ar',
              label: Text(l10n.languageArabic),
              icon: const Icon(Icons.translate, size: 18),
            ),
            ButtonSegment(
              value: 'en',
              label: Text(l10n.languageEnglish),
              icon: const Icon(Icons.language, size: 18),
            ),
          ],
          selected: {selected},
          showSelectedIcon: false,
          onSelectionChanged: (set) {
            if (set.isEmpty) return;
            appStore.setLocaleCode(set.first);
          },
        ),
      ],
    );
  }
}
