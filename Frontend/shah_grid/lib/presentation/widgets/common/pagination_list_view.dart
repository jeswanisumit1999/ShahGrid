import 'package:flutter/material.dart';

/// ListView that fires [onLoadMore] when scrolled near the bottom.
class PaginationListView<T> extends StatefulWidget {
  const PaginationListView({
    super.key,
    required this.items,
    required this.hasMore,
    required this.itemBuilder,
    required this.onLoadMore,
    this.onRefresh,
    this.padding,
  });

  final List<T> items;
  final bool hasMore;
  final Widget Function(BuildContext, T) itemBuilder;
  final VoidCallback onLoadMore;
  final Future<void> Function()? onRefresh;
  final EdgeInsets? padding;

  @override
  State<PaginationListView<T>> createState() => _PaginationListViewState<T>();
}

class _PaginationListViewState<T> extends State<PaginationListView<T>> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onScroll);
  }

  void _onScroll() {
    if (_controller.position.pixels >= _controller.position.maxScrollExtent - 200) {
      widget.onLoadMore();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = ListView.builder(
      controller: _controller,
      padding: widget.padding,
      itemCount: widget.items.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (ctx, i) {
        if (i == widget.items.length) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        return widget.itemBuilder(ctx, widget.items[i]);
      },
    );

    if (widget.onRefresh != null) {
      return RefreshIndicator(onRefresh: widget.onRefresh!, child: child);
    }
    return child;
  }
}
