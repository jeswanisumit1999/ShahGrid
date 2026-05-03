class CheckInModel {
  const CheckInModel({
    required this.id,
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.checkedInAt,
    this.notes,
    this.userName,
  });

  final String id;
  final String userId;
  final double latitude;
  final double longitude;
  final String checkedInAt;
  final String? notes;
  final String? userName;

  factory CheckInModel.fromJson(Map<String, dynamic> json) {
    final user = json['user'] as Map<String, dynamic>?;
    return CheckInModel(
      id: json['id'] as String,
      userId: json['userId'] as String,
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      checkedInAt: json['checkedInAt'] as String,
      notes: json['notes'] as String?,
      userName: user?['name'] as String?,
    );
  }
}
