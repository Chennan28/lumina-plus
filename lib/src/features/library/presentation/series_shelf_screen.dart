import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ereader/src/core/services/toast_service.dart';
import 'package:ereader/src/core/theme/app_theme.dart';
import 'package:ereader/src/core/widgets/book_cover.dart';
import '../../../../l10n/app_localizations.dart';
import '../application/bookshelf_notifier.dart';
import '../data/repositories/shelf_book_repository_provider.dart';
import '../domain/shelf_book.dart';
import '../domain/shelf_series.dart';
import 'widgets/book_grid_item.dart';
import 'widgets/reorderable_shelf_grid.dart';

/// Snapshot of a series and its member books (in series order).
class SeriesDetail {
  final ShelfSeries series;
  final List<ShelfBook> books;
  const SeriesDetail({required this.series, required this.books});
}

/// Resolves the series definition + member books (series order).
final seriesDetailProvider = FutureProvider.autoDispose
    .family<SeriesDetail?, int>((ref, seriesId) async {
  final state = ref.watch(bookshelfNotifierProvider).valueOrNull;
  final series = state?.series.where((s) => s.id == seriesId).toList() ?? [];
  if (series.isEmpty) return null;

  final allBooks = await ref
      .read(shelfBookRepositoryProvider)
      .getAllBooks();
  final byId = <int, ShelfBook>{for (final b in allBooks) b.id: b};
  final books = series.first.bookIds
      .map((id) => byId[id])
      .whereType<ShelfBook>()
      .toList();
  return SeriesDetail(series: series.first, books: books);
});

/// Sub-shelf showing all works of one merged series.
///
/// Books are always shown in the series' own manual order and can be
/// reordered by long-press dragging. The cover of the series (shown on the
/// main shelf) can be switched to any member's cover here.
class SeriesShelfScreen extends ConsumerStatefulWidget {
  final int seriesId;
  const SeriesShelfScreen({super.key, required this.seriesId});

  @override
  ConsumerState<SeriesShelfScreen> createState() =>
      _SeriesShelfScreenState();
}

class _SeriesShelfScreenState extends ConsumerState<SeriesShelfScreen> {
  final Set<int> _selectedBookIds = {};
  bool _isSelectionMode = false;

  void _toggleBookSelection(int bookId) {
    setState(() {
      if (!_selectedBookIds.add(bookId)) {
        _selectedBookIds.remove(bookId);
      }
    });
  }

