import 'dart:math' as math;

import 'package:flutter/services.dart' show Clipboard, ClipboardData;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'repository_extras.dart';
import 'screens.dart';
import 'studio.dart';
import 'theme.dart';

// ------------------------------------------------------------ providers

final projectProvider = FutureProvider.autoDispose
    .family<Rec, String>((ref, id) async =>
        Map<String, dynamic>.from(await sb.from('projects').select().eq('id', id).single()));

final buildSessionsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) async => List<Rec>.from(await sb
        .from('sessions')
        .select('id, build_version, tester_id, started_at')
        .eq('project_id', id)
        .limit(1000)));

/// Every event's session and name, for per-build counts on Compare builds.
final compareEventsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) async => List<Rec>.from(await sb
        .from('events')
        .select('session_id, name')
        .eq('project_id', id)
        .limit(5000)));

final buildReportsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) async => List<Rec>.from(await sb
        .from('reports')
        .select()
        .eq('project_id', id)
        .order('created_at', ascending: false)
        .limit(1000)));

final eventCountProvider = FutureProvider.autoDispose.family<int, String>(
    (ref, id) async =>
        (await sb.from('events').select('id').eq('project_id', id).limit(1000)).length);

final projectEventsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) async => List<Rec>.from(await sb
        .from('events')
        .select()
        .eq('project_id', id)
        .order('created_at', ascending: false)
        .limit(pageSize)));

final retestsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) async => List<Rec>.from(await sb
        .from('retests')
        .select()
        .eq('report_id', id)
        .order('created_at', ascending: false)));

final testerSessionsProvider = FutureProvider.autoDispose
    .family<List<Rec>, (String, String)>((ref, a) async => List<Rec>.from(await sb
        .from('sessions')
        .select()
        .eq('project_id', a.$1)
        .eq('tester_id', a.$2)
        .order('started_at', ascending: false)
        .limit(pageSize)));

final testerReportsProvider = FutureProvider.autoDispose
    .family<List<Rec>, (String, String)>((ref, a) async => List<Rec>.from(await sb
        .from('reports')
        .select()
        .eq('project_id', a.$1)
        .eq('tester_id', a.$2)
        .order('created_at', ascending: false)
        .limit(pageSize)));

class SessionStats {
  final Map<String, int> events, reports;
  SessionStats(this.events, this.reports);
}

/// Per-session event and report counts for the Sessions list and dashboard.
final sessionStatsProvider = FutureProvider.autoDispose.family<SessionStats, String>((ref, id) async {
  Map<String, int> count(List rows) {
    final m = <String, int>{};
    for (final r in rows) {
      m.update('${r['session_id']}', (v) => v + 1, ifAbsent: () => 1);
    }
    return m;
  }

  final ev = await sb.from('events').select('session_id').eq('project_id', id).limit(1000);
  final rp = await sb.from('reports').select('session_id').eq('project_id', id).limit(1000);
  return SessionStats(count(ev), count(rp));
});

void push(BuildContext c, Widget w) =>
    Navigator.push(c, MaterialPageRoute(builder: (_) => w));

Widget page(String title, List<Widget> children) => Builder(
      builder: (context) => Scaffold(
        body: SafeArea(
          child: Column(children: [
            TopBar(title),
            Expanded(
              child: ListView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: children),
            ),
          ]),
        ),
      ),
    );

// ----------------------------------------------------------- game shell

class GameShell extends ConsumerStatefulWidget {
  final String id;
  const GameShell({super.key, required this.id});
  @override
  ConsumerState<GameShell> createState() => _GameShellState();
}

class _GameShellState extends ConsumerState<GameShell> {
  int _index = 0; // 0 Dashboard, 1 Reports, 2 Sessions, 3 Events

  /// Back goes to the Dashboard first, then to the project list. It never leaves the app from here.
  void _back() {
    if (_index != 0) {
      setState(() => _index = 0);
    } else if (context.canPop()) {
      context.pop();
    } else {
      context.go('/');
    }
  }

  Future<void> _switchGame() async {
    final List<Rec> games = ref.read(projectsProvider).value ?? await ref.read(projectsProvider.future);
    if (!mounted) return;
    final picked = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: bg,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: ListView(shrinkWrap: true, padding: const EdgeInsets.fromLTRB(24, 0, 24, 16), children: [
          const Padding(padding: EdgeInsets.only(bottom: 8), child: Text('Switch game', style: TextStyle(fontSize: 20))),
          for (final g in games)
            ListTile(
              minTileHeight: 56,
              leading: Avatar('${g['name']}'.substring(0, 1).toUpperCase(), square: true, size: 40),
              title: Text('${g['name']}'),
              trailing: g['id'] == widget.id ? const Icon(Icons.check, color: ink) : null,
              onTap: () => Navigator.pop(c, '${g['id']}'),
            ),
          ListTile(
            minTileHeight: 56,
            leading: const Icon(Icons.grid_view_outlined),
            title: const Text('All games'),
            onTap: () => Navigator.pop(c, ''),
          ),
        ]),
      ),
    );
    if (!mounted || picked == null || picked == widget.id) return;
    if (picked.isEmpty) {
      context.go('/');
    } else {
      context.pushReplacement('/game/$picked');
    }
  }

  @override
  Widget build(BuildContext context) {
    final project = ref.watch(projectProvider(widget.id));
    final name = project.value?['name'] ?? '';
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(children: [
            TopBar('$name', onBack: _back, onTitleTap: _switchGame),
            Expanded(
              child: project.when(
                loading: () => const Center(child: CircularProgressIndicator(color: accent)),
                error: (e, _) => Center(child: Text(friendlyError(e))),
                data: (p) => IndexedStack(index: _index, children: [
                  DashboardTab(p, onReports: () => setState(() => _index = 1)),
                  ReportsTab(widget.id),
                  SessionsTab(widget.id),
                  EventsTab(widget.id),
                ]),
              ),
            ),
          ]),
        ),
        bottomNavigationBar: PillNav(
          index: _index,
          onTap: (i) => setState(() => _index = i),
          items: const [
            NavItem(Icons.dashboard_outlined, 'Dashboard'),
            NavItem(Icons.flag_outlined, 'Reports'),
            NavItem(Icons.schedule, 'Sessions'),
            NavItem(Icons.monitor_heart_outlined, 'Events'),
          ],
        ),
      ),
    );
  }
}

// ------------------------------------------------------------ dashboard

