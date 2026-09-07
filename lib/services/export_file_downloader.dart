import 'dart:typed_data';

import 'export_file_downloader_stub.dart'
    if (dart.library.html) 'export_file_downloader_web.dart' as platform;

Future<void> downloadExcelExport(Uint8List bytes, String fileName) =>
    platform.downloadExcelExport(bytes, fileName);
