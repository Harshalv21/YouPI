class Validators {
  Validators._();

  static String? validateMobile(String? value) {
    if (value == null || value.isEmpty) return 'Mobile number is required';
    if (value.length != 10) return 'Enter a valid 10-digit mobile number';
    if (!RegExp(r'^[6-9]\d{9}$').hasMatch(value)) {
      return 'Enter a valid Indian mobile number';
    }
    return null;
  }

  static String? validateOtp(String? value) {
    if (value == null || value.isEmpty) return 'OTP is required';
    if (value.length != 6) return 'Enter the 6-digit OTP';
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return 'OTP must be numeric';
    return null;
  }

  static String? validatePan(String? value) {
    if (value == null || value.isEmpty) return 'PAN number is required';
    final pan = value.toUpperCase();
    if (!RegExp(r'^[A-Z]{5}[0-9]{4}[A-Z]$').hasMatch(pan)) {
      return 'Enter a valid PAN (e.g. ABCDE1234F)';
    }
    return null;
  }

  static String? validateAadhaar(String? value) {
    if (value == null || value.isEmpty) return 'Aadhaar number is required';
    final cleaned = value.replaceAll(' ', '').replaceAll('-', '');
    if (cleaned.length != 12) return 'Enter a valid 12-digit Aadhaar number';
    if (!RegExp(r'^\d{12}$').hasMatch(cleaned)) {
      return 'Aadhaar must contain only digits';
    }
    return null;
  }

  static String? validateName(String? value) {
    if (value == null || value.trim().isEmpty) return 'Name is required';
    if (value.trim().length < 2) return 'Name must be at least 2 characters';
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(value)) {
      return 'Name can only contain letters';
    }
    return null;
  }

  static String? validateEmail(String? value) {
    if (value == null || value.isEmpty) return null; // optional
    if (!RegExp(r'^[\w\.-]+@[\w\.-]+\.\w+$').hasMatch(value)) {
      return 'Enter a valid email address';
    }
    return null;
  }

  static String? validateAmount(String? value, {double min = 1, double max = 500000}) {
    if (value == null || value.isEmpty) return 'Amount is required';
    final amount = double.tryParse(value.replaceAll(',', ''));
    if (amount == null) return 'Enter a valid amount';
    if (amount < min) return 'Minimum amount is ₹${min.toStringAsFixed(0)}';
    if (amount > max) return 'Maximum amount is ₹${max.toStringAsFixed(0)}';
    return null;
  }

  static String? validatePincode(String? value) {
    if (value == null || value.isEmpty) return 'Pincode is required';
    if (!RegExp(r'^\d{6}$').hasMatch(value)) return 'Enter a valid 6-digit pincode';
    return null;
  }

  static String? validateRequired(String? value, {String fieldName = 'This field'}) {
    if (value == null || value.trim().isEmpty) return '$fieldName is required';
    return null;
  }

  static String? validateMpin(String? value) {
    if (value == null || value.isEmpty) return 'MPIN is required';
    if (value.length != 4) return 'MPIN must be 4 digits';
    if (!RegExp(r'^\d{4}$').hasMatch(value)) return 'MPIN must be numeric';
    return null;
  }

  static bool isAbove18(DateTime dob) {
    final now = DateTime.now();
    final age = now.year - dob.year;
    if (age > 18) return true;
    if (age == 18) {
      if (now.month > dob.month) return true;
      if (now.month == dob.month && now.day >= dob.day) return true;
    }
    return false;
  }
}
