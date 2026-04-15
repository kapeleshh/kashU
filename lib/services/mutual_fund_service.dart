import 'dart:convert';
import 'package:http/http.dart' as http;
import '../core/utils/platform_config.dart';
import '../core/utils/result.dart';

/// A single mutual fund scheme from MFAPI.in
class MutualFundResult {
  /// AMFI scheme code (used as the asset symbol)
  final int schemeCode;

  /// Full scheme name (e.g. "SBI Bluechip Fund - Direct Plan - Growth")
  final String schemeName;

  /// Fund house (e.g. "SBI Mutual Fund")
  final String fundHouse;

  /// Scheme category (e.g. "Equity Scheme - Large Cap Fund")
  final String schemeCategory;

  /// Scheme type (e.g. "Open Ended Schemes")
  final String schemeType;

  /// Latest NAV in INR (null if not yet fetched)
  final double? nav;

  /// Date of latest NAV
  final String? navDate;

  const MutualFundResult({
    required this.schemeCode,
    required this.schemeName,
    required this.fundHouse,
    required this.schemeCategory,
    required this.schemeType,
    this.nav,
    this.navDate,
  });

  /// Whether this is a Direct Plan
  bool get isDirect =>
      schemeName.toLowerCase().contains('direct');

  /// Whether this is a Growth option
  bool get isGrowth =>
      schemeName.toLowerCase().contains('growth') &&
      !schemeName.toLowerCase().contains('idcw') &&
      !schemeName.toLowerCase().contains('dividend');

  /// Whether this is an IDCW/Dividend option
  bool get isIdcw =>
      schemeName.toLowerCase().contains('idcw') ||
      schemeName.toLowerCase().contains('dividend');

  /// Short display name — strips plan/option suffix for cleaner UI
  String get shortName {
    var name = schemeName
        .replaceAll(RegExp(r'\s*-\s*Direct Plan.*', caseSensitive: false), '')
        .replaceAll(RegExp(r'\s*-\s*Regular Plan.*', caseSensitive: false), '')
        .trim();
    return name.isEmpty ? schemeName : name;
  }

  /// Plan label: "Direct" or "Regular"
  String get planLabel => isDirect ? 'Direct' : 'Regular';

  /// Option label: "Growth" or "IDCW"
  String get optionLabel => isGrowth ? 'Growth' : isIdcw ? 'IDCW' : 'Other';

  factory MutualFundResult.fromListJson(Map<String, dynamic> json) {
    return MutualFundResult(
      schemeCode: json['schemeCode'] as int,
      schemeName: json['schemeName'] as String? ?? '',
      fundHouse: '',
      schemeCategory: '',
      schemeType: '',
    );
  }

  MutualFundResult withNav(double nav, String navDate) {
    return MutualFundResult(
      schemeCode: schemeCode,
      schemeName: schemeName,
      fundHouse: fundHouse,
      schemeCategory: schemeCategory,
      schemeType: schemeType,
      nav: nav,
      navDate: navDate,
    );
  }

  MutualFundResult withMeta({
    required String fundHouse,
    required String schemeCategory,
    required String schemeType,
  }) {
    return MutualFundResult(
      schemeCode: schemeCode,
      schemeName: schemeName,
      fundHouse: fundHouse,
      schemeCategory: schemeCategory,
      schemeType: schemeType,
      nav: nav,
      navDate: navDate,
    );
  }
}

/// Fetches Indian mutual fund data from MFAPI.in (free, no API key required).
///
/// Strategy:
/// 1. Fetch the full fund list once and cache it in memory.
/// 2. Search is done client-side (instant, no API call per keystroke).
/// 3. NAV is fetched on-demand when user selects a fund.
///
/// On web, requests are routed through the local CORS proxy.
class MutualFundService {
  static const String _baseUrl = 'https://api.mfapi.in/mf';

  final http.Client _client;

  /// In-memory cache of the full fund list
  List<MutualFundResult>? _cachedFundList;
  DateTime? _cacheTime;
  static const _cacheDuration = Duration(hours: 6);

  MutualFundService({http.Client? client})
      : _client = client ?? http.Client();