class DashboardTab extends ConsumerWidget {
  final Rec project;
  final VoidCallback onReports;
  const DashboardTab(this.project, {super.key, required this.onReports});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${project['id']}';
    final sessionsLite = ref.watch(buildSessionsProvider(id));
    final reportsLite = ref.watch(buildReportsProvider(id));
    final events = ref.watch(eventCountProvider(id));
    final recentSessions = ref.watch(sessionsProvider(id));
    final recentReports = ref.watch(reportsProvider((id, null)));
    final recentEvents = ref.watch(projectEventsProvider(id));
    void refresh() {
      for (final p in [buildSessionsProvider(id), buildReportsProvider(id), eventCountProvider(id), sessionsProvider(id), projectEventsProvider(id)]) {
        ref.invalidate(p);
      }
      ref.invalidate(reportsProvider);
    }

    if (sessionsLite.isLoading || reportsLite.isLoading) {
      return const Center(child: CircularProgressIndicator(color: accent));
    }
    if (sessionsLite.hasError || reportsLite.hasError) {
      return Center(
          child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(120, 44)),
              onPressed: refresh,
              child: const Text('Retry')));
    }
    final s = sessionsLite.value!, r = reportsLite.value!;
    final total = r.length;
    final open = r.where((x) => x['status'] == 'Open').length;
    final resolved = r.where((x) => x['status'] == 'Resolved').length;
    final pct = total == 0 ? 0.0 : resolved / total;
    final builds = {for (final x in [...s, ...r]) x['build_version'] as String}.toList()..sort();
    final current = recentSessions.value?.firstOrNull?['build_version'];
    final connected = s.isNotEmpty;

    if (total == 0 && s.isEmpty) {
      return ListView(padding: const EdgeInsets.all(32), children: [
        const SizedBox(height: 40),
        const Icon(Icons.sensors_off_outlined, size: 64, color: muted),
        const SizedBox(height: 16),
        const Text('Nothing received yet',
            textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w400)),
        const SizedBox(height: 8),
        const Text('Connect the game SDK and play a session. Reports and events will appear here.',
            textAlign: TextAlign.center, style: TextStyle(color: muted)),
        const SizedBox(height: 28),
        FilledButton(
            onPressed: () => push(context, SdkScreen(project)), child: const Text('Set up SDK')),
      ]);
    }

    return RefreshIndicator(
      color: accent,
      onRefresh: () async => refresh(),
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: [
        Center(
          child: SizedBox(
            width: 170,
            height: 170,
            child: Stack(alignment: Alignment.center, children: [
              SizedBox.expand(
                child: Semantics(
                  label: '$open open reports out of $total reported',
                  excludeSemantics: true,
                  child: CustomPaint(painter: _RingPainter(total == 0 ? 0 : open / total)),
                ),
              ),
              Column(mainAxisSize: MainAxisSize.min, children: [
                const Text('Open now', style: TextStyle(color: muted, fontSize: 14)),
                Text('$open', style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w400)),
                Text('of $total reported', style: const TextStyle(color: muted, fontSize: 14)),
              ]),
            ]),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: Text.rich(TextSpan(children: [
            TextSpan(text: current == null ? 'No builds yet' : 'Build $current  •  '),
            TextSpan(
                text: connected ? '● SDK connected' : '● SDK not connected',
                style: TextStyle(color: connected ? const Color(0xFF2F6B4A) : muted)),
          ]), style: const TextStyle(color: muted)),
        ),
        const SizedBox(height: 24),
        Row(children: [
          Expanded(
            child: Container(
              height: 80,
              decoration: BoxDecoration(
                  color: const Color(0xFFEBDDD3), borderRadius: BorderRadius.circular(6)),
              alignment: Alignment.centerLeft,
              child: FractionallySizedBox(
                widthFactor: pct.clamp(.12, 1),
                heightFactor: 1,
                child: Container(
                  color: accent,
                  alignment: Alignment.bottomLeft,
                  padding: const EdgeInsets.all(8),
                  child: const FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text('Resolved',
                        maxLines: 1, style: TextStyle(color: Colors.white, fontSize: 13.1)),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text('${(pct * 100).round()}%',
              style: const TextStyle(fontSize: 48, fontWeight: FontWeight.w400)),
        ]),
        const SizedBox(height: 8),
        InfoRow('Sessions', '${s.length}', bold: true),
        InfoRow('Testers (pseudonymous)', '${s.map((x) => x['tester_id']).toSet().length}', bold: true),
        InfoRow('Events recorded', '${events.value ?? '-'}', bold: true),
        const SizedBox(height: 16),
        Row(children: [
          for (final b in [
            ('Event Studio', () => push(context, EventStudioScreen(id))),
            ('Compare builds', builds.length < 2 ? null : () => push(context, CompareScreen(id))),
            ('SDK setup', () => push(context, SdkScreen(project))),
          ])
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(right: 6),
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 14),
                      textStyle: const TextStyle(fontSize: 13.1)),
                  onPressed: b.$2,
                  child: Text(b.$1, maxLines: 1),
                ),
              ),
            ),
        ]),
        const SectionTitle('Builds'),
        Panel(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
          child: Column(children: [
            for (var i = 0; i < builds.length; i++)
              InfoRow(
                'Build ${builds[i]}${builds[i] == current ? ' • current' : ''}',
                '${s.where((x) => x['build_version'] == builds[i]).length} sessions • '
                    '${r.where((x) => x['build_version'] == builds[i]).length} reports',
                last: i == builds.length - 1,
                onTap: builds.length < 2 ? null : () => push(context, CompareScreen(id)),
              ),
          ]),
        ),
        const SectionTitle('Recent sessions'),
        Panel(
          child: AsyncView<List<Rec>>(
            value: recentSessions,
            onRetry: refresh,
            isEmpty: (l) => l.isEmpty,
            emptyMessage: 'No sessions yet.',
            builder: (l) => Column(children: [
              for (final x in l.take(3)) SessionTile(x),
            ]),
          ),
        ),
        const SectionTitle('Recent reports'),
        Panel(
          child: AsyncView<List<Rec>>(
            value: recentReports,
            onRetry: refresh,
            isEmpty: (l) => l.isEmpty,
            emptyMessage: 'No reports yet.',
            builder: (l) => Column(children: [for (final x in l.take(3)) ReportTile(x)]),
          ),
        ),
        const SectionTitle('Recent events'),
        Panel(
          child: AsyncView<List<Rec>>(
            value: recentEvents,
            onRetry: refresh,
            isEmpty: (l) => l.isEmpty,
            emptyMessage: 'No events yet.',
            builder: (l) => Column(children: [for (final x in l.take(3)) EventRow(x)]),
          ),
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- tiles

int? _minutes(Rec s) {
  if (s['ended_at'] == null) return null;
  final d = DateTime.parse(s['ended_at']).difference(DateTime.parse(s['started_at']));
  return d.inMinutes < 1 ? 1 : d.inMinutes;
}

class SessionTile extends ConsumerWidget {
  final Rec s;
  const SessionTile(this.s, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final stats = ref.watch(sessionStatsProvider('${s['project_id']}')).value;
    final flags = stats?.reports['${s['id']}'] ?? 0;
    final events = stats?.events['${s['id']}'];
    return InkWell(
      onTap: () => context.push('/session/${s['id']}'),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(children: [
          Container(
            width: 54,
            height: 54,
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: flags > 0 ? accent : const Color(0xFFE0DAD4), shape: BoxShape.circle),
            child: Text(flags > 0 ? '$flags \u2691' : '\u2013',
                style: const TextStyle(fontSize: 17)),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(shortId('S', s['id']),
                  style: TextStyle(
                      fontSize: 20,
                      fontWeight: flags > 0 ? FontWeight.w700 : FontWeight.w400)),
              Text(
                  'Tester ${'${s['tester_id']}'.replaceFirst('tester-', 'T-')} \u2022 Build ${s['build_version']}\n'
                  '${_minutes(s) == null ? '' : '${_minutes(s)} min'}'
                  '${events == null ? '' : '${_minutes(s) == null ? '' : ' \u2022 '}$events events'}',
                  style: const TextStyle(color: muted, fontSize: 13.1)),
            ]),
          ),
        ]),
      ),
    );
  }
}

