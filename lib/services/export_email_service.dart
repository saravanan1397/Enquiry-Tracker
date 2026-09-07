import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class ExportEmailService {
  static const _channel = MethodChannel('enquiry_tracker/export_email');

  /// Opens an Android email draft with the XLSX export attached.
  /// Web browsers cannot attach a locally generated file to a mailto link.
  static Future<bool> composeAndroidEmail({
    required String recipient,
    required String subject,
    required String body,
    required String fileName,
    required Uint8List bytes,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return false;
    }
    return await _channel.invokeMethod<bool>('composeWithAttachment', {
          'recipient': recipient,
          'subject': subject,
          'body': body,
          'fileName': fileName,
          'bytes': bytes,
        }) ??
        false;
  }
}
