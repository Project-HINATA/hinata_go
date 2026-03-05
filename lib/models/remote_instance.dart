class RemoteInstance {
  final String id;
  final String name;
  final String icon;
  final String url;

  RemoteInstance({
    required this.id,
    required this.name,
    required this.icon,
    required this.url,
  });

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'icon': icon, 'url': url};
  }

  factory RemoteInstance.fromJson(Map<String, dynamic> json) {
    return RemoteInstance(
      id: json['id'] as String,
      name: json['name'] as String,
      icon: json['icon'] as String,
      url: json['url'] as String,
    );
  }

  RemoteInstance copyWith({
    String? id,
    String? name,
    String? icon,
    String? url,
  }) {
    return RemoteInstance(
      id: id ?? this.id,
      name: name ?? this.name,
      icon: icon ?? this.icon,
      url: url ?? this.url,
    );
  }
}
