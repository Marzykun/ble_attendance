import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'ble.dart';
import 'protocol.dart';
import 'roster.dart';

// Each still-broadcasting student gets the ack slot for this long, in turn.
const _ackRotate = Duration(seconds: 1);
// A student not heard for this long has got their ack and stopped.
const _ackWindow = Duration(seconds: 5);

class _Attendee {
  _Attendee(this.name, this.time, {this.rssi, this.lastSeen});
  final String name;
  final DateTime time;
  int? rssi; // null when marked by hand
  DateTime? lastSeen;
  bool get manual => lastSeen == null && rssi == null;
}

/// A broadcast that wasn't accepted, kept so the teacher can allow it.
class _Flag {
  _Flag(this.name, this.device, this.reason);
  final String name;
  final int device;
  final String reason;
}

class TeacherPage extends StatefulWidget {
  const TeacherPage({super.key});

  @override
  State<TeacherPage> createState() => _TeacherPageState();
}

class _TeacherPageState extends State<TeacherPage> {
  int? _session;
  bool _started = false;
  StreamSubscription? _scan;
  Timer? _ackTimer;
  String _ack = '';
  int _ackTurn = 0;
  final _present = <String, _Attendee>{}; // key: roll number
  final _flagged = <String, _Flag>{};
  // Saved across sessions. An empty roster accepts any roll number.
  var _roster = <String, String>{};
  var _devices = <String, int>{}; // roll -> the phone first used for it
  // Weaker signals than this are treated as outside the room.
  // Measure in your classroom and adjust.
  double _minRssi = -75;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final roster = prefs.getString('roster');
    final devices = prefs.getString('devices');
    if (!mounted) return;
    setState(() {
      if (roster != null) _roster = Map<String, String>.from(jsonDecode(roster));
      if (devices != null) _devices = Map<String, int>.from(jsonDecode(devices));
    });
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('roster', jsonEncode(_roster));
    await prefs.setString('devices', jsonEncode(_devices));
  }

  Future<void> _start() async {
    if (!await requestBlePermissions()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bluetooth permission denied.')),
        );
      }
      return;
    }
    final session = randomId();
    await startAdvertising(teacherPayload(session));
    _scan = scanPayloads().listen((p) => _onBroadcast(session, p.data, p.rssi));
    _ack = '';
    _ackTimer = Timer.periodic(_ackRotate, (_) => _rotateAck(session));
    setState(() {
      _session = session;
      _started = true;
      _present.clear();
      _flagged.clear();
    });
  }

  void _onBroadcast(int session, List<int> data, int rssi) {
    final s = parseStudent(data);
    // An old or foreign session code means a replayed or stale broadcast.
    if (s == null || s.session != session) return;
    final name = _roster[s.roll] ?? s.name;
    if (_roster.isNotEmpty && !_roster.containsKey(s.roll)) {
      return _flag(s.roll, _Flag(name, s.device, 'Not in class list'));
    }
    final bound = _devices[s.roll];
    if (bound != null && bound != s.device) {
      return _flag(s.roll, _Flag(name, s.device, 'Registered on a different phone'));
    }
    final known = _present[s.roll];
    if (known != null) {
      setState(() {
        known.rssi = rssi;
        known.lastSeen = DateTime.now();
      });
    } else if (rssi >= _minRssi) {
      if (bound == null) {
        _devices[s.roll] = s.device;
        _save();
      }
      final now = DateTime.now();
      setState(() => _present[s.roll] = _Attendee(name, now, rssi: rssi, lastSeen: now));
    }
  }

  void _flag(String roll, _Flag flag) {
    if (!_flagged.containsKey(roll)) setState(() => _flagged[roll] = flag);
  }

  /// Accepts a flagged phone for this roll number from now on (a new phone,
  /// or a student missing from the class list). Their next broadcast counts.
  void _allow(String roll) {
    setState(() {
      final f = _flagged.remove(roll)!;
      _devices[roll] = f.device;
      if (_roster.isNotEmpty) _roster.putIfAbsent(roll, () => f.name);
    });
    _save();
  }

  void _toggleManual(String roll) {
    setState(() {
      if (_present.remove(roll) == null) {
        _present[roll] = _Attendee(_roster[roll] ?? roll, DateTime.now());
      }
    });
  }

  Future<void> _rotateAck(int session) async {
    final now = DateTime.now();
    final waiting = _present.entries
        .where((e) {
          final seen = e.value.lastSeen;
          return seen != null && now.difference(seen) < _ackWindow;
        })
        .map((e) => e.key)
        .toList()
      ..sort();
    final ack = waiting.isEmpty ? '' : waiting[_ackTurn++ % waiting.length];
    if (ack == _ack) return;
    _ack = ack;
    await stopAdvertising();
    if (_session != session) return; // stopped meanwhile
    await startAdvertising(teacherPayload(session, ack));
  }

  Future<void> _stop() async {
    _ackTimer?.cancel();
    _ackTimer = null;
    await _scan?.cancel();
    _scan = null;
    await stopScan();
    await stopAdvertising();
    if (mounted) setState(() => _session = null);
  }

  Future<void> _editRoster() async {
    final text = TextEditingController(text: formatRoster(_roster));
    final saved = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Class list'),
        content: TextField(
          controller: text,
          maxLines: 12,
          decoration: const InputDecoration(
            hintText: 'One student per line:\n22CS101,Aditya\n22CS102,Priya',
            helperText: 'Paste from a spreadsheet or CSV. Empty = accept anyone.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, text.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return;
    setState(() => _roster = parseRoster(saved));
    _save();
  }

  List<String> get _absent =>
      _roster.keys.where((r) => !_present.containsKey(r)).toList()..sort();

  String _csvField(String s) => '"${s.replaceAll('"', '""')}"';

  void _export() {
    final present = _present.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final rows = [
      'roll,name,status,time,method,rssi',
      for (final e in present)
        '${e.key},${_csvField(e.value.name)},present,'
            '${e.value.time.toIso8601String()},'
            '${e.value.manual ? 'manual' : 'bluetooth'},${e.value.rssi ?? ''}',
      for (final roll in _absent) '$roll,${_csvField(_roster[roll]!)},absent,,,',
    ];
    SharePlus.instance.share(ShareParams(
      text: rows.join('\n'),
      subject: 'Attendance ${DateTime.now().toIso8601String().substring(0, 10)}',
    ));
  }

  @override
  void dispose() {
    _stop();
    super.dispose();
  }

  Widget _header(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(text, style: Theme.of(context).textTheme.titleSmall),
      );

  @override
  Widget build(BuildContext context) {
    final running = _session != null;
    final present = _present.entries.toList()..sort((a, b) => a.key.compareTo(b.key));
    final absent = _absent;
    final total = _roster.isEmpty ? '' : '/${_roster.length}';
    // Tap-to-mark works during and after a session, not before one.
    final canMark = _started;
    return Scaffold(
      appBar: AppBar(
        title: Text('Teacher · ${_present.length}$total present'),
        actions: [
          IconButton(
            tooltip: 'Class list',
            icon: const Icon(Icons.groups),
            onPressed: _editRoster,
          ),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.share),
            onPressed: _present.isEmpty && absent.isEmpty ? null : _export,
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                FilledButton.icon(
                  icon: Icon(running ? Icons.stop : Icons.play_arrow),
                  label: Text(running ? 'Stop session' : 'Start session'),
                  onPressed: running ? _stop : _start,
                ),
                if (running)
                  Text('Session ${_session!.toRadixString(16).toUpperCase()}'),
                Row(
                  children: [
                    Text('Min signal ${_minRssi.round()} dBm'),
                    Expanded(
                      child: Slider(
                        min: -100,
                        max: -40,
                        value: _minRssi,
                        onChanged: (v) => setState(() => _minRssi = v),
                      ),
                    ),
                  ],
                ),
                if (canMark)
                  const Text('Tap a student to mark or unmark by hand.'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              children: [
                if (_flagged.isNotEmpty) _header('Needs your check'),
                for (final e in _flagged.entries)
                  ListTile(
                    leading: const Icon(Icons.warning_amber, color: Colors.orange),
                    title: Text(e.value.name),
                    subtitle: Text('${e.key} · ${e.value.reason}'),
                    trailing: TextButton(
                      onPressed: () => _allow(e.key),
                      child: const Text('Allow'),
                    ),
                  ),
                if (present.isNotEmpty) _header('Present (${present.length})'),
                for (final e in present)
                  ListTile(
                    leading: Icon(
                      e.value.manual ? Icons.edit : Icons.check_circle,
                      color: Colors.green,
                    ),
                    title: Text(e.value.name),
                    subtitle: Text('${e.key} · '
                        '${TimeOfDay.fromDateTime(e.value.time).format(context)}'
                        '${e.value.manual ? ' · by hand' : ''}'),
                    trailing: e.value.rssi == null ? null : Text('${e.value.rssi} dBm'),
                    onTap: canMark ? () => _toggleManual(e.key) : null,
                  ),
                if (absent.isNotEmpty) _header('Absent (${absent.length})'),
                for (final roll in absent)
                  ListTile(
                    leading: const Icon(Icons.radio_button_unchecked),
                    title: Text(_roster[roll]!),
                    subtitle: Text(roll),
                    onTap: canMark ? () => _toggleManual(roll) : null,
                  ),
                if (_flagged.isEmpty && present.isEmpty && absent.isEmpty)
                  const Padding(
                    padding: EdgeInsets.all(32),
                    child: Center(child: Text('No students yet.')),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
