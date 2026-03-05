class SavedCard {
  final String id;
  final String name;
  final String type;
  final String value;

  SavedCard({
    required this.id,
    required this.name,
    required this.type,
    required this.value,
  });

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'type': type, 'value': value};
  }

  factory SavedCard.fromJson(Map<String, dynamic> json) {
    return SavedCard(
      id: json['id'] as String,
      name: json['name'] as String,
      type: json['type'] as String,
      value: json['value'] as String,
    );
  }

  SavedCard copyWith({String? id, String? name, String? type, String? value}) {
    return SavedCard(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
    );
  }
}
