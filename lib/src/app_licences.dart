// The licences of what the app bundles that Flutter does not collect by
// itself: the fonts in assets/fonts. Registered at startup so the Licences
// page lists them with the packages.

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart'
    show LicenseEntryWithLineBreaks, rootBundle;

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