  /// Fetch and cache the full list of mutual fund schemes.
  /// Returns empty list on error.
  Future<List<MutualFundResult>> _getFundList() async {
    if (_cachedFundList != null &&
        _cacheTime != null &&
        DateTime.now().difference(_cacheTime!) < _cacheDuration) {
      return _cachedFundList!;
    }

    try {
      final response = await _client
          .get(PlatformConfig.buildUrl(_baseUrl))
          .timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) return [];

      final data = jsonDecode(response.body) as List<dynamic>;
      final funds = data
          .whereType<Map<String, dynamic>>()
          .map(MutualFundResult.fromListJson)
          .toList();

      _cachedFundList = funds;
      _cacheTime = DateTime.now();
      return funds;
    } catch (_) {
      return [];
    }
  }

  /// Search for mutual funds matching [query].
  ///
  /// Searches the full cached fund list client-side.
  /// Returns up to [maxResults] results.
  Future<List<MutualFundResult>> search(
    String query, {
    int maxResults = 20,
    bool directOnly = false,
    bool growthOnly = false,
  }) async {
    if (query.trim().length < 2) return [];

    final funds = await _getFundList();
    if (funds.isEmpty) return [];

    final terms = query.trim().toLowerCase().split(RegExp(r'\s+'));

    return funds
        .where((f) {
          final name = f.schemeName.toLowerCase();
          final matchesQuery = terms.every((t) => name.contains(t));
          if (!matchesQuery) return false;
          if (directOnly && !f.isDirect) return false;
          if (growthOnly && !f.isGrowth) return false;
          return true;
        })
        .take(maxResults)
        .toList();
  }

  /// Fetch the latest NAV for a given scheme code.
  ///
  /// Returns [Ok<MutualFundResult>] on success,
  /// or [Err<MutualFundResult>] with an error message on failure.
  Future<Result<MutualFundResult>> fetchNav(int schemeCode) async {
    try {
      final url = PlatformConfig.buildUrl('$_baseUrl/$schemeCode');
      final response = await _client
          .get(url)
          .timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return Err('HTTP ${response.statusCode} for scheme $schemeCode');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final meta = data['meta'] as Map<String, dynamic>? ?? {};
      final navData = data['data'] as List<dynamic>? ?? [];

      if (navData.isEmpty) {
        return Err('No NAV data returned for scheme $schemeCode');
      }

      final latest = navData[0] as Map<String, dynamic>;
      final navStr = latest['nav'] as String? ?? '0';
      final navDate = latest['date'] as String? ?? '';
      final nav = double.tryParse(navStr) ?? 0;

      if (nav <= 0) {
        return Err('Invalid NAV value for scheme $schemeCode');
      }

      final cached = _cachedFundList?.firstWhere(
        (f) => f.schemeCode == schemeCode,
        orElse: () => MutualFundResult(
          schemeCode: schemeCode,
          schemeName: meta['scheme_name'] as String? ?? '',
          fundHouse: meta['fund_house'] as String? ?? '',
          schemeCategory: meta['scheme_category'] as String? ?? '',
          schemeType: meta['scheme_type'] as String? ?? '',
        ),
      );

      final fund = (cached ?? MutualFundResult(
        schemeCode: schemeCode,
        schemeName: meta['scheme_name'] as String? ?? '',
        fundHouse: meta['fund_house'] as String? ?? '',
        schemeCategory: meta['scheme_category'] as String? ?? '',
        schemeType: meta['scheme_type'] as String? ?? '',
      )).withMeta(
        fundHouse: meta['fund_house'] as String? ?? cached?.fundHouse ?? '',
        schemeCategory:
            meta['scheme_category'] as String? ?? cached?.schemeCategory ?? '',
        schemeType: meta['scheme_type'] as String? ?? cached?.schemeType ?? '',
      ).withNav(nav, navDate);

      return Ok(fund);
    } catch (e) {
      return Err('Failed to fetch NAV for scheme $schemeCode: $e');
    }
  }

  /// Preload the fund list in the background (call on app start or when
  /// user navigates to Add Asset screen).
  Future<void> preload() async {
    await _getFundList();
  }
}
