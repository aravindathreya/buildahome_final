import 'chat_v1_api.dart';
import 'chat_v1_models.dart';

/// Difference of Cost service — backed by `/api/v1/chat` DOC APIs (web sync).
class ChatV1DocStore {
  ChatV1DocStore._();
  static final ChatV1DocStore instance = ChatV1DocStore._();

  final _api = ChatV1Api.instance;

  Future<List<ChatV1DocRequest>> list(
    String salesSopId, {
    String? query,
  }) async {
    final rows = await _api.listDocs(salesSopId, query: query);
    return rows.map(ChatV1DocRequest.fromJson).toList();
  }

  Future<ChatV1DocRequest> getById(String docId) async {
    final raw = await _api.getDoc(docId);
    var doc = ChatV1DocRequest.fromJson(raw);
    if (doc.messages.isEmpty) {
      try {
        final msgs = await _api.listDocMessages(docId);
        if (msgs.isNotEmpty) {
          doc = doc.copyWith(
            messages: msgs.map(ChatV1DocMessage.fromJson).toList(),
            messageCount: msgs.length,
          );
        }
      } catch (_) {}
    }
    return doc;
  }

  Future<ChatV1DocRequest> create({
    required String salesSopId,
    required String description,
    required num amount,
    String notes = '',
    String? pdfName,
    List<int>? pdfBytes,
  }) async {
    String? pdfUrl;
    var resolvedName = pdfName;
    if (pdfBytes != null && pdfName != null && pdfName.isNotEmpty) {
      final upload = await _api.uploadDiscussionAttachment(
        bytes: pdfBytes,
        fileName: pdfName,
      );
      pdfUrl = (upload?['url'] ?? upload?['storage_path'] ?? '').toString();
      if (pdfUrl.isEmpty) {
        throw ChatV1ApiException('PDF upload failed');
      }
      resolvedName =
          (upload?['filename'] ?? upload?['file_name'] ?? pdfName).toString();
    }
    final raw = await _api.createDoc(
      salesSopId,
      description: description,
      amount: amount,
      notes: notes,
      pdfName: resolvedName,
      pdfUrl: pdfUrl,
    );
    return ChatV1DocRequest.fromJson(raw);
  }

  Future<ChatV1DocRequest> approve(String docId) async {
    final raw = await _api.approveDoc(docId);
    return ChatV1DocRequest.fromJson(raw);
  }

  Future<ChatV1DocMessage> sendMessage(
    String docId, {
    required String body,
    List<Map<String, dynamic>>? attachments,
  }) async {
    final raw = await _api.sendDocMessage(
      docId,
      body: body,
      attachments: attachments,
    );
    return ChatV1DocMessage.fromJson(raw);
  }
}
