import 'dart:convert';

import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/providers/shared_preferences_provider.dart';
import '../domain/shelf_book.dart';
import '../domain/shelf_group.dart';
import '../domain/shelf_item.dart';
import '../domain/shelf_series.dart';
import '../data/shelf_book_repository.dart';
import '../data/repositories/shelf_book_repository_provider.dart';
import '../data/services/epub_import_service_provider.dart';
import '../data/services/epub_import_service.dart';

part 'bookshelf_notifier.g.dart';

/// How densely books are shown in the grid.
enum ViewMode { compact, relaxed }

/// State for bookshelf view (sorting, grouping, selection)
class BookshelfState {
  final List<ShelfBook> books;
  final ShelfBookSortBy sortBy;
  final ViewMode viewMode;
  final int? currentGroupId; // Navigation: which folder we're inside
  final int?
  filterGroupId; // Filter: show books from specific group (null = all)
  final Set<int> selectedBookIds;
  final Set<int> selectedGroupIds;
  final bool isSelectionMode;
  final List<ShelfGroup> availableGroups;
  final Map<int?, List<ShelfBook>> cachedBooks;

  // ─── Series support ─────────────────────────────────────────────────────

  /// All series definitions (persisted in SharedPreferences).
  final List<ShelfSeries> series;

  /// Merged shelf slots for the currently active tab
  /// (books + collapsed series items).
  final List<ShelfItem> items;

  /// Merged shelf slots per tab (LRU cache, same keys as [cachedBooks]).
  final Map<int?, List<ShelfItem>> cachedItems;

  /// Series ids selected in selection mode.
  final Set<int> selectedSeriesIds;

  /// Manual (drag) order per shelf container
  /// (`root`, `uncat`, `group_<id>`); values are item order keys
  /// (`b<bookId>` / `s<seriesId>`).
  final Map<String, List<String>> manualOrders;

  // Note: cacheOrder (LRU eviction order) is managed internally by
  // BookshelfNotifier._cacheOrder and is *not* part of the UI state.

  BookshelfState.bookshelfState({
    required this.books,
    this.sortBy = ShelfBookSortBy.recentlyAdded,
    this.viewMode = ViewMode.relaxed,
    this.currentGroupId,
    this.filterGroupId,
    this.selectedBookIds = const {},
    this.selectedGroupIds = const {},
    this.isSelectionMode = false,
    this.availableGroups = const [],
    this.cachedBooks = const {},
    this.series = const [],
    this.items = const [],
    this.cachedItems = const {},
    this.selectedSeriesIds = const {},
    this.manualOrders = const {},
  });

  BookshelfState copyWith({
    List<ShelfBook>? books,
    ShelfBookSortBy? sortBy,
    ViewMode? viewMode,
    int? currentGroupId,
    int? filterGroupId,
    Set<int>? selectedBookIds,
    Set<int>? selectedGroupIds,
    bool? isSelectionMode,
    List<ShelfGroup>? availableGroups,
    Map<int?, List<ShelfBook>>? cachedBooks,
    List<ShelfSeries>? series,
    List<ShelfItem>? items,
    Map<int?, List<ShelfItem>>? cachedItems,
    Set<int>? selectedSeriesIds,
    Map<String, List<String>>? manualOrders,
    bool clearGroup = false,
    bool clearFilter = false,
  }) {
    return BookshelfState.bookshelfState(
      books: books ?? this.books,
      sortBy: sortBy ?? this.sortBy,
      viewMode: viewMode ?? this.viewMode,
      currentGroupId: clearGroup
          ? null
          : (currentGroupId ?? this.currentGroupId),
      filterGroupId: clearFilter ? null : (filterGroupId ?? this.filterGroupId),
      selectedBookIds: selectedBookIds ?? this.selectedBookIds,
      selectedGroupIds: selectedGroupIds ?? this.selectedGroupIds,
      isSelectionMode: isSelectionMode ?? this.isSelectionMode,
      availableGroups: availableGroups ?? this.availableGroups,
      cachedBooks: cachedBooks ?? this.cachedBooks,
      series: series ?? this.series,
      items: items ?? this.items,
      cachedItems: cachedItems ?? this.cachedItems,
      selectedSeriesIds: selectedSeriesIds ?? this.selectedSeriesIds,
      manualOrders: manualOrders ?? this.manualOrders,
    );
  }

