// The licences of what the app bundles that Flutter does not collect by
// itself: the fonts in assets/fonts and the Rust crates compiled into the
// native library (assets/licences, generated from native/Cargo.lock by
// tool/licences.sh). Registered at startup so the Licences page lists them
// with the packages.

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show AssetBundle, rootBundle;

const _fontLicences = {
  'Atkinson Hyperlegible Next':
      'assets/fonts/licenses/atkinsonhyperlegiblenext-OFL.txt',
  'Bricolage Grotesque': 'assets/fonts/licenses/bricolagegrotesque-OFL.txt',
  'Fragment Mono': 'assets/fonts/licenses/fragmentmono-OFL.txt',
};

void registerFontLicences() {
  LicenseRegistry.addLicense(() async* {
    for (final font in _fontLicences.entries) {
      yield LicenseEntryWithLineBreaks([
        font.key,
      ], await rootBundle.loadString(font.value));
    }
  });
}

/// The crate list the desktop app ships (the embedded Core included).
const desktopCratesAsset = 'assets/licences/core-crates.json';

/// The crate list the phone app ships (the client-only build).
const phoneCratesAsset = 'assets/licences/phone-crates.json';

/// One licence text of one Rust crate. The Licences page lists these under
/// "Core crates", apart from Dart packages of the same name.
class CrateLicenceEntry extends LicenseEntry {
  const CrateLicenceEntry({
    required this.name,
    required this.version,
    required this.expression,
    required this.text,
  });

  final String name;
  final String version;

  /// The licence the crate declares, such as `Apache-2.0 OR MIT`.
  final String expression;
  final String text;

  @override
  Iterable<String> get packages => [name];

  @override
  Iterable<LicenseParagraph> get paragraphs => [LicenseParagraph(text, 0)];
}

/// The entries of a generated crate list ([json] is the file's content).
List<CrateLicenceEntry> parseCrateLicences(String json) {
  final data = jsonDecode(json) as Map<String, Object?>;
  final texts = (data['texts'] as List).cast<String>();
  return [
    for (final crate in (data['crates'] as List).cast<Map<String, Object?>>())
      for (final index in (crate['texts'] as List).cast<int>())
        CrateLicenceEntry(
          name: crate['name'] as String,
          version: crate['version'] as String,
          expression: crate['license'] as String,
          text: texts[index],
        ),
  ];
}

/// Registers the crate licences from [asset] (the phone passes
/// [phoneCratesAsset]).
void registerCrateLicences({
  String asset = desktopCratesAsset,
  AssetBundle? bundle,
}) {
  LicenseRegistry.addLicense(() async* {
    final json = await (bundle ?? rootBundle).loadString(asset);
    yield* Stream.fromIterable(parseCrateLicences(json));
  });
}
