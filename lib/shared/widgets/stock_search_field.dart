import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../services/stock_search_service.dart';

/// Exchange filter options for the stock search field.
enum ExchangeFilter {
  all,
  nse,
  bse,
  nasdaq,
  nyse;

  String get label {
    switch (this) {
      case ExchangeFilter.all:
        return 'All';
      case ExchangeFilter.nse:
        return 'NSE';
      case ExchangeFilter.bse:
        return 'BSE';
      case ExchangeFilter.nasdaq:
        return 'NASDAQ';
      case ExchangeFilter.nyse:
        return 'NYSE';
    }
  }

  /// Yahoo Finance exchange codes that map to this filter
  List<String> get exchangeCodes {
    switch (this) {
      case ExchangeFilter.all:
        return [];
      case ExchangeFilter.nse:
        return ['NSI'];
      case ExchangeFilter.bse:
        return ['BSE', 'BOM'];
      case ExchangeFilter.nasdaq:
        return ['NMS', 'NGM', 'NCM'];
      case ExchangeFilter.nyse:
        return ['NYQ', 'ASE'];
    }
  }

  Color get color {
    switch (this) {
      case ExchangeFilter.all:
        return Colors.grey;
      case ExchangeFilter.nse:
        return const Color(0xFF1565C0); // Blue
      case ExchangeFilter.bse:
        return const Color(0xFF6A1B9A); // Purple
      case ExchangeFilter.nasdaq:
        return const Color(0xFF00838F); // Teal
      case ExchangeFilter.nyse:
        return const Color(0xFF2E7D32); // Green
    }
  }

  String get searchHint {
    switch (this) {
      case ExchangeFilter.all:
        return 'Search by company name or symbol...';
      case ExchangeFilter.nse:
        return 'Search NSE stocks (e.g. Reliance, TCS, Infosys)...';
      case ExchangeFilter.bse:
        return 'Search BSE stocks (e.g. Reliance, HDFC, Wipro)...';
      case ExchangeFilter.nasdaq:
        return 'Search NASDAQ stocks (e.g. Apple, Google, Tesla)...';
      case ExchangeFilter.nyse:
        return 'Search NYSE stocks (e.g. Coca-Cola, JPMorgan)...';
    }
  }
}

/// A search-as-you-type field for finding stocks, ETFs, and mutual funds.
///
/// Includes exchange filter chips (NSE / BSE / NASDAQ / NYSE / All) to
/// restrict results to a specific exchange.
///
/// On selection, [onSelected] is called with the chosen [StockSearchResult].
class StockSearchField extends StatefulWidget {
  /// Called when the user selects a result from the dropdown.
  final void Function(StockSearchResult result) onSelected;

  /// Optional initial display text (e.g. when editing an existing asset).
  final String? initialText;

  /// Default hint text (overridden by exchange filter selection).
  final String hintText;

  const StockSearchField({
    super.key,
    required this.onSelected,
    this.initialText,
    this.hintText = 'Search by company name or symbol...',
  });

  @override
  State<StockSearchField> createState() => _StockSearchFieldState();
}

