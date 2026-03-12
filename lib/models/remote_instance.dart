enum InstanceType {
  hinataIo,
  spiceApiUnit0,
  spiceApiUnit1,
}

class RemoteInstance {
  final String id;
  final String name;
  final String icon;
  final String url;
  final InstanceType type;

  RemoteInstance({
    required this.id,
    required this.name,
    required this.icon,
    required this.url,
    this.type = InstanceType.hinataIo,
  });

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'icon': icon,
      'url': url,
      'type': type.name,
    };
  }

  factory RemoteInstance.fromJson(Map<String, dynamic> json) {
    return RemoteInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String,
      url: json['url'] as String,
      type: json['type'] != null
          ? InstanceType.values.firstWhere(
              (e) => e.name == json['type'],
              orElse: () => InstanceType.hinataIo,
            )
          : InstanceType.hinataIo,
    );
  }

  RemoteInstance copyWith({
    String? id,
    String? name,
    String? icon,
    String? url,
    InstanceType? type,
  }) {
    return RemoteInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      url: url ?? this.url,
      type: type ?? this.type,
    );
  }
}