  void _exitSelection() {
    setState(() {
      _isSelectionMode = false;
      _selectedBookIds.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final detailAsync = ref.watch(seriesDetailProvider(widget.seriesId));
    final bookshelfLoading = ref.watch(bookshelfNotifierProvider).isLoading;

    return PopScope(
      canPop: !_isSelectionMode,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _isSelectionMode) _exitSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(detailAsync.valueOrNull?.series.name ?? ''),
          actions: [
            if (_isSelectionMode)
              IconButton(
                tooltip: AppLocalizations.of(context)!.selectAll,
                icon: Icon(
                  _selectedBookIds.length == detailAsync.valueOrNull?.books.length
                      ? Icons.deselect_outlined
                      : Icons.select_all_outlined,
                ),
                onPressed: () {
                  final books = detailAsync.valueOrNull?.books ?? const [];
                  setState(() {
                    if (_selectedBookIds.length == books.length) {
                      _selectedBookIds.clear();
                    } else {
                      _selectedBookIds
                        ..clear()
                        ..addAll(books.map((b) => b.id));
                    }
                  });
                },
              )
            else if (detailAsync.valueOrNull != null)
              IconButton(
                tooltip: AppLocalizations.of(context)!.select,
                icon: const Icon(Icons.checklist_outlined),
                onPressed: () => setState(() => _isSelectionMode = true),
              ),
            if (!_isSelectionMode && detailAsync.valueOrNull != null)
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert_outlined),
                onSelected: (value) => _handleMenuAction(context, value),
                itemBuilder: (context) => [
                  PopupMenuItem(
                    value: 'rename',
                    child: Text(AppLocalizations.of(context)!.renameSeries),
                  ),
                  PopupMenuItem(
                    value: 'cover',
                    child: Text(AppLocalizations.of(context)!.changeSeriesCover),
                  ),
                  PopupMenuItem(
                    value: 'dissolve',
                    child: Text(AppLocalizations.of(context)!.dissolveSeries),
                  ),
                ],
              ),
          ],
        ),
        body: detailAsync.when(
          loading: () => const Center(
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          error: (error, stack) => Center(
            child: Text(
              AppLocalizations.of(context)!.errorLoadingLibrary(error.toString()),
            ),
          ),
          data: (detail) {
            if (detail == null && !bookshelfLoading) {
              // Series was dissolved while this screen was open.
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) Navigator.of(context).maybePop();
              });
              return const SizedBox.shrink();
            }
            if (detail == null) {
              return const Center(
                child: CircularProgressIndicator(strokeWidth: 2),
              );
            }
            return _buildBody(context, detail);
          },
        ),
        bottomNavigationBar: _isSelectionMode && detailAsync.valueOrNull != null
            ? _buildSelectionBar(context, detailAsync.valueOrNull!)
            : null,
      ),
    );
  }

  Widget _buildBody(BuildContext context, SeriesDetail detail) {
    if (detail.books.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.seriesIsEmpty,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final bottomStatusBarHeight = MediaQuery.of(context).padding.bottom;
    return CustomScrollView(
      key: PageStorageKey<String>('series_${widget.seriesId}'),
      slivers: [
        ReorderableShelfGrid<ShelfBook>(
          items: detail.books,
          // The series page is always manually ordered.
          dragEnabled: !_isSelectionMode,
          viewMode: ViewMode.relaxed,
          itemKey: (book) => ValueKey<String>('sb${book.id}'),
          onReorder: (oldIndex, newIndex) => ref
              .read(bookshelfNotifierProvider.notifier)
              .reorderSeriesBooks(widget.seriesId, oldIndex, newIndex),
          itemBuilder: (context, book) => BookGridItem(
            book: book,
            isSelectionMode: _isSelectionMode,
            isSelected: _selectedBookIds.contains(book.id),
            viewMode: ViewMode.relaxed,
            onTap: _isSelectionMode
                ? () => _toggleBookSelection(book.id)
                : null,
            // Long-press is reserved for drag-reordering in this screen;
            // selection mode is entered from the app bar action instead.
            onLongPress: null,
          ),
        ),
        if (_isSelectionMode)
          SliverToBoxAdapter(
            child: SizedBox(
              height: AppTheme.kBottomAppBarHeight + bottomStatusBarHeight,
            ),
          ),
      ],
    );
  }

  Widget _buildSelectionBar(BuildContext context, SeriesDetail detail) {
    final l10n = AppLocalizations.of(context)!;
    final bottomStatusBarHeight = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainer,
      ),
      constraints: BoxConstraints(
        maxHeight: AppTheme.kBottomAppBarHeight + bottomStatusBarHeight,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: _selectedBookIds.isEmpty
                    ? null
                    : () => _removeFromSeries(context, detail),
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.remove_circle_outline,
                        color: _selectedBookIds.isEmpty
                            ? Theme.of(context).colorScheme.onSurfaceVariant
                            : Theme.of(context).colorScheme.onSurface,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        l10n.removeFromSeries,
                        style: Theme.of(context).textTheme.labelMedium?.copyWith(
                          color: _selectedBookIds.isEmpty
                              ? Theme.of(context).colorScheme.onSurfaceVariant
                              : Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 24),
              Text(
                l10n.selected(_selectedBookIds.length),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _handleMenuAction(BuildContext context, String value) async {
    final detail = ref.read(seriesDetailProvider(widget.seriesId)).valueOrNull;
    if (detail == null) return;
    final notifier = ref.read(bookshelfNotifierProvider.notifier);
    final l10n = AppLocalizations.of(context)!;

    switch (value) {
      case 'rename':
        final name = await _promptRename(context, detail.series.name);
        if (name == null || name == detail.series.name || !mounted) return;
        final ok = await notifier.renameSeries(widget.seriesId, name);
        if (mounted) {
          if (ok) {
            ToastService.showSuccess(l10n.seriesCreated(name));
          } else {
            ToastService.showError(l10n.failedToMergeSeries);
          }
        }
        break;
      case 'cover':
        _showCoverPicker(context, detail);
        break;
      case 'dissolve':
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(l10n.dissolveSeries),
            content: Text(l10n.deleteSeriesConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(l10n.cancel),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(l10n.dissolveSeries),
              ),
            ],
          ),
        );
        if (confirmed == true && mounted) {
          final ok = await notifier.unmergeSeries(widget.seriesId);
          if (mounted && context.mounted) {
            if (ok) {
              ToastService.showSuccess(l10n.seriesDeleted(detail.series.name));
            } else {
              ToastService.showError(l10n.failedToDeleteSeries);
            }
            if (ok) context.pop();
          }
        }
        break;
    }
  }

  Future<String?> _promptRename(BuildContext context, String current) async {
    var draftName = current;
    final result = await showDialog<String?>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(AppLocalizations.of(context)!.renameSeries),
        content: TextField(
          controller: TextEditingController(text: current),
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: AppLocalizations.of(context)!.seriesName,
          ),
          onChanged: (value) => draftName = value,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, draftName.trim()),
            child: Text(AppLocalizations.of(context)!.save),
          ),
        ],
      ),
    );
    return (result?.trim().isNotEmpty ?? false) ? result : null;
  }

  /// Bottom sheet listing every member cover; tap to use it as the series
  /// cover (an "auto" option is also offered).
  void _showCoverPicker(BuildContext context, SeriesDetail detail) {
    final l10n = AppLocalizations.of(context)!;
    final notifier = ref.read(bookshelfNotifierProvider.notifier);
    final current = detail.series.coverBookId;

    Widget coverCell(ShelfBook book) {
      final isCurrent = book.id == current;
      return GestureDetector(
        onTap: () {
          notifier.setSeriesCover(widget.seriesId, book.id);
          Navigator.pop(context);
          ToastService.showSuccess(l10n.coverUpdated);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            BookCover(
              relativePath: book.coverPath,
              radius: BorderRadius.circular(6),
            ),
            if (isCurrent)
              Container(
                decoration: BoxDecoration(
                  color: Colors.black38,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Icon(Icons.check_circle, color: Colors.white),
              ),
          ],
        ),
      );
    }

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.changeSeriesCover,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.auto_awesome_outlined),
                title: Text(l10n.autoCover),
                trailing: current == null
                    ? const Icon(Icons.check, color: Colors.green)
                    : null,
                onTap: () {
                  notifier.setSeriesCover(widget.seriesId, null);
                  Navigator.pop(context);
                  ToastService.showSuccess(l10n.coverUpdated);
                },
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 200,
                child: GridView.builder(
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 90.0,
                    childAspectRatio: 210 / 297,
                    crossAxisSpacing: 8,
                    mainAxisSpacing: 8,
                  ),
                  itemCount: detail.books.length,
                  itemBuilder: (context, index) =>
                      coverCell(detail.books[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _removeFromSeries(
    BuildContext context,
    SeriesDetail detail,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final success = await ref
        .read(bookshelfNotifierProvider.notifier)
        .removeBooksFromSeries(widget.seriesId, Set.of(_selectedBookIds));
    if (!mounted) return;
    if (success) {
      ToastService.showSuccess(l10n.removedFromSeries);
      _exitSelection();
    } else {
      ToastService.showError(l10n.failedToRemoveFromSeries);
    }
  }
}
