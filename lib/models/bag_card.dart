class BagCard {
  final String id;
  final String name;
  final String value;
  final String showValue;
  final String folderId;
  final String source;
  final String apiType;
  final String displayType;

  BagCard({
    required this.id,
    required this.name,
    required this.value,
    required this.showValue,
    required this.folderId,
    this.source = 'Direct',
    this.apiType = 'aime',
    this.displayType = 'Manual Entry',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'value': value,
      'showValue': showValue,
      'folderId': folderId,
      'source': source,
      'apiType': apiType,
      'displayType': displayType,
    };
  }

  factory BagCard.fromJson(Map<String, dynamic> json) {
    return BagCard(
      id: json['id'] as String,
      name: json['name'] as String,
      value: json['value'] as String,
      showValue: json['showValue'] as String? ?? json['value'] as String,
      folderId: json['folderId'] as String,
      source: json['source'] as String? ?? 'Direct',
      apiType: json['apiType'] as String? ?? 'aime',
      displayType: json['displayType'] as String? ?? 'Manual Entry',
    );
  }

  BagCard copyWith({
    String? id,
    String? name,
    String? value,
    String? showValue,
    String? folderId,
    String? source,
    String? apiType,
    String? displayType,
  }) {
    return BagCard(
      id: id ?? this.id,
      name: name ?? this.name,
      value: value ?? this.value,
      showValue: showValue ?? this.showValue,
      folderId: folderId ?? this.folderId,
      source: source ?? this.source,
      apiType: apiType ?? this.apiType,
      displayType: displayType ?? this.displayType,
    );
  }
}
