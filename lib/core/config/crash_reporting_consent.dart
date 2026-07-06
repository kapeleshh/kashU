/// Crash reporting is strictly opt-in: KashU is a privacy-focused finance
/// app, so nothing leaves the device unless the user explicitly enabled the
/// toggle in Settings.
///
/// [storedValue] is the raw value read from the settings box. Only an
/// explicit `true` counts as consent — a missing key, `null`, or a corrupted
/// value of any other type all mean "no".
bool crashReportingConsentGiven(dynamic storedValue) => storedValue == true;
