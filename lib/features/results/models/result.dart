class LabResult {
  final String resultId;
  final String sampleId;
  final String patientId;
  final String parameterName; // जस्तै: Hemoglobin, Glucose
  final String value;
  final String unit;          // जस्तै: g/dL, mg/dL
  final String remarks;

  LabResult({
    required this.resultId,
    required this.sampleId,
    required this.patientId,
    required this.parameterName,
    required this.value,
    required this.unit,
    required this.remarks,
  });

  factory LabResult.fromJson(Map<String, dynamic> json) {
    return LabResult(
      resultId: json['resultId'] ?? '',
      sampleId: json['sampleId'] ?? '',
      patientId: json['patientId'] ?? '',
      parameterName: json['parameterName'] ?? '',
      value: json['value'] ?? '',
      unit: json['unit'] ?? '',
      remarks: json['remarks'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'resultId': resultId,
      'sampleId': sampleId,
      'patientId': patientId,
      'parameterName': parameterName,
      'value': value,
      'unit': unit,
      'remarks': remarks,
    };
  }
}