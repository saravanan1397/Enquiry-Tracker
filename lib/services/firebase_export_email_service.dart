import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_functions/cloud_functions.dart';

class FirebaseExportEmailService {
  FirebaseExportEmailService({FirebaseFunctions? functions})
      : _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'asia-south1');

  final FirebaseFunctions _functions;

  Future<void> sendExport({
    required String recipient,
    required String fileName,
    required Uint8List bytes,
  }) async {
    final callable = _functions.httpsCallable(
      'sendCustomerExport',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 60)),
    );
    await callable.call({
      'recipient': recipient,
      'fileName': fileName,
      'fileBase64': base64Encode(bytes),
    });
  }
}
