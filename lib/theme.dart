import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'data.dart';

// Palette taken from the Screen Guide: warm beige, dark brown ink, salmon accent.
const bg = Color(0xFFF5F0EC);
const ink = Color(0xFF1C130E);
const accent = Color(0xFFEC9A7A);
// Caption grey: 5.3:1 on the cream background (WCAG AA for normal text).
const muted = Color(0xFF6B615A);
const errorColor = Color(0xFFB3261E);
const cardColor = Color(0xFFFBF9F7);
const line = Color(0xFFE3D9D1);
const darkPanel = Color(0xFF16100C);
const mono = TextStyle(fontFamily: 'DejaVuMono', fontSize: 14, color: ink);

Color statusColor(String s) => switch (s) {
  'Open' => const Color(0xFFB3261E),
  'In Progress' => const Color(0xFF8A6410),
  _ => const Color(0xFF2F6B4A),
};

ThemeData appTheme() => ThemeData(
  useMaterial3: true,
  fontFamily: 'Manrope',
  scaffoldBackgroundColor: bg,
  colorScheme: ColorScheme.fromSeed(seedColor: accent)
      .copyWith(primary: accent, onPrimary: ink, surface: bg, onSurface: ink),
  textTheme: ThemeData.light().textTheme
      .apply(fontFamily: 'DejaVu', bodyColor: ink, displayColor: ink)
      .copyWith(
        // Material's smallest styles are 11-12 px; keep everything at 12 px or more after scaling.
        bodySmall: const TextStyle(
          fontSize: 13.1,
          fontFamily: 'DejaVu',
          color: ink,
        ),
        labelSmall: const TextStyle(
          fontSize: 13.1,
          fontFamily: 'DejaVu',
          color: ink,
        ),
        labelMedium: const TextStyle(
          fontSize: 13.1,
          fontFamily: 'DejaVu',
          color: ink,
        ),
      ),
  dividerColor: line,
  // Visible keyboard / switch-access focus.
  focusColor: ink.withValues(alpha: .16),
  materialTapTargetSize: MaterialTapTargetSize.padded,
  filledButtonTheme: FilledButtonThemeData(
    style: FilledButton.styleFrom(
      backgroundColor: accent,
      foregroundColor: ink,
      minimumSize: const Size.fromHeight(54),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w400,
        fontFamily: 'DejaVu',
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: ink,
      minimumSize: const Size(48, 48),
      side: const BorderSide(color: ink),
      shape: const StadiumBorder(),
      textStyle: const TextStyle(
        fontFamily: 'DejaVu',
        fontWeight: FontWeight.w400,
      ),
    ),
  ),
  snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
);

String fmt(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '-';
  String p(int n) => n.toString().padLeft(2, '0');
  return '${_months[d.month - 1]} ${d.day} ${p(d.hour)}:${p(d.minute)}';
}

String clock(dynamic iso) {
  final d = DateTime.tryParse('$iso')?.toLocal();
  if (d == null) return '-';
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.hour)}:${p(d.minute)}';
}

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

String shortId(String prefix, dynamic id) =>
    '$prefix-${'$id'.replaceAll('-', '').substring(0, 4).toUpperCase()}';

String shortTitle(String text) {
  final t = text.trim().split(RegExp(r'[.\n]')).first.trim();
  return t.length > 44 ? '${t.substring(0, 42)}...' : t;
}

// ---------------------------------------------------------------- widgets

class Panel extends StatelessWidget {
  final Widget child;
  final EdgeInsets padding;
  const Panel({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });
  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: cardColor,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: line.withValues(alpha: .6)),
      boxShadow: [
        BoxShadow(
          color: ink.withValues(alpha: .05),
          blurRadius: 18,
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: child,
  );
}

class Avatar extends StatelessWidget {
  final String label;
  final bool filled;
  final double size;
  final bool square;
  const Avatar(
    this.label, {
    super.key,
    this.filled = true,
    this.size = 46,
    this.square = false,
  });
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: square ? darkPanel : (filled ? accent : const Color(0xFFE0DAD4)),
      shape: square ? BoxShape.rectangle : BoxShape.circle,
      borderRadius: square ? BorderRadius.circular(16) : null,
    ),
    child: Text(
      label,
      style: TextStyle(
        color: square ? accent : ink,
        fontSize: size * .4,
        fontWeight: FontWeight.w500,
      ),
    ),
  );
}

class LogoMark extends StatelessWidget {
  final double size;
  const LogoMark({super.key, this.size = 40});
  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: darkPanel,
      borderRadius: BorderRadius.circular(size * .3),
    ),
    child: Icon(Icons.layers_outlined, color: accent, size: size * .6),
  );
}

class StatusLine extends StatelessWidget {
  final String status;
  final String rest;
  const StatusLine(this.status, this.rest, {super.key});
  @override
  Widget build(BuildContext context) => Text.rich(
    TextSpan(
      children: [
        TextSpan(
          text:
              '${status == 'In Progress'
                  ? '◐'
                  : status == 'Resolved'
                  ? '✓'
                  : '●'} $status',
          style: TextStyle(color: statusColor(status)),
        ),
        TextSpan(
          text: '  •  $rest',
          style: const TextStyle(color: muted),
        ),
      ],
    ),
    style: const TextStyle(fontSize: 13.1),
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

class BigTitle extends StatelessWidget {
  final String title;
  final String? sub;
  const BigTitle(this.title, {super.key, this.sub});
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w400),
      ),
      if (sub != null)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(sub!, style: const TextStyle(color: muted, fontSize: 14)),
        ),
    ],
  );
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 20, 4, 10),
    child: Text(
      text.toUpperCase(),
      style: const TextStyle(
        color: muted,
        fontSize: 13.1,
        letterSpacing: 1.2,
        fontWeight: FontWeight.w700,
      ),
    ),
  );
}