class EventRow extends StatelessWidget {
  final Rec e;
  const EventRow(this.e, {super.key});
  @override
  Widget build(BuildContext context) {
    final props = (e['props'] as Map).entries.map((x) => '${x.key}: ${x.value}').join(', ');
    final issue = e['name'] == 'issue_reported';
    return InkWell(
      onTap: () => showEvent(context, e),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
        child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          SizedBox(
              width: 64,
              child: Text(clock(e['created_at']),
                  style: const TextStyle(color: muted, fontSize: 17))),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(e['name'],
                  style: mono.copyWith(
                      fontSize: 16,
                      color: issue ? const Color(0xFFC0643F) : ink,
                      fontWeight: issue ? FontWeight.w700 : FontWeight.w400)),
              const SizedBox(height: 2),
              Text(props.isEmpty ? 'no properties' : props,
                  style: TextStyle(
                      color: muted,
                      fontSize: 14,
                      fontWeight: issue ? FontWeight.w700 : FontWeight.w400)),
            ]),
          ),
          Text(shortId('S', e['session_id']),
              style: TextStyle(
                  color: muted, fontSize: 15, fontWeight: issue ? FontWeight.w700 : FontWeight.w400)),
        ]),
      ),
    );
  }
}

void showEvent(BuildContext context, Rec e) => push(context, EventDetailScreen(e));

// ------------------------------------------------------------ list tabs

class SearchBox extends StatelessWidget {
  final String hint;
  final ValueChanged<String> onChanged;
  const SearchBox(this.hint, {super.key, required this.onChanged});
  @override
  Widget build(BuildContext context) => TextField(
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: const TextStyle(fontSize: 14, color: muted),
          prefixIcon: const Icon(Icons.search, color: muted, size: 20),
          filled: true,
          fillColor: cardColor,
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: line)),
          focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(18), borderSide: const BorderSide(color: ink)),
        ),
      );
}

class FilterChips extends StatelessWidget {
  final List<String> options;
  final String? value;
  final String allLabel;
  final Map<String, int>? counts;
  final int? total;
  final ValueChanged<String?> onChanged;
  const FilterChips(
      {super.key,
      required this.options,
      required this.value,
      required this.onChanged,
      this.allLabel = 'All',
      this.counts,
      this.total});

  Widget _label(String? o, bool on) {
    final n = o == null ? total : counts?[o];
    return Text.rich(TextSpan(children: [
      TextSpan(text: o ?? allLabel),
      if (n != null)
        TextSpan(text: '  $n', style: TextStyle(color: on ? const Color(0xFFBFB5AD) : muted)),
    ]));
  }

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 56,
        child: ListView(scrollDirection: Axis.horizontal, children: [
          for (final o in [null, ...options])
            Padding(
              padding: const EdgeInsets.only(right: 8, top: 2, bottom: 2),
              child: ChoiceChip(
                label: _label(o, value == o),
                selected: value == o,
                showCheckmark: false,
                selectedColor: darkPanel,
                labelStyle: TextStyle(color: value == o ? Colors.white : ink, fontSize: 13.1),
                labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                materialTapTargetSize: MaterialTapTargetSize.padded,
                backgroundColor: cardColor,
                side: const BorderSide(color: line),
                shape: const StadiumBorder(),
                onSelected: (_) => onChanged(o),
              ),
            ),
        ]),
      );
}

/// Bumped whenever a report is changed or removed, so open lists reload themselves.
final reportsChanged = ValueNotifier<int>(0);

final reportCountsProvider = FutureProvider.autoDispose.family<Map<String, int>, String>((ref, id) async {
  final rows = List<Rec>.from(await sb.from('reports').select('status').eq('project_id', id).limit(5000));
  return {for (final st in statuses) st: rows.where((r) => r['status'] == st).length, 'all': rows.length};
});

String _day(DateTime d) => '${d.day}/${d.month}/${d.year}';

/// 48dp-high outlined control used in the list filter rows.
Widget _control({required VoidCallback onTap, required Widget child, String? label}) => Semantics(
      button: true,
      label: label,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 48),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            textStyle: const TextStyle(fontSize: 13.1)),
        onPressed: onTap,
        child: child,
      ),
    );

class ReportsTab extends ConsumerStatefulWidget {
  final String projectId;
  const ReportsTab(this.projectId, {super.key});
  @override
  ConsumerState<ReportsTab> createState() => _ReportsTabState();
}

class _ReportsTabState extends ConsumerState<ReportsTab> {
  String? _status, _severity;
  String _sort = 'newest', _q = '';
  DateTimeRange? _range;
  final _rows = <Rec>[];
  bool _loading = false, _hasMore = true;
  Object? _error;

  void _onChanged() => _reload();

  @override
  void initState() {
    super.initState();
    reportsChanged.addListener(_onChanged);
    _reload();
  }

  @override
  void dispose() {
    reportsChanged.removeListener(_onChanged);
    super.dispose();
  }

  Future<void> _reload() async {
    _rows.clear();
    _hasMore = true;
    _error = null;
    ref.invalidate(reportCountsProvider(widget.projectId));
    await _more();
  }

