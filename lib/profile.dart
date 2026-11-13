import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'data.dart';
import 'game.dart' show push;
import 'theme.dart';

/// Name shown for the signed-in account: saved name, else the part of the email before "@".
String displayName() {
  final u = sb.auth.currentUser;
  final saved = '${u?.userMetadata?['name'] ?? ''}'.trim();
  if (saved.isNotEmpty) return saved;
  return (u?.email ?? '').split('@').first;
}

InputDecoration _field(String label) => InputDecoration(
      labelText: label,
      labelStyle: const TextStyle(color: muted),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      enabledBorder: const UnderlineInputBorder(borderSide: BorderSide(color: line)),
      focusedBorder: const UnderlineInputBorder(borderSide: BorderSide(color: ink)),
      contentPadding: const EdgeInsets.symmetric(vertical: 14),
    );

Widget _screen(BuildContext context, String title, List<Widget> children) => Scaffold(
      body: SafeArea(
        child: Column(children: [
          TopBar(title, onBack: () => Navigator.pop(context)),
          Expanded(
            child: ListView(padding: const EdgeInsets.fromLTRB(24, 8, 24, 40), children: children),
          ),
        ]),
      ),
    );

// ------------------------------------------------------------ new project

class NewProjectScreen extends ConsumerStatefulWidget {
  const NewProjectScreen({super.key});
  @override
  ConsumerState<NewProjectScreen> createState() => _NewProjectState();
}

class _NewProjectState extends ConsumerState<NewProjectScreen> {
  final _name = TextEditingController();
  final _build = TextEditingController(text: '0.1.0 Beta');
  String? _error;
  bool _busy = false;

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _build.text.trim().isEmpty) {
      setState(() => _error = 'Enter a game name and a build version.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final id = await ref.read(repoProvider).createProject(_name.text, _build.text);
      ref.invalidate(projectsProvider);
      if (mounted) {
        Navigator.pop(context);
        context.push('/game/$id');
      }
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => _screen(context, 'New project', [
        const BigTitle('Name your game', sub: 'You can connect the SDK after this.'),
        const SizedBox(height: 20),
        TextField(controller: _name, style: const TextStyle(fontSize: 18), decoration: _field('Game name')),
        const SizedBox(height: 8),
        TextField(controller: _build, style: const TextStyle(fontSize: 18), decoration: _field('Build version')),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
          ),
        const SizedBox(height: 20),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
          onPressed: _busy ? null : _create,
          child: Text(_busy ? 'Creating...' : 'Create project'),
        ),
      ]);
}

// ------------------------------------------------------------ edit profile

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key});
  @override
  State<EditProfileScreen> createState() => _EditProfileState();
}

class _EditProfileState extends State<EditProfileScreen> {
  final _name = TextEditingController(text: displayName());
  final _email = TextEditingController(text: sb.auth.currentUser?.email ?? '');
  String? _error;
  bool _busy = false;

  Future<void> _save() async {
    final name = _name.text.trim(), email = _email.text.trim();
    if (name.isEmpty) return setState(() => _error = 'Name cannot be empty.');
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      return setState(() => _error = 'Enter a valid email address.');
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final changed = email != sb.auth.currentUser?.email;
      await sb.auth.updateUser(UserAttributes(email: changed ? email : null, data: {'name': name}));
      if (!mounted) return;
      Navigator.pop(context, changed ? 'Profile saved. Confirm the new email from your inbox.' : 'Profile saved');
    } catch (e) {
      if (mounted) setState(() => _error = friendlyError(e));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = _name.text.isEmpty ? '?' : _name.text.trim().substring(0, 1).toUpperCase();
    return _screen(context, 'Edit profile', [
      const BigTitle('Edit profile', sub: 'Your name is shown on your profile.'),
      const SizedBox(height: 20),
      Row(children: [
        Container(
          width: 100,
          height: 100,
          alignment: Alignment.center,
          decoration: const BoxDecoration(color: Color(0xFFF3CDB9), shape: BoxShape.circle),
          child: Text(name, style: const TextStyle(fontSize: 40)),
        ),
        const SizedBox(width: 16),
        OutlinedButton(
          onPressed: () => ScaffoldMessenger.of(context)
              .showSnackBar(const SnackBar(content: Text('Photo upload is not connected in this build.'))),
          child: const Text('Change photo'),
        ),
      ]),
      const SizedBox(height: 16),
      TextField(controller: _name, style: const TextStyle(fontSize: 18), decoration: _field('Name'), onChanged: (_) => setState(() {})),
      const SizedBox(height: 8),
      TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          style: const TextStyle(fontSize: 18),
          decoration: _field('Email')),
      if (_error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(_error!, style: const TextStyle(color: Color(0xFFB3261E))),
        ),
      const SizedBox(height: 20),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(56)),
        onPressed: _busy ? null : _save,
        child: Text(_busy ? 'Saving...' : 'Save changes'),
      ),
    ]);
  }
}

void openEditProfile(BuildContext context, VoidCallback onSaved) async {
  final msg = await Navigator.push<String>(context, MaterialPageRoute(builder: (_) => const EditProfileScreen()));
  if (msg != null && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
    onSaved();
  }
}

void simulated(BuildContext context, String what) => ScaffoldMessenger.of(context)
    .showSnackBar(SnackBar(content: Text('$what is simulated in this build.')));

void openNewProject(BuildContext context) => push(context, const NewProjectScreen());
