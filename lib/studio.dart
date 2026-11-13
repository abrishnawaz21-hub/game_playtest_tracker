import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'data.dart';
import 'repository_extras.dart';
import 'game.dart';
import 'theme.dart';

const sdkEvents = ['session_started', 'session_ended', 'issue_reported'];
const categories = ['Gameplay', 'Progress', 'Interface', 'Other'];

/// Plain-language descriptions for events the SDK and the test game send.
const knownDescriptions = {
  'session_started': 'A play session began.',
  'session_ended': 'A play session ended.',
  'issue_reported': 'The tester submitted an issue report.',
  'game_started': 'The player started a round.',
  'food_eaten': 'The snake ate food and scored a point.',
  'level_up': 'The player reached a new level.',
  'game_over': 'The round ended.',
};

/// Beige explanation card with an "i" badge, used across the guide.
class InfoCard extends StatelessWidget {
  final String title, text;
  final bool warn;
  const InfoCard(this.title, this.text, {super.key, this.warn = false});
  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [Color(0xFFE8DED5), Color(0xFFDDD0C6)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
                child: Text(title,
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700))),
            Semantics(
              label: warn ? 'Warning' : 'Information',
              excludeSemantics: true,
              child: CircleAvatar(
                  radius: 18,
                  backgroundColor: ink,
                  child: Text(warn ? '!' : 'i',
                      style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 20))),
            ),
          ]),
          const SizedBox(height: 14),
          Text(text, style: const TextStyle(height: 1.5, color: Color(0xFF3A2E27))),
        ]),
      );
}

Widget hairlineRow({required Widget child, VoidCallback? onTap}) => InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: line))),
        child: child,
      ),
    );

Widget chip(String text, {bool mono_ = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
      decoration: BoxDecoration(
          color: cardColor,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: line)),
      child: Text(text,
          style: (mono_ ? mono : const TextStyle(color: ink)).copyWith(
              fontSize: 14, color: mono_ ? muted : muted)),
    );

// ------------------------------------------------------------ providers

class EventInfo {
  final String name;
  int recorded = 0;
  final Map<String, dynamic> sample = {};
  Rec? def;
  EventInfo(this.name);
  List<Rec> get props {
    if (def != null) return List<Rec>.from((def!['props'] as List).map((e) => Map<String, dynamic>.from(e)));
    return [
      for (final e in sample.entries)
        {'name': e.key, 'type': e.value is num ? 'number' : 'text', 'required': true}
    ];
  }
}

final definitionsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) async {
  try {
    return List<Rec>.from(
        await sb.from('event_definitions').select().eq('project_id', id).order('name', ascending: true));
  } catch (_) {
    return []; // table not created yet: Event Studio still shows recorded events
  }
});

final eventInfosProvider = FutureProvider.autoDispose
    .family<List<EventInfo>, String>((ref, id) async {
  final rows = List<Rec>.from(await sb
      .from('events')
      .select('name, props')
      .eq('project_id', id)
      .limit(1000));
  final defs = await ref.watch(definitionsProvider(id).future);
  final map = <String, EventInfo>{};
  for (final r in rows) {
    final i = map.putIfAbsent('${r['name']}', () => EventInfo('${r['name']}'));
    i.recorded++;
    (r['props'] as Map).forEach((k, v) => i.sample.putIfAbsent('$k', () => v));
  }
  for (final d in defs) {
    map.putIfAbsent('${d['name']}', () => EventInfo('${d['name']}')).def = d;
  }
  return map.values.toList()..sort((a, b) => a.name.compareTo(b.name));
});

// --------------------------------------------------------- event details

