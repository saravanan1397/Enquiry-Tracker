import 'package:flutter/material.dart';

import 'inventory_widget_frame_stub.dart'
    if (dart.library.js_interop) 'inventory_widget_frame_web.dart';

Uri? inventoryWidgetUrl(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null ||
      uri.scheme != 'https' ||
      !uri.hasAuthority ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.host == 'localhost' ||
      uri.host == 'saravanan1397.github.io' ||
      !uri.host.contains('.') ||
      RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(uri.host)) {
    return null;
  }
  return uri;
}

class InventoryWidgetScreen extends StatelessWidget {
  const InventoryWidgetScreen({super.key, required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Inventory System')),
        body: SafeArea(child: InventoryWidgetFrame(url: url)),
      );
}