class SectionTitle extends StatelessWidget {
  final String text;
  const SectionTitle(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 24, 4, 10),
    child: Text(text, style: const TextStyle(fontSize: 22)),
  );
}

/// Label on the left, value on the right, hairline below (Screen Guide rows).
class InfoRow extends StatelessWidget {
  final String label, value;
  final VoidCallback? onTap;
  final bool bold, last;
  const InfoRow(
    this.label,
    this.value, {
    super.key,
    this.onTap,
    this.bold = false,
    this.last = false,
  });
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        border: last ? null : const Border(bottom: BorderSide(color: line)),
      ),
      child: Row(
        children: [
          Text(label, style: const TextStyle(fontSize: 17)),
          const SizedBox(width: 16),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value + (onTap != null ? ' ›' : ''),
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: bold ? 20 : 16,
                    color: bold ? ink : muted,
                    fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

/// Round back arrow, centred title and logo, as in the guide.
class TopBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;

  /// When set the title becomes a button with a drop-down arrow (used to switch games).
  final VoidCallback? onTitleTap;
  const TopBar(this.title, {super.key, this.onBack, this.onTitleTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
    child: Row(
      children: [
        Semantics(
          button: true,
          label: 'Back',
          excludeSemantics: true,
          child: Material(
            color: Colors.white,
            shape: const CircleBorder(),
            elevation: 2,
            shadowColor: Colors.black26,
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: onBack ?? () => Navigator.maybePop(context),
              child: const SizedBox(
                width: 48,
                height: 48,
                child: Icon(Icons.arrow_back, size: 22),
              ),
            ),
          ),
        ),
        Expanded(
          child: onTitleTap == null
              ? Semantics(
                  header: true,
                  child: Text(
                    title,
                    textAlign: TextAlign.center,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 17),
                  ),
                )
              : Semantics(
                  button: true,
                  label: '$title. Switch game',
                  excludeSemantics: true,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(24),
                    onTap: onTitleTap,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 48),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              title,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 17),
                            ),
                          ),
                          const Icon(Icons.keyboard_arrow_down, size: 22),
                        ],
                      ),
                    ),
                  ),
                ),
        ),
        Semantics(
          label: 'Playtest Tracker',
          excludeSemantics: true,
          child: const LogoMark(size: 44),
        ),
      ],
    ),
  );
}

class NavItem {
  final IconData icon;
  final String label;
  final int badge;
  const NavItem(this.icon, this.label, [this.badge = 0]);
}

class PillNav extends StatelessWidget {
  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onTap;
  const PillNav({
    super.key,
    required this.items,
    required this.index,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: const BoxDecoration(
      color: Color(0xFFF1EAE4),
      border: Border(top: BorderSide(color: line)),
    ),
    child: SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              Expanded(
                child: Semantics(
                  button: true,
                  selected: i == index,
                  label: items[i].badge > 0
                      ? '${items[i].label}, ${items[i].badge} waiting'
                      : items[i].label,
                  excludeSemantics: true,
                  child: InkWell(
                    onTap: () => onTap(i),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Badge(
                          isLabelVisible: items[i].badge > 0,
                          label: Text('${items[i].badge}'),
                          backgroundColor: accent,
                          textColor: ink,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 20,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: i == index
                                  ? accent.withValues(alpha: .35)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Icon(
                              items[i].icon,
                              color: i == index ? ink : muted,
                              size: 24,
                            ),
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          items[i].label,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 13.1,
                            color: i == index ? ink : muted,
                            fontWeight: i == index
                                ? FontWeight.w700
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    ),
  );
}

/// Segmented control: dark selected pill, as on the retest screen.
class Segmented extends StatelessWidget {
  final List<String> options;
  final String value;
  final ValueChanged<String> onChanged;
  const Segmented({
    super.key,
    required this.options,
    required this.value,
    required this.onChanged,
  });
  @override
  Widget build(BuildContext context) => Container(
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: line),
    ),
    clipBehavior: Clip.antiAlias,
    child: Row(
      children: [
        for (final o in options)
          Expanded(
            child: InkWell(
              onTap: () => onChanged(o),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(vertical: 16),
                color: o == value ? darkPanel : Colors.transparent,
                child: Text(
                  o,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: o == value ? Colors.white : ink,
                    fontSize: 14,
                  ),
                ),
              ),
            ),
          ),
      ],
    ),
  );
}

/// Shows loading, error (with retry) and empty states for any async value.
class AsyncView<T> extends StatelessWidget {
  final AsyncValue<T> value;
  final VoidCallback onRetry;
  final bool Function(T)? isEmpty;
  final String emptyMessage;
  final Widget Function(T) builder;
  const AsyncView({
    super.key,
    required this.value,
    required this.onRetry,
    required this.builder,
    this.isEmpty,
    this.emptyMessage = 'Nothing here yet.',
  });

  @override
  Widget build(BuildContext context) => value.when(
    loading: () => const Padding(
      padding: EdgeInsets.all(32),
      child: Center(child: CircularProgressIndicator(color: accent)),
    ),
    error: (e, _) => Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(friendlyError(e), textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: onRetry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    ),
    data: (d) => (isEmpty?.call(d) ?? false)
        ? Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                emptyMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(color: muted),
              ),
            ),
          )
        : builder(d),
  );
}

class SetupNeeded extends StatelessWidget {
  const SetupNeeded({super.key});
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(24),
      child: Text(
        'Backend not configured.\nRun with\n--dart-define=SUPABASE_URL=...\n--dart-define=SUPABASE_ANON_KEY=...',
        textAlign: TextAlign.center,
      ),
    ),
  );
}
