import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'profile.dart';
import 'theme.dart';

// ------------------------------------------------------------ providers

/// Latest session per project, for the Projects list subtitle.
final projectSummaryProvider = FutureProvider.autoDispose<Map<String, Rec>>((ref) async {
  final rows = List<Rec>.from(await sb
      .from('sessions')
      .select('project_id, build_version, started_at')
      .order('started_at', ascending: false)
      .limit(500));
  final out = <String, Rec>{};
  for (final r in rows) {
    out.putIfAbsent('${r['project_id']}', () => r);
  }
  return out;
});

/// Reports still waiting for the developer, across all games.
final inboxProvider = FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(await sb
        .from('reports')
        .select('*, projects(name)')
        .neq('status', 'Resolved')
        .order('created_at', ascending: false)
        .limit(100)));

/// Highest level each session reached, read from level / game events (session id -> level).
final levelsProvider = FutureProvider.autoDispose<Map<String, int>>((ref) async {
  final rows = List<Rec>.from(await sb
      .from('events')
      .select('session_id, props')
      .inFilter('name', ['level_started', 'level_up', 'game_started', 'game_over', 'issue_reported'])
      .limit(3000));
  final out = <String, int>{};
  for (final e in rows) {
    final raw = (e['props'] as Map?)?['level'];
    final n = raw is num ? raw.toInt() : int.tryParse('$raw');
    if (n == null) continue;
    final id = '${e['session_id']}';
    if (n > (out[id] ?? 0)) out[id] = n;
  }
  return out;
});

/// Title row used on the root tabs: centred label with the logo at the right.
Widget rootTitle(String label) => Row(children: [
      const SizedBox(width: 40),
      Expanded(child: Center(child: Text(label, style: const TextStyle(fontSize: 17)))),
      const LogoMark(size: 40),
    ]);

final allStatusesProvider =FutureProvider.autoDispose<List<Rec>>((ref) async =>
    List<Rec>.from(await sb.from('reports').select('status').limit(1000)));

// ------------------------------------------------------------ root shell

class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});
  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final inbox = ref.watch(inboxProvider).value?.length ?? 0;
    // Back from Inbox or Profile returns to Projects; only from Projects does it leave the app.
    return PopScope(
      canPop: _index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _index = 0);
      },
      child: Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(index: _index, children: [
          ProjectsTab(onProfile: () => setState(() => _index = 2)),
          const InboxTab(),
          const ProfileTab(),
        ]),
      ),
      floatingActionButton: _index == 0
          ? FloatingActionButton.extended(
              backgroundColor: accent,
              foregroundColor: ink,
              onPressed: () => openNewProject(context),
              icon: const Icon(Icons.add),
              label: const Text('New project',
                  style: TextStyle(fontWeight: FontWeight.w700)),
            )
          : null,
      bottomNavigationBar: PillNav(
        index: _index,
        onTap: (i) => setState(() => _index = i),
        items: [
          const NavItem(Icons.grid_view_outlined, 'Projects'),
          NavItem(Icons.inbox_outlined, 'Inbox', inbox),
          const NavItem(Icons.person_outline, 'Profile'),
        ],
      ),
    ));
  }
}

// ------------------------------------------------------------- projects

class ProjectsTab extends ConsumerStatefulWidget {
  final VoidCallback onProfile;
  const ProjectsTab({super.key, required this.onProfile});
  @override
  ConsumerState<ProjectsTab> createState() => _ProjectsTabState();
}

class _ProjectsTabState extends ConsumerState<ProjectsTab> {
  String _q = '';

