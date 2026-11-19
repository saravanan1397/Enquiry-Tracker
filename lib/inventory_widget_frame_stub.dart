import 'package:flutter/widgets.dart';

class InventoryWidgetFrame extends StatelessWidget {
  const InventoryWidgetFrame({super.key, required this.url});

  final Uri url;

  @override
  Widget build(BuildContext context) =>
      const Center(child: Text('Inventory System is available on the web.'));
}
