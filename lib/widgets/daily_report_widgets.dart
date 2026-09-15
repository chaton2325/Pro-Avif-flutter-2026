import 'package:flutter/material.dart';
import '../utils/daily_report_colors.dart';

/// Identité visuelle partagée du module Rapport Journalier — un seul endroit pour le
/// dégradé, les cartes à accent et les badges, pour que chaque écran ait du relief
/// (dégradés, ombres colorées) plutôt que des cartes blanches plates à bordure grise.

const dailyReportHeaderGradient = LinearGradient(
  colors: [DailyReportColors.green900, DailyReportColors.green700],
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
);

class DailySortOption<T> {
  final T value;
  final String label;
  const DailySortOption(this.value, this.label);
}

/// Barre recherche + tri compacte (une seule ligne, ~38px) — réutilisée par tous les
/// écrans de référentiel admin (réceptions, effectifs, vaccins, personnel) pour éviter
/// de retaper le même Row à chaque fois.
class DailySearchSortBar<T> extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final ValueChanged<String> onSearchChanged;
  final T sortValue;
  final List<DailySortOption<T>> sortOptions;
  final ValueChanged<T> onSortChanged;

  const DailySearchSortBar({
    super.key,
    required this.controller,
    required this.hintText,
    required this.onSearchChanged,
    required this.sortValue,
    required this.sortOptions,
    required this.onSortChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Icon(Icons.search_rounded, size: 17, color: Colors.grey.shade400),
                const SizedBox(width: 6),
                Expanded(
                  child: TextField(
                    controller: controller,
                    onChanged: onSearchChanged,
                    style: const TextStyle(fontSize: 12.5),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      hintText: hintText,
                      hintStyle: TextStyle(fontSize: 12.5, color: Colors.grey.shade400),
                    ),
                  ),
                ),
                if (controller.text.isNotEmpty)
                  GestureDetector(
                    onTap: () {
                      controller.clear();
                      onSearchChanged('');
                    },
                    child: Icon(Icons.close_rounded, size: 16, color: Colors.grey.shade400),
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.grey.shade200),
          ),
          child: PopupMenuButton<T>(
            padding: EdgeInsets.zero,
            tooltip: 'Trier',
            icon: const Icon(Icons.sort_rounded, size: 18, color: DailyReportColors.green700),
            onSelected: onSortChanged,
            itemBuilder: (context) => [
              for (final o in sortOptions)
                CheckedPopupMenuItem(
                  value: o.value,
                  checked: sortValue == o.value,
                  child: Text(o.label, style: const TextStyle(fontSize: 13)),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

PreferredSizeWidget dailyReportAppBar(
  String title, {
  List<Widget>? actions,
  Widget? leading,
  String? subtitle,
  PreferredSizeWidget? bottom,
}) {
  return AppBar(
    leading: leading,
    foregroundColor: Colors.white,
    elevation: 4,
    shadowColor: DailyReportColors.green900.withValues(alpha: 0.4),
    title: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(title, style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.2, fontSize: 17)),
        if (subtitle != null)
          Text(subtitle, style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.78), fontWeight: FontWeight.w500)),
      ],
    ),
    flexibleSpace: Container(decoration: const BoxDecoration(gradient: dailyReportHeaderGradient)),
    actions: actions,
    bottom: bottom,
  );
}

/// Carte à accent : remplace les cartes blanches à simple bordure grise par un liseré de
/// couleur + une ombre teintée verte, pour donner du relief sans surcharger.
class DailyReportCard extends StatelessWidget {
  final List<Widget> children;
  final Color accentColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  const DailyReportCard({
    super.key,
    required this.children,
    this.accentColor = DailyReportColors.green600,
    this.padding = const EdgeInsets.all(16),
    this.margin = const EdgeInsets.only(bottom: 14),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border(left: BorderSide(color: accentColor, width: 4)),
        boxShadow: [
          BoxShadow(color: DailyReportColors.green900.withValues(alpha: 0.06), blurRadius: 16, offset: const Offset(0, 6)),
        ],
      ),
      child: Padding(
        padding: padding,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: children),
      ),
    );
  }
}

/// Titre de section avec puce colorée + trait, pour remplacer le simple texte gris majuscule.
class DailyReportSectionLabel extends StatelessWidget {
  final String text;
  final IconData? icon;
  const DailyReportSectionLabel(this.text, {super.key, this.icon});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, top: 6),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 15, color: DailyReportColors.green700),
            const SizedBox(width: 6),
          ],
          Text(
            text.toUpperCase(),
            style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: DailyReportColors.green700, letterSpacing: 0.6),
          ),
          const SizedBox(width: 8),
          Expanded(child: Container(height: 1.4, color: DailyReportColors.green100)),
        ],
      ),
    );
  }
}

/// Bloc statistique en dégradé (remplace les cases blanches à bordure fine des récapitulatifs).
class DailyReportStatTile extends StatelessWidget {
  final String value;
  final String label;
  final Color color;
  final IconData? icon;

  const DailyReportStatTile({
    super.key,
    required this.value,
    required this.label,
    this.color = DailyReportColors.green700,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.72)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [BoxShadow(color: color.withValues(alpha: 0.32), blurRadius: 10, offset: const Offset(0, 5))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, color: Colors.white, size: 16), const SizedBox(height: 4)],
          Text(value, style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 17, color: Colors.white)),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 9.3, color: Colors.white.withValues(alpha: 0.88), fontWeight: FontWeight.w700, letterSpacing: 0.2),
          ),
        ],
      ),
    );
  }
}

/// Badge de statut plein (remplace les pastilles pâles à fond translucide uniforme).
class DailyReportStatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;
  final bool solid;

  const DailyReportStatusBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
    this.solid = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 13, color: solid ? Colors.white : color), const SizedBox(width: 5)],
          Text(
            label,
            style: TextStyle(color: solid ? Colors.white : color, fontWeight: FontWeight.w800, fontSize: 11, letterSpacing: 0.3),
          ),
        ],
      ),
    );
  }
}

/// Tuile de menu (module_choice / admin hub) : icône en médaillon dégradé + ombre colorée,
/// plus vivante que l'ancienne carte blanche à icône plate.
class DailyReportMenuTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final String? tag;

  const DailyReportMenuTile({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.tag,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 16, offset: const Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [color, color.withValues(alpha: 0.7)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [BoxShadow(color: color.withValues(alpha: 0.35), blurRadius: 10, offset: const Offset(0, 4))],
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade600, fontSize: 11.5)),
                  ],
                ),
              ),
              if (tag != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(999)),
                  child: Text(tag!, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: color)),
                ),
              Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ),
    );
  }
}
