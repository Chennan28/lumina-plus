import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:ereader/l10n/app_localizations.dart';
import 'package:ereader/src/core/widgets/book_cover.dart';
import '../../application/bookshelf_notifier.dart';
import '../../domain/shelf_book.dart';

/// Single-book carousel for the pinned "Recent Reads" tab.
///
/// Shows the books as large single covers with a stack-overlay transition:
/// the cover of the previously-read book peeks out at the right edge,
/// semi-transparent, underneath the current cover. A thumbnail strip at the
/// bottom shows all up-to-5 recent books and follows the active page.
class RecentReadsView extends ConsumerStatefulWidget {
  final List<ShelfBook> books;
  const RecentReadsView({super.key, required this.books});

  @override
  ConsumerState<RecentReadsView> createState() => _RecentReadsViewState();
}

class _RecentReadsViewState extends ConsumerState<RecentReadsView> {
  PageController? _controller;
  int _current = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController(viewportFraction: 0.92);
  }

  @override
  void didUpdateWidget(RecentReadsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.books.length != widget.books.length &&
        _current >= widget.books.length) {
      _current = 0;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _openBook(ShelfBook book) {
    final notifier = ref.read(bookshelfNotifierProvider.notifier);
    context.push('/book/${book.fileHash}', extra: book).then((_) {
      notifier.reloadQuietly();
    });
  }

  @override
  Widget build(BuildContext context) {
    final books = widget.books;
    final l10n = AppLocalizations.of(context)!;

    if (books.isEmpty) {
      return Center(
        child: Text(
          l10n.noRecentReads,
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    final screenWidth = MediaQuery.sizeOf(context).width;
    final peekWidth = screenWidth / 6.0;
    // 当前页右侧露出的“前一本（更早阅读）”封面
    final nextBook = _current + 1 < books.length ? books[_current + 1] : null;

    return Column(
      children: [
        // ── 大封面轮播区 ───────────────────────────────────────────────
        Expanded(
          child: Stack(
            children: [
              // 底层：右侧半透明叠加的上一本封面（露出约六分之一）
              if (nextBook != null)
                Positioned(
                  right: 0,
                  top: 32,
                  bottom: 32,
                  width: peekWidth,
                  child: Opacity(
                    opacity: 0.45,
                    child: BookCover(
                      relativePath: nextBook.coverPath,
                      radius: BorderRadius.circular(6),
                    ),
                  ),
                ),
              // 上层：可滑动的单本封面
              PageView.builder(
                controller: _controller,
                itemCount: books.length,
                onPageChanged: (index) => setState(() => _current = index),
                itemBuilder: (context, index) => _buildBookPage(
                  context,
                  books[index],
                ),
              ),
            ],
          ),
        ),

        // ── 缩略图条 + 当前书名 ────────────────────────────────────────
        Container(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: 64,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    for (var i = 0; i < books.length; i++)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: GestureDetector(
                          onTap: () => _controller?.animateToPage(
                            i,
                            duration: const Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                          ),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: i == _current ? 48 : 40,
                            height: i == _current ? 64 : 56,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: i == _current
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                              boxShadow: i == _current
                                  ? [
                                      BoxShadow(
                                        color: Theme.of(
                                          context,
                                        ).colorScheme.primary.withValues(alpha: 0.25),
                                        blurRadius: 8,
                                      ),
                                    ]
                                  : null,
                            ),
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: BookCover(
                                relativePath: books[i].coverPath,
                                radius: BorderRadius.zero,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Text(
                books[_current].title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_current + 1} / ${books.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBookPage(BuildContext context, ShelfBook book) {
    return GestureDetector(
      onTap: () => _openBook(book),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(28, 4, 28, 0),
        child: Column(
          children: [
            // Cover: always fully visible (BoxFit.contain), centered in the
            // available space, sharing the same Hero tag as the shelf grid so
            // opening the book gets the smooth cover-flight transition.
            Expanded(
              child: Center(
                child: AspectRatio(
                  aspectRatio: 210 / 297,
                  child: Hero(
                    tag: 'book-cover-${book.id}',
                    child: BookCover(
                      relativePath: book.coverPath,
                      radius: BorderRadius.circular(10),
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Text(
              book.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 2),
            if (book.author.isNotEmpty)
              Text(
                book.author,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
            if (book.readingProgress > 0 && !book.isDeleted) ...[
              const SizedBox(height: 6),
              SizedBox(
                width: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: book.readingProgress,
                    minHeight: 2,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
