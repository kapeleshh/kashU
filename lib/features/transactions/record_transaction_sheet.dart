import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../core/utils/transaction_validator.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../data/models/transaction_type.dart';
import '../../shared/providers/portfolio_provider.dart';

/// Open the Record-transaction sheet for [assetId]: a sale, a dividend or an
/// interest payment. Resolves to true when something was recorded.
Future<bool> showRecordTransactionSheet(
  BuildContext context, {
  required String assetId,
}) async {
  final recorded = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    // The page colour, so the (surface-filled) input fields stand out.
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => RecordTransactionSheet(assetId: assetId),
  );
  return recorded == true;
}

/// The Activity tab's entry point: choose one of [assets], then record a
/// transaction against it.
Future<void> pickAssetAndRecord(
  BuildContext context,
  List<Asset> assets,
) async {
  final assetId = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
    builder: (_) => _AssetPicker(assets: assets),
  );
  if (assetId == null || !context.mounted) return;
  await showRecordTransactionSheet(context, assetId: assetId);
}

/// Record a sell, dividend or interest payment against one holding.
///
/// A sale is checked against the current holding and writes through
/// [PortfolioWriteService.recordSell], which lowers the quantity in the same
/// compensated write; income goes through
/// [PortfolioWriteService.recordIncome]. Every rule lives in
/// [TransactionValidator], so the inline errors here and the service's own
/// refusals can never disagree.
class RecordTransactionSheet extends ConsumerStatefulWidget {
  final String assetId;

  const RecordTransactionSheet({super.key, required this.assetId});

  @override
  ConsumerState<RecordTransactionSheet> createState() =>
      _RecordTransactionSheetState();
}

