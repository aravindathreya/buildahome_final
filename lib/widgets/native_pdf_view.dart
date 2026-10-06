export 'native_pdf_view_stub.dart'
    if (dart.library.html) 'native_pdf_view_web.dart'
    if (dart.library.io) 'native_pdf_view_io.dart';
