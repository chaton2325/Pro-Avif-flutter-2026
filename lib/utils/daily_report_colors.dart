import 'package:flutter/material.dart';

/// Palette du module Rapport Journalier (vert/jaune), reprise telle quelle de la maquette
/// (Maquettes-pro-avif/maquettes/rapport-journalier.html) — le thème global de l'app (orange,
/// voir main.dart) reste celui du module Pesées et n'est pas modifié.
class DailyReportColors {
  DailyReportColors._();

  static const green900 = Color(0xFF12331A);
  static const green700 = Color(0xFF206B2E);
  static const green600 = Color(0xFF2E8B3D);
  static const green100 = Color(0xFFE2F3E1);

  static const yellow600 = Color(0xFFA8720C);
  static const yellow500 = Color(0xFFE2A319);
  static const yellow100 = Color(0xFFFDF1DA);

  static const purple600 = Color(0xFF6D28D9);
  static const purple100 = Color(0xFFEDE4FB);

  static const blue600 = Color(0xFF1D6FB8);
  static const blue100 = Color(0xFFE0EDF9);

  static const grey500 = Color(0xFF8A978A);
  static const grey100 = Color(0xFFECEEE9);

  static const surface = Color(0xFFF3F6F1);

  /// Une couleur par aliment (jamais deux aliments avec la même), utilisée à la fois dans le
  /// formulaire de saisie et le récapitulatif pour qu'un même aliment garde la même couleur
  /// partout. Volontairement à l'écart du vert/jaune/rouge/violet déjà utilisés ailleurs pour
  /// un statut (validé/alerte/mortalité/en attente), pour ne pas laisser croire à un autre sens.
  static const List<Color> alimentPalette = [
    Color(0xFF2563EB), // bleu
    Color(0xFF0D9488), // sarcelle
    Color(0xFF4F46E5), // indigo
    Color(0xFF92400E), // brun
    Color(0xFFDB2777), // rose
    Color(0xFF0E7490), // cyan
    Color(0xFFEA580C), // orange foncé
    Color(0xFF0284C7), // bleu clair
    Color(0xFF4D7C0F), // vert olive
    Color(0xFF475569), // ardoise
  ];
}
