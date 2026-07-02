import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/api_client.dart';
import '../../../core/tokens.dart';
import '../../auth/auth_provider.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(currentUserProvider);

    final email = userAsync.maybeWhen(
      data: (u) => u['email'] as String? ?? '',
      orElse: () => '',
    );
    final displayName = userAsync.maybeWhen(
      data: (u) => u['display_name'] as String?,
      orElse: () => null,
    );
    final initial = (displayName?.isNotEmpty == true ? displayName! : email)
        .characters
        .firstOrNull
        ?.toUpperCase() ?? '?';
    final nameLabel = displayName?.isNotEmpty == true
        ? displayName!
        : (email.isNotEmpty ? email.split('@').first : '...');

    return Scaffold(
      backgroundColor: AppColors.paper2,
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 16, left: 0, right: 0),
              padding: const EdgeInsets.only(top: 10, bottom: 16),
              child: Text(
                'Профиль',
                style: GoogleFonts.playfairDisplay(
                  fontWeight: FontWeight.w500,
                  fontSize: 28,
                  letterSpacing: -0.6,
                  color: AppColors.ink,
                ),
              ),
            ),

            _UserCard(
              initial: initial,
              name: nameLabel,
              email: email,
              onTap: () => showModalBottomSheet(
                context: context,
                backgroundColor: Colors.transparent,
                isScrollControlled: true,
                builder: (_) => const _EditNameSheet(),
              ),
            ),
            const SizedBox(height: 24),

            const _SectionTitle('Уведомления'),
            const _ToggleRow(
              label: 'Когда гость снимает',
              desc: 'Push при каждом новом кадре',
              value: true,
            ),
            const _ToggleRow(
              label: 'До проявки 1 час',
              desc: 'Напомнить, что альбом скоро откроется',
              value: true,
            ),
            const _ToggleRow(
              label: 'Email-дайджест',
              desc: 'Сводка после ивента',
              value: false,
            ),

            const _SectionTitle('Помощь'),
            _FaqRow(
              question: 'Что такое «проявка»?',
              answer:
                  'Как настоящая плёночная камера — снимки не показываются сразу. '
                  'Вы выбираете при создании альбома, когда «плёнку проявить»: '
                  'сразу после каждого кадра или в конкретное время после события. '
                  'До проявки гости видят только чёрные квадраты — так интереснее ждать.',
            ),
            _FaqRow(
              question: 'Можно ли изменить плёнку?',
              answer:
                  'Плёнка (Portra 400, Fuji 400H, Cinestill, Ilford HP5) выбирается при '
                  'создании альбома и применяется ко всем кадрам этого события. '
                  'Поменять уже после создания нельзя, чтобы стиль альбома оставался цельным. '
                  'Для нового ощущения — создайте новое событие с другой плёнкой.',
            ),
            _FaqRow(
              question: 'Кто видит фотографии?',
              answer:
                  'Только участники события, у которых есть ссылка или QR-код от вас. '
                  'Все фото хранятся приватно, никаких «публичных лент» или поиска по кадрам. '
                  'Скачать оригиналы могут владелец альбома и авторы своих кадров.',
            ),
            _FaqRow(
              question: 'Сколько хранятся альбомы?',
              answer:
                  'Срок хранения зависит от тарифа: FREE — 14 дней, платные — от 30 до 365 дней. '
                  'Мы напоминаем за 7, 3 и 1 день до истечения. Продлить хранение можно в любой момент '
                  'из настроек альбома (от 490 ₽ за 3 месяца).',
            ),
            _FaqRow(
              question: 'Как работает возврат денег?',
              answer:
                  'Если событие не активировано — возможен возврат в течение 14 дней. '
                  'После активации (получения QR-кода) услуга считается оказанной. '
                  'При техническом сбое на нашей стороне вернём деньги полностью. '
                  'Заявку на возврат отправьте на support@impomento.pro.',
            ),

            const _SectionTitle('О проекте'),
            _FaqRow(
              question: 'Что такое Important Memories?',
              answer:
                  'Цифровая одноразовая камера для свадеб, ДР, корпоративов и любых событий. '
                  'Гости сканируют QR — снимают моменты — вы получаете один общий альбом с плёночной эстетикой. '
                  'Без загрузок, без облачных папок, без каши в чатах.',
            ),
            _FaqRow(
              question: 'Правила использования',
              answer:
                  'Публичная оферта: https://impomento.pro/offer\n'
                  'Политика конфиденциальности: https://impomento.pro/privacy\n\n'
                  'Возраст: 14+. Запрещён контент, нарушающий закон РФ. '
                  'Спорные материалы удаляем по жалобам от пользователей.',
            ),
            _FaqRow(
              question: 'Связаться с поддержкой',
              answer:
                  'Email: support@impomento.pro\n\n'
                  'В теме письма укажите категорию — «Возврат», '
                  '«Технический вопрос», «ПД» или «Другое» — так проще разобрать обращение быстрее.',
            ),

            const SizedBox(height: 18),
            _LogoutButton(
              onTap: () async {
                await ref.read(authProvider.notifier).logout();
                if (context.mounted) context.go('/auth/email');
              },
            ),
            const SizedBox(height: 18),

            const Center(
              child: Text(
                'IM · V0.1 · 2026',
                style: TextStyle(
                  fontFamily: 'JetBrains Mono',
                  fontSize: 10,
                  letterSpacing: 1.4,
                  color: AppColors.ink4,
                ),
              ),
            ),
          ],
        ),
      ),
      // bottomNavigationBar is provided by MainShell (StatefulShellRoute).
    );
  }
}

