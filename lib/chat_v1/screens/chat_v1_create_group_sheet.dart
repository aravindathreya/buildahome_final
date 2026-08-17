import 'package:flutter/material.dart';

import '../chat_v1_controller.dart';
import '../chat_v1_models.dart';
import '../chat_v1_theme.dart';
import '../widgets/chat_v1_common.dart';

class ChatV1CreateGroupSheet extends StatefulWidget {
  final List<ChatV1Member> members;
  const ChatV1CreateGroupSheet({super.key, required this.members});

  @override
  State<ChatV1CreateGroupSheet> createState() => _ChatV1CreateGroupSheetState();
}

class _ChatV1CreateGroupSheetState extends State<ChatV1CreateGroupSheet> {
  final _title = TextEditingController();
  final Set<String> _selected = {};
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a group title');
      return;
    }
    if (_selected.isEmpty) {
      setState(() => _error = 'Pick at least one member');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final ids = _selected
          .map((id) => int.tryParse(id))
          .whereType<int>()
          .toList();
      final item = await ChatV1Controller.instance.createCustomGroup(
        title: title,
        participantUserIds: ids,
      );
      if (!mounted) return;
      Navigator.of(context).pop(item);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: ChatV1Theme.border(context),
                borderRadius: BorderRadius.circular(99),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'New custom group',
            style: TextStyle(
              color: ChatV1Theme.text(context),
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            decoration: const InputDecoration(
              labelText: 'Group title',
              hintText: 'Site Coordination',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Members',
            style: TextStyle(
              color: ChatV1Theme.textSecondary(context),
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 280),
            child: widget.members.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'No project members loaded yet.',
                      style:
                          TextStyle(color: ChatV1Theme.textMuted(context)),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: widget.members.length,
                    itemBuilder: (_, i) {
                      final m = widget.members[i];
                      final checked = _selected.contains(m.id);
                      return CheckboxListTile(
                        value: checked,
                        onChanged: (v) {
                          setState(() {
                            if (v == true) {
                              _selected.add(m.id);
                            } else {
                              _selected.remove(m.id);
                            }
                          });
                        },
                        secondary: Cv1Avatar(
                          initials: m.initials,
                          color: m.color,
                          size: 36,
                        ),
                        title: Text(m.name),
                        subtitle: Text(m.role),
                      );
                    },
                  ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: const TextStyle(color: ChatV1Theme.rejected)),
          ],
          const SizedBox(height: 12),
          FilledButton(
            onPressed: _saving ? null : _create,
            child: _saving
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create group'),
          ),
        ],
      ),
    );
  }
}
