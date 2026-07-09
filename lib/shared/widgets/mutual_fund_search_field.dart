import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/theme/app_decorations.dart';
import '../../services/mutual_fund_service.dart';

/// Plan filter: Direct or Regular
enum MfPlanFilter { all, direct, regular }

/// Option filter: Growth or IDCW
enum MfOptionFilter { all, growth, idcw }

/// A search-as-you-type field for finding Indian mutual funds.
///
/// Uses MFAPI.in (37,500+ funds). The full fund list is fetched once
/// and cached; all searching is done client-side (instant).
///
/// Filter chips let users narrow by plan (Direct/Regular) and
/// option (Growth/IDCW) before or after typing.
///
/// On selection, [onSelected] is called with the chosen [MutualFundResult].
class MutualFundSearchField extends StatefulWidget {
  final void Function(MutualFundResult result) onSelected;
  final String? initialText;

  const MutualFundSearchField({
    super.key,
    required this.onSelected,
    this.initialText,
  });

  @override
  State<MutualFundSearchField> createState() => _MutualFundSearchFieldState();
}

class _MutualFundSearchFieldState extends State<MutualFundSearchField> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  final _service = MutualFundService();

  List<MutualFundResult> _results = [];
  bool _isLoading = false;
  bool _isLoadingList = false;
  bool _showDropdown = false;
  Timer? _debounce;
  MutualFundResult? _selectedResult;

  MfPlanFilter _planFilter = MfPlanFilter.direct; // default: Direct
  MfOptionFilter _optionFilter = MfOptionFilter.growth; // default: Growth

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
    // Preload fund list in background
    _preloadFunds();
  }

  Future<void> _preloadFunds() async {
    setState(() => _isLoadingList = true);
    await _service.preload();
    if (mounted) setState(() => _isLoadingList = false);
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

    if (_selectedResult != null && value == _selectedResult!.schemeName) return;

    setState(() {
      _selectedResult = null;
      _isLoading = true;
      _showDropdown = true;
    });

    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () async {
      final results = await _service.search(
        value,
        maxResults: 15,
        directOnly: _planFilter == MfPlanFilter.direct,
        growthOnly: _optionFilter == MfOptionFilter.growth,
      );
      if (mounted) {
        setState(() {
          _results = results;
          _isLoading = false;
        });
      }
    });
  }

  void _onFilterChanged() {
    // Re-run search with new filters if there's text
    if (_controller.text.isNotEmpty) {
      _onTextChanged(_controller.text);
    }
  }

  void _onResultSelected(MutualFundResult result) {
    setState(() {
      _selectedResult = result;
      _controller.text = result.schemeName;
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
        // Filter chips row
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // Plan filters
              _buildPlanChip(MfPlanFilter.direct, 'Direct',
                  const Color(0xFF1565C0)),
              const SizedBox(width: 6),
              _buildPlanChip(MfPlanFilter.regular, 'Regular',
                  const Color(0xFF6A1B9A)),
              const SizedBox(width: 6),
              _buildPlanChip(MfPlanFilter.all, 'All Plans',
                  Colors.grey),
              const SizedBox(width: 12),
              // Divider
              Container(
                  width: 1,
                  height: 20,
                  color: Theme.of(context).dividerColor),
              const SizedBox(width: 12),
              // Option filters
              _buildOptionChip(MfOptionFilter.growth, 'Growth',
                  const Color(0xFF2E7D32)),
              const SizedBox(width: 6),
              _buildOptionChip(MfOptionFilter.idcw, 'IDCW',
                  const Color(0xFFE65100)),
              const SizedBox(width: 6),
              _buildOptionChip(MfOptionFilter.all, 'All Options',
                  Colors.grey),
            ],
          ),
        ),

        const SizedBox(height: 10),

        // Search field
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _onTextChanged,
          decoration: InputDecoration(
            labelText: 'Search Mutual Fund',
            hintText: _isLoadingList
                ? 'Loading fund list...'
                : 'Search by fund name (e.g. SBI Flexi Cap, HDFC Mid Cap)...',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _isLoading || _isLoadingList
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
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
            child: _isLoading && _results.isEmpty
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
                          'No funds found. Try different keywords or change filters.',
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
                          // When a plan/option filter is active every row
                          // would carry the same badge — hide it.
                          return _MfResultTile(
                            result: result,
                            showPlanBadge: _planFilter == MfPlanFilter.all,
                            showOptionBadge:
                                _optionFilter == MfOptionFilter.all,
                            onTap: () => _onResultSelected(result),
                          );
                        },
                      ),
          ),
        ],

      ],
    );
  }

  Widget _buildPlanChip(MfPlanFilter filter, String label, Color color) {
    final isSelected = _planFilter == filter;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _planFilter = filter);
        _onFilterChanged();
      },
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isSelected ? color : color.withValues(alpha: 0.3),
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }

  Widget _buildOptionChip(MfOptionFilter filter, String label, Color color) {
    final isSelected = _optionFilter == filter;
    return FilterChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: isSelected ? Colors.white : color,
        ),
      ),
      selected: isSelected,
      onSelected: (_) {
        setState(() => _optionFilter = filter);
        _onFilterChanged();
      },
      selectedColor: color,
      backgroundColor: color.withValues(alpha: 0.08),
      checkmarkColor: Colors.white,
      side: BorderSide(
        color: isSelected ? color : color.withValues(alpha: 0.3),
        width: 1,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 4),
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
    );
  }
}

class _MfResultTile extends StatelessWidget {
  final MutualFundResult result;
  final bool showPlanBadge;
  final bool showOptionBadge;
  final VoidCallback onTap;

  const _MfResultTile({
    required this.result,
    required this.showPlanBadge,
    required this.showOptionBadge,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final planColor = result.isDirect
        ? const Color(0xFF1565C0)
        : const Color(0xFF6A1B9A);
    final optionColor = result.isGrowth
        ? const Color(0xFF2E7D32)
        : const Color(0xFFE65100);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    result.shortName,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (showPlanBadge || showOptionBadge) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (showPlanBadge)
                          _badge(result.planLabel, planColor),
                        if (showPlanBadge && showOptionBadge)
                          const SizedBox(width: 4),
                        if (showOptionBadge)
                          _badge(result.optionLabel, optionColor),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            // Scheme code
            Text(
              '#${result.schemeCode}',
              style: TextStyle(
                color: AppColors.textTertiaryOn(context),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _badge(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 10,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
