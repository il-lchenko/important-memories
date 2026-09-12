// Экран управления персональными приглашениями хостом.
// Список активных инвайтов, кнопка «Пригласить лично» (bottom-sheet), удаление,
// поделиться ссылкой через share_plus.
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:share_plus/share_plus.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

class InvitesScreen extends ConsumerStatefulWidget {
  final String eventId;
  const InvitesScreen({super.key, required this.eventId});

  @override
  ConsumerState<InvitesScreen> createState() => _InvitesScreenState();
}

class _InvitesScreenState extends ConsumerState<InvitesScreen> {
  bool _loading = true;
  List<Map<String, dynamic>> _invites = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.get('events/${widget.eventId}/invites');
      if (!mounted) return;
      setState(() {
        _invites = List<Map<String, dynamic>>.from(resp.data as List);
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = extractUserMessage(e);
      });
    }
  }

  Future<void> _delete(String inviteId) async {
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('events/${widget.eventId}/invites/$inviteId');
      await _load();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(extractUserMessage(e)),
          backgroundColor: AppColors.dark3,
        ),
      );
    }
  }

  void _showCreateSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CreateInviteSheet(
        eventId: widget.eventId,
        onCreated: (_) {
          _load();
        },
      ),
    );
  }

  void _shareInvite(Map<String, dynamic> inv) {
    final url = inv['invite_url'] as String?;
    final name = inv['display_name'] as String? ?? 'гостя';
    if (url == null) return;
    Share.share('Приглашение для $name в альбом ImpoMento:\n$url');
  }

  void _copyInvite(Map<String, dynamic> inv) {
    final url = inv['invite_url'] as String?;
    if (url == null) return;
    Clipboard.setData(ClipboardData(text: url));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Ссылка скопирована',
          style: GoogleFonts.inter(fontSize: 13, color: AppColors.paper),
        ),
        backgroundColor: AppColors.dark3,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        surfaceTintColor: AppColors.paper,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.ink),
          onPressed: () => context.pop(),
        ),
        title: Text(
          'Приглашения',
          style: GoogleFonts.inter(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: AppColors.ink,
          ),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColors.amber))
          : RefreshIndicator(
              onRefresh: _load,
              color: AppColors.amber,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 100),
                children: [
                  _HeaderCard(onCreate: _showCreateSheet),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: AppColors.shutter,
                      ),
                    ),
                  ],
                  if (_invites.isEmpty && _error == null) ...[
                    const SizedBox(height: 60),
                    Center(
                      child: Column(
                        children: [
                          const Icon(
                            Icons.mail_outline,
                            size: 48,
                            color: AppColors.ink3,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Пока никого не пригласили',
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              color: AppColors.ink3,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Инвайт-ссылка обходит PIN и лимит альбомов',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: AppColors.ink3,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  for (final inv in _invites)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: _InviteTile(
                        invite: inv,
                        onShare: () => _shareInvite(inv),
                        onCopy: () => _copyInvite(inv),
                        onDelete: () => _confirmDelete(inv),
                      ),
                    ),
                ],
              ),
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSheet,
        backgroundColor: AppColors.amber,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.person_add_alt_1),
        label: const Text(
          'Пригласить',
          style: TextStyle(
            fontFamily: 'Inter',
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  void _confirmDelete(Map<String, dynamic> inv) {
    final name = inv['display_name'] as String? ?? 'гостя';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.paper,
        title: Text(
          'Отозвать приглашение?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: AppColors.ink),
        ),
        content: Text(
          'Ссылка для «$name» перестанет работать.',
          style: GoogleFonts.inter(fontSize: 14, color: AppColors.ink3),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Отмена',
              style: GoogleFonts.inter(color: AppColors.ink2),
            ),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _delete(inv['id'] as String);
            },
            child: Text(
              'Отозвать',
              style: GoogleFonts.inter(color: AppColors.shutter, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}

// ── header explainer card ────────────────────────────────────────────────────
class _HeaderCard extends StatelessWidget {
  final VoidCallback onCreate;
  const _HeaderCard({required this.onCreate});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x141A1714)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.workspace_premium, size: 20, color: AppColors.amber),
              const SizedBox(width: 8),
              Text(
                'Персональные приглашения',
                style: GoogleFonts.inter(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppColors.ink,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Одноразовая ссылка с именем гостя. Обходит PIN и суточный лимит альбомов — используйте когда точно знаете, кого приглашаете.',
            style: GoogleFonts.inter(
              fontSize: 12,
              height: 1.5,
              color: AppColors.ink3,
            ),
          ),
        ],
      ),
    );
  }
}

