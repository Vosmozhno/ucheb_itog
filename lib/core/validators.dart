import '../models/entity_definition.dart';
import 'dates.dart';

abstract final class Validators {
  static String? email(String? input) {
    final value = (input ?? '').trim();
    if (value.isEmpty) return 'Обязательное поле';
    if (value.length > 254 ||
        !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
      return 'Введите корректную почту';
    }
    return null;
  }

  static String? password(String? value) {
    if (value == null || value.isEmpty) return 'Обязательное поле';
    if (value.length < 8) return 'Не менее 8 символов';
    if (value.length > 72) return 'Не более 72 символов';
    if (!RegExp(r'[A-Za-zА-Яа-я]').hasMatch(value) ||
        !RegExp(r'[0-9]').hasMatch(value)) {
      return 'Используйте буквы и цифры';
    }
    return null;
  }

  static String? field(FieldSpec field, Object? input) {
    final value = input?.toString().trim() ?? '';
    if (field.kind == FieldKind.multiReference) {
      final list = input is List ? input : [];
      if (field.required && list.isEmpty) return 'Выберите хотя бы одну запись';
      if (list.length > 20) return 'Выберите не более 20 записей';
      return null;
    }
    if (value.isEmpty) return field.required ? 'Обязательное поле' : null;
    switch (field.kind) {
      case FieldKind.integer:
        final number = int.tryParse(value);
        if (number == null) return 'Введите целое число';
        if (number < field.min || number > field.max) {
          return 'От ${field.min} до ${field.max}';
        }
      case FieldKind.reference:
        if ((int.tryParse(value) ?? 0) <= 0) return 'Выберите запись из списка';
      case FieldKind.choice:
        if (!field.choices.containsKey(value)) {
          return 'Выберите значение из списка';
        }
      case FieldKind.date:
        if (parseDate(value) == null) return 'Дата в формате ГГГГ-ММ-ДД';
      case FieldKind.text || FieldKind.email || FieldKind.phone:
        if (value.length < field.min) return 'Не менее ${field.min} символов';
        if (value.length > field.max) return 'Не более ${field.max} символов';
        if (field.kind == FieldKind.email) return email(value);
        if (field.kind == FieldKind.phone &&
            (!RegExp(r'^\+?[0-9 ()-]+$').hasMatch(value) ||
                !RegExp(
                  r'^\d{10,15}$',
                ).hasMatch(value.replaceAll(RegExp(r'\D'), '')))) {
          return 'Телефон должен содержать от 10 до 15 цифр';
        }
        if (['sku', 'inventory_code'].contains(field.key) &&
            !RegExp(
              r'^[A-Z0-9][A-Z0-9-]{2,29}$',
            ).hasMatch(value.toUpperCase())) {
          return 'Латинские буквы, цифры и дефисы: от 3 до 30';
        }
        if (field.key == 'number' &&
            !RegExp(r'^TR-\d{6}$').hasMatch(value.toUpperCase())) {
          return 'Формат: TR-000001';
        }
      case FieldKind.multiReference:
        break;
    }
    return null;
  }

  static Map<String, String> record(
    EntityDefinition definition,
    Map<String, dynamic> values, {
    DateTime? now,
  }) {
    final errors = <String, String>{};
    for (final f in definition.fields) {
      final error = field(f, values[f.key]);
      if (error != null) errors[f.key] = error;
    }
    final today = businessToday(now);
    if (definition.key == 'units') {
      final date = parseDate(values['acquired_on']);
      if (date != null && date.isAfter(today)) {
        errors['acquired_on'] = 'Дата не может быть в будущем';
      }
    }
    if (definition.key == 'loyalty_cards') {
      final first = parseDate(values['issued_on']),
          last = parseDate(values['expires_on']);
      if (first != null && last != null && !last.isAfter(first)) {
        errors['expires_on'] = 'Должна быть позже даты выдачи';
      }
    }
    if (definition.key == 'rentals') {
      final first = parseDate(values['start_on']),
          last = parseDate(values['end_on']);
      if (first != null && first.isBefore(today)) {
        errors['start_on'] = 'Начало аренды не может быть в прошлом';
      }
      if (first != null &&
          last != null &&
          (last.difference(first).inDays < 1 ||
              last.difference(first).inDays > 90)) {
        errors['end_on'] = 'Продолжительность: от 1 до 90 суток';
      }
    }
    return errors;
  }
}
