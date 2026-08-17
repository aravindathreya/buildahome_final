import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../chat_v1_doc_store.dart';
import '../chat_v1_theme.dart';
import '../chat_v1_utils.dart';

class ChatV1CreateDocSheet extends StatefulWidget {
  final String salesSopId;

  const ChatV1CreateDocSheet({super.key, required this.salesSopId});

  @override
  State<ChatV1CreateDocSheet> createState() => _ChatV1CreateDocSheetState();
}

class _ChatV1CreateDocSheetState extends State<ChatV1CreateDocSheet> {
  final _description = TextEditingController();
  final _amount = TextEditingController();
  final _notes = TextEditingController();
  final _store = ChatV1DocStore.instance;

  String? _pdfName;
  List<int>? _pdfBytes;
  int _pdfSize = 0;
  bool _saving = false;
  String? _error;

  static const int _maxPdfBytes = 20 * 1024 * 1024;

  @override
  void dispose() {
    _description.dispose();
    _amount.dispose();
    _notes.dispose();
    super.dispose();
  }

  double? _parseAmount(String raw) {
    final cleaned = raw.replaceAll(',', '').replaceAll('₹', '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  Future<void> _pickPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['pdf'],
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;
    final file = result.files.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Could not read PDF file');
      return;
    }
    if (bytes.length > _maxPdfBytes) {
      setState(() => _error = 'PDF must be 20 MB or smaller');
      return;
    }
    final name = file.name.toLowerCase().endsWith('.pdf')
        ? file.name
        : '${file.name}.pdf';
    setState(() {
      _pdfName = name;
      _pdfBytes = bytes;
      _pdfSize = bytes.length;
      _error = null;
    });
  }

  Future<void> _submit() async {
    final desc = _description.text.trim();
    final amount = _parseAmount(_amount.text);
    if (desc.isEmpty) {
      setState(() => _error = 'Description is required');
      return;
    }
    if (desc.length > 200) {
      setState(() => _error = 'Description max 200 characters');
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => _error = 'Enter an amount greater than 0');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final doc = await _store.create(
        salesSopId: widget.salesSopId,
        description: desc,
        amount: amount,
        notes: _notes.text.trim(),
        pdfName: _pdfName,
        pdfBytes: _pdfBytes,
      );
      if (!mounted) return;
      Navigator.of(context).pop(doc);
    } catch (e) {
      if (!mounted) return;
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
      child: SingleChildScrollView(
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
              'Difference of Cost',
              style: TextStyle(
                color: ChatV1Theme.text(context),
                fontWeight: FontWeight.w800,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Provide the cost difference details for client approval.',
              style: TextStyle(
                color: ChatV1Theme.textMuted(context),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Description *',
              style: TextStyle(
                color: ChatV1Theme.textSecondary(context),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _description,
              maxLength: 200,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Enter cost difference description',
                counterText: '',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Amount (₹) *',
              style: TextStyle(
                color: ChatV1Theme.textSecondary(context),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _amount,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9,.]')),
              ],
              decoration: const InputDecoration(
                hintText: 'Enter amount',
                prefixText: '₹ ',
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Supporting Document (PDF)',
              style: TextStyle(
                color: ChatV1Theme.textSecondary(context),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 6),
            if (_pdfName == null)
              OutlinedButton.icon(
                onPressed: _pickPdf,
                icon: const Icon(Icons.upload_file_rounded),
                label: const Text('Browse PDF'),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: ChatV1Theme.bg(context),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: ChatV1Theme.border(context)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.picture_as_pdf_rounded,
                        color: Color(0xFF0EA5E9)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _pdfName!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ChatV1Theme.text(context),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            ChatV1Utils.formatBytes(_pdfSize),
                            style: TextStyle(
                              color: ChatV1Theme.textMuted(context),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() {
                        _pdfName = null;
                        _pdfBytes = null;
                        _pdfSize = 0;
                      }),
                      child: const Text('Remove'),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            Text(
              'Additional Notes',
              style: TextStyle(
                color: ChatV1Theme.textSecondary(context),
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: _notes,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Extra comments (optional)',
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 10),
              Text(
                _error!,
                style: const TextStyle(
                  color: ChatV1Theme.rejected,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: ChatV1Theme.accent,
                minimumSize: const Size.fromHeight(48),
              ),
              child: _saving
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('Submit DOC'),
            ),
          ],
        ),
      ),
    );
  }
}
