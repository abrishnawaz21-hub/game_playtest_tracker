import 'dart:developer' as developer;

import 'package:supabase_flutter/supabase_flutter.dart';

/// Turns any exception into a short sentence that is safe to show to a person.
/// The raw error is only written to the developer log, never to the screen.
String friendlyError(Object e) {
  developer.log('$e', name: 'playtest.error');
  final m = switch (e) {
    AuthException() => e.message,
    PostgrestException() => '${e.code} ${e.message}',
    _ => '$e',
  }.toLowerCase();

  if (m.contains('invalid login') || m.contains('invalid_credentials')) {
    return 'That email or password is not right.';
  }
  if (m.contains('already registered') || m.contains('already been registered') || m.contains('user_already_exists')) {
    return 'An account with this email already exists. Try logging in.';
  }
  if (m.contains('email not confirmed') || m.contains('email_not_confirmed')) {
    return 'Please confirm your email first. Check your inbox for the link.';
  }
  if (m.contains('rate') && m.contains('limit') || m.contains('over_email_send_rate_limit') || m.contains('too many')) {
    return 'Too many attempts. Please wait a minute and try again.';
  }
  if (m.contains('password') && (m.contains('characters') || m.contains('weak') || m.contains('short'))) {
    return 'Use a password of at least 6 characters.';
  }
  if (m.contains('socketexception') || m.contains('failed host lookup') || m.contains('clientexception') ||
      m.contains('timeout') || m.contains('network')) {
    return 'No connection. Check your internet and try again.';
  }
  if (m.contains('row-level security') || m.contains('permission denied') || m.contains('42501')) {
    return 'You do not have access to that.';
  }
  if (m.contains('pgrst202') || m.contains('pgrst205') || m.contains('could not find')) {
    return 'This feature is not available yet. The backend needs its latest update.';
  }
  if (m.contains('event names are locked')) return 'Event names cannot be changed once created.';
  if (m.contains('duplicate key') || m.contains('23505')) return 'That already exists.';
  return 'Something went wrong. Please try again.';
}
