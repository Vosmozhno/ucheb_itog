import 'package:flutter/material.dart';
import '../models/list_query.dart';
import '../models/page_result.dart';

class PaginationBar extends StatelessWidget {
  const PaginationBar({
    super.key,
    required this.page,
    required this.query,
    required this.onChanged,
  });
  final PageResult<dynamic> page;
  final ListQuery query;
  final ValueChanged<ListQuery> onChanged;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 18),
    child: Wrap(
      spacing: 12,
      runSpacing: 12,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text(
          'Всего: ${page.total} · Страница ${page.page} из ${page.totalPages}',
        ),
        IconButton(
          tooltip: 'Предыдущая страница',
          onPressed: page.page > 1
              ? () => onChanged(query.copyWith(page: page.page - 1))
              : null,
          icon: const Icon(Icons.chevron_left),
        ),
        IconButton(
          tooltip: 'Следующая страница',
          onPressed: page.page < page.totalPages
              ? () => onChanged(query.copyWith(page: page.page + 1))
              : null,
          icon: const Icon(Icons.chevron_right),
        ),
        SizedBox(
          width: 150,
          child: DropdownButtonFormField<int>(
            initialValue: query.pageSize,
            decoration: const InputDecoration(labelText: 'На странице'),
            items: [
              for (final n in [5, 10, 20, 50])
                DropdownMenuItem(value: n, child: Text('$n')),
            ],
            onChanged: (n) {
              if (n != null) onChanged(query.copyWith(pageSize: n, page: 1));
            },
          ),
        ),
      ],
    ),
  );
}