  Future<void> _more() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page = await ref.read(repoProvider).reportsPage(widget.projectId,
          status: _status, severity: _severity, range: _range, sort: _sort, offset: _rows.length);
      _rows.addAll(page);
      _hasMore = page.length == listPage;
      _error = null;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: now,
      initialDateRange: _range,
    );
    if (r != null) {
      _range = r;
      _reload();
    }
  }

  Future<void> _export() async {
    try {
      final csv = await ref
          .read(repoProvider)
          .exportReportsCsv(widget.projectId, status: _status, severity: _severity, range: _range);
      await Clipboard.setData(ClipboardData(text: csv));
      final n = '\n'.allMatches(csv).length - 1;
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('CSV of $n report${n == 1 ? '' : 's'} copied. Paste it into a spreadsheet.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = ref.watch(projectProvider(widget.projectId)).value?['name'] ?? '';
    final counts = ref.watch(reportCountsProvider(widget.projectId)).value;
    final shown = _rows.where((r) {
      final hay =
          '${r['description']} ${shortId('R', r['id'])} ${r['tester_id']} ${shortId('S', r['session_id'] ?? '0000')}'
              .toLowerCase();
      return hay.contains(_q);
    }).toList();
    return RefreshIndicator(
      color: accent,
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: [
        BigTitle('Reports', sub: '$name'),
        const SizedBox(height: 16),
        SearchBox('Search by title, ID, tester or session', onChanged: (v) => setState(() => _q = v.toLowerCase())),
        const SizedBox(height: 8),
        FilterChips(
            options: statuses,
            value: _status,
            counts: counts,
            total: counts?['all'],
            onChanged: (v) {
              _status = v;
              _reload();
            }),
        const SizedBox(height: 4),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            PopupMenuButton<String?>(
              tooltip: 'Filter by severity',
              onSelected: (v) {
                _severity = v == '' ? null : v;
                _reload();
              },
              itemBuilder: (_) => [
                const PopupMenuItem(value: '', child: Text('All severities')),
                for (final s in severities) PopupMenuItem(value: s, child: Text(s)),
              ],
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: line), borderRadius: BorderRadius.circular(24)),
                child: Text(_severity == null ? 'Severity: any' : 'Severity: $_severity', style: const TextStyle(fontSize: 13.1)),
              ),
            ),
            const SizedBox(width: 8),
            PopupMenuButton<String>(
              tooltip: 'Sort reports',
              onSelected: (v) {
                _sort = v;
                _reload();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'newest', child: Text('Newest first')),
                PopupMenuItem(value: 'oldest', child: Text('Oldest first')),
                PopupMenuItem(value: 'severity', child: Text('Highest severity first')),
              ],
              child: Container(
                constraints: const BoxConstraints(minHeight: 48),
                padding: const EdgeInsets.symmetric(horizontal: 14),
                alignment: Alignment.center,
                decoration: BoxDecoration(border: Border.all(color: line), borderRadius: BorderRadius.circular(24)),
                child: Text('Sort: ${switch (_sort) { 'oldest' => 'oldest', 'severity' => 'severity', _ => 'newest' }}',
                    style: const TextStyle(fontSize: 13.1)),
              ),
            ),
            const SizedBox(width: 8),
            _control(
              label: 'Filter by date range',
              onTap: _pickRange,
              child: Text(_range == null ? 'Dates: any' : '${_day(_range!.start)} - ${_day(_range!.end)}'),
            ),
            if (_range != null)
              IconButton(
                tooltip: 'Clear date range',
                constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
                onPressed: () {
                  _range = null;
                  _reload();
                },
                icon: const Icon(Icons.close, size: 20),
              ),
            const SizedBox(width: 8),
            _control(label: 'Export reports as CSV', onTap: _export, child: const Text('Export CSV')),
          ]),
        ),
        const SizedBox(height: 8),
        if (_error != null && _rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(friendlyError(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            ]),
          )
        else if (_rows.isEmpty && _loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: accent)))
        else if (_rows.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No reports match.\nReports appear here when a tester submits one from the game.',
                  textAlign: TextAlign.center, style: TextStyle(color: muted)))
        else ...[
          for (final r in shown) ReportTile(r),
          if (shown.isEmpty && _q.isNotEmpty)
            const Padding(
                padding: EdgeInsets.all(16), child: Text('No loaded reports match your search. Try Load more.', style: TextStyle(color: muted))),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _loading ? null : _more,
                child: Text(_loading ? 'Loading...' : 'Load more'),
              ),
            ),
          if (_error != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(friendlyError(_error!), style: const TextStyle(color: errorColor))),
        ],
      ]),
    );
  }
}

class SessionsTab extends ConsumerStatefulWidget {
  final String projectId;
  const SessionsTab(this.projectId, {super.key});
  @override
  ConsumerState<SessionsTab> createState() => _SessionsTabState();
}

class _SessionsTabState extends ConsumerState<SessionsTab> {
  String? _build;
  DateTimeRange? _range;
  final _rows = <Rec>[];
  bool _loading = false, _hasMore = true;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    _rows.clear();
    _hasMore = true;
    _error = null;
    ref.invalidate(sessionStatsProvider(widget.projectId));
    await _more();
  }

  Future<void> _more() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final page =
          await ref.read(repoProvider).sessionsPage(widget.projectId, build: _build, range: _range, offset: _rows.length);
      _rows.addAll(page);
      _hasMore = page.length == listPage;
      _error = null;
    } catch (e) {
      _error = e;
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _pickRange() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
        context: context, firstDate: DateTime(now.year - 3), lastDate: now, initialDateRange: _range);
    if (r != null) {
      _range = r;
      _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final builds = ({
      for (final x in ref.watch(buildSessionsProvider(widget.projectId)).value ?? <Rec>[]) '${x['build_version']}'
    }.toList()
      ..sort());
    return RefreshIndicator(
      color: accent,
      onRefresh: _reload,
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: [
        const BigTitle('Sessions', sub: 'One session is one recorded period of play. A tester can have many.'),
        const SizedBox(height: 12),
        FilterChips(
            options: builds,
            value: _build,
            allLabel: 'All builds',
            onChanged: (v) {
              _build = v;
              _reload();
            }),
        Row(children: [
          _control(
            label: 'Filter by date range',
            onTap: _pickRange,
            child: Text(_range == null ? 'Dates: any' : '${_day(_range!.start)} - ${_day(_range!.end)}'),
          ),
          if (_range != null)
            IconButton(
              tooltip: 'Clear date range',
              constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
              onPressed: () {
                _range = null;
                _reload();
              },
              icon: const Icon(Icons.close, size: 20),
            ),
        ]),
        const SizedBox(height: 8),
        if (_error != null && _rows.isEmpty)
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              Text(friendlyError(_error!), textAlign: TextAlign.center),
              const SizedBox(height: 12),
              OutlinedButton(onPressed: _reload, child: const Text('Try again')),
            ]),
          )
        else if (_rows.isEmpty && _loading)
          const Padding(padding: EdgeInsets.all(32), child: Center(child: CircularProgressIndicator(color: accent)))
        else if (_rows.isEmpty)
          const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No sessions match.\nRun the game with the SDK to record one.',
                  textAlign: TextAlign.center, style: TextStyle(color: muted)))
        else ...[
          for (final s in _rows) SessionTile(s),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _loading ? null : _more,
                child: Text(_loading ? 'Loading...' : 'Load more'),
              ),
            ),
        ],
      ]),
    );
  }
}

