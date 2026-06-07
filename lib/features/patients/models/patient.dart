class Patient {
  final String patientId;
  final String name;
  final int age;
  final String phone;

  Patient({
    required this.patientId,
    required this.name,
    required this.age,
    required this.phone,
  });

  // Convert JSON from DB/API to a Patient object
  factory Patient.fromJson(Map<String, dynamic> json) {
    return Patient(
      patientId: json['patientId'] as String,
      name: json['name'] as String,
      age: json['age'] as int,
      phone: json['phone'] as String,
    );
  }

  // Convert a Patient object to JSON/Map for DB storage
  Map<String, dynamic> toJson() {
    return {
      'patientId': patientId,
      'name': name,
      'age': age,
      'phone': phone,
    };
  }
}
