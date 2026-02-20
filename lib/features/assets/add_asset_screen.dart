import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../services/price_service.dart';

class AddAssetScreen extends ConsumerStatefulWidget {
  final Asset? existingAsset;

  const AddAssetScreen({super.key, this.existingAsset});

  @override
  ConsumerState<AddAssetScreen> createState() => _AddAssetScreenState();
}

class _AddAssetScreenState extends ConsumerState<AddAssetScreen> {
  final _formKey = GlobalKey<FormState>();
  
  late TextEditingController _nameController;
  late TextEditingController _symbolController;
  late TextEditingController _quantityController;
  late TextEditingController _purchasePriceController;
  late TextEditingController _currentPriceController;
  late TextEditingController _notesController;
  
  AssetType _selectedType = AssetType.stock;
  String _selectedCurrency = 'INR';
  String? _selectedPlatform;
  DateTime _purchaseDate = DateTime.now();

  bool get isEditing => widget.existingAsset != null;

  @override
  void initState() {
    super.initState();
    final asset = widget.existingAsset;
    
    _nameController = TextEditingController(text: asset?.name ?? '');
    _symbolController = TextEditingController(text: asset?.symbol ?? '');
    _quantityController = TextEditingController(text: asset?.quantity.toString() ?? '');
    _purchasePriceController = TextEditingController(text: asset?.purchasePrice.toString() ?? '');
    _currentPriceController = TextEditingController(text: asset?.currentPrice.toString() ?? '');
    _notesController = TextEditingController(text: asset?.notes ?? '');
    
    if (asset != null) {
      _selectedType = asset.type;
      _selectedCurrency = asset.currency;
      _selectedPlatform = asset.platform;
      _purchaseDate = asset.purchaseDate;
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _symbolController.dispose();
    _quantityController.dispose();
    _purchasePriceController.dispose();
    _currentPriceController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(isEditing ? 'Edit Asset' : 'Add Asset'),
        actions: [
          if (isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline, color: AppColors.error),
              onPressed: _showDeleteDialog,
            ),
        ],
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // Asset Type Selection
            Text(
              AppStrings.selectAssetType,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: AssetType.values.map((type) {
                final isSelected = _selectedType == type;
                return ChoiceChip(
                  avatar: Icon(
                    type.icon,
                    size: 18,
                    color: isSelected ? Colors.white : type.color,
                  ),
                  label: Text(type.displayName),
                  selected: isSelected,
                  selectedColor: type.color,
                  onSelected: (_) => setState(() => _selectedType = type),
                );
              }).toList(),
            ),
            
            const SizedBox(height: 24),
            
            // Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: AppStrings.assetName,
                hintText: 'e.g., Reliance Industries',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return AppStrings.errorRequired;
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // Symbol field with smart hints based on asset type
            _buildSymbolField(),
            
            const SizedBox(height: 16),
            
            // Quantity and Purchase Price Row
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _quantityController,
                    decoration: InputDecoration(
                      labelText: AppStrings.quantity,
                      hintText: 'e.g., 10',
                      suffixText: _selectedType.unitLabel,
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.errorRequired;
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed <= 0) {
                        return AppStrings.errorInvalidNumber;
                      }
                      return null;
                    },
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: TextFormField(
                    controller: _purchasePriceController,
                    decoration: InputDecoration(
                      labelText: AppStrings.purchasePrice,
                      prefixText: '${AppConstants.currencies[_selectedCurrency] ?? _selectedCurrency} ',
                    ),
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return AppStrings.errorRequired;
                      }
                      final parsed = double.tryParse(value);
                      if (parsed == null || parsed < 0) {
                        return AppStrings.errorInvalidNumber;
                      }
                      return null;
                    },
                  ),
                ),
              ],
            ),
            
            const SizedBox(height: 16),
            
            // Current Price
            TextFormField(
              controller: _currentPriceController,
              decoration: InputDecoration(
                labelText: AppStrings.currentPrice,
                prefixText: '${AppConstants.currencies[_selectedCurrency] ?? _selectedCurrency} ',
              ),
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return AppStrings.errorRequired;
                }
                if (double.tryParse(value) == null) {
                  return AppStrings.errorInvalidNumber;
                }
                return null;
              },
            ),
            
            const SizedBox(height: 16),
            
            // Purchase Date
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text(AppStrings.purchaseDate),
              subtitle: Text(
                '${_purchaseDate.day}/${_purchaseDate.month}/${_purchaseDate.year}',
                style: TextStyle(color: AppColors.textPrimary),
              ),
              trailing: const Icon(Icons.calendar_today),
              onTap: _selectDate,
            ),
            
            const SizedBox(height: 16),
            
            // Platform Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedPlatform,
              decoration: const InputDecoration(
                labelText: AppStrings.platform,
              ),
              items: AppConstants.popularPlatforms.map((platform) {
                return DropdownMenuItem(
                  value: platform,
                  child: Text(platform),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedPlatform = value),
            ),
            
            const SizedBox(height: 16),
            
            // Currency Dropdown
            DropdownButtonFormField<String>(
              initialValue: _selectedCurrency,
              decoration: const InputDecoration(
                labelText: AppStrings.selectCurrency,
              ),
              items: AppConstants.currencies.entries.map((entry) {
                return DropdownMenuItem(
                  value: entry.key,
                  child: Text('${entry.key} (${entry.value})'),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedCurrency = value ?? 'INR'),
            ),
            
            const SizedBox(height: 16),
            
            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: '${AppStrings.notes} (Optional)',
                hintText: 'Add any notes about this investment...',
              ),
              maxLines: 3,
            ),
            
            const SizedBox(height: 32),
            
            // Save Button
            ElevatedButton(
              onPressed: _saveAsset,
              child: Text(isEditing ? AppStrings.update : AppStrings.save),
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a smart symbol input field based on the selected asset type
  Widget _buildSymbolField() {
    final supportsTracking = PriceSymbols.supportsAutoTracking(_selectedType);
    final hint = PriceSymbols.symbolHint(_selectedType);
    final defaultSym = PriceSymbols.defaultSymbol(_selectedType);

    // Auto-fill default symbol for gold if field is empty
    if (defaultSym != null && _symbolController.text.isEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _symbolController.text.isEmpty) {
          setState(() => _symbolController.text = defaultSym);
        }
      });
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          controller: _symbolController,
          enabled: supportsTracking,
          decoration: InputDecoration(
            labelText: supportsTracking
                ? '${AppStrings.symbol} (for auto price updates)'
                : AppStrings.symbol,
            hintText: hint,
            suffixIcon: supportsTracking
                ? Icon(Icons.sync, color: AppColors.primary, size: 18)
                : Icon(Icons.lock_outline, color: AppColors.textTertiary, size: 18),
          ),
          textCapitalization: _selectedType == AssetType.crypto
              ? TextCapitalization.none
              : TextCapitalization.characters,
        ),
        if (supportsTracking) ...[
          const SizedBox(height: 4),
          Text(
            _selectedType == AssetType.crypto
                ? '💡 Use CoinGecko ID (e.g. bitcoin, ethereum)'
                : '💡 Use Yahoo Finance symbol (e.g. RELIANCE.NS for NSE)',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ] else ...[
          const SizedBox(height: 4),
          Text(
            '⚠ Auto price tracking not available for ${_selectedType.displayName}',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
        ],
      ],
    );
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2000),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() => _purchaseDate = picked);
    }
  }

  Future<void> _saveAsset() async {
    if (!_formKey.currentState!.validate()) return;

    final now = DateTime.now();
    final isNew = !isEditing;
    final asset = Asset(
      id: widget.existingAsset?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      symbol: _symbolController.text.trim().isNotEmpty
          ? _symbolController.text.trim()
          : null,
      type: _selectedType,
      quantity: double.tryParse(_quantityController.text) ?? 0,
      purchasePrice: double.tryParse(_purchasePriceController.text) ?? 0,
      currentPrice: double.tryParse(_currentPriceController.text) ?? 0,
      currency: _selectedCurrency,
      purchaseDate: _purchaseDate,
      platform: _selectedPlatform,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      createdAt: widget.existingAsset?.createdAt ?? now,
      updatedAt: now,
      priceUpdatedAt: now,
    );

    final assetRepo = ref.read(assetRepositoryProvider);
    final txRepo = TransactionRepository();

    if (isEditing) {
      await assetRepo.updateAsset(asset);
    } else {
      await assetRepo.addAsset(asset);
      // Log a BUY transaction for the new asset
      await txRepo.logBuyTransaction(asset);
    }

    // Refresh providers
    ref.invalidate(allAssetsProvider);
    ref.invalidate(portfolioSummaryProvider);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNew ? 'Asset added & transaction logged' : 'Asset updated successfully',
          ),
        ),
      );
    }
  }

  void _showDeleteDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text(AppStrings.delete),
        content: const Text(AppStrings.confirmDelete),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () async {
              final assetId = widget.existingAsset!.id;
              final assetRepo = ref.read(assetRepositoryProvider);
              final txRepo = TransactionRepository();

              // Delete asset AND its associated transactions
              await assetRepo.deleteAsset(assetId);
              await txRepo.deleteTransactionsForAsset(assetId);

              ref.invalidate(allAssetsProvider);
              ref.invalidate(portfolioSummaryProvider);

              if (mounted) {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Close screen
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Asset and its transactions deleted')),
                );
              }
            },
            child: Text(
              AppStrings.delete,
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }
}
