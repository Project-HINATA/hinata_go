enum InstanceType { hinataIo, spiceApi, spiceApiWebSocket }

class RemoteInstance {
  final String id;
  final String name;
  final String icon;
  final String url;
  final InstanceType type;
  final int unit;
  final String password;

  RemoteInstance({
    required this.id,
    required this.name,
    required this.icon,
    required this.url,
    this.type = InstanceType.hinataIo,
    this.unit = 0,
    this.password = '',
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'url': url,
      'type': type.name,
      'unit': unit,
      'password': password,
    };
  }

  factory RemoteInstance.fromJson(Map<String, dynamic> json) {
    // Handle legacy types
    InstanceType parseType(String? typeStr) {
      if (typeStr == 'spiceApiUnit0') return InstanceType.spiceApi;
      if (typeStr == 'spiceApiUnit1') return InstanceType.spiceApi;
      if (typeStr != null) {
        return InstanceType.values.firstWhere(
          (e) => e.name == typeStr,
          orElse: () => InstanceType.hinataIo,
        );
      }
      return InstanceType.hinataIo;
    }

    int parseUnit(Map<String, dynamic> json) {
      if (json['unit'] != null) return json['unit'] as int;
      if (json['type'] == 'spiceApiUnit1') return 1;
      return 0;
    }

    return RemoteInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String,
      url: json['url'] as String,
      type: parseType(json['type']),
      unit: parseUnit(json),
      password: json['password'] as String? ?? '',
    );
  }

  RemoteInstance copyWith({
    String? id,
    String? name,
    String? icon,
    String? url,
    InstanceType? type,
    int? unit,
    String? password,
  }) {
    return RemoteInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      url: url ?? this.url,
      type: type ?? this.type,
      unit: unit ?? this.unit,
      password: password ?? this.password,
    );
  }
}
