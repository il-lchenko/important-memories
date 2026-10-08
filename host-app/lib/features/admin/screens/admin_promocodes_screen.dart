import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../../core/api_client.dart';
import '../../../core/tokens.dart';

final _adminPromocodesProvider = FutureProvider.autoDispose((ref) async {
  final dio = ref.watch(dioProvider);
  final resp = await dio.get('admin/promocodes');
  return (resp.data as List).cast<Map<String, dynamic>>();
});

class AdminPromocodesScreen extends ConsumerStatefulWidget {
  const AdminPromocodesScreen({super.key});
  @override
  ConsumerState<AdminPromocodesScreen> createState() => _AdminPromocodesScreenState();
}

class _AdminPromocodesScreenState extends ConsumerState<AdminPromocodesScreen> {
  @override
  Widget build(BuildContext context) {
    final async = ref.watch(_adminPromocodesProvider);
    return Scaffold(
      backgroundColor: AppColors.paper,
      appBar: AppBar(
        backgroundColor: AppColors.paper,
        elevation: 0,
        title: Text('Промокоды',
            style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()],
                fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openCreateDialog(context),
        backgroundColor: AppColors.ink,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('Создать', style: TextStyle(fontFamily: 'Inter', fontWeight: FontWeight.w600)),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator(color: AppColors.amber)),
        error: (e, _) => Center(child: Text(extractUserMessage(e))),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('Пока нет ни одного промокода',
                style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink3)));
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) => _PromoAdminCard(promo: items[i], onDeleted: () {
              ref.invalidate(_adminPromocodesProvider);
            }),
          );
        },
      ),
    );
  }

  Future<void> _openCreateDialog(BuildContext context) async {
    final result = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColors.paper,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => const _CreatePromoSheet(),
    );
    if (result != null) {
      try {
        final dio = ref.read(dioProvider);
        await dio.post('admin/promocodes', data: result);
        if (mounted) ref.invalidate(_adminPromocodesProvider);
      } on DioException catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(extractUserMessage(e),
                style: const TextStyle(fontFamily: 'Inter', fontSize: 14)),
            backgroundColor: AppColors.shutter,
          ));
        }
      }
    }
  }
}

class _PromoAdminCard extends ConsumerWidget {
  final Map<String, dynamic> promo;
  final VoidCallback onDeleted;
  const _PromoAdminCard({required this.promo, required this.onDeleted});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final code = promo['code'] as String;
    final kind = promo['kind'] as String;
    final discountType = promo['discount_type'] as String;
    final discountValue = promo['discount_value'] as int;
    final redemptionsCount = promo['redemptions_count'] as int? ?? 0;
    final maxRedemptions = promo['max_redemptions'] as int?;
    final expiresAt = promo['expires_at'] as String?;
    final expiredAt = expiresAt != null ? DateTime.tryParse(expiresAt)?.toLocal() : null;

    final discountLabel = discountType == 'percent'
        ? '$discountValue%'
        : '${(discountValue / 100).toStringAsFixed(0)} ₽';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.paper2,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(code,
                        style: const TextStyle(
                            fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w700,
                            color: AppColors.ink, letterSpacing: 0.5)),
                    const SizedBox(width: 8),
                    _KindBadge(kind: kind),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  '$discountLabel · использован ${maxRedemptions == null ? redemptionsCount : "$redemptionsCount/$maxRedemptions"}'
                  '${expiredAt != null ? " · до ${DateFormat('d MMM y', 'ru').format(expiredAt)}" : ""}',
                  style: const TextStyle(fontFamily: 'Inter', fontSize: 12, color: AppColors.ink3),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 20, color: AppColors.shutter),
            onPressed: () => _confirmDelete(context, ref, promo['id'] as String, code),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, String id, String code) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Удалить $code?'),
        content: const Text('Существующие redemptions сохранятся, новые применения будут заблокированы.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Отмена')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Удалить')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final dio = ref.read(dioProvider);
      await dio.delete('admin/promocodes/$id');
      onDeleted();
    } on DioException catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(extractUserMessage(e)),
          backgroundColor: AppColors.shutter,
        ));
      }
    }
  }
}

class _KindBadge extends StatelessWidget {
  final String kind;
  const _KindBadge({required this.kind});
  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      'admin_bypass' => AppColors.amber,
      'referral' => const Color(0xFF4CAF79),
      _ => AppColors.ink3,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(kind.toUpperCase(),
          style: TextStyle(
              fontFamily: 'Inter', fontSize: 10,
              fontWeight: FontWeight.w700, color: color, letterSpacing: 0.4)),
    );
  }
}

