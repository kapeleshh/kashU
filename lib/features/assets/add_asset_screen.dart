import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../../shared/widgets/crypto_search_field.dart';
import '../../shared/widgets/fd_bond_input_field.dart';
import '../../shared/widgets/mutual_fund_search_field.dart';
import '../../shared/widgets/stock_search_field.dart';
import '../../data/repositories/transaction_repository.dart';
import '../../services/coingecko_service.dart';
import '../../services/mutual_fund_service.dart';
import '../../services/price_service.dart';
import '../../services/stock_search_service.dart';
import '../../services/yahoo_finance_service.dart';

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

  // Gold live price fetch state
  bool _isFetchingGoldPrice = false;
  String? _goldFetchStatus;

  // Stock search state
  Key _stockSearchKey = UniqueKey(); // reset widget when type changes
  bool _isFetchingStockPrice = false;
  String? _stockFetchStatus;
  StockSearchResult? _selectedStock;

  // Mutual fund search state
  final Key _mfSearchKey = UniqueKey();
  bool _isFetchingMfNav = false;
  String? _mfFetchStatus;
  // ignore: unused_field
  MutualFundResult? _selectedMf;

  // Crypto search state
  final Key _cryptoSearchKey = UniqueKey();
  bool _isFetchingCryptoPrice = false;
  String? _cryptoFetchStatus;

  // FD/Bond calculator state (stored for potential future use e.g. maturity date in notes)
  // ignore: unused_field
  FdBondInputResult? _fdBondResult;

  bool get isEditing => widget.existingAsset != null;

  /// Types that use the stock search autocomplete
  bool get _usesStockSearch => _selectedType == AssetType.stock;

  /// Whether this type uses the FD/Bond calculator
  bool get _usesFdBondCalculator =>
      _selectedType == AssetType.fixedDeposit ||
      _selectedType == AssetType.bond;

  /// Whether this type uses the mutual fund search
  bool get _usesMfSearch => _selectedType == AssetType.mutualFund;

  /// Whether this type uses the crypto search
  bool get _usesCryptoSearch => _selectedType == AssetType.crypto;

  @override
  void initState() {
    super.initState();
    final asset = widget.existingAsset;

    _nameController = TextEditingController(text: asset?.name ?? '');
    _symbolController = TextEditingController(text: asset?.symbol ?? '');
    _quantityController =
        TextEditingController(text: asset?.quantity.toString() ?? '');
    _purchasePriceController =
        TextEditingController(text: asset?.purchasePrice.toString() ?? '');
    _currentPriceController =
        TextEditingController(text: asset?.currentPrice.toString() ?? '');
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
              // Bond is temporarily hidden — code preserved for future use
              children: AssetType.values.where((type) => type != AssetType.bond).map((type) {
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
                  onSelected: (_) {
                    setState(() {
                      _selectedType = type;
                      _goldFetchStatus = null;
                      _stockFetchStatus = null;
                      _selectedStock = null;
                      // Reset stock search widget
                      _stockSearchKey = UniqueKey();
                    });
                    if (type == AssetType.gold) {
                      _symbolController.text = PriceSymbols.goldComex;
                      _fetchGoldPrice();
                    } else {
                      if (_symbolController.text == PriceSymbols.goldComex) {
                        _symbolController.clear();
                      }
                    }
                  },
                );
              }).toList(),
            ),

            const SizedBox(height: 24),

            // Mutual fund search (MFAPI.in)
            if (_usesMfSearch && !isEditing) ...[
              MutualFundSearchField(
                key: _mfSearchKey,
                onSelected: _onMfSelected,
              ),
              const SizedBox(height: 8),
              if (_isFetchingMfNav)
                Text(
                  '⏳ Fetching latest NAV...',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (_mfFetchStatus != null)
                Text(
                  _mfFetchStatus!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _mfFetchStatus!.startsWith('✅')
                        ? AppColors.success
                        : AppColors.error,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // Crypto search (CoinGecko)
            if (_usesCryptoSearch && !isEditing) ...[
              CryptoSearchField(
                key: _cryptoSearchKey,
                onSelected: _onCryptoSelected,
              ),
              const SizedBox(height: 8),
              if (_isFetchingCryptoPrice)
                Text(
                  '⏳ Fetching live price...',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (_cryptoFetchStatus != null)
                Text(
                  _cryptoFetchStatus!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _cryptoFetchStatus!.startsWith('✅')
                        ? AppColors.success
                        : AppColors.error,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // FD/Bond calculator
            if (_usesFdBondCalculator && !isEditing) ...[
              FdBondInputField(
                isFd: _selectedType == AssetType.fixedDeposit,
                onChanged: (result) {
                  setState(() {
                    _fdBondResult = result;
                    // Auto-fill principal as purchase price
                    _purchasePriceController.text =
                        result.principal.toStringAsFixed(2);
                    // Auto-fill current value
                    _currentPriceController.text =
                        result.calculation.currentValue.toStringAsFixed(2);
                    // Set purchase date to start date
                    _purchaseDate = result.startDate;
                  });
                },
              ),
              const SizedBox(height: 16),
            ],

            // Stock search
            if (_usesStockSearch && !isEditing) ...[
              StockSearchField(
                key: _stockSearchKey,
                onSelected: _onStockSelected,
                hintText: _selectedType == AssetType.bond
                    ? 'Search bond or treasury name...'
                    : 'Search by company name (e.g. Reliance, TCS, Apple)...',
              ),
              const SizedBox(height: 8),
              if (_isFetchingStockPrice)
                Text(
                  '⏳ Fetching live price...',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontStyle: FontStyle.italic,
                  ),
                )
              else if (_stockFetchStatus != null)
                Text(
                  _stockFetchStatus!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _stockFetchStatus!.startsWith('✅')
                        ? AppColors.success
                        : AppColors.error,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              const SizedBox(height: 16),
            ],

            // Name field (always shown; auto-filled for stocks/MFs)
            TextFormField(
              controller: _nameController,
              decoration: InputDecoration(
                labelText: _usesFdBondCalculator
                    ? 'Deposit Name'
                    : AppStrings.assetName,
                hintText: (_usesStockSearch || _usesMfSearch) && !isEditing
                    ? 'Auto-filled from search'
                    : _usesFdBondCalculator
                        ? 'e.g., SBI FD, HDFC RD'
                        : 'e.g., Reliance Industries',
              ),
              validator: (value) {
                if (value == null || value.isEmpty) {
                  return AppStrings.errorRequired;
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Symbol field — hidden for deposits (no symbol needed) and stock search
            if (!_usesStockSearch && !_usesFdBondCalculator || isEditing) ...[
              _buildSymbolField(),
              const SizedBox(height: 16),
            ] else if (_selectedStock != null) ...[
              // Show read-only symbol chip when stock is selected
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.card,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tag, color: AppColors.textTertiary, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Symbol: ',
                      style: TextStyle(color: AppColors.textSecondary),
                    ),
                    Text(
                      _symbolController.text,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        _selectedStock!.exchangeLabel,
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],

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
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                      prefixText:
                          '${AppConstants.currencies[_selectedCurrency] ?? _selectedCurrency} ',
                    ),
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
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
                prefixText:
                    '${AppConstants.currencies[_selectedCurrency] ?? _selectedCurrency} ',
                hintText: _isFetchingStockPrice ? 'Fetching...' : null,
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
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
              onChanged: (value) =>
                  setState(() => _selectedPlatform = value),
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
              onChanged: (value) =>
                  setState(() => _selectedCurrency = value ?? 'INR'),
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

  /// Called when user selects a stock from the search dropdown.
  /// Auto-fills name, symbol, and fetches live price.
  Future<void> _onStockSelected(StockSearchResult result) async {
    setState(() {
      _selectedStock = result;
      _nameController.text = result.name;
      _symbolController.text = result.symbol;
      _stockFetchStatus = null;
      _isFetchingStockPrice = true;
    });

    // Fetch live price for the selected stock
    try {
      final yahooService = YahooFinanceService();
      final priceResult = await yahooService.fetchPrice(result.symbol);

      if (!mounted) return;

      if (priceResult.success && priceResult.price > 0) {
        setState(() {
          _isFetchingStockPrice = false;
          _currentPriceController.text =
              priceResult.price.toStringAsFixed(2);
          _stockFetchStatus =
              '✅ Live price: ${priceResult.currency} ${priceResult.price.toStringAsFixed(2)}';
        });
      } else {
        setState(() {
          _isFetchingStockPrice = false;
          _stockFetchStatus =
              '⚠ Could not fetch price. Enter manually.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingStockPrice = false;
        _stockFetchStatus = '⚠ Could not fetch price. Enter manually.';
      });
    }
  }

  /// Called when user selects a mutual fund from the search dropdown.
  /// Auto-fills name, symbol (scheme code), and fetches latest NAV.
  Future<void> _onMfSelected(MutualFundResult result) async {
    setState(() {
      _selectedMf = result;
      _nameController.text = result.shortName;
      _symbolController.text = result.schemeCode.toString();
      _mfFetchStatus = null;
      _isFetchingMfNav = true;
    });

    try {
      final mfService = MutualFundService();
      final navResult = await mfService.fetchNav(result.schemeCode);

      if (!mounted) return;

      if (navResult != null && navResult.nav != null) {
        setState(() {
          _isFetchingMfNav = false;
          _currentPriceController.text =
              navResult.nav!.toStringAsFixed(4);
          _mfFetchStatus =
              '✅ Latest NAV: ₹${navResult.nav!.toStringAsFixed(4)} (${navResult.navDate ?? ''})';
        });
      } else {
        setState(() {
          _isFetchingMfNav = false;
          _mfFetchStatus = '⚠ Could not fetch NAV. Enter manually.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingMfNav = false;
        _mfFetchStatus = '⚠ Could not fetch NAV. Enter manually.';
      });
    }
  }

  /// Called when user selects a crypto from the search dropdown.
  /// Auto-fills name, symbol (CoinGecko ID), and fetches live price in INR.
  Future<void> _onCryptoSelected(CryptoSearchResult result) async {
    setState(() {
      _nameController.text = result.name;
      _symbolController.text = result.id; // CoinGecko ID (e.g. "bitcoin")
      _cryptoFetchStatus = null;
      _isFetchingCryptoPrice = true;
    });

    try {
      // Fetch price in INR
      final cryptoService = CoinGeckoService(vsCurrency: 'inr');
      final priceResult = await cryptoService.fetchPrice(result.id);

      if (!mounted) return;

      if (priceResult.success && priceResult.price > 0) {
        setState(() {
          _isFetchingCryptoPrice = false;
          _currentPriceController.text =
              priceResult.price.toStringAsFixed(2);
          _cryptoFetchStatus =
              '✅ Live price: ₹${priceResult.price.toStringAsFixed(2)} (${result.symbol})';
        });
      } else {
        setState(() {
          _isFetchingCryptoPrice = false;
          _cryptoFetchStatus = '⚠ Could not fetch price. Enter manually.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingCryptoPrice = false;
        _cryptoFetchStatus = '⚠ Could not fetch price. Enter manually.';
      });
    }
  }

  /// Builds a smart symbol input field for non-stock types (gold, crypto, etc.)
  Widget _buildSymbolField() {
    final baseCurrency = ref.read(baseCurrencyProvider);
    final supportsTracking = PriceSymbols.supportsAutoTracking(_selectedType);
    final hint =
        PriceSymbols.symbolHint(_selectedType, baseCurrency: baseCurrency);
    final defaultSym =
        PriceSymbols.defaultSymbol(_selectedType, baseCurrency: baseCurrency);

    if (defaultSym != null &&
        _selectedType != AssetType.gold &&
        _symbolController.text.isEmpty) {
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
            suffixIcon: _isFetchingGoldPrice
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : supportsTracking
                    ? Icon(Icons.sync, color: AppColors.primary, size: 18)
                    : Icon(Icons.lock_outline,
                        color: AppColors.textTertiary, size: 18),
          ),
          textCapitalization: _selectedType == AssetType.crypto
              ? TextCapitalization.none
              : TextCapitalization.characters,
        ),
        const SizedBox(height: 4),
        if (_isFetchingGoldPrice)
          Text(
            '⏳ Fetching live gold price...',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.primary,
              fontStyle: FontStyle.italic,
            ),
          )
        else if (_goldFetchStatus != null)
          Text(
            _goldFetchStatus!,
            style: TextStyle(
              fontSize: 11,
              color: _goldFetchStatus!.startsWith('✅')
                  ? AppColors.success
                  : AppColors.error,
              fontStyle: FontStyle.italic,
            ),
          )
        else if (supportsTracking)
          Text(
            _selectedType == AssetType.crypto
                ? '💡 Use CoinGecko ID (e.g. bitcoin, ethereum)'
                : _selectedType == AssetType.gold
                    ? '💡 Live gold price will be fetched automatically'
                    : '💡 Use Yahoo Finance symbol (e.g. RELIANCE.NS for NSE)',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          )
        else
          Text(
            '⚠ Auto price tracking not available for ${_selectedType.displayName}',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiary,
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }

  /// Fetches live gold price and auto-fills the current price field
  Future<void> _fetchGoldPrice() async {
    setState(() {
      _isFetchingGoldPrice = true;
      _goldFetchStatus = null;
    });

    try {
      final goldService = ref.read(goldPriceServiceProvider);
      final breakdown = await goldService.fetchGoldPriceBreakdown(
        targetCurrency: _selectedCurrency,
      );

      if (!mounted) return;

      if (breakdown == null) {
        setState(() {
          _isFetchingGoldPrice = false;
          _goldFetchStatus =
              '❌ Could not fetch price. Check internet connection.';
        });
        return;
      }

      final price = breakdown.finalPerGram;
      setState(() {
        _isFetchingGoldPrice = false;
        _currentPriceController.text = price.toStringAsFixed(2);
        _goldFetchStatus =
            '✅ Live gold price: ₹${price.toStringAsFixed(2)}/gram';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingGoldPrice = false;
        _goldFetchStatus = '❌ Error: $e';
      });
    }
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
      await txRepo.logBuyTransaction(asset);
    }

    ref.invalidate(allAssetsProvider);
    ref.invalidate(portfolioSummaryProvider);

    if (mounted) {
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isNew
                ? 'Asset added & transaction logged'
                : 'Asset updated successfully',
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
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              await assetRepo.deleteAsset(assetId);
              await txRepo.deleteTransactionsForAsset(assetId);

              ref.invalidate(allAssetsProvider);
              ref.invalidate(portfolioSummaryProvider);

              if (mounted) {
                navigator.pop();
                navigator.pop();
                messenger.showSnackBar(
                  const SnackBar(
                      content:
                          Text('Asset and its transactions deleted')),
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
