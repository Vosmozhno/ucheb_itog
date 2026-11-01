import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/api_error.dart';
import '../core/app_theme.dart';
import '../core/validators.dart';
import '../data/entity_definitions.dart';
import '../state/auth_state.dart';
import '../widgets/data_states.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, this.register = false, this.next});
  final bool register;
  final String? next;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final _name = TextEditingController(),
      _email = TextEditingController(),
      _phone = TextEditingController(),
      _password = TextEditingController(),
      _confirm = TextEditingController();
  bool _busy = false, _obscure = true, _sent = false;
  String? _error;
  Map<String, String> _serverFields = {};
  void _clearField(String key) {
    if (_serverFields.containsKey(key)) {
      setState(() => _serverFields.remove(key));
    }
  }

  @override
  void dispose() {
    for (final c in [_name, _email, _phone, _password, _confirm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy || !_form.currentState!.validate()) return;
    setState(() {
      _busy = true;
      _error = null;
      _serverFields.clear();
    });
    final auth = context.read<AuthState>();
    try {
      if (widget.register) {
        final signedIn = await auth.register(
          fullName: _name.text,
          email: _email.text,
          phone: _phone.text,
          password: _password.text,
        );
        if (mounted && !signedIn) setState(() => _sent = true);
      } else {
        await auth.login(_email.text, _password.text);
      }
    } on ApiError catch (e) {
      if (mounted) {
        setState(() {
          _error = e.message;
          _serverFields = {...e.fields};
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      body: SafeArea(
        child: Row(
          children: [
            if (wide)
              Expanded(
                child: Container(
                  color: AppTheme.forest,
                  padding: const EdgeInsets.all(64),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.terrain,
                        size: 72,
                        color: Color(0xFFD8E9BD),
                      ),
                      const SizedBox(height: 32),
                      const Text(
                        'Ближе\nк природе.',
                        style: TextStyle(
                          fontSize: 56,
                          height: 1.12,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 24),
                      const Text(
                        'Снаряжение для новых маршрутов.\nУдобное бронирование. Больше впечатлений.',
                        style: TextStyle(
                          fontSize: 18,
                          height: 1.65,
                          color: Color(0xFFDDE9DE),
                        ),
                      ),
                      const SizedBox(height: 48),
                      Wrap(
                        spacing: 12,
                        runSpacing: 12,
                        children: [
                          for (final text in [
                            'Палатки',
                            'Рюкзаки',
                            'Походная кухня',
                          ])
                            Chip(
                              label: Text(text),
                              backgroundColor: const Color(0xFFE5EEE3),
                              side: BorderSide.none,
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            Expanded(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: Form(
                      key: _form,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.terrain,
                                color: AppTheme.forest,
                                size: 30,
                              ),
                              SizedBox(width: 10),
                              Text(
                                'ПОХОД',
                                style: TextStyle(
                                  fontSize: 23,
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 2,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 36),
                          Text(
                            widget.register
                                ? 'Начнём новый маршрут'
                                : 'С возвращением',
                            style: Theme.of(context).textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            widget.register
                                ? 'Создайте аккаунт, чтобы бронировать снаряжение.'
                                : 'Войдите, чтобы продолжить работу с прокатом.',
                          ),
                          const SizedBox(height: 28),
                          if (_sent) ...[
                            const Card(
                              child: Padding(
                                padding: EdgeInsets.all(20),
                                child: Text(
                                  'Проверьте почту и подтвердите адрес по ссылке из письма. После подтверждения можно войти.',
                                ),
                              ),
                            ),
                            const SizedBox(height: 20),
                            FilledButton(
                              onPressed: () => context.go('/login'),
                              child: const Text('Перейти ко входу'),
                            ),
                          ] else ...[
                            if (_error != null) ...[
                              ErrorNotice(message: _error!),
                              const SizedBox(height: 16),
                            ],
                            if (widget.register) ...[
                              TextFormField(
                                controller: _name,
                                forceErrorText: _serverFields['full_name'],
                                onChanged: (_) => _clearField('full_name'),
                                enabled: !_busy,
                                decoration: const InputDecoration(
                                  labelText: 'Имя и фамилия',
                                ),
                                textCapitalization: TextCapitalization.words,
                                validator: (v) =>
                                    v == null || v.trim().length < 2
                                    ? 'Не менее 2 символов'
                                    : v.trim().length > 100
                                    ? 'Не более 100 символов'
                                    : null,
                              ),
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _phone,
                                forceErrorText: _serverFields['phone'],
                                onChanged: (_) => _clearField('phone'),
                                enabled: !_busy,
                                keyboardType: TextInputType.phone,
                                decoration: const InputDecoration(
                                  labelText: 'Телефон',
                                  hintText: '+7 900 000-00-00',
                                ),
                                validator: (v) => Validators.field(
                                  definitionOf('customers').field('phone')!,
                                  v,
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],
                            TextFormField(
                              controller: _email,
                              forceErrorText: _serverFields['email'],
                              onChanged: (_) => _clearField('email'),
                              enabled: !_busy,
                              keyboardType: TextInputType.emailAddress,
                              autofillHints: const [AutofillHints.email],
                              decoration: const InputDecoration(
                                labelText: 'Электронная почта',
                              ),
                              validator: Validators.email,
                            ),
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _password,
                              forceErrorText: _serverFields['password'],
                              onChanged: (_) => _clearField('password'),
                              enabled: !_busy,
                              obscureText: _obscure,
                              autofillHints: widget.register
                                  ? const [AutofillHints.newPassword]
                                  : const [AutofillHints.password],
                              textInputAction: widget.register
                                  ? TextInputAction.next
                                  : TextInputAction.done,
                              onFieldSubmitted: (_) {
                                if (!widget.register) _submit();
                              },
                              decoration: InputDecoration(
                                labelText: 'Пароль',
                                helperText: widget.register
                                    ? 'От 8 символов, буквы и цифры'
                                    : null,
                                suffixIcon: IconButton(
                                  tooltip: _obscure
                                      ? 'Показать пароль'
                                      : 'Скрыть пароль',
                                  onPressed: () =>
                                      setState(() => _obscure = !_obscure),
                                  icon: Icon(
                                    _obscure
                                        ? Icons.visibility_outlined
                                        : Icons.visibility_off_outlined,
                                  ),
                                ),
                              ),
                              validator: widget.register
                                  ? Validators.password
                                  : (v) => v == null || v.isEmpty
                                        ? 'Введите пароль'
                                        : null,
                            ),
                            if (widget.register) ...[
                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _confirm,
                                enabled: !_busy,
                                obscureText: true,
                                decoration: const InputDecoration(
                                  labelText: 'Повторите пароль',
                                ),
                                validator: (v) => v != _password.text
                                    ? 'Пароли не совпадают'
                                    : null,
                                onFieldSubmitted: (_) => _submit(),
                              ),
                            ],
                            const SizedBox(height: 24),
                            FilledButton(
                              onPressed: _busy ? null : _submit,
                              child: _busy
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : Text(
                                      widget.register
                                          ? 'Зарегистрироваться'
                                          : 'Войти',
                                    ),
                            ),
                            const SizedBox(height: 16),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => context.go(
                                      widget.register ? '/login' : '/register',
                                    ),
                              child: Text(
                                widget.register
                                    ? 'Уже есть аккаунт? Войти'
                                    : 'Создать аккаунт',
                              ),
                            ),
                          ],
                        ],
                      ),
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
}
