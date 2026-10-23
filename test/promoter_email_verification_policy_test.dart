import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/services/leadloop_auth_service.dart';

void main() {
  test('new promoter accounts can sign in before email verification', () {
    expect(
      requiresPromoterEmailVerification(
        authEmail: 'new.promoter@example.com',
        emailVerified: false,
        verificationOptional: true,
      ),
      isFalse,
    );
  });

  test('existing promoter accounts retain the email verification gate', () {
    expect(
      requiresPromoterEmailVerification(
        authEmail: 'existing.promoter@example.com',
        emailVerified: false,
        verificationOptional: false,
      ),
      isTrue,
    );
  });

  test('verified and mobile-backed legacy accounts are not blocked', () {
    expect(
      requiresPromoterEmailVerification(
        authEmail: 'verified.promoter@example.com',
        emailVerified: true,
        verificationOptional: false,
      ),
      isFalse,
    );
    expect(
      requiresPromoterEmailVerification(
        authEmail: '9876543210@auth.leadloop.app',
        emailVerified: false,
        verificationOptional: false,
      ),
      isFalse,
    );
  });
}
