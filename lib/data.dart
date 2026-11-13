import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

export 'package:game_playtest_tracker/core/errors.dart';

// Set with: flutter run --dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...
const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
bool get isConfigured => supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

const statuses = ['Open', 'In Progress', 'Resolved'];
const pageSize = 50;

/// Lists load this many rows at a time and offer Load more (history is never fetched in one go).
const listPage = 20;
const severities = ['Critical', 'High', 'Medium', 'Low'];

SupabaseClient get sb => Supabase.instance.client;

typedef Rec = Map<String, dynamic>;

/// Backend access in one place so screens stay free of query code.
class Repo {
  Future<List<Rec>> projects() async => List<Rec>.from(
      await sb.from('projects').select().order('created_at', ascending: false));

  Future<String> createProject(String name, String build) async {
    final row = await sb
        .from('projects')
        .insert({'name': name.trim(), 'description': 'Build ${build.trim()}'})
        .select('id')
        .single();
    return '${row['id']}';
  }

  Future<List<Rec>> reports(String projectId, String? status) async {
    var q = sb.from('reports').select().eq('project_id', projectId);
    if (status != null) q = q.eq('status', status);
    return List<Rec>.from(
        await q.order('created_at', ascending: false).limit(pageSize));
  }

  Future<Rec?> report(String id) =>
      sb.from('reports').select().eq('id', id).maybeSingle();

  Future<void> setStatus(String reportId, String status) =>
      sb.from('reports').update({'status': status}).eq('id', reportId);

  Future<List<Rec>> sessions(String projectId) async => List<Rec>.from(await sb
      .from('sessions')
      .select()
      .eq('project_id', projectId)
      .order('started_at', ascending: false)
      .limit(pageSize));

  Future<Rec?> session(String id) =>
      sb.from('sessions').select().eq('id', id).maybeSingle();

  Future<List<Rec>> events(String sessionId) async => List<Rec>.from(await sb
      .from('events')
      .select()
      .eq('session_id', sessionId)
      .order('created_at', ascending: true)
      .limit(200));

  Future<List<Rec>> sessionReports(String sessionId) async =>
      List<Rec>.from(await sb
          .from('reports')
          .select()
          .eq('session_id', sessionId)
          .order('created_at'));
}

final repoProvider = Provider((_) => Repo());

final projectsProvider =
    FutureProvider.autoDispose((ref) => ref.read(repoProvider).projects());

final reportsProvider = FutureProvider.autoDispose
    .family<List<Rec>, (String, String?)>((ref, a) =>
        ref.read(repoProvider).reports(a.$1, a.$2));

final reportProvider = FutureProvider.autoDispose
    .family<Rec?, String>((ref, id) => ref.read(repoProvider).report(id));

final sessionsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) => ref.read(repoProvider).sessions(id));

final sessionProvider = FutureProvider.autoDispose
    .family<Rec?, String>((ref, id) => ref.read(repoProvider).session(id));

final eventsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>((ref, id) => ref.read(repoProvider).events(id));

final sessionReportsProvider = FutureProvider.autoDispose
    .family<List<Rec>, String>(
        (ref, id) => ref.read(repoProvider).sessionReports(id));

const retestResults = ['Not Tested', 'Reproduced', 'Not Reproduced'];
