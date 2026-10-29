// File-type helpers for project documents (extension detection, labels and
// safe save names) so non-previewable files keep their real extension.

/// Extensions we recognise and keep when caching or saving a document.
const Map<String, String> kDocumentTypeLabels = {
  'pdf': 'PDF document',
  'dwg': 'AutoCAD drawing',
  'dxf': 'AutoCAD DXF drawing',
  'dwf': 'Autodesk DWF drawing',
  'dwfx': 'Autodesk DWFx drawing',
  'skp': 'SketchUp model',
  'rvt': 'Revit model',
  'rfa': 'Revit family',
  'ifc': 'IFC (BIM) model',
  'nwd': 'Navisworks model',
  'max': '3ds Max scene',
  '3dm': 'Rhino model',
  'stl': 'STL 3D model',
  'obj': 'OBJ 3D model',
  'zip': 'ZIP archive',
  'rar': 'RAR archive',
  '7z': '7-Zip archive',
  'tar': 'TAR archive',
  'gz': 'GZip archive',
  'doc': 'Word document',
  'docx': 'Word document',
  'docm': 'Word document',
  'xls': 'Excel spreadsheet',
  'xlsx': 'Excel spreadsheet',
  'xlsm': 'Excel spreadsheet',
  'csv': 'CSV spreadsheet',
  'ppt': 'PowerPoint presentation',
  'pptx': 'PowerPoint presentation',
  'pptm': 'PowerPoint presentation',
  'pps': 'PowerPoint slideshow',
  'ppsx': 'PowerPoint slideshow',
  'odt': 'OpenDocument text',
  'ods': 'OpenDocument spreadsheet',
  'odp': 'OpenDocument presentation',
  'rtf': 'Rich text document',
  'txt': 'Text file',
  'png': 'PNG image',
  'jpg': 'JPEG image',
  'jpeg': 'JPEG image',
  'webp': 'WebP image',
  'gif': 'GIF image',
  'heic': 'HEIC image',
  'bmp': 'Bitmap image',
  'tif': 'TIFF image',
  'tiff': 'TIFF image',
  'svg': 'SVG image',
  'psd': 'Photoshop image',
  'ai': 'Illustrator file',
  'mp4': 'MP4 video',
  'mov': 'QuickTime video',
  'mp3': 'MP3 audio',
};

String _leafExtension(String? value) {
  if (value == null) return '';
  var v = value.trim();
  final q = v.indexOf(RegExp(r'[?#]'));
  if (q >= 0) v = v.substring(0, q);
  try {
    v = Uri.decodeComponent(v);
  } catch (_) {}
  final slash = v.lastIndexOf(RegExp(r'[\\/]'));
  final leaf = slash >= 0 ? v.substring(slash + 1) : v;
  final dot = leaf.lastIndexOf('.');
  if (dot <= 0 || dot == leaf.length - 1) return '';
  return leaf.substring(dot + 1).toLowerCase();
}

/// Known extension (lowercase, no dot) of [value] (a file name or URL), or ''.
String knownExtensionOf(String? value) {
  final ext = _leafExtension(value);
  return kDocumentTypeLabels.containsKey(ext) ? ext : '';
}

/// Real extension of a document from its name first, then its URL. Only
/// recognised extensions count, so "27.04.2026" is not read as ".2026".
String detectDocumentExtension({String? name, String? url}) {
  final fromName = knownExtensionOf(name);
  if (fromName.isNotEmpty) return fromName;
  return knownExtensionOf(url);
}

/// Human label such as "AutoCAD drawing (.dwg)"; "File" when unknown.
String documentTypeLabel(String ext) {
  final e = ext.toLowerCase().replaceFirst('.', '');
  if (e.isEmpty) return 'File';
  final label = kDocumentTypeLabels[e];
  return label == null ? '${e.toUpperCase()} file (.$e)' : '$label (.$e)';
}

/// Adds [ext] to [name] unless it already ends with it.
String ensureFileExtension(String name, String ext) {
  final e = ext.toLowerCase().replaceFirst('.', '');
  if (e.isEmpty) return name;
  if (name.toLowerCase().endsWith('.$e')) return name;
  return '$name.$e';
}