class EventDetailScreen extends StatelessWidget {
  final Rec e;
  const EventDetailScreen(this.e, {super.key});
  @override
  Widget build(BuildContext context) {
    final props = (e['props'] as Map).entries.toList();
    return Consumer(builder: (context, ref, _) {
      final session = ref.watch(sessionProvider('${e['session_id']}')).value;
      return page('Event', [
        Text('${e['name']}', style: mono.copyWith(fontSize: 28)),
        const SizedBox(height: 6),
        Text(knownDescriptions['${e['name']}'] ?? 'Recorded event.', style: const TextStyle(color: muted)),
        const SizedBox(height: 16),
        InfoRow('Time', clock(e['created_at'])),
        InfoRow('Build', '${session?['build_version'] ?? '-'}'),
        InfoRow('Session', shortId('S', e['session_id']),
            onTap: () => context.push('/session/${e['session_id']}')),
        if (session != null)
          InfoRow('Tester', '${session['tester_id']}',
              onTap: () => push(context,
                  TesterScreen(projectId: '${e['project_id']}', testerId: '${session['tester_id']}'))),
        const InfoRow('Recorded by', 'Game call to the SDK', last: true),
        const SectionTitle('Properties'),
        if (props.isEmpty)
          const Text('No properties.', style: TextStyle(color: muted)),
        for (final p in props)
          hairlineRow(
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${p.key}', style: mono),
                  Text(p.value is num ? 'number' : 'text',
                      style: mono.copyWith(color: muted, fontSize: 13.1)),
                ]),
              ),
              Text('${p.value}', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ]),
          ),
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: () => push(context,
                EventDefinitionScreen(projectId: '${e['project_id']}', name: '${e['name']}')),
            child: const Text('View definition'),
          ),
        ),
      ]);
    });
  }
}

// ---------------------------------------------------------- event studio

class EventStudioScreen extends ConsumerWidget {
  final String projectId;
  const EventStudioScreen(this.projectId, {super.key});

  static const examples = [
    ('checkpoint_reached', 'Racing game', ['lap', 'checkpoint']),
    ('answer_incorrect', 'Quiz game', ['question_id']),
    ('boss_defeated', 'Action game', ['boss_id', 'time_taken_seconds', 'attempts']),
  ];

  Widget _tile(BuildContext context, EventInfo i) => InkWell(
        onTap: () => push(context, EventDefinitionScreen(projectId: projectId, name: i.name)),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(children: [
            Container(
              width: 54,
              height: 54,
              alignment: Alignment.center,
              decoration: const BoxDecoration(color: Color(0xFFE0DAD4), shape: BoxShape.circle),
              child: const Text('›', style: TextStyle(fontSize: 22)),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(i.name, style: mono.copyWith(fontSize: 17)),
                Text('${i.props.length} properties • ${i.recorded} recorded',
                    style: const TextStyle(color: muted, fontSize: 14)),
              ]),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final infos = ref.watch(eventInfosProvider(projectId));
    return page('Event Studio', [
      const BigTitle('Event Studio',
          sub: 'Describe the events your game sends and the properties each one carries.'),
      const SizedBox(height: 18),
      const InfoCard('What this does',
          'A definition tells the dashboard what data to expect. It does not make the game send the event. Your game must call the SDK at the right moment, or a supported trigger must be set up.'),
      const SizedBox(height: 18),
      Align(
        alignment: Alignment.centerLeft,
        child: FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(150, 50)),
          onPressed: () => push(context, NewEventScreen(projectId: projectId)),
          child: const Text('New event'),
        ),
      ),
      AsyncView<List<EventInfo>>(
        value: infos,
        onRetry: () => ref.invalidate(eventInfosProvider(projectId)),
        builder: (all) {
          final sdk = all.where((i) => sdkEvents.contains(i.name)).toList();
          final game = all.where((i) => !sdkEvents.contains(i.name)).toList();
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const SectionTitle('Recorded by the SDK'),
            if (sdk.isEmpty) const Text('Nothing recorded yet.', style: TextStyle(color: muted)),
            for (final i in sdk) _tile(context, i),
            const SectionTitle('Sent by your game'),
            if (game.isEmpty) const Text('Nothing recorded yet.', style: TextStyle(color: muted)),
            for (final i in game) _tile(context, i),
          ]);
        },
      ),
      const SectionTitle('Examples from other game types'),
      const Text('Starting points only. They are not part of your game’s data.',
          style: TextStyle(color: muted)),
      const SizedBox(height: 8),
      for (final x in examples)
        hairlineRow(
          child: Row(children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(x.$1, style: mono),
                Text('${x.$2} • ${x.$3.join(', ')}',
                    style: const TextStyle(color: muted, fontSize: 14)),
              ]),
            ),
            OutlinedButton(
              style: OutlinedButton.styleFrom(minimumSize: const Size(64, 44)),
              onPressed: () => push(
                  context,
                  NewEventScreen(
                      projectId: projectId, name: x.$1, props: [for (final p in x.$3) {'name': p, 'type': 'text', 'required': true}])),
              child: const Text('Use'),
            ),
          ]),
        ),
    ]);
  }
}

