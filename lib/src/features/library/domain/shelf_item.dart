import 'shelf_book.dart';
import 'shelf_series.dart';

/// A single slot on the bookshelf: either one standalone book or a whole
/// series collapsed into one item.
sealed class ShelfItem {
  const ShelfItem();

  /// Stable key used for manual-order persistence (`b<bookId>` / `s<seriesId>`).
  String get orderKey;

  /// Numeric identity (book id or series id).
  int get identity;
}

/// A standalone (non-series) book slot.
final class BookShelfItem extends ShelfItem {
  final ShelfBook book;
  const BookShelfItem(this.book);

  @override
  String get orderKey => 'b${book.id}';

  @override
  int get identity => book.id;
}

/// A merged series slot. [books] holds ALL members (in series order),
/// regardless of which tab it is shown in.
final class SeriesShelfItem extends ShelfItem {
  final ShelfSeries series;
  final List<ShelfBook> books;
  const SeriesShelfItem({required this.series, required this.books});

  @override
  String get orderKey => 's${series.id}';

  @override
  int get identity => series.id;

  /// The book whose cover represents the series. Honors the user-picked
  /// [ShelfSeries.coverBookId]; falls back to the first member that has a
  /// cover image, then to the first member.
  ShelfBook? get coverBook {
    final picked = series.coverBookId;
    if (picked != null) {
      for (final b in books) {
        if (b.id == picked && (b.coverPath?.isNotEmpty ?? false)) return b;
      }
    }
    for (final b in books) {
      if (b.coverPath?.isNotEmpty ?? false) return b;
    }
    return books.isEmpty ? null : books.first;
  }
}

/// Merges a (pre-sorted) book list with the series definitions into shelf
/// items. A series is emitted at the position of its first member; its
/// members are then skipped.
///
/// [books] is the current tab's book list (drives the emission position);
/// [allBooks] is the full live book list, used to resolve ALL members of a
/// series so that the count badge and the series cover stay correct even in
/// filtered (category) tabs.
///
/// When [manualOrders] contains an order for [containerKey], the items are
/// re-ordered to match it (unknown items are appended in their natural
/// order). Containers without their own order inherit the root order, so the
/// whole shelf stays consistent until the user reorders inside a tab.
List<ShelfItem> buildShelfItems({
  required List<ShelfBook> books,
  required List<ShelfBook> allBooks,
  required List<ShelfSeries> series,
  Map<String, List<String>> manualOrders = const {},
  String? containerKey,
}) {
  if (books.isEmpty) return const [];

  final tabIds = <int>{for (final b in books) b.id};
  final byId = <int, ShelfBook>{for (final b in allBooks) b.id: b};

  // bookId -> series (only for series that still have members in [allBooks])
  final seriesOfBook = <int, ShelfSeries>{};
  final membersBySeries = <int, List<ShelfBook>>{};
  for (final s in series) {
    final members = <ShelfBook>[];
    for (final bookId in s.bookIds) {
      final b = byId[bookId];
      if (b != null) {
        members.add(b);
        if (tabIds.contains(bookId)) seriesOfBook[bookId] = s;
      }
    }
    if (members.isNotEmpty) membersBySeries[s.id] = members;
  }

  final items = <ShelfItem>[];
  final emittedSeries = <int>{ };
  for (final b in books) {
    final s = seriesOfBook[b.id];
    if (s == null) {
      items.add(BookShelfItem(b));
    } else if (emittedSeries.add(s.id)) {
      items.add(
        SeriesShelfItem(series: s, books: membersBySeries[s.id] ?? const []),
      );
    }
    // else: member of an already-emitted series -> skipped
  }

  final order = containerKey == null
      ? null
      : (manualOrders[containerKey] ?? manualOrders['root']);
  if (order == null || order.isEmpty || items.length <= 1) return items;

  final orderIndex = <String, int>{for (var i = 0; i < order.length; i++) order[i]: i};
  final sorted = List<ShelfItem>.of(items)
    ..sort((a, b) {
      final ia = orderIndex[a.orderKey];
      final ib = orderIndex[b.orderKey];
      if (ia != null && ib != null) return ia.compareTo(ib);
      if (ia != null) return -1;
      if (ib != null) return 1;
      return 0; // both unknown: keep natural order (stable sort)
    });
  return sorted;
}
