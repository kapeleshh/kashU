import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';

import 'package:kashu/core/constants/app_constants.dart';
import 'package:kashu/data/security/database_key_service.dart';

class MockSecureStorage extends Mock implements FlutterSecureStorage {}

/// In-memory stand-in for the platform keystore: `read` returns whatever was
/// last written, so tests exercise real create → reopen sequences.
class FakeSecureStorage extends Fake implements FlutterSecureStorage {
  final Map<String, String> values = {};
  int deleteAllCalls = 0;

  @override
  Future<String?> read({
    required String key,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async =>
      values[key];

  @override
  Future<void> write({
    required String key,
    required String? value,
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (value == null) {
      values.remove(key);
    } else {
      values[key] = value;
    }
  }

  @override
  Future<void> deleteAll({
    IOSOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    MacOsOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    deleteAllCalls++;
    values.clear();
  }
}

void main() {
  late Directory tempDir;
  late FakeSecureStorage storage;
  late DatabaseKeyService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('kashu_key_test');
    Hive.init(tempDir.path);
    storage = FakeSecureStorage();
    service = DatabaseKeyService(storage: storage);
  });

  tearDown(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Simulate an existing install: a settings box with data, encrypted with
  /// [cipher], then closed as it would be between launches.
  Future<void> seedSettingsBox(HiveAesCipher cipher) async {
    final box =
        await Hive.openBox(AppConstants.settingsBox, encryptionCipher: cipher);
    await box.put(AppConstants.keyOnboardingComplete, true);
    await box.close();
  }

  test('a fresh install creates, stores and returns a new key', () async {
    final result = await service.loadOrCreate();

    expect(result.problem, isNull);
    expect(result.cipher, isNotNull);
    final stored = storage.values[DatabaseKeyService.storageKey];
    expect(stored, isNotNull);
    expect(base64Decode(stored!), hasLength(32));
  });

  test('the same key is returned on the next launch and opens the data',
      () async {
    final first = await service.loadOrCreate();
    await seedSettingsBox(first.cipher!);
    await Hive.close();

    final second = await DatabaseKeyService(storage: storage).loadOrCreate();

    expect(second.problem, isNull);
    final box = await Hive.openBox(AppConstants.settingsBox,
        encryptionCipher: second.cipher);
    expect(box.get(AppConstants.keyOnboardingComplete), isTrue);
  });

  test(
      'a missing key while encrypted boxes exist is refused — never replaced '
      'by a new key that cannot open them', () async {
    // Phone backup restored without the Keystore key: the boxes came across,
    // secure storage reads back nothing.
    final original = await service.loadOrCreate();
    await seedSettingsBox(original.cipher!);
    await Hive.close();
    storage.values.clear();

    final result = await DatabaseKeyService(storage: storage).loadOrCreate();

    expect(result.cipher, isNull);
    expect(result.problem, DatabaseKeyProblem.missing);
    expect(storage.values, isEmpty, reason: 'no replacement key written');
  });

  test('a key-store read that throws is reported, not crashed on', () async {
    final original = await service.loadOrCreate();
    await seedSettingsBox(original.cipher!);
    await Hive.close();

    final throwing = MockSecureStorage();
    when(() => throwing.read(key: any(named: 'key'))).thenThrow(
        PlatformException(code: 'Exception', message: 'AEADBadTagException'));

    final result = await DatabaseKeyService(storage: throwing).loadOrCreate();

    expect(result.cipher, isNull);
    expect(result.problem, DatabaseKeyProblem.unreadable);
    expect(result.error, isA<PlatformException>());
  });

  test(
      'an unreadable key store with no data starts fresh — the state right '
      'after a reset', () async {
    final throwing = MockSecureStorage();
    when(() => throwing.read(key: any(named: 'key')))
        .thenThrow(PlatformException(code: 'Exception'));
    when(() => throwing.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        )).thenAnswer((_) async {});

    final result = await DatabaseKeyService(storage: throwing).loadOrCreate();

    expect(result.problem, isNull);
    expect(result.cipher, isNotNull);
  });

  test('a stored key that is not the one the data was written with is '
      'refused before any box is opened', () async {
    final original = await service.loadOrCreate();
    await seedSettingsBox(original.cipher!);
    await Hive.close();

    storage.values[DatabaseKeyService.storageKey] =
        base64Encode(List<int>.filled(32, 7));

    final result = await DatabaseKeyService(storage: storage).loadOrCreate();

    expect(result.problem, DatabaseKeyProblem.mismatch);
    // The data is untouched: the original key still opens it.
    final box = await Hive.openBox(AppConstants.settingsBox,
        encryptionCipher: original.cipher);
    expect(box.get(AppConstants.keyOnboardingComplete), isTrue);
  });

  test('a damaged stored key (wrong length / not base64) is unreadable',
      () async {
    storage.values[DatabaseKeyService.storageKey] = base64Encode([1, 2, 3]);
    expect((await service.loadOrCreate()).problem,
        DatabaseKeyProblem.unreadable);

    storage.values[DatabaseKeyService.storageKey] = 'not base64!';
    expect((await service.loadOrCreate()).problem,
        DatabaseKeyProblem.unreadable);
  });

  test('an install from before the key check gets one recorded', () async {
    // Existing data + key, but no key_check_box yet.
    final keyBytes = Hive.generateSecureKey();
    storage.values[DatabaseKeyService.storageKey] = base64Encode(keyBytes);
    await seedSettingsBox(HiveAesCipher(keyBytes));
    expect(await Hive.boxExists(AppConstants.keyCheckBox), isFalse);

    final result = await service.loadOrCreate();
    expect(result.problem, isNull);
    await Hive.close();

    // A different key on the next launch is now caught.
    storage.values[DatabaseKeyService.storageKey] =
        base64Encode(List<int>.filled(32, 9));
    expect((await DatabaseKeyService(storage: storage).loadOrCreate()).problem,
        DatabaseKeyProblem.mismatch);
  });

  test('reset deletes every box, the key check and the stored key', () async {
    final original = await service.loadOrCreate();
    await seedSettingsBox(original.cipher!);
    await Hive.openBox(AppConstants.priceCacheBox,
        encryptionCipher: original.cipher);

    await service.reset();

    for (final name in AppConstants.encryptedBoxes) {
      expect(await Hive.boxExists(name), isFalse, reason: name);
    }
    expect(await Hive.boxExists(AppConstants.keyCheckBox), isFalse);
    expect(storage.deleteAllCalls, 1);

    // The next launch behaves like a fresh install.
    final fresh = await service.loadOrCreate();
    expect(fresh.problem, isNull);
    expect(fresh.cipher, isNotNull);
  });
}