// ------------------------------------------------------ event definition

class EventDefinitionScreen extends ConsumerWidget {
  final String projectId, name;
  const EventDefinitionScreen({super.key, required this.projectId, required this.name});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final info = ref.watch(eventInfosProvider(projectId)).value?.where((i) => i.name == name).firstOrNull;
    final props = info?.props ?? [];
    final fromSdk = sdkEvents.contains(name);
    final args = props.map((p) => '${p['name']} = "…"').join(', ');
    return page('Event definition', [
      Text(name, style: mono.copyWith(fontSize: 28)),
      const SizedBox(height: 6),
      Text(info?.def?['description'] ?? knownDescriptions[info?.name] ?? 'Recorded from your game.',
          style: const TextStyle(color: muted)),
      const SizedBox(height: 10),
      Wrap(spacing: 8, children: [
        chip(fromSdk ? 'Recorded by the SDK' : 'Sent by your game'),
        chip('${info?.def?['category'] ?? 'Gameplay'}'),
      ]),
      const SectionTitle('Properties'),
      if (props.isEmpty) const Text('No properties.', style: TextStyle(color: muted)),
      for (final p in props)
        hairlineRow(
          child: Row(children: [
            Expanded(child: Text('${p['name']}', style: mono)),
            Text('${p['type']} • ${p['required'] == true ? 'required' : 'optional'}',
                style: const TextStyle(color: muted)),
          ]),
        ),
      const SectionTitle('How it gets recorded'),
      const InfoCard('How it gets recorded',
          'Your game has to call the SDK where this happens. Saving the definition here does not detect anything by itself. The Unity Editor extension is only a proposed helper for some trigger types.'),
      const SizedBox(height: 14),
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration:
            BoxDecoration(color: darkPanel, borderRadius: BorderRadius.circular(18)),
        child: Text('PlaytestSDK.Track("$name"${args.isEmpty ? '' : ',\n  $args'});',
            style: mono.copyWith(color: Colors.white, height: 1.5)),
      ),
      const SizedBox(height: 8),
      const Text('Illustrative call. The final SDK API is not decided.',
          style: TextStyle(color: muted, fontSize: 13.1)),
      const SizedBox(height: 20),
      Text('${info?.recorded ?? 0} recorded.', style: const TextStyle(color: muted)),
      const SizedBox(height: 10),
      Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: () => push(
              context,
              NewEventScreen(
                  projectId: projectId,
                  name: name,
                  description: info?.def?['description'],
                  category: info?.def?['category'],
                  props: props,
                  editing: true)),
          child: const Text('Edit definition'),
        ),
      ),
    ]);
  }
}

// ------------------------------------------------------------ new event

class NewEventScreen extends ConsumerStatefulWidget {
  final String projectId;
  final String? name, description, category;
  final List<Rec>? props;
  final bool editing;
  const NewEventScreen(
      {super.key,
      required this.projectId,
      this.name,
      this.description,
      this.category,
      this.props,
      this.editing = false});
  @override
  ConsumerState<NewEventScreen> createState() => _NewEventScreenState();
}

class _NewEventScreenState extends ConsumerState<NewEventScreen> {
  late final _name = TextEditingController(text: widget.name);
  late final _desc = TextEditingController(text: widget.description);
  final _prop = TextEditingController();
  late String _cat = widget.category ?? categories.first;
  late final List<Rec> _props = [...?widget.props];
  String _type = 'text';
  bool _required = true;
  bool _busy = false;
  String? _error;

