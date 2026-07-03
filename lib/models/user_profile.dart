class UserProfile {
  final String id;
  final String name;
  final String email;
  final String passwordHash;
  final int? age;
  final double? weightKg;
  final double? heightCm;
  final String? gender;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    required this.passwordHash,
    this.age,
    this.weightKg,
    this.heightCm,
    this.gender,
  });

  /// Body Mass Index, if both weight and height are known.
  double? get bmi {
    if (weightKg == null || heightCm == null || heightCm == 0) return null;
    final heightM = heightCm! / 100;
    return weightKg! / (heightM * heightM);
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'passwordHash': passwordHash,
      'age': age,
      'weightKg': weightKg,
      'heightCm': heightCm,
      'gender': gender,
    };
  }

  factory UserProfile.fromMap(Map<String, dynamic> map) {
    return UserProfile(
      id: map['id'],
      name: map['name'],
      email: map['email'],
      passwordHash: map['passwordHash'],
      age: map['age'],
      weightKg: map['weightKg'],
      heightCm: map['heightCm'],
      gender: map['gender'],
    );
  }

  UserProfile copyWith({
    String? name,
    int? age,
    double? weightKg,
    double? heightCm,
    String? gender,
  }) {
    return UserProfile(
      id: id,
      name: name ?? this.name,
      email: email,
      passwordHash: passwordHash,
      age: age ?? this.age,
      weightKg: weightKg ?? this.weightKg,
      heightCm: heightCm ?? this.heightCm,
      gender: gender ?? this.gender,
    );
  }
}
