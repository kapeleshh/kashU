import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/constants/app_strings.dart';
import '../../core/theme/app_decorations.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/currency_formatter.dart';
import '../../data/models/asset.dart';
import '../../data/models/asset_type.dart';
import '../../shared/providers/portfolio_provider.dart';
import '../../shared/widgets/crypto_search_field.dart';
import '../../shared/widgets/fd_bond_input_field.dart';
import '../../shared/widgets/mutual_fund_search_field.dart';
import '../../shared/widgets/stock_search_field.dart';
import '../../services/coingecko_service.dart';
import '../../services/currency_converter_service.dart';
import '../../services/mutual_fund_service.dart';
import '../../services/price_service.dart';
import '../../services/quote_currency.dart';
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

  /// Whether the user picked the currency themselves. Until they do, an
  /// autofilled quote may move the field to the quote's own currency.
  bool _currencyChosenByUser = false;

  /// The raw quote behind an autofilled stock / fund price, kept so a later
  /// currency change re-derives the price instead of relabelling a number
  /// that is in another currency.
  ({double price, String currency})? _autofillQuote;

  /// The current-price text an autofill wrote. A currency change re-derives
  /// the price only while the field still holds it — never a typed price.
  String? _autofilledPriceText;

  String? _selectedPlatform;
  DateTime _purchaseDate = DateTime.now();

  // Gold/Silver toggle state
  bool _isSilver = false; // false = Gold, true = Silver

  // Gold/Silver live price fetch state
  bool _isFetchingGoldPrice = false;
  _FetchStatus? _goldFetchStatus;

  // Stock search state
  Key _stockSearchKey = UniqueKey(); // reset widget when type changes
  bool _isFetchingStockPrice = false;
  _FetchStatus? _stockFetchStatus;
  StockSearchResult? _selectedStock;

  // Mutual fund search state
  final Key _mfSearchKey = UniqueKey();
  bool _isFetchingMfNav = false;
  _FetchStatus? _mfFetchStatus;
  MutualFundResult? _selectedMf;

  // Crypto search state
  final Key _cryptoSearchKey = UniqueKey();
  bool _isFetchingCryptoPrice = false;
  _FetchStatus? _cryptoFetchStatus;
  CryptoSearchResult? _selectedCrypto;

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

  /// Whether the symbol was confirmed via a search selection
  /// (stock, mutual fund, or crypto) — shows the read-only symbol chip.
  bool get _hasSearchSelection =>
      (_usesStockSearch && _selectedStock != null) ||
      (_usesMfSearch && _selectedMf != null) ||
      (_usesCryptoSearch && _selectedCrypto != null);

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

    if (asset == null) {
      // New holdings start in the portfolio's base currency.
      final base = ref.read(baseCurrencyProvider);
      if (QuoteCurrency.isSupported(base)) _selectedCurrency = base;
    } else {
      _selectedType = asset.type;
      _selectedCurrency = asset.currency;
      _currencyChosenByUser = true;
      _selectedPlatform = asset.platform;
      _purchaseDate = asset.purchaseDate;
      // Gold and silver share AssetType.gold — the stored symbol is the only
      // thing that tells them apart, so the chip has to be restored from it.
      _isSilver = PriceSymbols.isComexSilver(asset.symbol);
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
        automaticallyImplyLeading: false,
        titleSpacing: 16,
        title: Row(
          children: [
            _SoftIconButton(
              icon: Icons.arrow_back_ios_new_rounded,
              onTap: () => Navigator.of(context).maybePop(),
            ),
            const SizedBox(width: 11),
            Text(
              isEditing ? 'Edit asset' : 'Add asset',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ],
        ),
        actions: [
          if (isEditing)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: _SoftIconButton(
                icon: Icons.delete_outline_rounded,
                iconColor: AppColors.error,
                onTap: _showDeleteDialog,
              ),
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
              'What did you invest in?',
              style: AppTheme.body(
                size: 13,
                weight: FontWeight.w700,
                color: AppColors.textSecondaryOn(context),
              ),
            ),
            const SizedBox(height: 10),
            // Soft 2-column grid of asset-type tiles.
            // Bond is temporarily hidden — code preserved for future use.
            _buildTypeGrid(),

            // Gold / Silver toggle (shown when Metals is selected)
            if (_selectedType == AssetType.gold && !isEditing) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  _metalChip('Gold', false, const Color(0xFFFFD700)),
                  const SizedBox(width: 8),
                  _metalChip('Silver', true, const Color(0xFF9E9E9E)),
                ],
              ),
            ],

            const SizedBox(height: 24),

            // Mutual fund search (MFAPI.in)
            if (_usesMfSearch && !isEditing) ...[
              MutualFundSearchField(
                key: _mfSearchKey,
                onSelected: _onMfSelected,
              ),
              const SizedBox(height: 8),
              if (_isFetchingMfNav)
                const _FetchStatusLine(
                  text: 'Fetching latest NAV...',
                  state: _FetchState.pending,
                )
              else if (_mfFetchStatus != null)
                _FetchStatusLine(
                  text: _mfFetchStatus!.text,
                  state: _mfFetchStatus!.state,
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
                const _FetchStatusLine(
                  text: 'Fetching live price...',
                  state: _FetchState.pending,
                )
              else if (_cryptoFetchStatus != null)
                _FetchStatusLine(
                  text: _cryptoFetchStatus!.text,
                  state: _cryptoFetchStatus!.state,
                ),
              const SizedBox(height: 16),
            ],

            // FD/Bond calculator
            if (_usesFdBondCalculator && !isEditing) ...[
              FdBondInputField(
                isFd: _selectedType == AssetType.fixedDeposit,
                currency: _selectedCurrency,
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
                const _FetchStatusLine(
                  text: 'Fetching live price...',
                  state: _FetchState.pending,
                )
              else if (_stockFetchStatus != null)
                _FetchStatusLine(
                  text: _stockFetchStatus!.text,
                  state: _stockFetchStatus!.state,
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

            // Symbol field — hidden for deposits (no symbol needed).
            // A search selection (stock / mutual fund / crypto) shows a
            // read-only symbol chip instead of the editable field.
            if (!isEditing && _hasSearchSelection) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(AppRadii.small),
                  boxShadow: AppShadows.soft(opacity: 0.12, y: 8, blur: 20),
                ),
                child: Row(
                  children: [
                    Icon(Icons.tag_rounded,
                        color: AppColors.textTertiaryOn(context), size: 18),
                    const SizedBox(width: 8),
                    Text(
                      'Symbol: ',
                      style: AppTheme.body(
                        size: 13,
                        color: AppColors.textSecondaryOn(context),
                      ),
                    ),
                    Text(
                      _symbolController.text,
                      style: AppTheme.body(
                        size: 13,
                        weight: FontWeight.w800,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    if (_selectedStock != null) ...[
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.12),
                          borderRadius:
                              BorderRadius.circular(AppRadii.avatar),
                        ),
                        child: Text(
                          _selectedStock!.exchangeLabel,
                          style: AppTheme.body(
                            size: 11,
                            weight: FontWeight.w800,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ] else if (!_usesStockSearch && !_usesFdBondCalculator ||
                isEditing) ...[
              _buildSymbolField(),
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
                      // An edited holding may be at 0 — fully sold, kept
                      // for its history; a new one must hold something.
                      if (parsed == null ||
                          !parsed.isFinite ||
                          parsed < 0 ||
                          (parsed == 0 && !isEditing)) {
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
                      if (parsed == null || parsed.isNaN || parsed <= 0) {
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
                final parsed = double.tryParse(value);
                if (parsed == null || parsed.isNaN || parsed < 0) {
                  return AppStrings.errorInvalidNumber;
                }
                return null;
              },
            ),

            const SizedBox(height: 16),

            // Purchase Date
            Material(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.small),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: _selectDate,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 14),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              AppStrings.purchaseDate,
                              style: AppTheme.body(
                                size: 12,
                                color: AppColors.textSecondaryOn(context),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              '${_purchaseDate.day}/${_purchaseDate.month}/${_purchaseDate.year}',
                              style: AppTheme.body(
                                size: 15,
                                weight: FontWeight.w700,
                                color:
                                    Theme.of(context).colorScheme.onSurface,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.calendar_today_rounded,
                          size: 18,
                          color: AppColors.textSecondaryOn(context)),
                    ],
                  ),
                ),
              ),
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
              // Keyed by value: an autofill can move the currency, and
              // initialValue is only read when the field is created.
              key: ValueKey('currency-$_selectedCurrency'),
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
              onChanged: (value) => _onCurrencyChanged(value ?? 'INR'),
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

            // Save Button — indigo→lavender gradient CTA
            Container(
              decoration: BoxDecoration(
                gradient: AppColors.primaryGradient,
                borderRadius: BorderRadius.circular(AppRadii.tile),
                boxShadow: AppShadows.glow(AppColors.primary, opacity: 0.5),
              ),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadii.tile),
                  onTap: _saveAsset,
                  child: SizedBox(
                    height: 54,
                    child: Center(
                      child: Text(
                        isEditing
                            ? AppStrings.update
                            : 'Add to portfolio',
                        style: AppTheme.heading(
                          size: 16,
                          color: Colors.white,
                        ),
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

  /// Soft 2-column grid of asset-type tiles. Each tile is a soft card with a
  /// gradient square icon + label; the selected tile gets a colored border and
  /// a check badge.
  Widget _buildTypeGrid() {
    // Bond is temporarily hidden — code preserved for future use.
    final types =
        AssetType.values.where((type) => type != AssetType.bond).toList();
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: types.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 9,
        crossAxisSpacing: 9,
        mainAxisExtent: 56,
      ),
      itemBuilder: (context, index) {
        final type = types[index];
        return _TypeTile(
          type: type,
          isSelected: _selectedType == type,
          onTap: () => _onTypeSelected(type),
        );
      },
    );
  }

  /// Handles asset-type selection (preserves the original chip onSelected logic).
  void _onTypeSelected(AssetType type) {
    setState(() {
      _selectedType = type;
      _goldFetchStatus = null;
      _stockFetchStatus = null;
      _selectedStock = null;
      _selectedMf = null;
      _selectedCrypto = null;
      _autofillQuote = null;
      _autofilledPriceText = null;
      // Reset stock search widget
      _stockSearchKey = UniqueKey();
    });
    if (type == AssetType.gold) {
      _symbolController.text =
          _isSilver ? PriceSymbols.silverComex : PriceSymbols.goldComex;
      _fetchGoldPrice();
    } else {
      if (_symbolController.text == PriceSymbols.goldComex ||
          _symbolController.text == PriceSymbols.silverComex) {
        _symbolController.clear();
      }
    }
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
        final status = await _applyQuote(
          priceResult.price,
          priceResult.currency,
          label: 'Live price',
        );
        if (!mounted) return;
        setState(() {
          _isFetchingStockPrice = false;
          _stockFetchStatus = status;
        });
      } else {
        setState(() {
          _isFetchingStockPrice = false;
          _stockFetchStatus = const _FetchStatus(
            'Could not fetch price — enter it manually.',
            _FetchState.failure,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingStockPrice = false;
        _stockFetchStatus = const _FetchStatus(
          'Could not fetch price — enter it manually.',
          _FetchState.failure,
        );
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

      if (navResult.isOk && navResult.valueOrNull?.nav != null) {
        final mf = navResult.valueOrNull!;
        // MFAPI.in quotes NAV in INR.
        final status = await _applyQuote(
          mf.nav!,
          'INR',
          label: 'Latest NAV',
          suffix: mf.navDate == null ? '' : ' (${mf.navDate})',
          decimals: 4,
        );
        if (!mounted) return;
        setState(() {
          _isFetchingMfNav = false;
          _mfFetchStatus = status;
        });
      } else {
        setState(() {
          _isFetchingMfNav = false;
          _mfFetchStatus = const _FetchStatus(
            'Could not fetch NAV — enter it manually.',
            _FetchState.failure,
          );
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isFetchingMfNav = false;
        _mfFetchStatus = const _FetchStatus(
          'Could not fetch NAV — enter it manually.',
          _FetchState.failure,
        );
      });
    }
  }

  /// Called when user selects a crypto from the search dropdown.
  /// Auto-fills name, symbol (CoinGecko ID), and fetches the live price.
  Future<void> _onCryptoSelected(CryptoSearchResult result) async {
    setState(() {
      _selectedCrypto = result;
      _nameController.text = result.name;
      _symbolController.text = result.id; // CoinGecko ID (e.g. "bitcoin")
    });
    await _fetchCryptoPrice(result);
  }

  /// Fetch [coin]'s price directly in the selected currency — CoinGecko
  /// quotes every currency the app offers, so no conversion is needed.
  Future<void> _fetchCryptoPrice(CryptoSearchResult coin) async {
    final currency = _selectedCurrency;
    setState(() {
      _cryptoFetchStatus = null;
      _isFetchingCryptoPrice = true;
    });

    try {
      final cryptoService =
          CoinGeckoService(vsCurrency: currency.toLowerCase());
      final priceResult = await cryptoService.fetchPrice(coin.id);

      // A newer fetch (the currency changed meanwhile) owns the field now.
      if (!mounted || currency != _selectedCurrency) return;

      if (priceResult.success && priceResult.price > 0) {
        setState(() {
          _isFetchingCryptoPrice = false;
          _currentPriceController.text =
              priceResult.price.toStringAsFixed(2);
          _autofilledPriceText = _currentPriceController.text;
          _cryptoFetchStatus = _FetchStatus(
            'Live price: ${CurrencyFormatter.formatCurrency(priceResult.price, currency)} (${coin.symbol})',
            _FetchState.success,
          );
        });
      } else {
        setState(() {
          _isFetchingCryptoPrice = false;
          _cryptoFetchStatus = const _FetchStatus(
            'Could not fetch price — enter it manually.',
            _FetchState.failure,
          );
        });
      }
    } catch (e) {
      if (!mounted || currency != _selectedCurrency) return;
      setState(() {
        _isFetchingCryptoPrice = false;
        _cryptoFetchStatus = const _FetchStatus(
          'Could not fetch price — enter it manually.',
          _FetchState.failure,
        );
      });
    }
  }

  bool get _priceStillAutofilled =>
      _autofilledPriceText != null &&
      _currentPriceController.text == _autofilledPriceText;

  /// Write a fetched quote into the current-price field so that the price
  /// and the currency field always agree (rules in [QuoteCurrency.plan]):
  /// a quote in another supported currency moves the field to it unless the
  /// user chose the currency, anything else is converted with live rates,
  /// and with no honest conversion the price is left to the user. Returns
  /// the status line to show.
  Future<_FetchStatus> _applyQuote(
    double price,
    String quoteCurrency, {
    required String label,
    String suffix = '',
    int decimals = 2,
  }) async {
    _autofillQuote = (price: price, currency: quoteCurrency);
    // Planned against the state as it is when called — after the forex
    // await too, in case the user changed the currency meanwhile.
    AutofillPlan planWith(ExchangeRateResult? rates) => QuoteCurrency.plan(
          quotePrice: price,
          quoteCurrency: quoteCurrency,
          selectedCurrency: _selectedCurrency,
          currencyChosenByUser: _currencyChosenByUser,
          rates: rates,
        );
    var decision = planWith(null);
    if (decision.action == AutofillAction.needsManualPrice &&
        quoteCurrency.isNotEmpty) {
      // Only now is a forex fetch worth it: the price must be converted.
      decision = planWith(
          await ref.read(currencyConverterServiceProvider).fetchRates());
    }
    if (!mounted) return const _FetchStatus('', _FetchState.pending);

    final quoted = QuoteCurrency.normalize(price, quoteCurrency);
    final quotedText =
        CurrencyFormatter.formatCurrency(quoted.price, quoted.currency);
    final filled = decision.price;
    setState(() {
      _selectedCurrency = decision.currency;
      if (filled != null) {
        _currentPriceController.text = filled.toStringAsFixed(decimals);
        _autofilledPriceText = _currentPriceController.text;
      } else if (_priceStillAutofilled) {
        // The old figure is in a currency the field no longer says.
        _currentPriceController.clear();
        _autofilledPriceText = null;
      }
    });

    switch (decision.action) {
      case AutofillAction.asQuoted:
        return _FetchStatus('$label: $quotedText$suffix', _FetchState.success);
      case AutofillAction.adoptQuoteCurrency:
        return _FetchStatus(
          '$label: $quotedText$suffix — currency set to ${decision.currency}',
          _FetchState.success,
        );
      case AutofillAction.converted:
        return _FetchStatus(
          '$label: $quotedText ≈ '
          '${CurrencyFormatter.formatCurrency(filled!, decision.currency)}'
          '$suffix',
          _FetchState.success,
        );
      case AutofillAction.needsManualPrice:
        return _FetchStatus(
          'Quoted in ${quoted.currency} — enter the price in '
          '${decision.currency} manually.',
          _FetchState.failure,
        );
    }
  }

  /// The user picked a currency. An autofilled price is re-derived in it
  /// (re-fetched for metals and crypto, converted for stocks and funds);
  /// a price the user typed is theirs and stays as it is.
  void _onCurrencyChanged(String currency) {
    if (currency == _selectedCurrency) return;
    setState(() {
      _selectedCurrency = currency;
      _currencyChosenByUser = true;
    });
    if (isEditing) return;

    // A fetch still in flight ignores its result once the currency moved
    // on, so it must be replaced, not just left to finish.
    if (_selectedType == AssetType.gold) {
      if (_priceStillAutofilled || _isFetchingGoldPrice) _fetchGoldPrice();
    } else if (_usesCryptoSearch && _selectedCrypto != null) {
      if (_priceStillAutofilled || _isFetchingCryptoPrice) {
        _fetchCryptoPrice(_selectedCrypto!);
      }
    } else if (_autofillQuote != null && _priceStillAutofilled) {
      final quote = _autofillQuote!;
      final isMf = _usesMfSearch;
      _applyQuote(
        quote.price,
        quote.currency,
        label: isMf ? 'Latest NAV' : 'Live price',
        decimals: isMf ? 4 : 2,
      ).then((status) {
        if (!mounted) return;
        setState(() {
          if (isMf) {
            _mfFetchStatus = status;
          } else {
            _stockFetchStatus = status;
          }
        });
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
                        color: AppColors.textTertiaryOn(context), size: 18),
          ),
          textCapitalization: _selectedType == AssetType.crypto
              ? TextCapitalization.none
              : TextCapitalization.characters,
        ),
        const SizedBox(height: 4),
        if (_isFetchingGoldPrice)
          _FetchStatusLine(
            text: 'Fetching live ${_isSilver ? 'silver' : 'gold'} price...',
            state: _FetchState.pending,
          )
        else if (_goldFetchStatus != null)
          _FetchStatusLine(
            text: _goldFetchStatus!.text,
            state: _goldFetchStatus!.state,
          )
        else if (supportsTracking &&
            _selectedType != AssetType.crypto &&
            _selectedType != AssetType.mutualFund)
          Text(
            _selectedType == AssetType.gold
                ? 'Live ${_isSilver ? 'silver' : 'gold'} price will be fetched automatically'
                : 'Use Yahoo Finance symbol (e.g. RELIANCE.NS for NSE)',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiaryOn(context),
              fontStyle: FontStyle.italic,
            ),
          )
        else if (!supportsTracking)
          Text(
            'Auto price tracking not available for ${_selectedType.displayName}',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.textTertiaryOn(context),
              fontStyle: FontStyle.italic,
            ),
          ),
      ],
    );
  }

  /// Gold/Silver toggle chip
  Widget _metalChip(String label, bool isSilver, Color color) {
    final isSelected = _isSilver == isSilver;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() {
          _isSilver = isSilver;
          _goldFetchStatus = null;
          // Update symbol
          _symbolController.text =
              isSilver ? PriceSymbols.silverComex : PriceSymbols.goldComex;
        });
        _fetchGoldPrice();
      },
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.1),
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isSelected ? color : color.withValues(alpha: 0.3),
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  /// Fetches live metal (gold or silver) price and auto-fills the current price field
  Future<void> _fetchGoldPrice() async {
    final currency = _selectedCurrency;
    final isSilver = _isSilver;
    setState(() {
      _isFetchingGoldPrice = true;
      _goldFetchStatus = null;
    });

    try {
      final goldService = ref.read(goldPriceServiceProvider);

      final breakdown = isSilver
          ? await goldService.fetchSilverPriceBreakdown(
              targetCurrency: currency)
          : await goldService.fetchGoldPriceBreakdown(
              targetCurrency: currency);

      // A newer fetch (currency or metal changed meanwhile) owns the field.
      if (!mounted || currency != _selectedCurrency || isSilver != _isSilver) {
        return;
      }

      if (breakdown == null) {
        setState(() {
          _isFetchingGoldPrice = false;
          _goldFetchStatus = const _FetchStatus(
            'Could not fetch price — check your internet connection.',
            _FetchState.failure,
          );
        });
        return;
      }

      final price = breakdown.finalPerGram;
      final metalName = isSilver ? 'silver' : 'gold';
      setState(() {
        _isFetchingGoldPrice = false;
        _currentPriceController.text = price.toStringAsFixed(2);
        _autofilledPriceText = _currentPriceController.text;
        _goldFetchStatus = _FetchStatus(
          'Live $metalName price: '
          '${CurrencyFormatter.formatCurrency(price, currency)}/gram',
          _FetchState.success,
        );
      });
    } catch (e) {
      if (!mounted || currency != _selectedCurrency || isSilver != _isSilver) {
        return;
      }
      setState(() {
        _isFetchingGoldPrice = false;
        // Never surface the raw exception to the user.
        _goldFetchStatus = const _FetchStatus(
          'Could not fetch price — enter it manually.',
          _FetchState.failure,
        );
      });
    }
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(1990),
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
    final existing = widget.existingAsset;
    final currentPrice = double.tryParse(_currentPriceController.text) ?? 0;
    final asset = Asset(
      id: widget.existingAsset?.id ?? const Uuid().v4(),
      name: _nameController.text.trim(),
      symbol: _symbolController.text.trim().isNotEmpty
          ? _symbolController.text.trim()
          : null,
      type: _selectedType,
      quantity: double.tryParse(_quantityController.text) ?? 0,
      purchasePrice: double.tryParse(_purchasePriceController.text) ?? 0,
      currentPrice: currentPrice,
      currency: _selectedCurrency,
      purchaseDate: _purchaseDate,
      platform: _selectedPlatform,
      notes: _notesController.text.trim().isNotEmpty
          ? _notesController.text.trim()
          : null,
      createdAt: widget.existingAsset?.createdAt ?? now,
      updatedAt: now,
      // Editing the name or notes must not stamp an old price as fresh.
      priceUpdatedAt:
          existing != null && existing.currentPrice == currentPrice
              ? existing.priceUpdatedAt
              : now,
    );

    if (isEditing) {
      await ref.read(assetRepositoryProvider).updateAsset(asset);
    } else {
      await ref
          .read(portfolioWriteServiceProvider)
          .addAssetWithBuyTransaction(asset);
    }

    ref.invalidate(allAssetsProvider);
    ref.invalidate(portfolioSummaryProvider);

    if (mounted) {
      // true = saved, so a detail screen underneath knows the edit happened
      // (backing out pops with null).
      Navigator.pop(context, true);
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
              final navigator = Navigator.of(context);
              final messenger = ScaffoldMessenger.of(context);

              await ref
                  .read(portfolioWriteServiceProvider)
                  .deleteAssetWithTransactions(assetId);

              ref.invalidate(allAssetsProvider);
              ref.invalidate(portfolioSummaryProvider);

              if (mounted) {
                navigator.pop(); // the dialog
                navigator.pop(true); // this screen — deleted counts as done
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

/// The lifecycle of a price/NAV fetch shown under a search field.
enum _FetchState { pending, success, failure }

/// A fetch outcome message plus its state (used to pick the text color).
class _FetchStatus {
  final String text;
  final _FetchState state;

  const _FetchStatus(this.text, this.state);
}

/// A single small status line shown under search/symbol fields while a
/// price/NAV fetch is pending, succeeded, or failed.
class _FetchStatusLine extends StatelessWidget {
  final String text;
  final _FetchState state;

  const _FetchStatusLine({required this.text, required this.state});

  @override
  Widget build(BuildContext context) {
    final Color color;
    switch (state) {
      case _FetchState.pending:
        color = AppColors.textSecondaryOn(context);
      case _FetchState.success:
        color = AppColors.gainOn(context);
      case _FetchState.failure:
        color = AppColors.error;
    }
    return Text(
      text,
      style: AppTheme.body(size: 11, color: color),
    );
  }
}

/// A soft circular/rounded icon button used in the app bar (back / delete).
class _SoftIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final Color? iconColor;

  const _SoftIconButton({
    required this.icon,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadii.avatar),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(
            icon,
            size: 18,
            color: iconColor ?? Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// A soft asset-type tile: gradient square icon + label, with a colored border
/// and check badge when selected. Works in both light and dark mode.
class _TypeTile extends StatelessWidget {
  final AssetType type;
  final bool isSelected;
  final VoidCallback onTap;

  const _TypeTile({
    required this.type,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    final tone = type.color;

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadii.tile),
        boxShadow:
            isSelected ? null : AppShadows.soft(opacity: 0.12, y: 8, blur: 20),
      ),
      child: Material(
        color: isSelected ? tone.withValues(alpha: 0.12) : surface,
        borderRadius: BorderRadius.circular(AppRadii.tile),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Stack(
            alignment: Alignment.centerLeft,
            clipBehavior: Clip.none,
            children: [
              // Border layer — fills the entire tile so it traces the card edge.
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadii.tile),
                    border: Border.all(
                      color: isSelected ? tone : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 11),
                child: Row(
                  children: [
                    Container(
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        gradient: softAvatarGradient(tone),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(type.icon, size: 17, color: Colors.white),
                    ),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        type.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTheme.heading(
                          size: 13,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              if (isSelected)
                Positioned(
                  top: 0,
                  bottom: 0,
                  right: 6,
                  child: Center(
                    child: Container(
                      width: 21,
                      height: 21,
                      decoration: BoxDecoration(
                        color: tone,
                        shape: BoxShape.circle,
                        boxShadow: AppShadows.glow(tone, opacity: 0.5),
                      ),
                      child: const Icon(Icons.check_rounded,
                          size: 13, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
