/// List/card title. Never use comments or follow-up text as the task name.
String workflowTaskDisplayTitle(
  Map task, {
  String emptyFallback = 'Task',
}) {
  final taskId = task['id']?.toString().trim() ?? '';

  final dedicated = _firstNonEmpty(task, const [
    'task_name',
    'workflow_item_name',
    'workflow_task_name',
    'item_name',
    'subject',
  ]);
  if (dedicated != null) return _sentenceCaseKeepRest(dedicated);

  // s_note is the original scheduler/task name. `note` is often overwritten with
  // comments after a workflow response.
  final scheduled = _trimmedTaskField(task, 's_note');
  if (scheduled != null) return _sentenceCaseKeepRest(scheduled);

  final note = _trimmedTaskField(task, 'note');
  if (note != null) {
    return _sentenceCaseKeepRest(_stripCommentDecoratedTitle(note));
  }

  final looseTitle = _trimmedTaskField(task, 'title');
  if (looseTitle != null) {
    return _sentenceCaseKeepRest(_stripCommentDecoratedTitle(looseTitle));
  }

  return taskId.isEmpty ? emptyFallback : 'Task #$taskId';
}

String? _firstNonEmpty(Map task, List<String> keys) {
  for (final key in keys) {
    final value = task[key]?.toString().trim() ?? '';
    if (value.isNotEmpty && value.toLowerCase() != 'null') return value;
  }
  return null;
}

String? _trimmedTaskField(Map task, String key) {
  final value = task[key]?.toString().trim() ?? '';
  if (value.isEmpty || value.toLowerCase() == 'null') return null;
  return value;
}

String _stripCommentDecoratedTitle(String raw) {
  var value = raw.trim();
  // App used to append the first follow-up item after an em dash.
  final emIndex = value.indexOf(' — ');
  if (emIndex > 0) {
    value = value.substring(0, emIndex).trim();
  }
  // Backend sometimes prefixes older rectification comments: "comment - Task name".
  final dashIndex = value.lastIndexOf(' - ');
  if (emIndex < 0 && dashIndex > 0) {
    final prefix = value.substring(0, dashIndex).trim();
    final suffix = value.substring(dashIndex + 3).trim();
    if (prefix.length > suffix.length &&
        prefix.contains(' ') &&
        suffix.length >= 3 &&
        suffix.length <= 80 &&
        !suffix.contains('\n')) {
      return suffix;
    }
  }
  return value;
}

String _sentenceCaseKeepRest(String value) {
  if (value.isEmpty) return value;
  return value[0].toUpperCase() + value.substring(1);
}