class EventsTab extends ConsumerStatefulWidget {
  final String projectId;
  const EventsTab(this.projectId, {super.key});
  @override
  ConsumerState<EventsTab> createState() => _EventsTabState();
}

class _EventsTabState extends ConsumerState<EventsTab> {
  String? _build, _name;
  @override
  Widget build(BuildContext context) {
    final events = ref.watch(projectEventsProvider(widget.projectId));
    final sessions = ref.watch(sessionsProvider(widget.projectId)).value ?? [];
    final buildOf = {for (final x in sessions) '${x['id']}': '${x['build_version']}'};
    final builds = {...buildOf.values}.toList()..sort();
    return RefreshIndicator(
      color: accent,
      onRefresh: () async => ref.refresh(projectEventsProvider(widget.projectId).future),
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
              child: BigTitle('Events', sub: 'Any event name, with its own properties.')),
          const SizedBox(width: 12),
          SizedBox(
            width: 130,
            height: 76,
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(38))),
              onPressed: () => push(context, EventStudioScreen(widget.projectId)),
              child: const Text('Event\nStudio', textAlign: TextAlign.center),
            ),
          ),
        ]),
        const SizedBox(height: 12),
        AsyncView<List<Rec>>(
          value: events,
          onRetry: () => ref.invalidate(projectEventsProvider(widget.projectId)),
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No events yet.\nThey appear when the game SDK sends them.',
          builder: (all) {
            final names = {for (final e in all) e['name'] as String}.toList()..sort();
            final list = all
                .where((e) =>
                    (_build == null || buildOf['${e['session_id']}'] == _build) &&
                    (_name == null || e['name'] == _name))
                .toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              FilterChips(
                  options: builds,
                  value: _build,
                  allLabel: 'All builds',
                  onChanged: (v) => setState(() => _build = v)),
              Container(
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    isExpanded: true,
                    value: _name,
                    style: const TextStyle(fontSize: 18, color: ink, fontFamily: 'DejaVu'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('All events')),
                      for (final n in names) DropdownMenuItem(value: n, child: Text(n, style: mono)),
                    ],
                    onChanged: (v) => setState(() => _name = v),
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
                child: Text('${list.length} events shown', style: const TextStyle(color: muted)),
              ),
              for (final e in list) EventRow(e),
            ]);
          },
        ),
      ]),
    );
  }
}

// -------------------------------------------------------------- report

class ReportScreen extends ConsumerWidget {
  final String id;
  const ReportScreen({super.key, required this.id});

  Future<void> _setStatus(BuildContext context, WidgetRef ref, String status) async {
    try {
      await ref.read(repoProvider).setStatus(id, status);
      ref.invalidate(reportProvider(id));
      ref.invalidate(reportsProvider);
      ref.invalidate(inboxProvider);
      ref.invalidate(allStatusesProvider);
      ref.invalidate(buildReportsProvider);
      reportsChanged.value++;
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final report = ref.watch(reportProvider(id));
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar('Report ${shortId('R', id)}'),
          Expanded(
            child: AsyncView<Rec?>(
              value: report,
              onRetry: () => ref.invalidate(reportProvider(id)),
              isEmpty: (r) => r == null,
              emptyMessage: 'This report no longer exists.',
              builder: (r) => ListView(children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(shortTitle(r!['description']),
                        style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w400)),
                    const SizedBox(height: 4),
                    Text('${shortId('R', id)} • ${fmt(r['created_at'])}',
                        style: const TextStyle(color: muted)),
                    if (r['session_id'] != null) ...[
                      const SizedBox(height: 16),
                      EventTimeline(r['session_id'], at: r['created_at']),
                    ],
                  ]),
                ),
                Container(
                  color: darkPanel,
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 28),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('Tester wrote', style: TextStyle(color: Color(0xFF9C928A))),
                    const SizedBox(height: 10),
                    Text('"${r['description']}"',
                        style: const TextStyle(color: Colors.white, fontSize: 21, height: 1.35)),
                    const SizedBox(height: 28),
                    Row(children: [
                      for (final s in statuses)
                        Expanded(
                          child: InkWell(
                            onTap: s == r['status'] ? null : () => _setStatus(context, ref, s),
                            child: Column(children: [
                              Icon(
                                  switch (s) {
                                    'Open' => Icons.circle,
                                    'In Progress' => Icons.contrast,
                                    _ => Icons.check,
                                  },
                                  color: s == r['status'] ? Colors.white : const Color(0xFF8A7E76)),
                              const SizedBox(height: 6),
                              Text(s,
                                  style: TextStyle(
                                      color: s == r['status']
                                          ? Colors.white
                                          : const Color(0xFF8A7E76))),
                              Text(s == r['status'] ? 'report status' : '',
                                  style: const TextStyle(color: accent, fontSize: 13.1)),
                            ]),
                          ),
                        ),
                    ]),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 40),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const SectionTitle('Where it happened'),
                    InfoRow('Tester', '${r['tester_id']}',
                        onTap: () => push(context,
                            TesterScreen(projectId: '${r['project_id']}', testerId: '${r['tester_id']}'))),
                    if (r['session_id'] != null)
                      InfoRow('Session', shortId('S', r['session_id']),
                          onTap: () => context.push('/session/${r['session_id']}')),
                    InfoRow('Build', '${r['build_version']}'),
                    if (ref.watch(levelsProvider).value?['${r['session_id']}'] != null)
                      InfoRow('Level', 'Level ${ref.watch(levelsProvider).value!['${r['session_id']}']}'),
                    InfoRow('Category', '${r['category']}'),
                    if (r['severity'] != null) InfoRow('Severity', '${r['severity']}'),
                    if (r['device_model'] != null) InfoRow('Device', '${r['device_model']}'),
                    if (r['android_version'] != null) InfoRow('Android', '${r['android_version']}', last: true),
                    const SizedBox(height: 8),
                    const Text(
                        'Tester IDs are pseudonymous. They are not names or emails and do not prove who played.',
                        style: TextStyle(color: muted, fontSize: 13.1)),
                    const SectionTitle('Retests'),
                    Text(
                        'A retest checks this issue on a later build. It is separate from the report status (${r['status']}).',
                        style: const TextStyle(color: muted, height: 1.5)),
                    const SizedBox(height: 8),
                    RetestList(r),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                      onPressed: () => push(context, RetestScreen(r)),
                      child: const Text('Start a retest'),
                    ),
                    if (r['session_id'] != null) ...[
                      SectionTitle('Events before the report in session ${shortId('S', r['session_id'])}'),
                      EventTimeline(r['session_id'], list: true),
                      const SizedBox(height: 20),
                      const InfoCard('Evidence, not proof',
                          'Events show what was recorded. They do not prove what caused the problem.',
                          warn: true),
                    ],
                    const SectionTitle('Privacy'),
                    const Text(
                        'Testers should not include personal details. If one did, redact the text or delete the report.',
                        style: TextStyle(color: muted, height: 1.5)),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                          onPressed: r['redacted'] == true
                              ? null
                              : () => _reportAction(context, ref, r,
                                  title: 'Redact this report?',
                                  body: 'The tester text is replaced with "[redacted by developer]". The events and status stay.',
                                  confirm: 'Redact',
                                  run: () => ref.read(repoProvider).redactReport('${r['id']}'),
                                  done: 'Report redacted'),
                          child: Text(r['redacted'] == true ? 'Redacted' : 'Redact text'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                              minimumSize: const Size.fromHeight(48), foregroundColor: errorColor),
                          onPressed: () => _reportAction(context, ref, r,
                              title: 'Delete this report?',
                              body: 'The report is removed for good. Its session and events are not deleted.',
                              confirm: 'Delete',
                              run: () => ref.read(repoProvider).deleteReport('${r['id']}'),
                              done: 'Report deleted',
                              leave: true),
                          child: const Text('Delete report'),
                        ),
                      ),
                    ]),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Confirm, run, refresh the lists that show the report, and report the result in plain words.
