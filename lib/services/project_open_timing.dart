import 'package:flutter/foundation.dart';

/// Collects timings for "open project" and prints them to the Flutter console.
class ProjectOpenTiming {
  ProjectOpenTiming(this.projectName) : _startedAt = DateTime.now();

  final String projectName;
  final DateTime _startedAt;
  final Map<String, int> _ms = {};

  void recordMs(String name, int ms) {
    _ms[name] = ms;
    debugPrint('[ProjectOpen] ■ $name: ${ms}ms');
  }

  Future<T> measure<T>(String name, Future<T> Function() run) async {
    debugPrint('[ProjectOpen] ▶ $name');
    final watch = Stopwatch()..start();
    try {
      return await run();
    } finally {
      watch.stop();
      recordMs(name, watch.elapsedMilliseconds);
    }
  }

  int get totalMs => DateTime.now().difference(_startedAt).inMilliseconds;

  String get summaryText {
    final buf = StringBuffer()
      ..writeln('Project open: $projectName')
      ..writeln('Total: ${totalMs}ms');
    final entries = _ms.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final e in entries) {
      buf.writeln('• ${e.key}: ${e.value}ms');
    }
    return buf.toString().trimRight();
  }

  void logReport() {
    debugPrint('========== PROJECT OPEN TIMING ==========');
    debugPrint(summaryText);
    debugPrint('=========================================');
  }
}
