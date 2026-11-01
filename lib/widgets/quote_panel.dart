import 'package:flutter/material.dart';
import '../core/dates.dart';
import '../models/rental_quote.dart';

class QuotePanel extends StatelessWidget {
  const QuotePanel({super.key, required this.quote, this.confirmed = true});
  final RentalQuote quote;
  final bool confirmed;
  @override
  Widget build(BuildContext context) => Card(
    color: const Color(0xFFF0F5EC),
    child: Padding(
      padding: const EdgeInsets.all(22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            confirmed ? 'Стоимость аренды' : 'Предварительная стоимость',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 16),
          _line(
            'Снаряжение · ${quote.days} сут.',
            money(quote.values['base_cost']),
          ),
          _line(
            'Скидка ${quote.discount} %',
            '−${money(quote.values['discount_amount'])}',
          ),
          _line('Дополнительные услуги', money(quote.values['services_cost'])),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(),
          ),
          _line('Аренда и услуги', money(quote.total), bold: true),
          _line('Возвратный залог', money(quote.deposit)),
          const SizedBox(height: 8),
          _line('К внесению при получении', money(quote.dueNow), bold: true),
          const SizedBox(height: 14),
          const Text(
            'Залог возвращается после приёмки снаряжения. Оплата производится в пункте проката.',
            style: TextStyle(fontSize: 12, height: 1.5),
          ),
          if (!confirmed) ...[
            const SizedBox(height: 8),
            const Text(
              'Перед бронированием получите актуальный расчёт.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        ],
      ),
    ),
  );
  Widget _line(String label, String value, {bool bold = false}) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontWeight: bold ? FontWeight.w700 : FontWeight.w400,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: TextStyle(
            fontWeight: bold ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ],
    ),
  );
}