  Widget _card(Rec p, Rec? last) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: () => context.push('/game/${p['id']}'),
          child: Panel(
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              Avatar('${p['name']}'.substring(0, 1).toUpperCase(), square: true, size: 58),
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(p['name'],
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 3),
                  Text(
                      last == null
                          ? 'No sessions yet'
                          : 'Build ${last['build_version']} • Last session ${fmt(last['started_at']).split(' ').take(2).join(' ')}',
                      style: const TextStyle(color: muted, fontSize: 13.1)),
                ]),
              ),
              const Icon(Icons.chevron_right, color: muted),
            ]),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final projects = ref.watch(projectsProvider);
    final summary = ref.watch(projectSummaryProvider).value ?? {};
    return RefreshIndicator(
      color: accent,
      onRefresh: () async {
        ref.invalidate(projectSummaryProvider);
        ref.invalidate(projectsProvider);
        await ref.read(projectsProvider.future);
      },
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 12, 24, 100), children: [
        Row(children: [
          const LogoMark(size: 44),
          const SizedBox(width: 12),
          const Text.rich(TextSpan(children: [
            TextSpan(text: 'Playtest ', style: TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: 'Tracker', style: TextStyle(fontWeight: FontWeight.w400)),
          ]), style: TextStyle(fontSize: 19)),
          const Spacer(),
          InkWell(
            customBorder: const CircleBorder(),
            onTap: widget.onProfile,
            child: Container(
              width: 48,
              height: 48,
              decoration: const BoxDecoration(color: Color(0xFFE0DAD4), shape: BoxShape.circle),
              child: const Icon(Icons.person_outline),
            ),
          ),
        ]),
        const SizedBox(height: 28),
        BigTitle('Projects', sub: '${projects.value?.length ?? 0} games'),
        const SizedBox(height: 20),
        TextField(
          onChanged: (v) => setState(() => _q = v.toLowerCase()),
          decoration: InputDecoration(
            hintText: 'Search games',
            prefixIcon: const Icon(Icons.search, color: muted),
            filled: true,
            fillColor: cardColor,
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: line)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(18),
                borderSide: const BorderSide(color: ink)),
          ),
        ),
        AsyncView<List<Rec>>(
          value: projects,
          onRetry: () => ref.invalidate(projectsProvider),
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'No games yet.\nTap "New project" to add your first game.',
          builder: (all) {
            final list =
                all.where((p) => '${p['name']}'.toLowerCase().contains(_q)).toList();
            final connected = list.where((p) => summary.containsKey('${p['id']}'));
            final setup = list.where((p) => !summary.containsKey('${p['id']}'));
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (connected.isNotEmpty) const SectionLabel('Connected'),
              for (final p in connected) _card(p, summary['${p['id']}']),
              if (setup.isNotEmpty) const SectionLabel('Needs setup'),
              for (final p in setup) _card(p, null),
              if (list.isEmpty)
                const Padding(
                    padding: EdgeInsets.all(24),
                    child: Text('No games match your search.',
                        style: TextStyle(color: muted))),
            ]);
          },
        ),
      ]),
    );
  }
}

// ---------------------------------------------------------------- inbox

class InboxTab extends ConsumerWidget {
  const InboxTab({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inbox = ref.watch(inboxProvider);
    return RefreshIndicator(
      color: accent,
      onRefresh: () async => ref.refresh(inboxProvider.future),
      child: ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 40), children: [
        rootTitle('Inbox'),
        const SizedBox(height: 16),
        const BigTitle('Inbox', sub: 'Reports waiting for you, across all your games'),
        AsyncView<List<Rec>>(
          value: inbox,
          onRetry: () => ref.invalidate(inboxProvider),
          isEmpty: (l) => l.isEmpty,
          emptyMessage: 'All caught up.\nNew reports from testers will show up here.',
          builder: (list) {
            final groups = <String, List<Rec>>{};
            for (final r in list) {
              groups.putIfAbsent('${r['project_id']}', () => []).add(r);
            }
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              for (final g in groups.values) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(4, 24, 4, 8),
                  child: Row(children: [
                    Text(
                        '${(g.first['projects']?['name'] ?? 'Game')} • ${g.length}'
                            .toUpperCase(),
                        style: const TextStyle(
                            color: muted,
                            fontSize: 13.1,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700)),
                    const Spacer(),
                    InkWell(
                      onTap: () => context.push('/game/${g.first['project_id']}'),
                      child: const Text('Open game ›',
                          style: TextStyle(color: muted, fontSize: 14)),
                    ),
                  ]),
                ),
                for (final r in g) ReportTile(r),
              ],
            ]);
          },
        ),
      ]),
    );
  }
}

class ReportTile extends ConsumerWidget {
  final Rec r;
  const ReportTile(this.r, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final level = ref.watch(levelsProvider).value?['${r['session_id']}'];
    return InkWell(
        onTap: () => context.push('/report/${r['id']}'),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Avatar(level != null ? 'L$level' : '${r['category']}'.substring(0, 1).toUpperCase(),
                filled: r['status'] == 'Open', size: 54),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(shortTitle(r['description']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight:
                            r['status'] == 'Open' ? FontWeight.w700 : FontWeight.w400)),
                const SizedBox(height: 3),
                StatusLine(r['status'],
                    '${shortId('R', r['id'])} • Build ${r['build_version']}'),
              ]),
            ),
          ]),
        ),
      );
  }
}

