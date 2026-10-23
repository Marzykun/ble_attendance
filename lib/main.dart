import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'protocol.dart';
import 'student_page.dart';
import 'teacher_page.dart';

void main() => runApp(const AttendanceApp());

class AttendanceApp extends StatelessWidget {
  const AttendanceApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'BLE Attendance',
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: const HomePage(),
      );
}

class HomePage extends StatelessWidget {
  const HomePage({super.key});

  Future<void> _openStudent(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    var roll = prefs.getString('roll');
    var name = prefs.getString('name');
    if (roll == null || name == null) {
      if (!context.mounted) return;
      final profile = await showDialog<(String, String)>(
        context: context,
        builder: (_) => const _ProfileDialog(),
      );
      if (profile == null) return;
      (roll, name) = profile;
      // Saved once and never editable: one roll number per phone.
      await prefs.setString('roll', roll);
      await prefs.setString('name', name);
    }
    // Lets the teacher's phone tell this phone apart from others; a reinstall
    // gets a new one, which the teacher must approve.
    var device = prefs.getInt('device');
    if (device == null) {
      device = randomId();
      await prefs.setInt('device', device);
    }
    if (!context.mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => StudentPage(roll: roll!, name: name!, device: device!),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('BLE Attendance')),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FilledButton.icon(
                icon: const Icon(Icons.person),
                label: const Text("I'm a student"),
                onPressed: () => _openStudent(context),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                icon: const Icon(Icons.school),
                label: const Text("I'm the teacher"),
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const TeacherPage()),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ProfileDialog extends StatefulWidget {
  const _ProfileDialog();

  @override
  State<_ProfileDialog> createState() => _ProfileDialogState();
}

class _ProfileDialogState extends State<_ProfileDialog> {
  final _form = GlobalKey<FormState>();
  final _roll = TextEditingController();
  final _name = TextEditingController();

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Register this phone'),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _roll,
                decoration: const InputDecoration(labelText: 'Roll number'),
                maxLength: kMaxRollLength,
                validator: (v) {
                  final t = v?.trim() ?? '';
                  if (t.isEmpty) return 'Required';
                  if (t.contains('|')) return 'No "|" allowed';
                  return null;
                },
              ),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
                validator: (v) =>
                    (v?.trim().isEmpty ?? true) ? 'Required' : null,
              ),
              const Text('This cannot be changed later.'),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (_form.currentState!.validate()) {
                Navigator.pop(context, (_roll.text.trim(), _name.text.trim()));
              }
            },
            child: const Text('Save'),
          ),
        ],
      );
}
