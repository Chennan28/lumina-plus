import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../application/bookshelf_notifier.dart';

/// A grid of shelf items that supports long-press drag reordering.
///
/// Uses the built-in [LongPressDraggable] + [DragTarget] combo with a
/// hover-swap strategy: while dragging, hovering over another cell swaps the
/// dragged item to that position immediately (and the grid animates the
/// shift via implicit keyed updates). Auto-scrolls when the drag reaches the
/// top/bottom edges of the grid viewport.
class ReorderableShelfGrid<T> extends StatefulWidget {
  final List<T> items;

  /// When false the cells render as a plain, non-draggable grid.
  final bool dragEnabled;

  final ViewMode viewMode;
  final Key Function(T item) itemKey;
  final Widget Function(BuildContext context, T item) itemBuilder;
  final void Function(int oldIndex, int newIndex) onReorder;

  /// Horizontal padding of the enclosing grid (used to compute cell sizes
  /// for the drag ghost).
  final double horizontalPadding;

  const ReorderableShelfGrid({
    super.key,
    required this.items,
    required this.dragEnabled,
    required this.viewMode,
    required this.itemKey,
    required this.itemBuilder,
    required this.onReorder,
    this.horizontalPadding = 32.0,
  });

  @override
  State<ReorderableShelfGrid<T>> createState() =>
      _ReorderableShelfGridState<T>();
}

class _ReorderableShelfGridState<T> extends State<ReorderableShelfGrid<T>> {
  /// Index of the item currently being dragged (null = not dragging).
  int? _dragIndex;

  /// Timestamp of the last hover-swap, used to avoid index oscillation when
  /// the pointer hovers on a cell boundary.
  DateTime? _lastSwap;

  ScrollableState? _scrollable;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scrollable ??= Scrollable.maybeOf(context);
  }

  @override
  Widget build(BuildContext context) {
    final delegate = switch (widget.viewMode) {
      ViewMode.relaxed => const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180.0,
        childAspectRatio: 0.55,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
      ),
      ViewMode.compact => const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 120.0,
        childAspectRatio: 0.68,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
    };

    return SliverPadding(
      padding: EdgeInsets.fromLTRB(
        widget.horizontalPadding / 2,
        16,
        widget.horizontalPadding / 2,
        128,
      ),
      sliver: SliverGrid(
        gridDelegate: delegate,
        delegate: SliverChildBuilderDelegate(
          (context, index) => _buildCell(context, index),
          childCount: widget.items.length,
        ),
      ),
    );
  }

  Widget _buildCell(BuildContext context, int index) {
    final item = widget.items[index];
    final cell = widget.itemBuilder(context, item);

    if (!widget.dragEnabled || widget.items.length < 2) {
      return KeyedSubtree(key: widget.itemKey(item), child: cell);
    }

    return LongPressDraggable<T>(
      key: widget.itemKey(item),
      data: item,
      hapticFeedbackOnStart: true,
      feedback: _buildGhost(context, item),
      childWhenDragging: Opacity(opacity: 0.35, child: cell),
      onDragStarted: () {
        HapticFeedback.selectionClick();
        setState(() => _dragIndex = index);
      },
      onDragUpdate: (details) => _handleAutoScroll(details.globalPosition),
      onDragEnd: (_) => setState(() => _dragIndex = null),
      onDraggableCanceled: (_, _) => setState(() => _dragIndex = null),
      child: DragTarget<T>(
        onWillAcceptWithDetails: (details) {
          final from = _dragIndex;
          if (from == null || from == index) return false;
          final now = DateTime.now();
          if (_lastSwap != null &&
              now.difference(_lastSwap!) < const Duration(milliseconds: 90)) {
            return false;
          }
          _lastSwap = now;
          // Live swap: move the dragged item to this cell's position.
          setState(() => _dragIndex = index);
          widget.onReorder(from, index);
          return false;
        },
        builder: (context, candidates, rejected) => cell,
      ),
    );
  }

  Widget _buildGhost(BuildContext context, T item) {
    final size = _cellSize(context);
    return Material(
      color: Colors.transparent,
      elevation: 8,
      shadowColor: Colors.black45,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: Transform.scale(
          scale: 1.04,
          child: widget.itemBuilder(context, item),
        ),
      ),
    );
  }

  /// Mirrors the layout math of [SliverGridDelegateWithMaxCrossAxisExtent]
  /// so the drag ghost matches the real cell size.
  Size _cellSize(BuildContext context) {
    final crossAxisExtent =
        MediaQuery.sizeOf(context).width - widget.horizontalPadding;
    final (maxExtent, aspect, spacing) = switch (widget.viewMode) {
      ViewMode.relaxed => (180.0, 0.55, 16.0),
      ViewMode.compact => (120.0, 0.68, 8.0),
    };
    final crossAxisCount = math.max(
      1,
      (crossAxisExtent / (maxExtent + spacing)).ceil(),
    );
    final cellWidth =
        (crossAxisExtent - spacing * (crossAxisCount - 1)) / crossAxisCount;
    return Size(cellWidth, cellWidth / aspect);
  }

  void _handleAutoScroll(Offset globalPosition) {
    final scrollable = _scrollable;
    if (scrollable == null || !scrollable.position.hasContentDimensions) {
      return;
    }
    final renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null || !renderBox.hasSize) return;

    const edge = 72.0;
    final top = renderBox.localToGlobal(Offset.zero).dy;
    final bottom = top + renderBox.size.height;
    final position = scrollable.position;
    final maxPixels = position.maxScrollExtent;

    double delta = 0;
    if (globalPosition.dy < top + edge) {
      delta = -((top + edge - globalPosition.dy) / edge) * 12;
    } else if (globalPosition.dy > bottom - edge) {
      delta = ((globalPosition.dy - (bottom - edge)) / edge) * 12;
    }
    if (delta != 0) {
      position.jumpTo(
        (position.pixels + delta).clamp(0.0, maxPixels),
      );
    }
  }
}