// -------------------------------------------------------------- profile

class ProfileTab extends ConsumerStatefulWidget {
  const ProfileTab({super.key});
  @override
  ConsumerState<ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends ConsumerState<ProfileTab> {
  @override
  Widget build(BuildContext context) {
    final email = sb.auth.currentUser?.email ?? '';
    final name = displayName();
    final projects = ref.watch(projectsProvider).value ?? [];
    final statuses = ref.watch(allStatusesProvider).value ?? [];
    int count(String s) => statuses.where((r) => r['status'] == s).length;
    void edit() => openEditProfile(context, () => setState(() {}));
    return ListView(padding: const EdgeInsets.fromLTRB(24, 16, 24, 40), children: [
      rootTitle('Profile'),
      const SizedBox(height: 24),
      Center(
        child: Semantics(
          label: 'Profile picture showing the letter ${name.isEmpty ? '?' : name.substring(0, 1).toUpperCase()}',
          excludeSemantics: true,
          child: Container(
            width: 150,
            height: 150,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent.withValues(alpha: .6)),
            ),
            padding: const EdgeInsets.all(12),
            child: Container(
              decoration: const BoxDecoration(color: Color(0xFFF3CDB9), shape: BoxShape.circle),
              alignment: Alignment.center,
              child: Text(name.isEmpty ? '?' : name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(fontSize: 56, fontWeight: FontWeight.w400)),
            ),
          ),
        ),
      ),
      const SizedBox(height: 16),
      Center(child: Text(name, style: const TextStyle(fontSize: 30))),
      Center(
          child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text('$email  •  Game developer',
                  maxLines: 1, style: const TextStyle(color: muted, fontSize: 14)))),
      const SizedBox(height: 14),
      Center(child: OutlinedButton(onPressed: edit, child: const Text('Edit profile'))),
      const SizedBox(height: 20),
      Panel(
        padding: const EdgeInsets.symmetric(vertical: 14),
        child: Row(children: [
          for (final s in [
            ('${projects.length}', 'Games'),
            ('${count('Open') + count('In Progress')}', 'Open'),
            ('${count('Resolved')}', 'Resolved'),
          ])
            Expanded(
              child: Semantics(
                label: '${s.$1} ${s.$2}',
                excludeSemantics: true,
                child: Column(children: [
                  Text(s.$1, style: const TextStyle(fontSize: 28)),
                  Text(s.$2, style: const TextStyle(color: muted)),
                ]),
              ),
            ),
        ]),
      ),
      const SectionTitle('Account'),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(children: [
          InfoRow('Name', name, onTap: edit),
          InfoRow('Email', email, onTap: edit),
          const InfoRow('Sign-in method', 'Email and password'),
          InfoRow('Password', 'Change', last: true, onTap: () => context.push('/reset-password')),
        ]),
      ),
      const SectionTitle('Your games'),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: projects.isEmpty
            ? const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('No games yet.', style: TextStyle(color: muted)))
            : Column(children: [
                for (var i = 0; i < projects.length; i++)
                  InfoRow('${projects[i]['name']}', '', last: i == projects.length - 1,
                      onTap: () => context.push('/game/${projects[i]['id']}')),
              ]),
      ),
      const SectionTitle('Privacy and data'),
      Panel(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
        child: Column(children: [
          InfoRow('How reports are used', '', onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Privacy and retention'),
                  content: const Text(privacyText),
                  actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Close'))],
                ),
              )),
          InfoRow('Delete account', '', last: true, onTap: () => context.push('/delete-account')),
        ]),
      ),
      const SizedBox(height: 28),
      OutlinedButton(
        style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
        onPressed: () => sb.auth.signOut(),
        child: const Text('Log out', style: TextStyle(fontSize: 16)),
      ),
    ]);
  }
}

/// Shown under Profile > Privacy and in the in-game report form's help text.
const privacyText =
    'Reports and gameplay events are used only so the developer of the game can investigate problems. '
    'Testers are identified by a random ID, not a name or email. Please do not put personal details in a report. '
    'Data is kept while the developer keeps the game in the tracker; a developer can delete or redact any report, '
    'and deleting an account removes all of its data.';
