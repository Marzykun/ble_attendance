import 'dart:async';

import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import 'ble.dart';
import 'protocol.dart';

const _findTeacherTimeout = Duration(seconds: 20);
const _broadcastTime = Duration(seconds: 60);

class StudentPage extends StatefulWidget {
  const StudentPage({
    super.key,
    required this.roll,
    required this.name,
    required this.device,
  });

  final String roll;
  final String name;
  final int device;

  @override
  State<StudentPage> createState() => _StudentPageState();
}

class _StudentPageState extends State<StudentPage> {
  String _status = 'Tap the button when the teacher starts the session.';
  bool _busy = false;
  bool _confirmed = false;

  void _say(String s) {
    if (mounted) setState(() => _status = s);
  }

  Future<void> _markAttendance() async {
    setState(() {
      _busy = true;
      _confirmed = false;
    });
    try {
      if (!await requestBlePermissions()) {
        return _say('Bluetooth permission denied.');
      }

      _say('Looking for the teacher’s phone…');
      int? session;
      try {
        final found = await scanPayloads()
            .map((p) => parseTeacher(p.data)?.session)
            .firstWhere((s) => s != null)
            .timeout(_findTeacherTimeout);
        session = found;
      } on TimeoutException {
        return _say('Teacher not found. Move closer and try again.');
      } finally {
        await stopScan();
      }

      _say('Teacher found. Verify it’s you…');
      final ok = await LocalAuthentication().authenticate(
        localizedReason: 'Confirm you are ${widget.name}',
        biometricOnly: true,
      );
      if (!ok) return _say('Fingerprint/face check failed.');

      await startAdvertising(
        studentPayload(session!, widget.device, widget.roll, widget.name),
      );
      _say('Sending attendance… keep the app open.');
      try {
        await scanPayloads()
            .map((p) => parseTeacher(p.data))
            .firstWhere((t) => t?.session == session && t?.ack == widget.roll)
            .timeout(_broadcastTime);
        if (mounted) setState(() => _confirmed = true);
        _say('Present marked.');
      } on TimeoutException {
        _say('No confirmation from the teacher. Move closer and try again.');
      } finally {
        await stopScan();
        await stopAdvertising();
      }
    } catch (e) {
      _say('Error: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    stopAdvertising();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Student')),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(widget.name, style: Theme.of(context).textTheme.headlineSmall),
              Text('Roll no: ${widget.roll}'),
              const SizedBox(height: 32),
              FilledButton.icon(
                icon: const Icon(Icons.bluetooth_searching),
                label: const Text('Mark attendance'),
                onPressed: _busy ? null : _markAttendance,
              ),
              const SizedBox(height: 24),
              if (_busy) const LinearProgressIndicator(),
              if (_confirmed)
                const Icon(Icons.check_circle, color: Colors.green, size: 96),
              const SizedBox(height: 8),
              Text(_status, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}