  InputDecoration _dec(String hint) => InputDecoration(
        hintText: hint,
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14), borderSide: const BorderSide(color: line)),
      );

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: const TextStyle(color: muted)),
      );

  void _addProp() {
    final n = _prop.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(n)) {
      setState(() => _error = 'Property names use lowercase letters, numbers and underscores.');
      return;
    }
    if (_props.any((p) => p['name'] == n)) return;
    setState(() {
      _props.add({'name': n, 'type': _type, 'required': _required});
      _prop.clear();
      _error = null;
    });
  }

  Future<void> _save() async {
    final n = _name.text.trim();
    if (!RegExp(r'^[a-z][a-z0-9_]{0,63}$').hasMatch(n)) {
      setState(() => _error = 'Event name: lowercase letters, numbers and underscores, starting with a letter.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await sb.from('event_definitions').upsert({
        'project_id': widget.projectId,
        'name': n,
        'description': _desc.text.trim().isEmpty ? null : _desc.text.trim(),
        'category': _cat,
        'props': _props,
      }, onConflict: 'project_id,name');
      ref.invalidate(definitionsProvider(widget.projectId));
      ref.invalidate(eventInfosProvider(widget.projectId));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = friendlyError(e);
        });
      }
    }
  }

  /// Property names that already have recorded data for this event: they cannot be removed or retyped.
  Set<String> get _locked {
    final infos = ref.watch(eventInfosProvider(widget.projectId)).value ?? [];
    final n = widget.name ?? _name.text.trim();
    return {for (final i in infos.where((i) => i.name == n)) ...i.sample.keys};
  }

  @override
  Widget build(BuildContext context) {
    final locked = widget.editing ? _locked : <String>{};
    return page(widget.editing ? 'Edit event' : 'New event', [
        BigTitle(widget.editing ? 'Edit event' : 'New event',
            sub: 'Describe an event your game will send.'),
        const SizedBox(height: 16),
        if (widget.editing) ...[
          const InfoCard('Changing a live event',
              'The name is locked. Properties that already have recorded data cannot be removed or changed to another type. '
              'Mark them deprecated instead: old data stays readable and new games should stop sending them.',
              warn: true),
          const SizedBox(height: 16),
        ],
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Event name', style: TextStyle(color: muted)),
            const SizedBox(height: 8),
            TextField(
                controller: _name,
                enabled: !widget.editing,
                decoration: _dec('e.g. boss_defeated')),
            _label('Description'),
            TextField(controller: _desc, decoration: _dec('When does this happen?')),
            _label('Category'),
            Wrap(spacing: 8, runSpacing: 8, children: [
              for (final c in categories)
                ChoiceChip(
                  label: Text(c),
                  selected: _cat == c,
                  showCheckmark: false,
                  selectedColor: darkPanel,
                  labelStyle: TextStyle(color: _cat == c ? Colors.white : ink),
                  backgroundColor: cardColor,
                  side: const BorderSide(color: line),
                  shape: const StadiumBorder(),
                  onSelected: (_) => setState(() => _cat = c),
                ),
            ]),
          ]),
        ),
        const SectionTitle('Properties'),
        Panel(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (var i = 0; i < _props.length; i++)
              hairlineRow(
                child: Row(children: [
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('${_props[i]['name']}', style: mono),
                      Text(
                          '${_props[i]['type']} • ${_props[i]['required'] == true ? 'required' : 'optional'}'
                          '${_props[i]['deprecated'] == true ? ' • deprecated' : ''}'
                          '${locked.contains(_props[i]['name']) ? ' • has data' : ''}',
                          style: const TextStyle(color: muted, fontSize: 13.1)),
                    ]),
                  ),
                  if (locked.contains(_props[i]['name']))
                    TextButton(
                      onPressed: () => setState(() => _props[i] = {..._props[i], 'deprecated': _props[i]['deprecated'] != true}),
                      child: Text(_props[i]['deprecated'] == true ? 'Restore' : 'Deprecate'),
                    )
                  else
                    IconButton(
                      tooltip: 'Remove property ${_props[i]['name']}',
                      icon: const Icon(Icons.close),
                      onPressed: () => setState(() => _props.removeAt(i)),
                    ),
                ]),
              ),
            _label('Property name'),
            TextField(controller: _prop, decoration: _dec('e.g. boss_id')),
            const SizedBox(height: 12),
            Segmented(
                options: const ['text', 'number'],
                value: _type,
                onChanged: (v) => setState(() => _type = v)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Required'),
              value: _required,
              activeThumbColor: accent,
              onChanged: (v) => setState(() => _required = v),
            ),
            OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                onPressed: _addProp,
                child: const Text('Add property')),
          ]),
        ),
        if (_error != null)
          Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Text(_error!, style: const TextStyle(color: Color(0xFFB3261E)))),
        const SizedBox(height: 20),
        FilledButton(
            onPressed: _busy ? null : _save,
            child: Text(_busy ? 'Saving...' : 'Save event')),
      ]);
  }
}

