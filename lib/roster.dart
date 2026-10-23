import 'dart:convert';

/// Parses one "roll,name" per line, as pasted from a CSV, notes app or
/// spreadsheet (tab-separated). Header, blank and malformed lines are skipped.
Map<String, String> parseRoster(String text) {
  final roster = <String, String>{};
  for (final line in const LineSplitter().convert(text)) {
    final sep = line.indexOf(RegExp(r'[,\t]'));
    if (sep <= 0) continue;
    final roll = line.substring(0, sep).trim();
    final name = line.substring(sep + 1).trim();
    if (roll.isEmpty || name.isEmpty || roll.toLowerCase() == 'roll') continue;
    roster[roll] = name;
  }
  return roster;
}

String formatRoster(Map<String, String> roster) =>
    roster.entries.map((e) => '${e.key},${e.value}').join('\n');