class _UserCard extends StatelessWidget {
  final String initial;
  final String name;
  final String email;
  final VoidCallback? onTap;
  const _UserCard({required this.initial, required this.name, required this.email, this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFFD4A373), Color(0xFFA6701A)],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: GoogleFonts.playfairDisplay(
                fontSize: 24,
                color: Colors.white,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.playfairDisplay(
                    fontWeight: FontWeight.w500,
                    fontSize: 20,
                    color: AppColors.ink,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  email,
                  style: const TextStyle(
                    fontFamily: 'JetBrains Mono',
                    fontSize: 11,
                    color: AppColors.ink3,
                    letterSpacing: 0.04,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const Icon(Icons.chevron_right, color: AppColors.ink4, size: 18),
        ],
      ),
    ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  final String text;
  const _SectionTitle(this.text);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 8),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontFamily: 'JetBrains Mono',
          fontSize: 11,
          letterSpacing: 1.6,
          color: AppColors.ink3,
        ),
      ),
    );
  }
}

class _ToggleRow extends StatefulWidget {
  final String label;
  final String desc;
  final bool value;
  const _ToggleRow({required this.label, required this.desc, required this.value});

  @override
  State<_ToggleRow> createState() => _ToggleRowState();
}

class _ToggleRowState extends State<_ToggleRow> {
  late bool _val;

  @override
  void initState() {
    super.initState();
    _val = widget.value;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
      decoration: BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.label,
                    style: const TextStyle(
                        fontFamily: 'Inter',
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: AppColors.ink)),
                const SizedBox(height: 2),
                Text(widget.desc,
                    style: const TextStyle(
                        fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3)),
              ],
            ),
          ),
          Switch(
            value: _val,
            onChanged: (v) => setState(() => _val = v),
            activeColor: AppColors.amber,
            activeTrackColor: AppColors.amber.withValues(alpha: 0.3),
          ),
        ],
      ),
    );
  }
}

class _FaqRow extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqRow({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => showModalBottomSheet(
        context: context,
        backgroundColor: Colors.transparent,
        isScrollControlled: true,
        builder: (_) => _FaqSheet(question: question, answer: answer),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        decoration: BoxDecoration(
          color: AppColors.paper,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                question,
                style: const TextStyle(
                    fontFamily: 'Inter',
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: AppColors.ink),
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.ink4, size: 18),
          ],
        ),
      ),
    );
  }
}

class _FaqSheet extends StatelessWidget {
  final String question;
  final String answer;
  const _FaqSheet({required this.question, required this.answer});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).padding.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(24, 12, 24, 24 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: AppColors.paper3,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            question,
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            answer,
            style: GoogleFonts.manrope(
              fontSize: 14.5,
              color: AppColors.ink2,
              height: 1.55,
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}

class _LogoutButton extends StatelessWidget {
  final VoidCallback onTap;
  const _LogoutButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: AppSizes.buttonHeight,
        decoration: BoxDecoration(
          color: AppColors.shutter.withValues(alpha: 0.10),
          border: Border.all(color: AppColors.shutter.withValues(alpha: 0.35), width: 1.2),
          borderRadius: AppRadius.mdBR,
        ),
        alignment: Alignment.center,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: const [
            Icon(Icons.logout, size: 18, color: AppColors.shutter),
            SizedBox(width: 8),
            Text(
              'Выйти из аккаунта',
              style: TextStyle(
                fontFamily: 'Inter',
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: AppColors.shutter,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── edit name sheet ──────────────────────────────────────────────────────────

class _EditNameSheet extends ConsumerStatefulWidget {
  const _EditNameSheet();

  @override
  ConsumerState<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends ConsumerState<_EditNameSheet> {
  late TextEditingController _ctrl;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final user = ref.read(currentUserProvider).valueOrNull;
    _ctrl = TextEditingController(text: user?['display_name'] as String? ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _ctrl.text.trim();
    setState(() { _saving = true; _error = null; });
    try {
      final dio = ref.read(dioProvider);
      await dio.patch('users/me', data: {'display_name': name.isEmpty ? null : name});
      ref.invalidate(currentUserProvider);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) setState(() => _error = extractUserMessage(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(20, 12, 20, bottom > 0 ? bottom + 16 : 36),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            decoration: BoxDecoration(color: AppColors.line, borderRadius: BorderRadius.circular(2)),
          ),
          const SizedBox(height: 20),
          Text(
            'Имя профиля',
            style: GoogleFonts.playfairDisplay(
              fontSize: 22,
              fontWeight: FontWeight.w500, color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _ctrl,
            autofocus: true,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            style: const TextStyle(fontFamily: 'Inter', fontSize: 16, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: 'Имя Фамилия',
              hintStyle: const TextStyle(fontFamily: 'Inter', color: AppColors.ink4),
              filled: true,
              fillColor: AppColors.paper2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: AppColors.amber, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(_error!, style: const TextStyle(fontFamily: 'Inter', fontSize: 13, color: AppColors.shutter)),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _saving ? null : _save,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.amber,
                disabledBackgroundColor: AppColors.amber.withValues(alpha: 0.5),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                elevation: 0,
              ),
              child: _saving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Сохранить', style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }
}
