import 'package:flutter_test/flutter_test.dart';

import '../lib/inventory_widget.dart';

void main() {
  test('allows a configured HTTPS Inventory System host', () {
    expect(inventoryWidgetUrl('https://inventory.example.com/').toString(),
        'https://inventory.example.com/');
  });

  test('fails closed for unset, local and insecure URLs', () {
    for (final value in [
      '',
      'http://inventory.example.com/',
      'https://localhost/',
      'https://127.0.0.1/',
      'https://saravanan1397.github.io/Enquiry-Tracker/',
      'https://person@inventory.example.com/',
      'javascript:alert(1)',
    ]) {
      expect(inventoryWidgetUrl(value), isNull);
    }
  });
}
