import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../services/stock_search_service.dart';

/// A search-as-you-type field for finding stocks, ETFs, and mutual funds.
///
/// The user types a company name (e.g. "Reliance", "TCS", "Apple") and
/// gets a live dropdown of matching results from Yahoo Finance.
///
/// On selection, [onSelected] is called with the chosen [StockSearchResult].
class StockSearchField extends StatefulWidget {
  /// Called when the user selects a result from the dropdown.
  final void Function(StockSearchResult result) onSelected;

  /// Optional initial display text (e.g. when editing an existing asset).
  final String? initialText;

  /// Hint text shown when the field is empty.
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

  List<StockSearchResult> _results = [];
  bool _isSearching = false;
  bool _showDropdown = false;
  Timer? _debounce;
  StockSearchResult? _selectedResult;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    _focusNode.addListener(() {
      if (!_focusNode.hasFocus) {
        // Delay hiding so tap on dropdown item registers first
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

  void _onTextChanged(String value) {
    // If user clears the field, reset selection
    if (value.isEmpty) {
      setState(() {
        _results = [];
        _showDropdown = false;
        _selectedResult = null;
      });
      return;
    }

    // Don't search if user just selected a result and text matches
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
          _results = results;
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
      _results = [];
    });
    _focusNode.unfocus();
    widget.onSelected(result);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            labelText: 'Search Stock / ETF / Fund',
            hintText: widget.hintText,
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
                    ? Icon(Icons.check_circle, color: AppColors.success, size: 20)
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
              color: AppColors.card,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.15),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: _isSearching && _results.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(16),
                    child: Center(
                      child: Text(
                        'Searching...',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  )
                : _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No results found. Try a different name or symbol.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _results.length,
                        separatorBuilder: (context, index) =>
                            Divider(color: AppColors.divider, height: 1),
                        itemBuilder: (context, index) {
                          final result = _results[index];
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.success.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.check_circle, color: AppColors.success, size: 16),
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
                      _results = [];
                    });
                  },
                  style: TextButton.styleFrom(
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(40, 24),
                  ),
                  child: Text(
                    'Change',
                    style: TextStyle(
                      color: AppColors.textSecondary,
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
        return const Color(0xFF1565C0); // Blue
      case 'BSE':
        return const Color(0xFF6A1B9A); // Purple
      case 'NYSE':
        return const Color(0xFF2E7D32); // Green
      case 'NASDAQ':
        return const Color(0xFF00838F); // Teal
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                      color: AppColors.textSecondary,
                      fontSize: 12,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            // Type badge (ETF, EQUITY, etc.)
            if (result.quoteType != 'EQUITY')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
