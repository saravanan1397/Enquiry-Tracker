import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/services/firebase_lead_backend.dart';

LeadloopPromoterProfile _profile(String status) => LeadloopPromoterProfile(
      uid: status,
      name: status,
      mobile: '',
      shopId: '',
      shopName: '',
      active: status == 'approved',
      status: status,
    );

void main() {
  test('only unapproved promoter registrations count as pending', () {
    expect(
      pendingPromoterRequestCount([
        _profile('pending'),
        _profile('pending'),
        _profile('approved'),
        _profile('disabled'),
      ]),
      2,
    );
  });
}