  int get selectedCount =>
      selectedBookIds.length + selectedGroupIds.length + selectedSeriesIds.length;
  bool get hasSelection => selectedCount > 0;
}

/// Notifier for managing bookshelf operations with dependency injection
@riverpod
class BookshelfNotifier extends _$BookshelfNotifier {
  static const int _maxCachedTabs = 8;
  static const String _sortOrderKey = 'bookshelf_sort_order';
  static const String _viewModeKey = 'bookshelf_view_mode';

  /// Series + manual-order persistence keys (JSON in SharedPreferences).
  static const String _seriesKey = 'shelf_series_v1';
  static const String _seriesCounterKey = 'shelf_series_counter_v1';
  static const String _manualOrderKey = 'shelf_manual_order_v1';

  // LRU cache eviction order — stored here, not in BookshelfState, because it
  // is an internal optimization detail that widgets never need to read.
  final List<int?> _cacheOrder = [];

  // Cached SharedPreferences instance, set during build.
  SharedPreferences? _prefs;

  /// Working copies of the persisted series / manual-order data.
  List<ShelfSeries> _series = [];
  int _seriesCounter = 1;
  Map<String, List<String>> _manualOrders = {};

  // Access repositories via providers (lazy initialization)
  ShelfBookRepository get _repository => ref.read(shelfBookRepositoryProvider);
  EpubImportService get _importService => ref.read(epubImportServiceProvider);

  @override
  Future<BookshelfState> build() async {
    // Load SharedPreferences and restore the previously saved sort order.
    _prefs = ref.read(sharedPreferencesProvider);
    _series = _loadSeries();
    _seriesCounter = _prefs?.getInt(_seriesCounterKey) ?? 1;
    _manualOrders = _loadManualOrders();

    final savedSortName = _prefs?.getString(_sortOrderKey);
    final savedSort = savedSortName != null
        ? ShelfBookSortBy.values.firstWhere(
            (e) => e.name == savedSortName,
            orElse: () => ShelfBookSortBy.recentlyAdded,
          )
        : ShelfBookSortBy.recentlyAdded;
    final savedViewModeName = _prefs?.getString(_viewModeKey);
    final savedViewMode = savedViewModeName != null
        ? ViewMode.values.firstWhere(
            (e) => e.name == savedViewModeName,
            orElse: () => ViewMode.relaxed,
          )
        : ViewMode.relaxed;
    return await _loadBooks(sortBy: savedSort, viewMode: savedViewMode);
  }

  // ─── Persistence helpers ────────────────────────────────────────────────

  List<ShelfSeries> _loadSeries() {
    final raw = _prefs?.getString(_seriesKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => ShelfSeries.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return [];
    }
  }

  void _persistSeries() {
    final encoded = jsonEncode(_series.map((s) => s.toJson()).toList());
    _prefs?.setString(_seriesKey, encoded);
  }

