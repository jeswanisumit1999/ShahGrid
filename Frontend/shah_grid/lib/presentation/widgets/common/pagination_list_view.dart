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
    this.emptyWidget,
  });

  final List<T> items;
  final bool hasMore;
  final Widget Function(BuildContext, T) itemBuilder;
  final VoidCallback onLoadMore;
  final Future<void> Function()? onRefresh;
  final EdgeInsets? padding;
  /// Shown when [items] is empty (e.g. "No results for 'xyz'").
  final Widget? emptyWidget;

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
    if (widget.items.isEmpty && widget.emptyWidget != null) {
      if (widget.onRefresh != null) {
        return RefreshIndicator(
          onRefresh: widget.onRefresh!,
          child: ListView(children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.5,
              child: Center(child: widget.emptyWidget!),
            ),
          ]),
        );
      }
      return Center(child: widget.emptyWidget!);
    }

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