// ----------------------------------------------------------- sdk setup

enum _Tone { ok, error, waiting }

const _eventCode = '''using System.Collections.Generic;
using Playtest;

// Put these lines inside any method, where the thing happens in your game:

PlaytestSDK.TrackEvent("level_started", new Dictionary<string, object> { { "level", 1 } });

// When a tester reports a problem (category and severity are optional):
PlaytestSDK.SubmitReport("The door does not open", "Bug", "High");''';

class SdkScreen extends ConsumerStatefulWidget {
  final Rec project;
  const SdkScreen(this.project, {super.key});
  @override
  ConsumerState<SdkScreen> createState() => _SdkScreenState();
}

class _SdkScreenState extends ConsumerState<SdkScreen> {
  // test event (checks the ingest key from this phone)
  String? _result;
  bool _ok = false, _busy = false;
  // check for real data from the developer's game
  String? _checkMsg;
  _Tone _checkTone = _Tone.waiting;
  bool _checking = false;

  late String _ingestKey = '${widget.project['sdk_key']}';
  final _buildCtl = TextEditingController(text: '0.1.0');

  @override
  void dispose() {
    _buildCtl.dispose();
    super.dispose();
  }

  String get _build => _buildCtl.text.trim().isEmpty ? '0.1.0' : _buildCtl.text.trim();
  String get _gameName => '${widget.project['name'] ?? 'your game'}';

  String get _initCode => '''using UnityEngine;
using Playtest;

public class PlaytestSetup : MonoBehaviour
{
    const string Url = "$supabaseUrl";
    const string AnonKey = "$supabaseAnonKey";
    const string IngestKey = "$_ingestKey";
    const string Build = "$_build";

    void Start()
    {
        PlaytestSDK.Initialize(Url, AnonKey, IngestKey, Build);
    }
}''';

  String get _fullSetup => '''Playtest Tracker - Unity setup for "$_gameName"

STEP 1 - Add the SDK
Copy the unity/PlaytestSDK folder from the project repository into the Assets folder of your Unity project.

STEP 2 - Your values
Backend URL: $supabaseUrl
Anon (public) key: $supabaseAnonKey
Ingest key: $_ingestKey
Build version: $_build

STEP 3 - Add this script to an object in your first scene
$_initCode

Then record events and reports from your game code:
$_eventCode

STEP 4 - Build and play
Unity: Edit > Project Settings > Player > Android > Other Settings > Internet Access = Require.
Build the APK, install it on a phone with internet, play for a minute.

STEP 5 - Check
Open Playtest Tracker > this game > SDK setup > "Check for data from my game".
''';