class _RecordTransactionSheetState
    extends ConsumerState<RecordTransactionSheet> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _amountController = TextEditingController();
  final _notesController = TextEditingController();

  late TransactionType _type;
  late DateTime _date;
  String? _dateError;
  String? _saveError;
  bool _saving = false;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    final asset = ref.read(assetByIdProvider(widget.assetId));
    final now = DateTime.now();
    _date = DateTime(now.year, now.month, now.day);
    _type = asset == null || asset.quantity > 0
        ? TransactionType.sell
        : _defaultIncomeType(asset.type);
    if (asset != null && asset.currentPrice > 0) {
      // The latest known price is the likeliest sale price — editable.
      _priceController.text = asset.currentPrice.toStringAsFixed(2);
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _priceController.dispose();
    _amountController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  /// Deposits, bonds and cash pay interest; everything else, dividends.
  static TransactionType _defaultIncomeType(AssetType type) {
    switch (type) {
      case AssetType.fixedDeposit:
      case AssetType.bond:
      case AssetType.cash:
        return TransactionType.interest;
      default:
        return TransactionType.dividend;
    }
  }

  static double? _parse(String text) => double.tryParse(text.trim());

  /// [quantity] as text that parses back to exactly [quantity]. The display
  /// format rounds to 4 decimals, which for a coin holding could read as
  /// slightly *more* than is held and be refused as an over-sell.
  static String _exactQuantityText(double quantity) {
    final pretty = CurrencyFormatter.formatQuantity(quantity);
    return double.tryParse(pretty) == quantity ? pretty : quantity.toString();
  }

  /// 'unit', 'gram', 'coin' — for "Price per …".
  static String _singular(String unitLabel) {
    if (unitLabel.isEmpty) return 'unit';
    return unitLabel.endsWith('s')
        ? unitLabel.substring(0, unitLabel.length - 1)
        : unitLabel;
  }

  String _symbol(Asset asset) =>
      '${AppConstants.currencies[asset.currency] ?? asset.currency} ';

  @override
  Widget build(BuildContext context) {
    final asset = ref.watch(assetByIdProvider(widget.assetId));
    if (asset == null) {
      // Deleted underneath us — nothing left to record against.
      if (!_closing) {
        _closing = true;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) Navigator.of(context).maybePop();
        });
      }
      return const SizedBox.shrink();
    }

    final isSell = _type == TransactionType.sell;
    final unit = asset.type.unitLabel;
    final holdingText =
        '${CurrencyFormatter.formatQuantity(asset.quantity)}${unit.isEmpty ? '' : ' $unit'}';

    return Padding(
      // Lift the form above the keyboard.
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const _SheetHandle(),
              const SizedBox(height: 16),
              Text(
                'Record transaction',
                style: AppTheme.heading(
                  size: 20,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${asset.name} · you hold $holdingText',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTheme.body(
                  size: 12.5,
                  weight: FontWeight.w700,
                  color: AppColors.textSecondaryOn(context),
                ),
              ),
              const SizedBox(height: 16),

              // Sell / Dividend / Interest
              Row(
                children: [
                  for (final type in const [
                    TransactionType.sell,
                    TransactionType.dividend,
                    TransactionType.interest,
                  ]) ...[
                    if (type != TransactionType.sell) const SizedBox(width: 9),
                    _TypePill(
                      label: type.displayName,
                      isSelected: _type == type,
                      // Nothing left to sell once the holding is closed.
                      enabled:
                          type != TransactionType.sell || asset.quantity > 0,
                      onTap: () => setState(() {
                        _type = type;
                        _saveError = null;
                      }),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 18),

              if (isSell) ...[
                TextFormField(
                  key: const ValueKey('sell-quantity'),
                  controller: _quantityController,
                  decoration: InputDecoration(
                    labelText: AppStrings.quantity,
                    hintText:
                        'e.g. ${CurrencyFormatter.formatQuantity(asset.quantity)}',
                    suffixText: unit.isEmpty ? null : unit,
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  validator: (v) => TransactionValidator.sellQuantity(
                      _parse(v ?? ''), asset.quantity),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => setState(() => _quantityController.text =
                        _exactQuantityText(asset.quantity)),
                    child: const Text('Sell all'),
                  ),
                ),
                TextFormField(
                  key: const ValueKey('sell-price'),
                  controller: _priceController,
                  decoration: InputDecoration(
                    labelText: 'Price per ${_singular(unit)}',
                    prefixText: _symbol(asset),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  onChanged: (_) => setState(() {}),
                  validator: (v) =>
                      TransactionValidator.positive(_parse(v ?? '')),
                ),
                _ProceedsLine(
                  quantity: _parse(_quantityController.text),
                  price: _parse(_priceController.text),
                  currency: asset.currency,
                ),
              ] else
                TextFormField(
                  key: const ValueKey('income-amount'),
                  controller: _amountController,
                  decoration: InputDecoration(
                    labelText: _type == TransactionType.dividend
                        ? 'Dividend received'
                        : 'Interest received',
                    prefixText: _symbol(asset),
                  ),
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  validator: (v) =>
                      TransactionValidator.positive(_parse(v ?? '')),
                ),

              const SizedBox(height: 14),
              _DateTile(
                label: isSell ? 'Sale date' : 'Date received',
                date: _date,
                error: _dateError,
                onTap: () => _pickDate(asset),
              ),
              const SizedBox(height: 14),
              TextFormField(
                controller: _notesController,
                decoration: const InputDecoration(
                  labelText: '${AppStrings.notes} (Optional)',
                ),
                maxLines: 2,
              ),

              if (_saveError != null) ...[
                const SizedBox(height: 12),
                Text(
                  _saveError!,
                  style: AppTheme.body(
                    size: 12.5,
                    color: AppColors.lossOn(context),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              _SaveButton(
                label: switch (_type) {
                  TransactionType.sell => 'Record sale',
                  TransactionType.dividend => 'Record dividend',
                  _ => 'Record interest',
                },
                busy: _saving,
                onTap: () => _save(asset),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _pickDate(Asset asset) async {
    final today = DateTime.now();
    final lastDate = DateTime(today.year, today.month, today.day);
    final purchased = DateTime(asset.purchaseDate.year,
        asset.purchaseDate.month, asset.purchaseDate.day);
    // A purchase dated in the future would invert the range; the validator
    // still reports it, the picker just must not assert.
    final firstDate = purchased.isAfter(lastDate) ? lastDate : purchased;
    final initial = _date.isBefore(firstDate)
        ? firstDate
        : (_date.isAfter(lastDate) ? lastDate : _date);
    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: firstDate,
      lastDate: lastDate,
    );
    if (picked != null && mounted) {
      setState(() {
        _date = picked;
        _dateError = null;
      });
    }
  }

  Future<void> _save(Asset asset) async {
    if (_saving) return;
    final dateError =
        TransactionValidator.date(_date, purchaseDate: asset.purchaseDate);
    final fieldsOk = _formKey.currentState!.validate();
    setState(() {
      _dateError = dateError;
      _saveError = null;
    });
    if (!fieldsOk || dateError != null) return;

    setState(() => _saving = true);
    final writes = ref.read(portfolioWriteServiceProvider);
    final notes = _notesController.text;
    final String message;
    try {
      if (_type == TransactionType.sell) {
        final quantity = _parse(_quantityController.text)!;
        final price = _parse(_priceController.text)!;
        await writes.recordSell(
          assetId: asset.id,
          quantity: quantity,
          pricePerUnit: price,
          date: _date,
          notes: notes,
        );
        final closed =
            TransactionValidator.remainingAfterSell(asset.quantity, quantity) ==
                0;
        message = closed
            ? 'Sale recorded — ${asset.name} is fully sold'
            : 'Sale recorded: ${CurrencyFormatter.formatQuantity(quantity)} '
                'for ${CurrencyFormatter.formatCurrency(quantity * price, asset.currency)}';
      } else {
        final amount = _parse(_amountController.text)!;
        await writes.recordIncome(
          assetId: asset.id,
          type: _type,
          amount: amount,
          date: _date,
          notes: notes,
        );
        message = '${_type.displayName} of '
            '${CurrencyFormatter.formatCurrency(amount, asset.currency)} recorded';
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = e is ArgumentError
            ? '${e.message}'
            : 'Could not record this transaction. Please try again.';
      });
      return;
    }

    if (!mounted) return;
    // Providers don't observe Hive — refresh everything that shows holdings.
    ref.invalidate(allAssetsProvider);
    ref.invalidate(portfolioSummaryProvider);
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop(true);
    messenger.showSnackBar(SnackBar(content: Text(message)));
  }
}

// ─── Pieces ──────────────────────────────────────────────────────────────────

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: AppColors.textTertiaryOn(context).withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Soft selectable pill — matches the Activity filter chips.
class _TypePill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool enabled;
  final VoidCallback onTap;

  const _TypePill({
    required this.label,
    required this.isSelected,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: AnimatedContainer(
          duration: AppConstants.animationFast,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          decoration: BoxDecoration(
            gradient: isSelected ? AppColors.primaryGradient : null,
            color: isSelected ? null : Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(AppRadii.pill),
            boxShadow: isSelected
                ? AppShadows.glow(AppColors.primary, opacity: 0.40)
                : AppShadows.soft(opacity: 0.12, y: 6, blur: 14),
          ),
          child: Text(
            label,
            style: AppTheme.body(
              size: 12.5,
              weight: FontWeight.w800,
              color: isSelected
                  ? Colors.white
                  : AppColors.textSecondaryOn(context),
            ),
          ),
        ),
      ),
    );
  }
}

/// Live "Proceeds" figure under the sale fields, once both parse.
class _ProceedsLine extends StatelessWidget {
  final double? quantity;
  final double? price;
  final String currency;

  const _ProceedsLine({
    required this.quantity,
    required this.price,
    required this.currency,
  });

  @override
  Widget build(BuildContext context) {
    final q = quantity;
    final p = price;
    if (q == null ||
        p == null ||
        !q.isFinite ||
        !p.isFinite ||
        q <= 0 ||
        p <= 0) {
      return const SizedBox(height: 4);
    }
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Text(
        'Proceeds ${CurrencyFormatter.formatCurrency(q * p, currency)}',
        style: AppTheme.body(
          size: 12.5,
          weight: FontWeight.w700,
          color: AppColors.textSecondaryOn(context),
        ),
      ),
    );
  }
}

class _DateTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final String? error;
  final VoidCallback onTap;

  const _DateTile({
    required this.label,
    required this.date,
    required this.error,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: Theme.of(context).colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadii.small),
            side: error == null
                ? BorderSide.none
                : BorderSide(color: AppColors.error),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label,
                          style: AppTheme.body(
                            size: 12,
                            color: AppColors.textSecondaryOn(context),
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          TransactionValidator.formatDate(date),
                          style: AppTheme.body(
                            size: 15,
                            weight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.calendar_today_rounded,
                      size: 18, color: AppColors.textSecondaryOn(context)),
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6, left: 16),
            child: Text(
              error!,
              style: AppTheme.body(size: 12, color: AppColors.error),
            ),
          ),
      ],
    );
  }
}

