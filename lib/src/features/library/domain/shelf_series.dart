import 'dart:convert';

/// A user-created series: a named collection of books shown as ONE item on the
/// bookshelf. Membership is stored as an ordered list of [ShelfBook.id]s.
///
/// Stored as JSON in SharedPreferences (not an Isar collection) so that no
/// schema migration / code generation is required.
class ShelfSeries {
  /// Locally unique id (from a persisted counter).
  int id;

  /// Display name shown on the shelf card and the series shelf title.
  String name;

  /// Ordered member book ids (shelf order inside the series).
  List<int> bookIds;

  /// Book whose cover is used as the series cover.
  /// `null` = auto (first member that has a cover image).
  int? coverBookId;

  /// Creation timestamp (milliseconds since epoch).
  int createdAt;

  /// Last modification timestamp (milliseconds since epoch).
  int updatedAt;

  ShelfSeries({
    required this.id,
    required this.name,
    List<int>? bookIds,
    this.coverBookId,
    required this.createdAt,
    required this.updatedAt,
  }) : bookIds = bookIds ?? [];

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'bookIds': bookIds,
    'coverBookId': coverBookId,
    'createdAt': createdAt,
    'updatedAt': updatedAt,
  };

  factory ShelfSeries.fromJson(Map<String, dynamic> json) => ShelfSeries(
    id: (json['id'] as num?)?.toInt() ?? 0,
    name: (json['name'] as String?) ?? '',
    bookIds: ((json['bookIds'] as List?) ?? const [])
        .map((e) => (e as num).toInt())
        .toList(),
    coverBookId: (json['coverBookId'] as num?)?.toInt(),
    createdAt: (json['createdAt'] as num?)?.toInt() ?? 0,
    updatedAt: (json['updatedAt'] as num?)?.toInt() ?? 0,
  );

  String encode() => jsonEncode(toJson());

  static ShelfSeries? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return ShelfSeries.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }
}