Future<void> _reportAction(BuildContext context, WidgetRef ref, Rec r,
    {required String title,
    required String body,
    required String confirm,
    required Future<void> Function() run,
    required String done,
    bool leave = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(confirm)),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  try {
    await run();
    ref.invalidate(reportProvider('${r['id']}'));
    ref.invalidate(inboxProvider);
    ref.invalidate(reportCountsProvider('${r['project_id']}'));
    reportsChanged.value++;
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(done)));
    if (leave) context.pop();
  } catch (e) {
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
  }
}

/// Ruler of ticks (one per event) with the report moment marked, or a list.
class EventTimeline extends ConsumerWidget {
  final String sessionId;
  final String? at;
  final bool list;
  const EventTimeline(this.sessionId, {super.key, this.at, this.list = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final events = ref.watch(eventsProvider(sessionId));
    return AsyncView<List<Rec>>(
      value: events,
      onRetry: () => ref.invalidate(eventsProvider(sessionId)),
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No events were recorded for this session.',
      builder: (l) {
        if (list) return Column(children: [for (final e in l) EventRow(e)]);
        return _Ruler(l, onTap: (e) => showEvent(context, e), highlight: at);
      },
    );
  }
}

class RetestList extends ConsumerWidget {
  final Rec report;
  const RetestList(this.report, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final id = '${report['id']}';
    return AsyncView<List<Rec>>(
      value: ref.watch(retestsProvider(id)),
      onRetry: () => ref.invalidate(retestsProvider(id)),
      isEmpty: (l) => l.isEmpty,
      emptyMessage: 'No retests yet.',
      builder: (l) => Panel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(children: [
          for (var i = 0; i < l.length; i++)
            InfoRow('${l[i]['result']}', 'Build ${l[i]['build_version']}', last: i == l.length - 1),
        ]),
      ),
    );
  }
}

class RetestScreen extends ConsumerStatefulWidget {
  final Rec report;
  const RetestScreen(this.report, {super.key});
  @override
  ConsumerState<RetestScreen> createState() => _RetestScreenState();
}

class _RetestScreenState extends ConsumerState<RetestScreen> {
  late String _build = '${widget.report['build_version']}';
  String _result = retestResults.first;
  final _note = TextEditingController();
  bool _busy = false;

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await sb.from('retests').insert({
        'report_id': widget.report['id'],
        'project_id': widget.report['project_id'],
        'build_version': _build,
        'result': _result,
        'note': _note.text.trim().isEmpty ? null : _note.text.trim(),
      });
      ref.invalidate(retestsProvider('${widget.report['id']}'));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Could not save retest: ${friendlyError(e)}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final builds = ref
            .watch(buildSessionsProvider('${widget.report['project_id']}'))
            .value
            ?.map((x) => x['build_version'] as String)
            .toSet() ??
        {};
    builds.add('${widget.report['build_version']}');
    final options = builds.toList()..sort();
    return page('Retest', [
      BigTitle('Retest ${shortId('R', widget.report['id'])}',
          sub: '${shortTitle(widget.report['description'])} • first reported on build ${widget.report['build_version']}'),
      const SizedBox(height: 20),
      Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Retested on build', style: TextStyle(color: muted)),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            initialValue: _build,
            items: [for (final b in options) DropdownMenuItem(value: b, child: Text(b))],
            onChanged: (v) => setState(() => _build = v!),
            decoration: InputDecoration(
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
          const SizedBox(height: 18),
          const Text('Result', style: TextStyle(color: muted)),
          const SizedBox(height: 8),
          Segmented(
              options: retestResults,
              value: _result,
              onChanged: (v) => setState(() => _result = v)),
          const SizedBox(height: 18),
          const Text('Note (optional)', style: TextStyle(color: muted)),
          const SizedBox(height: 8),
          TextField(
            controller: _note,
            maxLines: 3,
            decoration: InputDecoration(
              hintText: 'What did you observe?',
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 20),
      FilledButton(
          onPressed: _busy ? null : _save,
          child: Text(_busy ? 'Saving...' : 'Save retest')),
    ]);
  }
}

// ------------------------------------------------------------- session

class SessionScreen extends ConsumerWidget {
  final String id;
  const SessionScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider(id));
    final reports = ref.watch(sessionReportsProvider(id));
    return Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar('Session ${shortId('S', id)}'),
          Expanded(
            child: AsyncView<Rec?>(
              value: session,
              onRetry: () => ref.invalidate(sessionProvider(id)),
              isEmpty: (s) => s == null,
              emptyMessage: 'This session no longer exists.',
              builder: (s) => ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: [
                BigTitle(shortId('S', id), sub: 'Started ${fmt(s!['started_at'])}'),
                const SizedBox(height: 12),
                InfoRow('Tester', '${s['tester_id']}',
                    onTap: () => push(context,
                        TesterScreen(projectId: '${s['project_id']}', testerId: '${s['tester_id']}'))),
                InfoRow('Build', '${s['build_version']}'),
                InfoRow('Ended', fmt(s['ended_at']), last: true),
                const SizedBox(height: 10),
                Text('Session ${shortId('S', id)} belongs to tester ${s['tester_id']}. The ID is pseudonymous.',
                    style: const TextStyle(color: muted, height: 1.5)),
                const SectionTitle('Events'),
                EventTimeline(id),
                EventTimeline(id, list: true),
                const SectionTitle('Linked reports'),
                AsyncView<List<Rec>>(
                  value: reports,
                  onRetry: () => ref.invalidate(sessionReportsProvider(id)),
                  isEmpty: (l) => l.isEmpty,
                  emptyMessage: 'No reports in this session.',
                  builder: (l) => Panel(child: Column(children: [for (final r in l) ReportTile(r)])),
                ),
              ]),
            ),
          ),
        ]),
      ),
    );
  }
}