class _CreatePromoSheet extends StatefulWidget {
  const _CreatePromoSheet();
  @override
  State<_CreatePromoSheet> createState() => _CreatePromoSheetState();
}

class _CreatePromoSheetState extends State<_CreatePromoSheet> {
  final _codeCtrl = TextEditingController();
  final _valueCtrl = TextEditingController(text: '20');
  final _maxCtrl = TextEditingController();
  final _minAmountCtrl = TextEditingController(text: '0');
  String _kind = 'manual';
  String _discountType = 'percent';
  String _appliesTo = 'all';
  bool _singleUse = true;

  @override
  void dispose() {
    _codeCtrl.dispose();
    _valueCtrl.dispose();
    _maxCtrl.dispose();
    _minAmountCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Новый промокод',
                style: GoogleFonts.playfairDisplay(fontFeatures: [const FontFeature.liningFigures()],
                    fontSize: 22, fontWeight: FontWeight.w600, color: AppColors.ink)),
            const SizedBox(height: 16),
            _label('Код'),
            TextField(
              controller: _codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: _dec(hint: 'WELCOME20'),
              style: const TextStyle(fontFamily: 'Inter', fontSize: 15, letterSpacing: 0.5),
            ),
            const SizedBox(height: 12),
            _label('Тип'),
            _DropdownRow(
              value: _kind,
              items: const {'manual': 'MANUAL', 'admin_bypass': 'ADMIN_BYPASS', 'referral': 'REFERRAL'},
              onChanged: (v) => setState(() => _kind = v),
            ),
            const SizedBox(height: 12),
            _label('Скидка'),
            Row(
              children: [
                Expanded(
                  child: _DropdownRow(
                    value: _discountType,
                    items: const {'percent': '%', 'fixed': 'фикс. ₽ (копейки)'},
                    onChanged: (v) => setState(() => _discountType = v),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _valueCtrl,
                    keyboardType: TextInputType.number,
                    decoration: _dec(hint: _discountType == 'percent' ? '20' : '10000 (=100₽)'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            _label('Действует на'),
            _DropdownRow(
              value: _appliesTo,
              items: const {'all': 'Всё', 'checkout': 'Первая оплата', 'extend': 'Продление', 'upgrade': 'Апгрейд'},
              onChanged: (v) => setState(() => _appliesTo = v),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Лимит применений'),
                      TextField(
                        controller: _maxCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _dec(hint: 'без лимита'),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _label('Мин. сумма (коп.)'),
                      TextField(
                        controller: _minAmountCtrl,
                        keyboardType: TextInputType.number,
                        decoration: _dec(hint: '0'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              activeColor: AppColors.amber,
              value: _singleUse,
              onChanged: (v) => setState(() => _singleUse = v),
              title: const Text('Один раз на юзера',
                  style: TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink)),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  final code = _codeCtrl.text.trim();
                  final value = int.tryParse(_valueCtrl.text.trim());
                  if (code.length < 3 || value == null || value <= 0) return;
                  Navigator.of(context).pop({
                    'code': code,
                    'kind': _kind,
                    'discount_type': _discountType,
                    'discount_value': value,
                    'applies_to': _appliesTo,
                    'min_amount_kopecks': int.tryParse(_minAmountCtrl.text.trim()) ?? 0,
                    if (_maxCtrl.text.trim().isNotEmpty)
                      'max_redemptions': int.tryParse(_maxCtrl.text.trim()),
                    'single_use_per_user': _singleUse,
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.amber,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 0,
                ),
                child: const Text('Создать',
                    style: TextStyle(fontFamily: 'Inter', fontSize: 15, fontWeight: FontWeight.w600)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _label(String s) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(s.toUpperCase(),
          style: const TextStyle(fontFamily: 'Inter', fontSize: 11, letterSpacing: 0.4,
              fontWeight: FontWeight.w600, color: AppColors.ink3)));
  InputDecoration _dec({required String hint}) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontFamily: 'Inter', fontSize: 14, color: AppColors.ink4),
      filled: true, fillColor: AppColors.paper2,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none));
}

class _DropdownRow extends StatelessWidget {
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;
  const _DropdownRow({required this.value, required this.items, required this.onChanged});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: AppColors.paper2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: DropdownButtonHideUnderline(
          child: DropdownButton<String>(
            value: value,
            isExpanded: true,
            items: items.entries
                .map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value,
                        style: const TextStyle(fontFamily: 'Inter', fontSize: 14))))
                .toList(),
            onChanged: (v) => v != null ? onChanged(v) : null,
          ),
        ),
      );
}
