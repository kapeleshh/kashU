import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// The SIL Open Font License texts of the fonts bundled in assets/fonts/,
/// keyed by the family name shown on the licences page. The OFL requires the
/// licence to travel with the font files.
const Map<String, String> bundledFontLicenseAssets = {
  'Quicksand': 'assets/fonts/quicksand/OFL.txt',
  'Plus Jakarta Sans': 'assets/fonts/plus_jakarta_sans/OFL.txt',
};

/// One [LicenseEntry] per bundled font family, read from [bundle].
Stream<LicenseEntry> fontLicenseEntries(AssetBundle bundle) async* {
  for (final font in bundledFontLicenseAssets.entries) {
    yield LicenseEntryWithLineBreaks(
      <String>[font.key],
      await bundle.loadString(font.value),
    );
  }
}

/// Adds the bundled fonts' licences to [LicenseRegistry], so Flutter's
/// licences page lists them next to the packages. Call once, from `main()`:
/// the registry has no de-duplication, and the collector only runs when the
/// page is opened.
void registerFontLicenses() =>
    LicenseRegistry.addLicense(() => fontLicenseEntries(rootBundle));
