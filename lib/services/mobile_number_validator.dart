class MobileNumberValidator {
  const MobileNumberValidator._();

  static bool isValid(String value) =>
      RegExp(r'^\d{10}$').hasMatch(value.trim());

  static const errorMessage = 'Mobile number must contain exactly 10 digits.';
}