  Map<String, List<String>> _loadManualOrders() {
    final raw = _prefs?.getString(_manualOrderKey);
    if (raw == null || raw.isEmpty) return {};
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      return map.map(
        (k, v) => MapEntry(
          k,
          ((v as List?) ?? const []).map((e) => e as String).toList(),
        ),
      );
    } catch (_) {
      return {};
    }
  }

  void _persistManualOrders() {
    _prefs?.setString(_manualOrderKey, jsonEncode(_manualOrders));
  }

  ShelfSeries? _findSeries(int id) {
    for (final s in _series) {
      if (s.id == id) return s;
    }
    return null;
  }

  /// Container key for the manual order map.
  String _containerKeyForFilter(int? filterGroupId) {
    if (filterGroupId == null) return 'root';
    if (filterGroupId == -1) return 'uncat';
    return 'group_$filterGroupId';
  }

  /// Load folders + books with current filters
  Future<BookshelfState> _loadBooks({
    ShelfBookSortBy? sortBy,
    ViewMode? viewMode,
    int? groupId,
    int? filterGroupId,
    bool clearGroup = false,
    bool clearFilter = false,
  }) async {
    final currentState =
        state.valueOrNull ?? BookshelfState.bookshelfState(books: []);

    final actualSortBy = sortBy ?? currentState.sortBy;
    final actualViewMode = viewMode ?? currentState.viewMode;
    final actualGroupId = clearGroup
        ? null
        : (groupId ?? currentState.currentGroupId);
    final actualFilterGroupId = clearFilter
        ? null
        : (filterGroupId ?? currentState.filterGroupId);

    // Get group name for filtering
    String? filterGroupName;
    if (actualFilterGroupId != null && actualFilterGroupId != -1) {
      final group = await _repository.getGroupById(actualFilterGroupId);
      filterGroupName = group?.name;
    }

    final shouldFilterByGroup =
        actualFilterGroupId != null || actualGroupId != null;
    final books = await _repository.getBooksSorted(
      sortBy: actualSortBy,
      groupName: actualFilterGroupId == -1 ? null : filterGroupName,
      includeAll: !shouldFilterByGroup,
    );

    // All books (unfiltered) — used for group recency ordering and for
    // pruning series memberships of deleted books.
    final allBooks = await _repository.getAllBooks();
    final liveIds = <int>{for (final b in allBooks) b.id};
    final now = DateTime.now().millisecondsSinceEpoch;

    // Prune series: drop members that no longer exist; auto-dissolve
    // series that ended up empty.
    var seriesChanged = false;
    final prunedSeries = <ShelfSeries>[];
    for (final s in _series) {
      final members = s.bookIds.where(liveIds.contains).toList();
      if (members.isEmpty) {
        seriesChanged = true;
        continue;
      }
      final coverInvalid =
          s.coverBookId != null && !liveIds.contains(s.coverBookId);
      if (members.length != s.bookIds.length || coverInvalid) {
        s.bookIds = members;
        if (coverInvalid) s.coverBookId = null;
        s.updatedAt = now;
        seriesChanged = true;
      }
      prunedSeries.add(s);
    }
    if (seriesChanged) {
      _series = prunedSeries;
      _persistSeries();
    }

    final allGroups = await _repository.getGroups();

    // ── Tab order by reading recency (most recently read = leftmost) ───────
    final groupRecency = <String, int>{};
    for (final b in allBooks) {
      final g = b.groupName;
      if (g == null || g.isEmpty) continue;
      final t = b.lastOpenedDate ?? 0;
      final cur = groupRecency[g];
      if (cur == null || t > cur) groupRecency[g] = t;
    }
    allGroups.sort((a, b) {
      final ra = groupRecency[a.name] ?? 0;
      final rb = groupRecency[b.name] ?? 0;
      if (ra != rb) return rb.compareTo(ra);
      return a.name.compareTo(b.name);
    });

    // Merge books + series into shelf items.
    final containerKey = _containerKeyForFilter(actualFilterGroupId);
    final items = buildShelfItems(
      books: books,
      allBooks: allBooks,
      series: _series,
      manualOrders: _manualOrders,
      containerKey: actualSortBy == ShelfBookSortBy.custom
          ? containerKey
          : null,
    );

    final updatedCache = Map<int?, List<ShelfBook>>.from(
      currentState.cachedBooks,
    );
    final updatedItemsCache = Map<int?, List<ShelfItem>>.from(
      currentState.cachedItems,
    );
    final cacheKey = shouldFilterByGroup ? actualFilterGroupId : null;
    updatedCache[cacheKey] = books;
    updatedItemsCache[cacheKey] = items;
    _touchCacheKey(cacheKey);
    _trimCache(updatedCache, updatedItemsCache);

    return BookshelfState.bookshelfState(
      books: books,
      sortBy: actualSortBy,
      viewMode: actualViewMode,
      currentGroupId: actualGroupId,
      filterGroupId: actualFilterGroupId,
      availableGroups: allGroups,
      selectedBookIds: currentState.selectedBookIds,
      selectedGroupIds: currentState.selectedGroupIds,
      isSelectionMode: currentState.isSelectionMode,
      cachedBooks: updatedCache,
      series: List.of(_series),
      items: items,
      cachedItems: updatedItemsCache,
      selectedSeriesIds: currentState.selectedSeriesIds,
      manualOrders: Map.of(_manualOrders),
    );
  }

  /// Change sort order and persist the selection.
  Future<void> changeSortOrder(ShelfBookSortBy sortBy) async {
    // Persist asynchronously – fire and forget, no need to await.
    _prefs?.setString(_sortOrderKey, sortBy.name);
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadBooks(sortBy: sortBy));
  }

  /// Change view mode and persist the selection.
  void changeViewMode(ViewMode mode) {
    _prefs?.setString(_viewModeKey, mode.name);
    final currentState = state.valueOrNull;
    if (currentState == null) return;
    state = AsyncValue.data(currentState.copyWith(viewMode: mode));
  }

  /// Filter by group (null = show all books)
  Future<void> filterByGroup(int? groupId) async {
    state = await AsyncValue.guard(
      () => _loadBooks(filterGroupId: groupId, clearFilter: groupId == null),
    );
  }

  /// Enter a group (folder)
  Future<void> enterGroup(int groupId) async {
    state = const AsyncValue.loading();
    // Clear filter when navigating into a group
    state = await AsyncValue.guard(
      () => _loadBooks(groupId: groupId, clearFilter: true),
    );
  }

  /// Go back to root (simplified - no nesting)
  Future<void> goBack() async {
    final currentState = state.valueOrNull;
    if (currentState == null || currentState.currentGroupId == null) {
      return;
    }

    state = const AsyncValue.loading();
    // Clear group and filter when navigating back
    state = await AsyncValue.guard(
      () => _loadBooks(groupId: null, clearFilter: true),
    );
  }

  /// Create a new group (flat structure, no nesting)
  Future<int?> createGroup(String name) async {
    final result = await _repository.createGroup(name: name);
    if (result.isLeft()) {
      return null;
    }

    await refresh();

    final newGroupId = result.getRight().toNullable()!;
    return newGroupId;
  }

  /// Toggle selection mode
  void toggleSelectionMode() {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    if (currentState.isSelectionMode) {
      // Exit selection mode and clear selections
      state = AsyncValue.data(
        currentState.copyWith(
          isSelectionMode: false,
          selectedBookIds: {},
          selectedGroupIds: {},
          selectedSeriesIds: {},
        ),
      );
    } else {
      // Enter selection mode
      state = AsyncValue.data(currentState.copyWith(isSelectionMode: true));
    }
  }

  /// Toggle item selection
  void toggleItemSelection(ShelfBook book) {
    final currentState = state.valueOrNull;
    if (currentState == null || !currentState.isSelectionMode) return;

    final newSelection = Set<int>.from(currentState.selectedBookIds);
    if (newSelection.contains(book.id)) {
      newSelection.remove(book.id);
    } else {
      newSelection.add(book.id);
    }
    state = AsyncValue.data(
      currentState.copyWith(selectedBookIds: newSelection),
    );
  }

  /// Toggle selection of a series item.
  void toggleSeriesSelection(ShelfSeries series) {
    final currentState = state.valueOrNull;
    if (currentState == null || !currentState.isSelectionMode) return;

    final newSelection = Set<int>.from(currentState.selectedSeriesIds);
    if (newSelection.contains(series.id)) {
      newSelection.remove(series.id);
    } else {
      newSelection.add(series.id);
    }
    state = AsyncValue.data(
      currentState.copyWith(selectedSeriesIds: newSelection),
    );
  }

  /// Select all books and series in the current tab
  void selectAll() {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    final bookIds = <int>{};
    final seriesIds = <int>{};
    for (final item in currentState.items) {
      switch (item) {
        case BookShelfItem(:final book):
          bookIds.add(book.id);
        case SeriesShelfItem(:final series):
          seriesIds.add(series.id);
      }
    }
    state = AsyncValue.data(
      currentState.copyWith(
        selectedBookIds: bookIds,
        selectedGroupIds: {},
        selectedSeriesIds: seriesIds,
        isSelectionMode: true,
      ),
    );
  }

  /// Clear selection
  void clearSelection() {
    final currentState = state.valueOrNull;
    if (currentState == null) return;

    state = AsyncValue.data(
      currentState.copyWith(
        selectedBookIds: {},
        selectedGroupIds: {},
        selectedSeriesIds: {},
      ),
    );
  }

  /// Move selected items to a target group (null = root).
  /// Series items move ALL their member books.
  Future<bool> moveSelectedItems(int? targetGroupId) async {
    final currentState = state.valueOrNull;
    if (currentState == null || !currentState.hasSelection) return false;

    try {
      // Get target group name
      String? targetGroupName;
      if (targetGroupId != null) {
        final group = await _repository.getGroupById(targetGroupId);
        targetGroupName = group?.name;
      }

      final allBookIds = <int>{
        ...currentState.selectedBookIds,
        for (final seriesId in currentState.selectedSeriesIds)
          ...(_findSeries(seriesId)?.bookIds ?? const <int>[]),
      };

      if (allBookIds.isNotEmpty) {
        await _repository.moveBooksToGroup(
          bookIds: allBookIds,
          targetGroupName: targetGroupName,
        );
      }

      // Note: Group moving is removed (flat structure)
      // Groups selected will simply be ignored

      // Reload items and clear selection
      state = const AsyncValue.loading();
      final newState = await _loadBooks();
      state = AsyncValue.data(
        newState.copyWith(
          selectedBookIds: {},
          selectedGroupIds: {},
          selectedSeriesIds: {},
          isSelectionMode: false,
        ),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Delete selected books and/or dissolve selected series.
  /// Books are deleted permanently; series are dissolved (books stay).
  Future<bool> deleteSelected() async {
    final currentState = state.valueOrNull;
    if (currentState == null || !currentState.hasSelection) return false;

    try {
      // Dissolve selected series (their books stay on the shelf).
      if (currentState.selectedSeriesIds.isNotEmpty) {
        final selected = currentState.selectedSeriesIds;
        _series = _series.where((s) => !selected.contains(s.id)).toList();
        _persistSeries();
      }

      for (final bookId in currentState.selectedBookIds) {
        final book = await _repository.getBookById(bookId);
        if (book == null) {
          return false;
        }

        // Delete using import service (handles files + database)
        final deleteResult = await _importService.deleteBook(book);
        if (deleteResult.isLeft()) {
          return false;
        }
      }

      // Drop deleted books from any series membership.
      if (currentState.selectedBookIds.isNotEmpty) {
        final deletedIds = currentState.selectedBookIds;
        final now = DateTime.now().millisecondsSinceEpoch;
        var changed = false;
        for (final s in _series) {
          final before = s.bookIds.length;
          s.bookIds = s.bookIds.where((id) => !deletedIds.contains(id)).toList();
          if (s.bookIds.length != before) {
            s.updatedAt = now;
            changed = true;
          }
        }
        if (changed) _persistSeries();
      }

      // Reload items and clear selection
      state = const AsyncValue.loading();
      final newState = await _loadBooks();
      state = AsyncValue.data(
        newState.copyWith(
          selectedBookIds: {},
          selectedGroupIds: {},
          selectedSeriesIds: {},
          isSelectionMode: false,
        ),
      );

      return true;
    } catch (e) {
      return false;
    }
  }

  /// Refresh books
  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => _loadBooks());
  }

  Future<bool> reloadQuietly() async {
    if (state.valueOrNull == null) return true;
    try {
      // Re-use _loadBooks so the filter/sort/cache logic is in one place.
      // Unlike refresh(), we do NOT emit AsyncLoading first, so the UI keeps
      // showing the existing books during the background reload.
      final newState = await _loadBooks();
      state = AsyncValue.data(newState);
      return true;
    } catch (e) {
      return false;
    }
  }

  Future<bool> renameGroup(int groupId, String name) async {
    if (name.trim().isEmpty) return false;
    try {
      final result = await _repository.updateGroupName(
        groupId: groupId,
        name: name.trim(),
      );
      if (result.isRight()) {
        state = await AsyncValue.guard(() => _loadBooks());
      }
      return result.isRight();
    } catch (e) {
      return false;
    }
  }

  Future<bool> deleteGroup(int groupId) async {
    try {
      final result = await _repository.deleteGroup(groupId: groupId);
      if (result.isLeft()) return false;

      final currentState = state.valueOrNull;
      final clearFilter = currentState?.filterGroupId == groupId;
      final clearGroup = currentState?.currentGroupId == groupId;
      final newState = await _loadBooks(
        clearFilter: clearFilter,
        clearGroup: clearGroup,
      );
      // Remove the deleted group from the LRU cache.
      _cacheOrder.remove(groupId);
      final updatedCache = Map<int?, List<ShelfBook>>.from(newState.cachedBooks)
        ..remove(groupId);
      final updatedItemsCache = Map<int?, List<ShelfItem>>.from(
        newState.cachedItems,
      )..remove(groupId);
      state = AsyncValue.data(
        newState.copyWith(
          cachedBooks: updatedCache,
          cachedItems: updatedItemsCache,
        ),
      );
      return true;
    } catch (e) {
      return false;
    }
  }

  // ─── Series operations ──────────────────────────────────────────────────

  /// Merge the currently selected books into a new series ([name]) or into
  /// an existing one ([targetSeriesId]). Selected books are removed from any
  /// other series they belonged to.
  Future<bool> mergeSelectedIntoSeries({
    String? name,
    int? targetSeriesId,
  }) async {
    final currentState = state.valueOrNull;
    if (currentState == null) return false;
    final bookIds = currentState.selectedBookIds.toList();
    if (bookIds.isEmpty) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    var target = targetSeriesId != null
        ? _findSeries(targetSeriesId)
        : null;

    if (target == null) {
      _seriesCounter++;
      _prefs?.setInt(_seriesCounterKey, _seriesCounter);
      target = ShelfSeries(
        id: _seriesCounter,
        name: (name != null && name.trim().isNotEmpty)
            ? name.trim()
            : 'Series $_seriesCounter',
        createdAt: now,
        updatedAt: now,
      );
      _series.add(target);
    }

    // Take the selected books out of any other series first.
    final kept = <ShelfSeries>[];
    for (final s in _series) {
      if (s.id == target.id) {
        kept.add(s);
        continue;
      }
      final before = s.bookIds.length;
      s.bookIds = s.bookIds.where((id) => !bookIds.contains(id)).toList();
      if (s.bookIds.isEmpty) continue; // series became empty -> dissolve
      if (s.bookIds.length != before) s.updatedAt = now;
      kept.add(s);
    }
    _series = kept;

    // Append in current shelf order (stable).
    final ordered = <int>[];
    for (final item in currentState.items) {
      if (item is BookShelfItem && bookIds.contains(item.book.id)) {
        ordered.add(item.book.id);
      }
    }
    for (final id in bookIds) {
      if (!ordered.contains(id)) ordered.add(id);
    }

    final targetSeries = _findSeries(target.id)!;
    for (final id in ordered) {
      if (!targetSeries.bookIds.contains(id)) targetSeries.bookIds.add(id);
    }
    targetSeries.updatedAt = now;

    _persistSeries();

    // Reload and clear selection.
    state = const AsyncValue.loading();
    final newState = await _loadBooks();
    state = AsyncValue.data(
      newState.copyWith(
        selectedBookIds: {},
        selectedGroupIds: {},
        selectedSeriesIds: {},
        isSelectionMode: false,
      ),
    );
    return true;
  }

  /// Dissolve a series: the series item disappears from the shelf but all
  /// member books stay.
  Future<bool> unmergeSeries(int seriesId) async {
    final before = _series.length;
    _series = _series.where((s) => s.id != seriesId).toList();
    if (_series.length == before) return false;
    _persistSeries();

    state = const AsyncValue.loading();
    final newState = await _loadBooks();
    state = AsyncValue.data(
      newState.copyWith(
        selectedBookIds: {},
        selectedGroupIds: {},
        selectedSeriesIds: {},
        isSelectionMode: false,
      ),
    );
    return true;
  }

  Future<bool> renameSeries(int seriesId, String name) async {
    final s = _findSeries(seriesId);
    if (s == null || name.trim().isEmpty) return false;
    s.name = name.trim();
    s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _persistSeries();
    return reloadQuietly();
  }

  /// Set the book whose cover represents the series. `null` = auto.
  Future<bool> setSeriesCover(int seriesId, int? bookId) async {
    final s = _findSeries(seriesId);
    if (s == null) return false;
    if (bookId != null && !s.bookIds.contains(bookId)) return false;
    s.coverBookId = bookId;
    s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _persistSeries();
    return reloadQuietly();
  }

  /// Remove books from a series (they stay on the shelf).
  Future<bool> removeBooksFromSeries(int seriesId, Set<int> bookIds) async {
    final s = _findSeries(seriesId);
    if (s == null || bookIds.isEmpty) return false;
    s.bookIds = s.bookIds.where((id) => !bookIds.contains(id)).toList();
    s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    if (s.bookIds.isEmpty) {
      _series = _series.where((e) => e.id != seriesId).toList();
    }
    _persistSeries();
    return reloadQuietly();
  }

  /// Manual reorder of the current tab's shelf items (custom sort mode).
  /// Persists the order for the active container.
  Future<void> reorderItems(int oldIndex, int newIndex) async {
    final currentState = state.valueOrNull;
    if (currentState == null ||
        currentState.sortBy != ShelfBookSortBy.custom) {
      return;
    }
    final items = List<ShelfItem>.of(currentState.items);
    if (oldIndex < 0 || oldIndex >= items.length) return;
    if (newIndex < 0 || newIndex > items.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;

    final item = items.removeAt(oldIndex);
    items.insert(newIndex, item);

    final containerKey = _containerKeyForFilter(currentState.filterGroupId);
    _manualOrders[containerKey] = items.map((e) => e.orderKey).toList();
    _persistManualOrders();

    // Keep the per-tab cache in sync so switching tabs shows the new order.
    final updatedCache = Map<int?, List<ShelfItem>>.from(
      currentState.cachedItems,
    );
    updatedCache[currentState.filterGroupId] = items;
    state = AsyncValue.data(
      currentState.copyWith(items: items, cachedItems: updatedCache),
    );
  }

  /// Manual reorder of the books inside a series (always available).
  Future<void> reorderSeriesBooks(
    int seriesId,
    int oldIndex,
    int newIndex,
  ) async {
    final s = _findSeries(seriesId);
    if (s == null) return;
    if (oldIndex < 0 || oldIndex >= s.bookIds.length) return;
    if (newIndex < 0 || newIndex > s.bookIds.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    if (newIndex == oldIndex) return;

    final id = s.bookIds.removeAt(oldIndex);
    s.bookIds.insert(newIndex, id);
    s.updatedAt = DateTime.now().millisecondsSinceEpoch;
    _persistSeries();
    await reloadQuietly();
  }

  void _touchCacheKey(int? key) {
    _cacheOrder.remove(key);
    _cacheOrder.add(key);
  }

  void _trimCache(
    Map<int?, List<ShelfBook>> cache,
    Map<int?, List<ShelfItem>> itemsCache,
  ) {
    while (_cacheOrder.length > _maxCachedTabs) {
      final removedKey = _cacheOrder.removeAt(0);
      cache.remove(removedKey);
      itemsCache.remove(removedKey);
    }
  }
}
