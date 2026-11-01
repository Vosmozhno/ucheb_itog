import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../data/entity_definitions.dart';
import '../widgets/page_frame.dart';

const entityIcons = <String, IconData>{
  'categories': Icons.category_outlined,
  'brands': Icons.factory_outlined,
  'locations': Icons.storefront_outlined,
  'equipment': Icons.backpack_outlined,
  'units': Icons.inventory_2_outlined,
  'customers': Icons.people_outline,
  'loyalty_cards': Icons.card_membership_outlined,
  'services': Icons.room_service_outlined,
  'rentals': Icons.calendar_month_outlined,
};

class ManageScreen extends StatelessWidget {
  const ManageScreen({super.key});
  @override
  Widget build(BuildContext context) => PageFrame(
    title: 'Справочники',
    subtitle: 'Снаряжение, пункты проката и всё необходимое для работы.',
    child: LayoutBuilder(
      builder: (context, c) => Wrap(
        spacing: 16,
        runSpacing: 16,
        children: [
          for (final d in entityDefinitions)
            SizedBox(
              width: c.maxWidth >= 1000
                  ? (c.maxWidth - 32) / 3
                  : c.maxWidth >= 600
                  ? (c.maxWidth - 16) / 2
                  : c.maxWidth,
              child: Card(
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => context.go('/manage/${d.key}'),
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          entityIcons[d.key],
                          size: 30,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          d.title,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 8),
                        const Row(
                          children: [
                            Text('Открыть список'),
                            SizedBox(width: 8),
                            Icon(Icons.arrow_forward, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    ),
  );
}
