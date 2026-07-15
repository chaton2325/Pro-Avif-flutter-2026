import 'package:flutter/foundation.dart';

/// Vrai sur desktop (Windows, macOS, Linux) : la navigation s'affiche
/// en barre latérale au lieu de la barre du bas.
bool get isDesktop =>
    !kIsWeb &&
    (defaultTargetPlatform == TargetPlatform.windows ||
        defaultTargetPlatform == TargetPlatform.macOS ||
        defaultTargetPlatform == TargetPlatform.linux);
