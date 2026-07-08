class UserModel {
  final String id;
  final String name;
  final String mobile;
  final String email;
  final String kycStatus; // 'pending' | 'verified' | 'rejected'
  final double walletBalance;
  final double goldBalanceGrams;
  final double bnplLimit;
  final double bnplUsed;
  final String avatarUrl;

  const UserModel({
    required this.id,
    required this.name,
    required this.mobile,
    required this.email,
    required this.kycStatus,
    this.walletBalance = 0,
    this.goldBalanceGrams = 0,
    this.bnplLimit = 0,
    this.bnplUsed = 0,
    this.avatarUrl = '',
  });

  bool get isKycVerified => kycStatus == 'verified';
  String get initials => name.isNotEmpty ? name[0].toUpperCase() : 'Y';
  String get handle => '@${name.toLowerCase().replaceAll(' ', '_')}';

  /// Maps backend GET /v1/user/profile response.
  /// Backend fields (from users table, camelCased):
  ///   { userId/id, mobile, fullName, email, dateOfBirth,
  ///     isKycVerified: bool, userType, isActive }
  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: (json['userId'] ?? json['id'] ?? '').toString(),
      name: (json['fullName'] ?? json['name'] ?? '').toString(),
      mobile: (json['mobile'] ?? '').toString(),
      email: (json['email'] ?? '').toString(),
      kycStatus: _kycFromBool(json['isKycVerified'], json['kycStatus']),
      // These live in other endpoints (wallet/gold/bnpl); keep 0 here.
      walletBalance: 0,
      goldBalanceGrams: 0,
      bnplLimit: 0,
      bnplUsed: 0,
      avatarUrl: (json['avatarUrl'] ?? '').toString(),
    );
  }

  /// Backend uses is_kyc_verified (bool). Some endpoints send a string status.
  static String _kycFromBool(dynamic isVerified, dynamic statusStr) {
    if (statusStr is String && statusStr.isNotEmpty) {
      return statusStr.toLowerCase();
    }
    if (isVerified == true) return 'verified';
    return 'pending';
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? kycStatus,
    double? walletBalance,
    double? goldBalanceGrams,
    double? bnplLimit,
    double? bnplUsed,
  }) {
    return UserModel(
      id: id,
      name: name ?? this.name,
      mobile: mobile,
      email: email ?? this.email,
      kycStatus: kycStatus ?? this.kycStatus,
      walletBalance: walletBalance ?? this.walletBalance,
      goldBalanceGrams: goldBalanceGrams ?? this.goldBalanceGrams,
      bnplLimit: bnplLimit ?? this.bnplLimit,
      bnplUsed: bnplUsed ?? this.bnplUsed,
      avatarUrl: avatarUrl,
    );
  }
}