// -------------------------------------------------------------- tester

class TesterScreen extends ConsumerWidget {
  final String projectId, testerId;
  const TesterScreen({super.key, required this.projectId, required this.testerId});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = (projectId, testerId);
    final sessions = ref.watch(testerSessionsProvider(key)).value ?? [];
    final reports = ref.watch(testerReportsProvider(key)).value ?? [];
    final builds = {for (final s in sessions) s['build_version']}.length;
    Widget stat(String n, String l) => Expanded(
          child: Column(children: [
            Text(n, style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w400)),
            Text(l, style: const TextStyle(color: muted)),
          ]),
        );
    return page('Tester $testerId', [
      BigTitle('Tester $testerId', sub: 'Pseudonymous installation ID'),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
            color: const Color(0xFFE6DCD3), borderRadius: BorderRadius.circular(18)),
        child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text('About tester IDs',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700))),
            CircleAvatar(
                radius: 14,
                backgroundColor: ink,
                child: Text('i', style: TextStyle(color: Colors.white))),
          ]),
          SizedBox(height: 12),
          Text(
              'This ID stands for one install of the game. The same person may appear under another ID after a reinstall or on a second device, and one ID may be shared. It is not a verified identity, and no name or email is stored.',
              style: TextStyle(height: 1.5)),
        ]),
      ),
      const SizedBox(height: 16),
      Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(
            border: Border.symmetric(horizontal: BorderSide(color: line))),
        child: Row(children: [
          stat('${sessions.length}', 'Sessions'),
          stat('${reports.length}', 'Reports'),
          stat('$builds', 'Builds'),
        ]),
      ),
      const SectionTitle('Sessions'),
      AsyncView<List<Rec>>(
        value: ref.watch(testerSessionsProvider(key)),
        onRetry: () => ref.invalidate(testerSessionsProvider(key)),
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'No sessions.',
        builder: (l) => Column(children: [for (final s in l) SessionTile(s)]),
      ),
      const SectionTitle('Reports'),
      AsyncView<List<Rec>>(
        value: ref.watch(testerReportsProvider(key)),
        onRetry: () => ref.invalidate(testerReportsProvider(key)),
        isEmpty: (l) => l.isEmpty,
        emptyMessage: 'No reports.',
        builder: (l) => Column(children: [for (final r in l) ReportTile(r)]),
      ),
    ]);
  }
}

// ------------------------------------------------------------- compare

class CompareScreen extends ConsumerStatefulWidget {
  final String projectId;
  const CompareScreen(this.projectId, {super.key});
  @override
  ConsumerState<CompareScreen> createState() => _CompareScreenState();
}

final projectRetestsProvider = FutureProvider.autoDispose.family<List<Rec>, String>((ref, projectId) async {
  try {
    return List<Rec>.from(await sb.from('retests').select().eq('project_id', projectId));
  } catch (_) {
    return [];
  }
});

class _CompareScreenState extends ConsumerState<CompareScreen> {
  String? _a, _b;

  Widget _head(String a, String b) => Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: const BoxDecoration(border: Border(top: BorderSide(color: line), bottom: BorderSide(color: line))),
        child: Row(children: [
          const Expanded(flex: 5, child: SizedBox()),
          Expanded(flex: 3, child: Center(child: Text(a, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.1)))),
          Expanded(flex: 3, child: Center(child: Text(b, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13.1)))),
        ]),
      );

  Widget _row(String label, Object x, Object y, {bool mono = false}) => Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
        child: Row(children: [
          Expanded(
              flex: 5,
              child: Text(label, style: mono ? const TextStyle(fontFamily: 'DejaVuMono', fontSize: 13.1) : const TextStyle(fontSize: 16))),
          Expanded(flex: 3, child: Center(child: Text('$x', style: const TextStyle(fontWeight: FontWeight.w700)))),
          Expanded(flex: 3, child: Center(child: Text('$y', style: const TextStyle(fontWeight: FontWeight.w700)))),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final pid = widget.projectId;
    final sessions = ref.watch(buildSessionsProvider(pid));
    final reports = ref.watch(buildReportsProvider(pid));
    final events = ref.watch(compareEventsProvider(pid));
    final retests = ref.watch(projectRetestsProvider(pid)).value ?? [];
    return page('Compare builds', [
      const BigTitle('Compare builds'),
      const SizedBox(height: 12),
      if (sessions.isLoading || reports.isLoading)
        const Center(child: CircularProgressIndicator(color: accent))
      else if (sessions.hasError || reports.hasError)
        const Text('Could not load builds. Go back and try again.')
      else
        Builder(builder: (_) {
          final s = sessions.value!, r = reports.value!;
          final builds = {for (final x in [...s, ...r]) x['build_version'] as String}.toList()..sort();
          if (builds.length < 2) {
            return const Text('Comparison needs data from at least two builds.',
                style: TextStyle(color: muted));
          }
          // Default: the build of the newest session against the build tested before it.
          final byTime = [...s]..sort((x, y) => '${y['started_at']}'.compareTo('${x['started_at']}'));
          final newest = byTime.isEmpty ? builds.last : '${byTime.first['build_version']}';
          final older = builds.where((x) => x.compareTo(newest) < 0).toList();
          final b = builds.contains(_b) ? _b! : newest;
          final a = builds.contains(_a) ? _a! : (older.isNotEmpty ? older.last : builds.firstWhere((x) => x != b));
          Widget pick(String label, String v, ValueChanged<String?> on) => Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: v,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: label,
                    labelStyle: const TextStyle(color: muted),
                    floatingLabelBehavior: FloatingLabelBehavior.always,
                    enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: line)),
                    focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ink)),
                  ),
                  items: [for (final x in builds) DropdownMenuItem(value: x, child: Text(x))],
                  onChanged: on,
                ),
              );
          List<Rec> sOf(String x) => s.where((e) => e['build_version'] == x).toList();
          List<Rec> rOf(String x) => r.where((e) => e['build_version'] == x).toList();
          int testers(String x) => sOf(x).map((e) => e['tester_id']).toSet().length;
          int st(String x, String status) => rOf(x).where((e) => e['status'] == status).length;

          final buildOfSession = {for (final x in s) '${x['id']}': '${x['build_version']}'};
          final counts = <String, List<int>>{};
          for (final e in events.value ?? <Rec>[]) {
            final bld = buildOfSession['${e['session_id']}'];
            if (bld != a && bld != b) continue;
            final c = counts.putIfAbsent('${e['name']}', () => [0, 0]);
            c[bld == a ? 0 : 1]++;
          }
          final names = counts.keys.toList()
            ..sort((x, y) => (counts[y]![0] + counts[y]![1]).compareTo(counts[x]![0] + counts[x]![1]));

          final earlier = rOf(a);
          String retestOf(Rec rep) {
            final l = retests.where((t) => t['report_id'] == rep['id'] && t['build_version'] == b).toList();
            return l.isEmpty ? 'Not tested' : '${l.last['result']}';
          }

          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              pick('Previous build', a, (v) => setState(() => _a = v)),
              const SizedBox(width: 16),
              pick('New build', b, (v) => setState(() => _b = v)),
            ]),
            const SizedBox(height: 16),
            _head(a, b),
            _row('Sessions', sOf(a).length, sOf(b).length),
            _row('Unique testers', testers(a), testers(b)),
            _row('Reports', rOf(a).length, rOf(b).length),
            _row('Open', st(a, 'Open'), st(b, 'Open')),
            _row('In progress', st(a, 'In Progress'), st(b, 'In Progress')),
            _row('Resolved', st(a, 'Resolved'), st(b, 'Resolved')),
            const SectionTitle('Tracked events'),
            Text(
                'Same definitions on both builds. Counts depend on how many sessions each build has (${sOf(a).length} and ${sOf(b).length}).',
                style: const TextStyle(color: muted, fontSize: 13.1)),
            const SizedBox(height: 4),
            for (final n in names.take(8)) _row(n, counts[n]![0], counts[n]![1], mono: true),
            if (names.isEmpty) const Padding(padding: EdgeInsets.all(12), child: Text('No events recorded on these builds.', style: TextStyle(color: muted))),
            SectionTitle('Earlier reports and their retest on $b'),
            if (earlier.isEmpty) const Text('No reports on the previous build.', style: TextStyle(color: muted)),
            for (final rep in earlier)
              InkWell(
                onTap: () => context.push('/report/${rep['id']}'),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
                  child: Row(children: [
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(shortTitle(rep['description']), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
                        Text('${shortId('R', rep['id'])} • build ${rep['build_version']} • ${rep['status']}',
                            style: const TextStyle(color: muted, fontSize: 13.1)),
                      ]),
                    ),
                    Text(retestOf(rep),
                        style: TextStyle(
                            color: retestOf(rep) == 'Reproduced'
                                ? const Color(0xFFB3261E)
                                : retestOf(rep) == 'Not Reproduced'
                                    ? const Color(0xFF2F6B4A)
                                    : muted,
                            fontSize: 15)),
                  ]),
                ),
              ),
            SectionTitle('Reported on $b'),
            if (rOf(b).isEmpty) const Text('No reports on this build.', style: TextStyle(color: muted)),
            for (final rep in rOf(b)) ReportTile(rep),
            const SizedBox(height: 16),
            const InfoCard('How to read this',
                'Observed data only. It does not show that any change caused a difference. Open the linked reports, sessions and retests to judge.'),
          ]);
        }),
    ]);
  }
}

