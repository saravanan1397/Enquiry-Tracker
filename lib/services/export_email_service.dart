import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

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
    try {
      return await _channel.invokeMethod<bool>('composeWithAttachment', {
            'recipient': recipient,
            'subject': subject,
            'body': body,
            'fileName': fileName,
            'bytes': bytes,
          }) ??
          false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// Opens a pre-addressed web email draft. Browsers do not permit websites
  /// to attach a generated local file, so the caller downloads it first.
  static Future<bool> composeWebEmail({
    required String recipient,
    required String subject,
    required String body,
  }) async {
    if (!kIsWeb) return false;
    return launchUrl(
      Uri(
        scheme: 'mailto',
        path: recipient,
        queryParameters: {
          'subject': subject,
          'body': body,
        },
      ),
    );
  }
}
