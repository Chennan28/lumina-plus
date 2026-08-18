import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ereader/src/core/widgets/middle_ellipsis_two_lines_text.dart';
import 'package:ereader/src/core/widgets/book_cover.dart';
import '../../application/bookshelf_notifier.dart';
import '../../domain/shelf_item.dart';

/// Shelf card for a merged series: shows the (switchable) cover of one of its
/// members, the series name, and a semi-transparent black count badge at the
/// bottom-left of the cover.
class SeriesGridItem extends ConsumerWidget {
  final SeriesShelfItem item;
  final bool isSelectionMode;
  final bool isSelected;
  final ViewMode viewMode;
  final VoidCallback? onLongPress;

  const SeriesGridItem({
    super.key,
    required this.item,
    required this.isSelectionMode,
    required this.isSelected,
    required this.viewMode,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      onTap: () => _handleTap(context, ref),
      onLongPress: onLongPress,

      child: Stack(
        children: [
          switch (viewMode) {
            ViewMode.relaxed => _buildRelaxed(context),
            ViewMode.compact => Positioned.fill(child: _buildCompact(context)),
          },

          if (isSelectionMode)
            Positioned(top: 8, left: 8, child: _buildCheckbox(context)),
        ],
      ),
    );
  }

  Widget _buildRelaxed(BuildContext context) {
    final coverBook = item.coverBook;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: _buildCoverStack(context)),
        const SizedBox(height: 12),
        MiddleEllipsisTwoLinesText(item.series.name),
        const SizedBox(height: 4),
        if (coverBook != null && coverBook.author.isNotEmpty)
          Text(
            coverBook.author,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
      ],
    );
  }

  Widget _buildCompact(BuildContext context) {
    return _buildCoverStack(
      context,
      extras: [
        // Bottom gradient + title
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(6),
            ),
            child: Container(
              // Left padding leaves room for the count badge at bottom-left.
              padding: const EdgeInsets.fromLTRB(34, 32, 6, 6),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87],
                ),
              ),
              child: MiddleEllipsisTwoLinesText(
                item.series.name,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w500,
                  shadows: const [
                    Shadow(
                      color: Colors.black54,
                      blurRadius: 2.0,
                      offset: Offset(0, 1.0),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCoverStack(BuildContext context, {List<Widget> extras = const []}) {
    final coverBook = item.coverBook;
    return Stack(
      fit: StackFit.expand,
      children: [
        Container(
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(6)),
          child: BookCover(
            relativePath: coverBook?.coverPath,
            radius: BorderRadius.circular(6),
          ),
        ),
        if (isSelectionMode)
          Container(
            decoration: BoxDecoration(
              color: isSelected
                  ? Theme.of(context).colorScheme.primary.withAlpha(102)
                  : Theme.of(context).colorScheme.onSurface.withAlpha(51),
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ...extras,
        // ── Count badge (bottom-left): semi-transparent black circle ───────
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
            padding: const EdgeInsets.symmetric(horizontal: 6),
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black54,
            ),
            child: Text(
              '${item.books.length}',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCheckbox(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isSelected
            ? Theme.of(context).colorScheme.primary
            : Theme.of(context).colorScheme.surface,
        border: Border.all(
          color: isSelected
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.outline,
          width: 2,
        ),
      ),
      child: isSelected
          ? Icon(
              Icons.check_outlined,
              size: 16,
              color: Theme.of(context).colorScheme.onPrimary,
            )
          : null,
    );
  }

  void _handleTap(BuildContext context, WidgetRef ref) {
    if (isSelectionMode) {
      ref
          .read(bookshelfNotifierProvider.notifier)
          .toggleSeriesSelection(item.series);
    } else {
      final notifier = ref.read(bookshelfNotifierProvider.notifier);
      context.push('/series/${item.series.id}').then((_) {
        notifier.reloadQuietly();
      });
    }
  }
}