/// Time ruler: labels on top, ticks for every event, a dotted marker on the report.
class _Ruler extends StatelessWidget {
  final List<Rec> events;
  final void Function(Rec) onTap;
  final String? highlight;
  const _Ruler(this.events, {required this.onTap, this.highlight});

  @override
  Widget build(BuildContext context) {
    final times = [for (final e in events) DateTime.parse(e['created_at']).millisecondsSinceEpoch];
    final lo = times.reduce((a, b) => a < b ? a : b), hi = times.reduce((a, b) => a > b ? a : b);
    final span = (hi - lo) == 0 ? 1 : hi - lo;
    final labelCount = events.length < 6 ? events.length : 6;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      double pos(int t) => events.length == 1 ? w / 2 : 12 + (t - lo) / span * (w - 24);
      final issue = [for (var i = 0; i < events.length; i++) if (events[i]['name'] == 'issue_reported') i];
      return SizedBox(
        height: issue.isEmpty ? 100 : 130,
        child: Stack(children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            for (var i = 0; i < labelCount; i++)
              Text(
                  clock(events[labelCount == 1 ? 0 : (i * (events.length - 1) / (labelCount - 1)).round()]['created_at']),
                  style: const TextStyle(color: muted, fontSize: 13.1)),
          ]),
          Positioned.fill(
            top: 30,
            child: Semantics(
              label: 'Timeline of ${events.length} events. Tap an event tick to open it.',
              child: CustomPaint(
              painter: _RulerPainter([for (final t in times) pos(t)], [for (final i in issue) pos(times[i])], w),
            )),
          ),
          for (var i = 0; i < events.length; i++)
            Positioned(
              left: pos(times[i]) - 12,
              top: 30,
              width: 24,
              bottom: 0,
              child: GestureDetector(behavior: HitTestBehavior.translucent, onTap: () => onTap(events[i])),
            ),
        ]),
      );
    });
  }
}

class _RingPainter extends CustomPainter {
  final double fraction;
  _RingPainter(this.fraction);
  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero), r = size.width / 2 - 4;
    canvas.drawCircle(c, r, Paint()..color = line..style = PaintingStyle.stroke..strokeWidth = 1.5);
    final sweep = 2 * 3.141592653589793 * fraction;
    const start = -3.141592653589793 / 2;
    canvas.drawArc(Rect.fromCircle(center: c, radius: r), start, sweep, false,
        Paint()..color = accent..style = PaintingStyle.stroke..strokeWidth = 2.5..strokeCap = StrokeCap.round);
    if (fraction > 0 && fraction < 1) {
      final a = start + sweep;
      canvas.drawCircle(c + Offset(r * math.cos(a), r * math.sin(a)), 6, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(covariant _RingPainter o) => o.fraction != fraction;
}

class _RulerPainter extends CustomPainter {
  final List<double> ticks, marks;
  final double width;
  _RulerPainter(this.ticks, this.marks, this.width);
  @override
  void paint(Canvas canvas, Size size) {
    final base = size.height;
    final grey = Paint()..color = const Color(0xFFCFC4BB)..strokeWidth = 1.5;
    for (var x = 0.0; x <= width; x += 11) {
      canvas.drawLine(Offset(x, base), Offset(x, base - ((x ~/ 11) % 4 == 0 ? 32 : 18)), grey);
    }
    final tall = Paint()..color = const Color(0xFFB8ACA2)..strokeWidth = 2;
    for (final x in ticks) {
      canvas.drawLine(Offset(x, base), Offset(x, base - 44), tall);
    }
    final hot = Paint()..color = accent..strokeWidth = 3;
    for (final x in marks) {
      canvas.drawLine(Offset(x, base), Offset(x, base - 84), hot);
      canvas.drawCircle(Offset(x, base - 84), 6, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter o) => true;
}
