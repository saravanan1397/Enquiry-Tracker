import 'package:flutter_test/flutter_test.dart';
import 'package:leadloop/services/mobile_number_validator.dart';

void main() {
  test('accepts a mobile number containing exactly 10 digits', () {
    expect(MobileNumberValidator.isValid('9889998889'), isTrue);
  });

  test('rejects non-numeric and incorrectly sized mobile numbers', () {
    expect(MobileNumberValidator.isValid('98899A8889'), isFalse);
    expect(MobileNumberValidator.isValid('988999888'), isFalse);
    expect(MobileNumberValidator.isValid('98899988899'), isFalse);
  });
}
