import 'package:flutter/widgets.dart';

import 'gen/app_localizations.dart';

export 'gen/app_localizations.dart';

extension L10nX on BuildContext {
  /// Zentrale UI-Texte (lib/l10n/app_de.arb)
  S get s => S.of(this);
}
