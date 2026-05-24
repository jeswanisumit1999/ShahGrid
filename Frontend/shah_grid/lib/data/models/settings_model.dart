class AppSetting {
  const AppSetting({
    required this.key,
    required this.value,
    this.description,
    this.updatedAt,
  });

  final String key;
  final String value;
  final String? description;
  final String? updatedAt;

  bool get isBool => value == 'true' || value == 'false';
  bool get boolValue => value == 'true';
  int? get intValue => int.tryParse(value);

  factory AppSetting.fromJson(Map<String, dynamic> json) => AppSetting(
        key: json['key'] as String,
        value: json['value'] as String,
        description: json['description'] as String?,
        updatedAt: json['updatedAt'] as String?,
      );

  AppSetting copyWith({String? value}) =>
      AppSetting(key: key, value: value ?? this.value, description: description, updatedAt: updatedAt);
}
