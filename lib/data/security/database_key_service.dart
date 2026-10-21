import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../core/constants/app_constants.dart';

/// Why the encrypted database cannot be opened with the stored key.
enum DatabaseKeyProblem {
  /// The platform keystore/keychain threw while the key was read. Typical
  /// after a phone backup was restored onto a new device: the secure-storage
  /// file came across, the hardware-bound key that decrypts it did not.
  unreadable,

  /// No key is stored, yet encrypted boxes already exist. Creating a fresh
  /// key now would leave the existing data permanently unreadable.
  missing,

  /// A key is stored, but it is not the one the boxes were written with.
  mismatch,
}

/// Outcome of [DatabaseKeyService.loadOrCreate]: a [cipher] to open the
/// boxes with, or the [problem] that stops startup.
class DatabaseKeyResult {
  final HiveAesCipher? cipher;
  final DatabaseKeyProblem? problem;

  /// The underlying exception, for logging only — never shown raw to users.
  final Object? error;

  const DatabaseKeyResult.ok(HiveAesCipher this.cipher)
      : problem = null,
        error = null;

  const DatabaseKeyResult.failed(DatabaseKeyProblem this.problem,
      {this.error})
      : cipher = null;
}

/// Loads the AES key that encrypts every Hive box, deciding — before any box
/// is opened — whether it is safe to use.
///
/// Opening an encrypted box with the wrong key does not fail: Hive's crash
/// recovery treats every frame as corrupt and truncates the file, silently
/// destroying the portfolio. So this never creates a key while boxes exist,
/// and it compares the stored key with a key check recorded alongside the
/// data (CRC32 of the key's SHA-256, kept in an unencrypted box — it reveals
/// nothing usable about a random 256-bit key).
class DatabaseKeyService {
  /// Secure-storage entry holding the base64 AES key. Never rename: existing
  /// installs read their key under this name.
  static const String storageKey = 'kashu_hive_aes_key';

  static const String _keyCheckField = 'key_crc';

  final FlutterSecureStorage _storage;

  DatabaseKeyService({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(encryptedSharedPreferences: true),
            );

  /// Read the stored key, or create one on a fresh install.
  Future<DatabaseKeyResult> loadOrCreate() async {
    String? stored;
    Object? readError;
    try {
      stored = await _storage.read(key: storageKey);
    } catch (e) {
      readError = e;
    }

    if (stored == null) {
      if (await _hasExistingData()) {
        return readError != null
            ? DatabaseKeyResult.failed(DatabaseKeyProblem.unreadable,
                error: readError)
            : const DatabaseKeyResult.failed(DatabaseKeyProblem.missing);
      }
      // Nothing to protect yet (fresh install, or right after a reset):
      // start over with a new key — this also recovers a keystore entry that
      // could no longer be read.
      return _createKey();
    }

    final HiveAesCipher cipher;
    try {
      cipher = HiveAesCipher(base64Decode(stored));
    } catch (e) {
      // Not base64, or not 32 bytes: the stored value is damaged.
      return DatabaseKeyResult.failed(DatabaseKeyProblem.unreadable, error: e);
    }

    final recorded = await _readKeyCheck();
    if (recorded == null) {
      // Installs from before the key check existed have nothing to compare
      // against yet — record it now, so the next launch is protected.
      await _recordKeyCheck(cipher);
    } else if (recorded != cipher.calculateKeyCrc()) {
      return const DatabaseKeyResult.failed(DatabaseKeyProblem.mismatch);
    }
    return DatabaseKeyResult.ok(cipher);
  }

  /// Delete every box and the stored key, so the next [loadOrCreate] starts
  /// a fresh, empty database. Irreversible — the recovery screen only calls
  /// this after the user confirmed.
  Future<void> reset() async {
    for (final name in [
      ...AppConstants.encryptedBoxes,
      AppConstants.keyCheckBox,
    ]) {
      await Hive.deleteBoxFromDisk(name);
    }
    // Boxes first: if this throws, the old key still opens the now-empty
    // boxes. deleteAll (not delete) also clears an undecryptable Android
    // EncryptedSharedPreferences keyset left behind by a restore.
    await _storage.deleteAll();
  }

  Future<DatabaseKeyResult> _createKey() async {
    final keyBytes = Hive.generateSecureKey();
    try {
      await _storage.write(key: storageKey, value: base64Encode(keyBytes));
    } catch (e) {
      return DatabaseKeyResult.failed(DatabaseKeyProblem.unreadable, error: e);
    }
    final cipher = HiveAesCipher(keyBytes);
    await _recordKeyCheck(cipher);
    return DatabaseKeyResult.ok(cipher);
  }

  /// True if any encrypted box exists. An existence check that throws counts
  /// as "exists": wrongly refusing to create a key is recoverable from the
  /// recovery screen, wrongly creating one destroys data.
  Future<bool> _hasExistingData() async {
    for (final name in AppConstants.encryptedBoxes) {
      try {
        if (await Hive.boxExists(name)) return true;
      } catch (e) {
        debugPrint('[KashU] Could not check for box $name: $e');
        return true;
      }
    }
    return false;
  }

  Future<int?> _readKeyCheck() async {
    try {
      final box = await Hive.openBox(AppConstants.keyCheckBox);
      final value = box.get(_keyCheckField);
      return value is int ? value : null;
    } catch (e) {
      // The check is a safety net, not a gate: an unreadable check box
      // degrades to the pre-check behaviour instead of blocking startup.
      debugPrint('[KashU] Key check unavailable: $e');
      return null;
    }
  }

  Future<void> _recordKeyCheck(HiveAesCipher cipher) async {
    try {
      final box = await Hive.openBox(AppConstants.keyCheckBox);
      await box.put(_keyCheckField, cipher.calculateKeyCrc());
    } catch (e) {
      debugPrint('[KashU] Could not record the key check: $e');
    }
  }
}
