class Sample {
  final String sampleId;
  final String patientId;
  final String type; // e.g., "Blood", "Urine"
  final DateTime collectedAt;

  Sample({
    required this.sampleId,
    required this.patientId,
    required this.type,
    required this.collectedAt,
  });

  factory Sample.fromJson(Map<String, dynamic> json) => Sample(
        sampleId: json['sampleId'] as String,
        patientId: json['patientId'] as String,
        type: json['type'] as String,
        collectedAt: DateTime.parse(json['collectedAt'] as String),
      );

  Map<String, dynamic> toJson() => {
        'sampleId': sampleId,
        'patientId': patientId,
        'type': type,
        'collectedAt': collectedAt.toIso8601String(),
      };
}
