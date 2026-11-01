class RentalQuote {
  RentalQuote(this.values);
  final Map<String, dynamic> values;
  int get days => (values['days'] as num).toInt();
  int get discount => (values['discount_percent'] as num).toInt();
  num get total => values['total_cost'] as num;
  num get deposit => values['deposit'] as num;
  num get dueNow => values['due_now'] as num;
}

// Pure preview rule, tested independently. The server always calculates the final quote.
class TariffPreview {
  static ({num base, int discount, num total, num deposit, num dueNow})
  calculate({
    required int days,
    required int dailyRate,
    int loyalty = 0,
    int services = 0,
    int deposit = 0,
  }) {
    if (days < 1 ||
        days > 90 ||
        dailyRate < 0 ||
        services < 0 ||
        deposit < 0 ||
        loyalty < 0 ||
        loyalty > 10) {
      throw ArgumentError('Недопустимые параметры тарифа');
    }
    final duration = days >= 14
        ? 15
        : days >= 7
        ? 10
        : 0;
    final discount = (duration + loyalty).clamp(0, 20);
    final base = dailyRate * days;
    final total = (base * (100 - discount) + services * 100) / 100;
    return (
      base: base,
      discount: discount,
      total: total,
      deposit: deposit,
      dueNow: total + deposit,
    );
  }
}
