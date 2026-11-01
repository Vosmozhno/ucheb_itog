class PageResult<T> {
  const PageResult({
    required this.items,
    required this.total,
    required this.page,
    required this.pageSize,
  });
  final List<T> items;
  final int total;
  final int page;
  final int pageSize;
  int get totalPages => (total / pageSize).ceil().clamp(1, 1000000);
}