// ── single invite tile ──────────────────────────────────────────────────────
class _InviteTile extends StatelessWidget {
  final Map<String, dynamic> invite;
  final VoidCallback onShare;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  const _InviteTile({
    required this.invite,
    required this.onShare,
    required this.onCopy,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final name = invite['display_name'] as String? ?? '—';
    final usedAt = invite['used_at'] as String?;
    final expiresAt = invite['expires_at'] as String?;
    final used = usedAt != null;
    final expired = expiresAt != null && DateTime.tryParse(expiresAt)?.isBefore(DateTime.now().toUtc()) == true;
    final inactive = used || expired;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x141A1714)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: inactive
                    ? AppColors.ink3.withValues(alpha: 0.15)
                    : AppColors.amber.withValues(alpha: 0.15),
                child: Icon(
                  Icons.person_outline,
                  color: inactive ? AppColors.ink3 : AppColors.amber,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: inactive ? AppColors.ink3 : AppColors.ink,
                        decoration: used ? TextDecoration.lineThrough : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _statusLine(usedAt, expiresAt),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: inactive ? AppColors.ink3 : AppColors.success,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, color: AppColors.ink3, size: 20),
                onPressed: onDelete,
                tooltip: 'Отозвать',
              ),
            ],
          ),
          if (!inactive) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onCopy,
                    icon: const Icon(Icons.copy, size: 16),
                    label: Text(
                      'Копировать',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.ink,
                      side: const BorderSide(color: Color(0x201A1714)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onShare,
                    icon: const Icon(Icons.share, size: 16),
                    label: Text(
                      'Поделиться',
                      style: GoogleFonts.inter(fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                    style: FilledButton.styleFrom(
                      backgroundColor: AppColors.ink,
                      foregroundColor: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _statusLine(String? usedAt, String? expiresAt) {
    if (usedAt != null) {
      try {
        final dt = DateTime.parse(usedAt).toLocal();
        return 'Использовано ${DateFormat('dd.MM в HH:mm').format(dt)}';
      } catch (_) {
        return 'Использовано';
      }
    }
    if (expiresAt != null) {
      try {
        final dt = DateTime.parse(expiresAt).toLocal();
        if (dt.isBefore(DateTime.now())) return 'Истекло';
        return 'Активна до ${DateFormat('dd.MM').format(dt)}';
      } catch (_) {}
    }
    return 'Активна';
  }
}

// ── create sheet ─────────────────────────────────────────────────────────────
class _CreateInviteSheet extends ConsumerStatefulWidget {
  final String eventId;
  final ValueChanged<Map<String, dynamic>> onCreated;
  const _CreateInviteSheet({required this.eventId, required this.onCreated});

  @override
  ConsumerState<_CreateInviteSheet> createState() => _CreateInviteSheetState();
}

class _CreateInviteSheetState extends ConsumerState<_CreateInviteSheet> {
  final _nameCtrl = TextEditingController();
  int? _ttlDays;
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Введите имя');
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final dio = ref.read(dioProvider);
      final resp = await dio.post(
        'events/${widget.eventId}/invites',
        data: {
          'display_name': name,
          if (_ttlDays != null) 'ttl_days': _ttlDays,
        },
      );
      final invite = Map<String, dynamic>.from(resp.data as Map);
      if (!mounted) return;
      widget.onCreated(invite);
      Navigator.pop(context);
      // Сразу шарим только что созданную ссылку.
      final url = invite['invite_url'] as String?;
      if (url != null) {
        Share.share('Приглашение для $name в альбом ImpoMento:\n$url');
      }
    } on DioException catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.userMessage;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = extractUserMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      decoration: const BoxDecoration(
        color: AppColors.paper,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: const Color(0x201A1714),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Text(
            'Пригласить гостя',
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: AppColors.ink,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Одноразовая ссылка. Гость сможет войти без PIN и без лимита альбомов.',
            style: GoogleFonts.inter(fontSize: 12, color: AppColors.ink3, height: 1.4),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _nameCtrl,
            autofocus: true,
            maxLength: 40,
            style: GoogleFonts.inter(fontSize: 15, color: AppColors.ink),
            decoration: InputDecoration(
              hintText: 'Например, Анна',
              counterText: '',
              filled: true,
              fillColor: AppColors.paper2,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'Срок действия',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.ink2,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              _ttlChip('Без срока', null),
              _ttlChip('7 дней', 7),
              _ttlChip('30 дней', 30),
              _ttlChip('90 дней', 90),
            ],
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Text(
              _error!,
              style: GoogleFonts.inter(fontSize: 13, color: AppColors.shutter),
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            height: 52,
            child: FilledButton(
              onPressed: _loading ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: AppColors.ink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _loading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Создать и поделиться',
                      style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w600),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ttlChip(String label, int? days) {
    final active = _ttlDays == days;
    return ChoiceChip(
      label: Text(
        label,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
          color: active ? Colors.white : AppColors.ink,
        ),
      ),
      selected: active,
      selectedColor: AppColors.ink,
      backgroundColor: AppColors.paper2,
      showCheckmark: false,
      side: BorderSide.none,
      onSelected: (_) => setState(() => _ttlDays = days),
    );
  }
}
