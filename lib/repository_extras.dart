import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart' show DateTimeRange;
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';

/// Deep link used by confirmation and password-reset emails (also set under
/// Supabase > Authentication > URL Configuration).
const authRedirect = 'io.playtest.tracker://login-callback/';

PostgrestFilterBuilder<List<Map<String, dynamic>>> _reportFilter(
    String projectId, String? status, String? severity, DateTimeRange? range) {
  var q = sb.from('reports').select().eq('project_id', projectId);
  if (status != null) q = q.eq('status', status);
  if (severity != null) q = q.eq('severity', severity);
  if (range != null) {
    q = q
        .gte('created_at', range.start.toUtc().toIso8601String())
        .lt('created_at', range.end.add(const Duration(days: 1)).toUtc().toIso8601String());
  }
  return q;
}

/// Account, ingest, pagination and export operations. Screens call these instead of querying.
extension RepoExtras on Repo {
  // ------------------------------------------------------------ auth
  Future<void> signIn(String email, String password) =>
      sb.auth.signInWithPassword(email: email, password: password);

  /// Returns true when the new account is already signed in (email confirmation switched off).
  Future<bool> signUp(String email, String password) async =>
      (await sb.auth.signUp(email: email, password: password, emailRedirectTo: authRedirect)).session != null;

  Future<void> sendPasswordReset(String email) =>
      sb.auth.resetPasswordForEmail(email, redirectTo: authRedirect);

  Future<void> setPassword(String password) => sb.auth.updateUser(UserAttributes(password: password));

  Future<void> updateProfile({required String name, String? email}) =>
      sb.auth.updateUser(UserAttributes(email: email, data: {'name': name}));

  /// Removes the caller's projects and data, then the account, then signs out.
  Future<void> deleteAccount() async {
    await sb.rpc('delete_my_account');
    await sb.auth.signOut();
  }

  // ------------------------------------------------------------ lists (paged)
  /// One page of reports. [sort] is "newest", "oldest" or "severity".
  Future<List<Rec>> reportsPage(String projectId,
      {String? status, String? severity, DateTimeRange? range, String sort = 'newest', int offset = 0}) async {
    try {
      final q = _reportFilter(projectId, status, severity, range);
      final ordered = switch (sort) {
        'severity' => q.order('severity_rank', ascending: false).order('created_at', ascending: false),
        'oldest' => q.order('created_at', ascending: true),
        _ => q.order('created_at', ascending: false),
      };
      return List<Rec>.from(await ordered.range(offset, offset + listPage - 1));
    } on PostgrestException {
      // Severity columns arrive with migration 0004; until then fall back to plain newest-first.
      var q = sb.from('reports').select().eq('project_id', projectId);
      if (status != null) q = q.eq('status', status);
      return List<Rec>.from(await q.order('created_at', ascending: false).range(offset, offset + listPage - 1));
    }
  }

  Future<List<Rec>> sessionsPage(String projectId,
      {String? build, DateTimeRange? range, int offset = 0}) async {
    var q = sb.from('sessions').select().eq('project_id', projectId);
    if (build != null) q = q.eq('build_version', build);
    if (range != null) {
      q = q
          .gte('started_at', range.start.toUtc().toIso8601String())
          .lt('started_at', range.end.add(const Duration(days: 1)).toUtc().toIso8601String());
    }
    return List<Rec>.from(await q.order('started_at', ascending: false).range(offset, offset + listPage - 1));
  }

  /// CSV of the reports that match the filters. Export only. At most 5,000 rows, read 500 at a time.
  Future<String> exportReportsCsv(String projectId,
      {String? status, String? severity, DateTimeRange? range}) async {
    const cols = [
      'id', 'created_at', 'status', 'severity', 'category', 'build_version', 'tester_id', 'session_id',
      'device_model', 'android_version', 'description',
    ];
    final out = StringBuffer('${cols.join(',')}\n');
    String cell(Object? v) {
      var t = '${v ?? ''}'.replaceAll('"', '""');
      // Spreadsheet formula injection: a leading = + - @ gets an apostrophe in front.
      if (RegExp(r'^[=+\-@]').hasMatch(t)) t = "'$t";
      return '"$t"';
    }

    for (var offset = 0; offset < 5000; offset += 500) {
      final rows = List<Rec>.from(await _reportFilter(projectId, status, severity, range)
          .order('created_at', ascending: false)
          .range(offset, offset + 499));
      for (final r in rows) {
        out.writeln(cols.map((c) => cell(r[c])).join(','));
      }
      if (rows.length < 500) break;
    }
    return out.toString();
  }

  // ------------------------------------------------------------ report privacy
  Future<void> deleteReport(String id) => sb.from('reports').delete().eq('id', id);

  Future<void> redactReport(String id) =>
      sb.from('reports').update({'description': '[redacted by developer]', 'redacted': true}).eq('id', id);

  // ------------------------------------------------------------ ingest key
  Future<String> regenerateIngestKey(String projectId) async =>
      '${await sb.rpc('regenerate_ingest_key', params: {'p_project': projectId})}';

  /// Sends ONE test event the way a game does (public key only, no login), then reads it back
  /// as the signed-in developer. The returned sentence says exactly what was verified.
  Future<String> verifyIngestPath(String ingestKey) async {
    final now = DateTime.now().toUtc();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    String sessionId;
    try {
      Future<(int, String)> post(String fn, Map<String, dynamic> body) async {
        final req = await client.postUrl(Uri.parse('$supabaseUrl/rest/v1/rpc/$fn'));
        req.headers
          ..set('apikey', supabaseAnonKey)
          ..set('Authorization', 'Bearer $supabaseAnonKey')
          ..contentType = ContentType.json;
        req.write(jsonEncode(body));
        final res = await req.close().timeout(const Duration(seconds: 15));
        return (res.statusCode, await res.transform(utf8.decoder).join());
      }

      final events = [
        {'name': 'connection_test', 'props': {'source': 'dashboard'}, 'at': now.toIso8601String(), 'eid': 'e1'}
      ];
      var (code, body) = await post('sdk_ingest', {
        'p_ingest_key': ingestKey,
        'p_build': 'connection-test',
        'p_tester': 'connection-test',
        'p_client_session_id': 'ct-${now.millisecondsSinceEpoch}',
        'p_events': events,
      });
      if (code == 404) {
        // Backend not upgraded yet: first-generation entry point.
        (code, body) = await post('sdk_submit', {
          'p_sdk_key': ingestKey,
          'p_build': 'connection-test',
          'p_tester': 'connection-test',
          'p_events': events,
        });
      }
      if (code < 200 || code >= 300) throw Exception('ingest $code $body');
      sessionId = jsonDecode(body) as String;
    } finally {
      client.close(force: true);
    }
    final rows = await sb.from('events').select('id').eq('session_id', sessionId).eq('name', 'connection_test');
    if (rows.isEmpty) throw Exception('test event was accepted but not found');
    return 'Sent one test event with the ingest key and read it back from the database.';
  }
}