class _StockSearchFieldState extends State<StockSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _searchService = StockSearchService();

  List<StockSearchResult> _allResults = []; // unfiltered results from API
  List<StockSearchResult> _filteredResults = []; // after exchange filter
  bool _isSearching = false;
  bool _showDropdown = false;
  Timer? _debounce;
  StockSearchResult? _selectedResult;
  ExchangeFilter _selectedExchange = ExchangeFilter.all;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showDropdown = false);
        });
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  /// Apply the current exchange filter to [_allResults]
  List<StockSearchResult> _applyFilter(List<StockSearchResult> results) {
    if (_selectedExchange == ExchangeFilter.all) return results;
    final codes = _selectedExchange.exchangeCodes;
    return results
        .where((r) => codes.contains(r.exchange))
        .toList();
  }

  void _onExchangeChanged(ExchangeFilter exchange) {
    setState(() {
      _selectedExchange = exchange;
      _filteredResults = _applyFilter(_allResults);
      // If there are results, keep dropdown open
      if (_allResults.isNotEmpty) _showDropdown = true;
    });
  }

  void _onTextChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _allResults = [];
        _filteredResults = [];
        _showDropdown = false;
        _selectedResult = null;
      });
      return;
    }

    if (_selectedResult != null && value == _selectedResult!.name) return;

    setState(() {
      _selectedResult = null;
      _isSearching = true;
      _showDropdown = true;
    });

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () async {
      final results = await _searchService.search(value);
      if (mounted) {
        setState(() {
          _allResults = results;
          _filteredResults = _applyFilter(results);
          _isSearching = false;
        });
      }
    });
  }

  void _onResultSelected(StockSearchResult result) {
    setState(() {
      _selectedResult = result;
      _controller.text = result.name;
      _showDropdown = false;
      _allResults = [];
      _filteredResults = [];
    });
    _focusNode.unfocus();
    widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    final hint = _selectedExchange == ExchangeFilter.all
        ? widget.hintText
        : _selectedExchange.searchHint;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Exchange filter chips
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: ExchangeFilter.values.map((exchange) {
              final isSelected = _selectedExchange == exchange;
              final color = exchange.color;
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(
                    exchange.label,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: isSelected ? Colors.white : color,
                    ),
                  ),
                  selected: isSelected,
                  onSelected: (_) => _onExchangeChanged(exchange),
                  selectedColor: color,
                  backgroundColor: color.withValues(alpha: 0.08),
                  checkmarkColor: Colors.white,
                  side: BorderSide(
                    color: isSelected ? color : color.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 10),

        // Search text field
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            labelText: 'Search Stock / ETF / Fund',
            hintText: hint,
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isSearching
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : _selectedResult != null
                    ? Icon(Icons.check_circle,
                        color: AppColors.success, size: 20)
                    : _controller.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _controller.clear();
                              _onTextChanged('');
                            },
                          )
                        : null,
          ),
        ),

        // Dropdown results
        if (_showDropdown) ...[
          const SizedBox(height: 4),
          Container(
            constraints: const BoxConstraints(maxHeight: 280),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.small),
              boxShadow: AppShadows.soft(opacity: 0.18, y: 6, blur: 16),
            ),
            child: _isSearching && _filteredResults.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Searching...',
                        style: TextStyle(
                            color: AppColors.textSecondaryOn(context)),
                      ),
                    ),
                  )
                : _filteredResults.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          _selectedExchange == ExchangeFilter.all
                              ? 'No results found. Try a different name or symbol.'
                              : 'No ${_selectedExchange.label} results found. Try "All" or a different name.',
                          style: TextStyle(
                            color: AppColors.textSecondaryOn(context),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _filteredResults.length,
                        separatorBuilder: (context, index) =>
                            Divider(color: Theme.of(context).dividerColor, height: 1),
                        itemBuilder: (context, index) {
                          final result = _filteredResults[index];
                          return _SearchResultTile(
                            result: result,
                            onTap: () => _onResultSelected(result),
                          );
                        },
                      ),
          ),
        ],

        // Selected result confirmation
        if (_selectedResult != null && !_showDropdown) ...[
          const SizedBox(height: 6),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle,
                    color: AppColors.success, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${_selectedResult!.symbol} · ${_selectedResult!.exchangeLabel}',
                    style: TextStyle(
                      color: AppColors.success,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    _controller.clear();
                    setState(() {
                      _selectedResult = null;
                      _allResults = [];
                      _filteredResults = [];
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 24),
                  ),
                  child: Text(
                    'Change',
                    style: TextStyle(
                      color: AppColors.textSecondaryOn(context),
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final StockSearchResult result;
  final VoidCallback onTap;

  const _SearchResultTile({required this.result, required this.onTap});

  Color _exchangeColor(String exchange) {
    switch (exchange) {
      case 'NSE':
        return const Color(0xFF1565C0);
      case 'BSE':
        return const Color(0xFF6A1B9A);
      case 'NYSE':
        return const Color(0xFF2E7D32);
      case 'NASDAQ':
        return const Color(0xFF00838F);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final exchangeColor = _exchangeColor(result.exchangeLabel);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Exchange badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: exchangeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                result.exchangeLabel,
                style: TextStyle(
                  color: exchangeColor,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            const SizedBox(width: 10),
            // Symbol + name
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.symbol,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    result.name,
                    style: TextStyle(
                      color: AppColors.textSecondaryOn(context),
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Type badge (ETF, MUTUALFUND, etc.)
            if (result.quoteType != 'EQUITY')
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  result.quoteType,
                  style: const TextStyle(
                    color: Colors.orange,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