  void _copy(String label, String value) {
    Clipboard.setData(ClipboardData(text: value));
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('$label copied')));
  }

  /// Sends one test event with the ingest key (no login) and reads it back.
  Future<void> _test() async {
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      _result = await ref.read(repoProvider).verifyIngestPath(_ingestKey);
      _ok = true;
    } catch (e) {
      _ok = false;
      _result = 'The test event did not get through. ${friendlyError(e)}';
    }
    if (mounted) setState(() => _busy = false);
  }

  /// Looks for sessions that really came from the developer's game (ignores the app's own test event).
  Future<void> _check() async {
    final id = '${widget.project['id']}';
    setState(() {
      _checking = true;
      _checkMsg = null;
    });
    try {
      final all = await ref.read(repoProvider).sessions(id);
      final real = all
          .where((s) =>
              !'${s['tester_id']}'.contains('connection-test') && !'${s['build_version']}'.contains('connection-test'))
          .toList();
      if (real.isEmpty) {
        _checkTone = _Tone.waiting;
        _checkMsg = 'Waiting for your game\'s first session. Run the game on a phone with internet, '
            'play for a minute, then close or pause it and check again.';
      } else {
        final builds = {for (final s in real) '${s['build_version']}'};
        _checkTone = _Tone.ok;
        _checkMsg = 'Connected. ${real.length} session${real.length == 1 ? '' : 's'} received from your game '
            '(build ${builds.join(', ')}). Open the Dashboard to see them.';
        // make the Dashboard and lists show the new data
        ref.invalidate(sessionsProvider(id));
        ref.invalidate(buildSessionsProvider(id));
        ref.invalidate(eventCountProvider(id));
        ref.invalidate(projectEventsProvider(id));
      }
    } catch (e) {
      _checkTone = _Tone.error;
      _checkMsg = friendlyError(e);
    }
    if (mounted) setState(() => _checking = false);
  }

  Future<void> _regenerate() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Regenerate the ingest key?'),
        content: const Text('The current key stops working immediately. Games using it must be rebuilt with the new key.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Regenerate')),
        ],
      ),
    );
    if (yes != true) return;
    try {
      final k = await ref.read(repoProvider).regenerateIngestKey('${widget.project['id']}');
      ref.invalidate(projectProvider('${widget.project['id']}'));
      if (!mounted) return;
      setState(() => _ingestKey = k);
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('New ingest key created. Copy the setup again into your game.')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(friendlyError(e))));
    }
  }

  // ------------------------------------------------------------ small building blocks

  Widget _step(int n, String title, List<Widget> body, {bool last = false}) => IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 36,
            child: Column(children: [
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(color: last ? accent : const Color(0xFFE0DAD4), shape: BoxShape.circle),
                child: Text('$n', style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700)),
              ),
              if (!last) Expanded(child: Container(width: 1, color: line)),
            ]),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const SizedBox(height: 6),
                Semantics(header: true, child: Text(title, style: const TextStyle(fontSize: 18))),
                const SizedBox(height: 6),
                ...body,
              ]),
            ),
          ),
        ]),
      );

  Widget _copyRow(String label, String value) => hairlineRow(
        child: Row(children: [
          Text(label, style: const TextStyle(fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(value,
                textAlign: TextAlign.right,
                style: mono.copyWith(fontSize: 13.1, color: muted),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 10),
          OutlinedButton(
            style: OutlinedButton.styleFrom(
                minimumSize: const Size(64, 48),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                textStyle: const TextStyle(fontSize: 13.1)),
            onPressed: () => _copy(label, value),
            child: const Text('Copy'),
          ),
        ]),
      );

  Widget _codeBlock(String code) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: darkPanel, borderRadius: BorderRadius.circular(14)),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(code,
              style: mono.copyWith(fontSize: 12.5, color: const Color(0xFFF5F0EC), height: 1.5)),
        ),
      );

  Widget _copyButton(String label, String value, String toast) => OutlinedButton.icon(
        style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
        onPressed: () => _copy(toast, value),
        icon: const Icon(Icons.copy, size: 18),
        label: Text(label),
      );

  Widget _notice(String text, _Tone tone) {
    final color = switch (tone) {
      _Tone.ok => const Color(0xFF2F6B4A),
      _Tone.error => errorColor,
      _Tone.waiting => const Color(0xFF8A6410),
    };
    final icon = switch (tone) {
      _Tone.ok => Icons.check_circle_outline,
      _Tone.error => Icons.error_outline,
      _Tone.waiting => Icons.hourglass_empty,
    };
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Semantics(
        liveRegion: true,
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(color: color, fontWeight: FontWeight.w600))),
        ]),
      ),
    );
  }

  static const _body = TextStyle(color: muted, height: 1.5);

  // ------------------------------------------------------------ the page

  @override
  Widget build(BuildContext context) {
    final id = '${widget.project['id']}';
    final infos = ref.watch(eventInfosProvider(id)).value ?? [];
    final sdk = infos.where((i) => sdkEvents.contains(i.name)).map((i) => i.name).toList();
    final game = infos.where((i) => !sdkEvents.contains(i.name)).map((i) => i.name).toList();

    return page('SDK setup', [
      const BigTitle('Connect your game',
          sub: 'For Unity games built for Android. Five steps, about 10 minutes.'),
      const SizedBox(height: 16),
      const InfoCard('Where you do what',
          'Steps 1 to 4 happen on your computer, in Unity. This phone app is where you copy your values from. '
          'Tap "Copy full setup" and send it to yourself (email, WhatsApp or Notes), then open it on your computer.'),
      const SizedBox(height: 12),
      FilledButton.icon(
        onPressed: () => _copy('Full setup', _fullSetup),
        icon: const Icon(Icons.copy_all, size: 20),
        label: const Text('Copy full setup'),
      ),
      const SizedBox(height: 28),

      _step(1, 'Add the SDK file', const [
        Text(
            'On your computer, open the project repository and find the folder unity/PlaytestSDK (it contains '
            'Runtime/PlaytestSDK.cs). Drag the whole folder into the Assets panel of your Unity project and wait '
            'for Unity to finish compiling. If red errors appear in the Console, the import did not work.',
            style: _body),
      ]),

      _step(2, 'Your project values', [
        _copyRow('Backend URL', supabaseUrl),
        _copyRow('Anon key', supabaseAnonKey),
        _copyRow('Ingest key', _ingestKey),
        const SizedBox(height: 12),
        TextField(
          controller: _buildCtl,
          onChanged: (_) => setState(() {}),
          autocorrect: false,
          enableSuggestions: false,
          decoration: const InputDecoration(
              labelText: 'Build version', helperText: 'Use a new number for every build you give to testers.'),
        ),
        const SizedBox(height: 14),
        const Text.rich(TextSpan(children: [
          TextSpan(text: 'The anon key ', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          TextSpan(text: 'is the public key of the backend. It is meant to be inside a game. Never use a service key. '),
          TextSpan(text: 'The ingest key ', style: TextStyle(fontWeight: FontWeight.w700, color: ink)),
          TextSpan(
              text: 'can only send data from your game. It cannot read anything, and the backend limits how fast it '
                  'can send. It is visible inside the game, so if it is ever abused, regenerate it.'),
        ]), style: _body),
        const SizedBox(height: 12),
        OutlinedButton(
            style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
            onPressed: _regenerate,
            child: const Text('Regenerate ingest key')),
      ]),

      _step(3, 'Add the code to your game', [
        const Text(
            'Create a new C# script in Unity called PlaytestSetup, replace everything in it with this code, and add '
            'it to an object in your first scene. Your values are already filled in.',
            style: _body),
        const SizedBox(height: 12),
        _codeBlock(_initCode),
        const SizedBox(height: 10),
        _copyButton('Copy script', _initCode, 'Script'),
        const SizedBox(height: 20),
        const Text(
            'Sessions start and end by themselves. To record what players do, and to let testers report problems, '
            'call these from your own game code:',
            style: _body),
        const SizedBox(height: 12),
        _codeBlock(_eventCode),
        const SizedBox(height: 10),
        _copyButton('Copy example', _eventCode, 'Example'),
        const SizedBox(height: 20),
        const Text('Recorded by the SDK by itself', style: _body),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: [
          for (final n in (sdk.isEmpty ? sdkEvents : sdk)) chip(n, mono_: true),
        ]),
        if (game.isNotEmpty) ...[
          const SizedBox(height: 14),
          const Text('Your own events (each needs a TrackEvent call)', style: _body),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [for (final n in game) chip(n, mono_: true)]),
        ],
        const SizedBox(height: 12),
        const Text('Naming an event in Event Studio does not hook it into your game. Only the TrackEvent call does.',
            style: _body),
        const SizedBox(height: 12),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 48)),
          onPressed: () => push(context, EventStudioScreen(id)),
          child: const Text('Open Event Studio'),
        ),
      ]),

      _step(4, 'Build and play', const [
        Text(
            'In Unity: Edit > Project Settings > Player > Android tab > Other Settings > set Internet Access to '
            'Require. Then File > Build Settings > Android > Build. Install the APK on a phone with internet and play '
            'for a minute. Data is sent in the background, and again when the game is paused or closed.',
            style: _body),
      ]),

      _step(5, 'Check the connection', [
        const Text(
            'First send a test event from this phone to check that your ingest key works. Then, after you have played '
            'your game, check that its sessions arrived.',
            style: _body),
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _test, child: Text(_busy ? 'Testing...' : 'Send test event')),
        if (_result != null) _notice(_result!, _ok ? _Tone.ok : _Tone.error),
        const SizedBox(height: 16),
        OutlinedButton(
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(54)),
          onPressed: _checking ? null : _check,
          child: Text(_checking ? 'Checking...' : 'Check for data from my game'),
        ),
        if (_checkMsg != null) _notice(_checkMsg!, _checkTone),
      ], last: true),
    ]);
  }
}