/// Indigo→lavender gradient CTA, as on the add-asset form.
class _SaveButton extends StatelessWidget {
  final String label;
  final bool busy;
  final VoidCallback onTap;

  const _SaveButton({
    required this.label,
    required this.busy,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.5),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadii.tile),
          onTap: busy ? null : onTap,
          child: SizedBox(
            height: 52,
            width: double.infinity,
            child: Center(
              child: busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      label,
                      style: AppTheme.heading(size: 16, color: Colors.white),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Which holding?" list for the Activity tab's entry point.
class _AssetPicker extends StatelessWidget {
  final List<Asset> assets;

  const _AssetPicker({required this.assets});

  @override
  Widget build(BuildContext context) {
    final sorted = [...assets]
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 14),
          const _SheetHandle(),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'Record for which holding?',
              style: AppTheme.heading(
                size: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
              itemCount: sorted.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) {
                final asset = sorted[i];
                final unit = asset.type.unitLabel;
                final holding = asset.quantity > 0
                    ? '${CurrencyFormatter.formatQuantity(asset.quantity)}'
                        '${unit.isEmpty ? '' : ' $unit'} · ${asset.type.displayName}'
                    : 'Sold · ${asset.type.displayName}';
                return Material(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: () => Navigator.of(context).pop(asset.id),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 13, vertical: 11),
                      child: Row(
                        children: [
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              gradient: softAvatarGradient(asset.type.color),
                              borderRadius:
                                  BorderRadius.circular(AppRadii.avatar),
                            ),
                            child: Icon(asset.type.icon,
                                color: Colors.white, size: 18),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  asset.name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.heading(
                                    size: 14,
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                                Text(
                                  holding,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTheme.body(
                                    size: 11,
                                    weight: FontWeight.w600,
                                    color: AppColors.textSecondaryOn(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Icon(Icons.chevron_right_rounded,
                              color: AppColors.textTertiaryOn(context)),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
