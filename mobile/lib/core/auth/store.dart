class Store {
  Store({
    required this.id,
    required this.name,
    required this.code,
    required this.isMain,
    required this.isActive,
  });

  factory Store.fromJson(Map<String, dynamic> json) => Store(
    id: json['id'] as int,
    name: json['name'] as String,
    code: json['code'] as String,
    isMain: json['is_main'] as bool? ?? false,
    isActive: json['is_active'] as bool? ?? true,
  );

  final int id;
  final String name;
  final String code;
  final bool isMain;
  final bool isActive;
}
