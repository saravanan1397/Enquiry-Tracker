import 'dart:js_interop';

import 'package:flutter/widgets.dart';

extension type _Iframe(JSObject _) {
  external void setAttribute(String name, String value);
}

class InventoryWidgetFrame extends StatelessWidget {
  const InventoryWidgetFrame({super.key, required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) => HtmlElementView.fromTagName(
        tagName: 'iframe',
        onElementCreated: (element) {
          final frame = _Iframe(element as JSObject);
          frame.setAttribute('title', 'Inventory System');
          frame.setAttribute('style', 'width:100%;height:100%;border:0');
          frame.setAttribute('referrerpolicy', 'no-referrer');
          frame.setAttribute('sandbox',
              'allow-scripts allow-same-origin allow-forms allow-downloads');
          frame.setAttribute('src', url.toString());
        },
      );
}
