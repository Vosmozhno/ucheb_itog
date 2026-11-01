enum DeletedFilter { active, deleted, all }

class ListQuery {
  const ListQuery({
    this.keyword = '',
    this.page = 1,
    this.pageSize = 10,
    this.sort = 'id',
    this.ascending = false,
    this.deleted = DeletedFilter.active,
    this.filters = const {},
  });
  final String keyword;
  final int page;
  final int pageSize;
  final String sort;
  final bool ascending;
  final DeletedFilter deleted;
  final Map<String, String> filters;
  factory ListQuery.fromUri(Uri uri) {
    final p = uri.queryParameters;
    return ListQuery(
      keyword: (p['q'] ?? '').trim().substring(
        0,
        (p['q'] ?? '').trim().length.clamp(0, 120),
      ),
      page: (int.tryParse(p['page'] ?? '') ?? 1).clamp(1, 1000000),
      pageSize: [5, 10, 20, 50].contains(int.tryParse(p['size'] ?? ''))
          ? int.parse(p['size']!)
          : 10,
      sort: p['sort'] ?? 'id',
      ascending: p['direction'] == 'asc',
      deleted: DeletedFilter.values.firstWhere(
        (d) => d.name == p['deleted'],
        orElse: () => DeletedFilter.active,
      ),
      filters: {
        for (final e in p.entries)
          if (e.key.startsWith('f_') && e.value.isNotEmpty)
            e.key.substring(2): e.value,
      },
    );
  }
  Map<String, String> get parameters => {
    if (keyword.isNotEmpty) 'q': keyword,
    if (page > 1) 'page': '$page',
    if (pageSize != 10) 'size': '$pageSize',
    if (sort != 'id') 'sort': sort,
    if (ascending) 'direction': 'asc',
    if (deleted != DeletedFilter.active) 'deleted': deleted.name,
    for (final e in filters.entries)
      if (e.value.isNotEmpty) 'f_${e.key}': e.value,
  };
  ListQuery copyWith({
    String? keyword,
    int? page,
    int? pageSize,
    String? sort,
    bool? ascending,
    DeletedFilter? deleted,
    Map<String, String>? filters,
  }) => ListQuery(
    keyword: keyword ?? this.keyword,
    page: page ?? this.page,
    pageSize: pageSize ?? this.pageSize,
    sort: sort ?? this.sort,
    ascending: ascending ?? this.ascending,
    deleted: deleted ?? this.deleted,
    filters: filters ?? this.filters,
  );
}
