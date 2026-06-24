import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../services/coingecko_service.dart';

/// A search-as-you-type field for finding cryptocurrencies.
///
/// Uses CoinGecko's free search API. Results are sorted by market cap rank
/// so the most popular coins (Bitcoin, Ethereum, etc.) appear first.
///
/// On selection, [onSelected] is called with the chosen [CryptoSearchResult].
class CryptoSearchField extends StatefulWidget {
  final void Function(CryptoSearchResult result) onSelected;
  final String? initialText;

  const CryptoSearchField({
    super.key,
    required this.onSelected,
    this.initialText,
  });

  @override
  State<CryptoSearchField> createState() => _CryptoSearchFieldState();
}

class _CryptoSearchFieldState extends State<CryptoSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _service = CoinGeckoService();

  List<CryptoSearchResult> _results = [];
  bool _isSearching = false;
  bool _showDropdown = false;
  Timer? _debounce;
  CryptoSearchResult? _selectedResult;

  @override
  void initState() {
    super.initState();
    if (widget.initialText != null) {
      _controller.text = widget.initialText!;
    }
    _focusNode.addListener(() {
      if (_focusNode.hasFocus && _controller.text.isEmpty) {
        // Show popular coins when field is focused and empty
        _showPopularCoins();
      } else if (!_focusNode.hasFocus) {
        Future.delayed(const Duration(milliseconds: 200), () {
          if (mounted) setState(() => _showDropdown = false);
        });
      }
    });
  }

  Future<void> _showPopularCoins() async {
    setState(() {
      _isSearching = true;
      _showDropdown = true;
    });
    // Fetch top coins by searching for common ones
    final results = await _service.search('bitcoin ethereum solana', maxResults: 8);
    // If that doesn't work well, just show a curated list
    if (mounted) {
      setState(() {
        _results = results.isNotEmpty ? results : [];
        _isSearching = false;
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onTextChanged(String value) {
    if (value.isEmpty) {
      setState(() {
        _results = [];
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
      final results = await _service.search(value, maxResults: 10);
      if (mounted) {
        setState(() {
          _results = results;
          _isSearching = false;
        });
      }
    });
  }

  void _onResultSelected(CryptoSearchResult result) {
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
            labelText: 'Search Cryptocurrency',
            hintText: 'Search by name or symbol (e.g. Bitcoin, ETH, Solana)...',
            prefixIcon: const Icon(Icons.currency_bitcoin),
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
            constraints: const BoxConstraints(maxHeight: 300),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(AppRadii.small),
              boxShadow: AppShadows.soft(opacity: 0.18, y: 6, blur: 16),
            ),
            child: _isSearching && _results.isEmpty
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: Center(
                      child: Text('Searching...',
                          style: TextStyle(
                              color: AppColors.textSecondaryOn(context))),
                    ),
                  )
                : _results.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No coins found. Try "bitcoin", "ethereum", or "BTC".',
                          style: TextStyle(
                            color: AppColors.textSecondaryOn(context),
                            fontSize: 13,
                          ),
                        ),
                      )
                    : ListView.separated(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        itemCount: _results.length,
                        separatorBuilder: (context, index) =>
                            Divider(color: Theme.of(context).dividerColor, height: 1),
                        itemBuilder: (context, index) {
                          final result = _results[index];
                          return _CryptoResultTile(
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
                    '${_selectedResult!.symbol} · CoinGecko ID: ${_selectedResult!.id}',
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

class _CryptoResultTile extends StatelessWidget {
  final CryptoSearchResult result;
  final VoidCallback onTap;

  const _CryptoResultTile({required this.result, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Rank badge
            if (result.marketCapRank != null)
              Container(
                width: 36,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: _rankColor(result.marketCapRank!).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  '#${result.marketCapRank}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _rankColor(result.marketCapRank!),
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              )
            else
              Container(
                width: 36,
                padding: const EdgeInsets.symmetric(vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.grey.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: const Text(
                  '—',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 10),
                ),
              ),
            const SizedBox(width: 10),
            // Name + ID
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                  ),
                  Text(
                    result.id,
                    style: TextStyle(
                      color: AppColors.textTertiaryOn(context),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            // Symbol badge
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFFF7931A).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                result.symbol,
                style: const TextStyle(
                  color: Color(0xFFF7931A),
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color _rankColor(int rank) {
    if (rank <= 10) return const Color(0xFFFFD700); // Gold
    if (rank <= 50) return const Color(0xFF00838F); // Teal
    if (rank <= 200) return const Color(0xFF1565C0); // Blue
    return Colors.grey;
  }
}
