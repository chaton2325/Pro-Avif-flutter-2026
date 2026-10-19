import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'admin_feed_receptions_screen.dart';
import 'admin_room_transfers_screen.dart';
import 'admin_egg_shipments_screen.dart';
import 'admin_inventory_screen.dart';
import 'admin_daily_report_settings_tab.dart';
import 'admin_daily_report_starting_values_tab.dart';
import 'building_tracking_screen.dart';
import 'validator_overview_screen.dart';

/// Point d'entrée admin du module Rapport Journalier : l'administrateur a accès complet aux
/// deux modules (cahier des charges section 4) — tableau de suivi + tous les référentiels.
///
/// Une seule grille de boutons carrés, deux par ligne (même design que l'accueil rédacteur,
/// voir DailyReportSquareMenuTile / _actionsGrid dans daily_report_home_screen.dart) — jamais
/// groupée par section : largeur calculée (LayoutBuilder), pas une grille rigide qui force un
/// carré dans une cellule trop grande.
class AdminDailyReportHubScreen extends StatefulWidget {
  const AdminDailyReportHubScreen({super.key});

  @override
  State<AdminDailyReportHubScreen> createState() => _AdminDailyReportHubScreenState();
}

class _AdminDailyReportHubScreenState extends State<AdminDailyReportHubScreen> {
  final MongoService _mongoService = MongoService();
  late DateTime _now;
  Timer? _clockTimer;
  int _pendingReceptions = 0;
  int _pendingEggShipments = 0;
  int _pendingInventoryRequests = 0;
  int _tab = 0; // 0 = Accueil, 1 = Valeurs de départ, 2 = Paramètres

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    // Toutes les secondes : une simple horloge sur une carte de bienvenue, pas un compteur
    // critique — la fréquence n'a besoin d'être ni plus précise ni économisée davantage.
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadPendingReceptions();
    _loadPendingEggShipments();
    _loadPendingInventoryRequests();
  }

  // Pas de farmName = toutes fermes confondues (vue admin globale).
  Future<void> _loadPendingReceptions() async {
    final count = await _mongoService.getPendingReceptionsCount();
    if (!mounted) return;
    setState(() => _pendingReceptions = count);
  }

  Future<void> _loadPendingEggShipments() async {
    final count = await _mongoService.getPendingEggShipmentsCount();
    if (!mounted) return;
    setState(() => _pendingEggShipments = count);
  }

  Future<void> _loadPendingInventoryRequests() async {
    final count = await _mongoService.getPendingInventoryRequestsCount();
    if (!mounted) return;
    setState(() => _pendingInventoryRequests = count);
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        icon: Icons.fact_check_rounded,
        color: DailyReportColors.green700,
        title: 'Tableau de suivi',
        subtitle: 'Valider ou renvoyer les rapports du jour',
        badgeCount: 0,
        builder: (BuildContext c) => ValidatorOverviewScreen(user: MongoService().currentUser!),
      ),
      (
        icon: Icons.insights_rounded,
        color: DailyReportColors.green900,
        title: 'Suivi bâtiment',
        subtitle: 'Effectifs & aliments : ce qui reste, par ferme',
        badgeCount: 0,
        builder: (BuildContext c) => const BuildingTrackingScreen(),
      ),
      (
        icon: Icons.local_shipping_rounded,
        color: DailyReportColors.yellow600,
        title: 'Réceptions — toutes fermes',
        subtitle: 'En attente et historique, tous bâtiments',
        badgeCount: _pendingReceptions,
        builder: (BuildContext c) => const AdminFeedReceptionsScreen(),
      ),
      (
        icon: Icons.swap_horiz_rounded,
        color: DailyReportColors.purple600,
        title: 'Transferts de sujets',
        subtitle: 'Déplacer des sujets entre salles',
        badgeCount: 0,
        builder: (BuildContext c) => const AdminRoomTransfersScreen(),
      ),
      (
        icon: Icons.local_shipping_rounded,
        color: DailyReportColors.purple600,
        title: "Expéditions d'œufs",
        subtitle: 'Œufs à couver (OAC) vers un couvoir',
        badgeCount: _pendingEggShipments,
        builder: (BuildContext c) => const AdminEggShipmentsScreen(),
      ),
      (
        icon: Icons.fact_check_outlined,
        color: DailyReportColors.green700,
        title: 'Inventaire',
        subtitle: 'Corriger le stock aliment/œufs — demandes à valider',
        badgeCount: _pendingInventoryRequests,
        builder: (BuildContext c) => const AdminInventoryScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        'Rapport Journalier',
        subtitle: const ['Espace administrateur', 'Valeurs de départ', 'Paramètres'][_tab],
      ),
      bottomNavigationBar: _bottomNav(),
      // IndexedStack : chaque onglet garde son état (défilement, données chargées) quand on
      // passe de l'un à l'autre, au lieu d'être reconstruit à chaque fois.
      body: IndexedStack(
        index: _tab,
        children: [
          ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _welcomeCard(),
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              const spacing = 12.0;
              final tileWidth = (constraints.maxWidth - spacing) / 2;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final e in items)
                    SizedBox(
                      width: tileWidth,
                      child: Badge(
                        isLabelVisible: e.badgeCount > 0,
                        label: Text('${e.badgeCount}'),
                        backgroundColor: Colors.red.shade600,
                        alignment: const Alignment(1.02, -1.05),
                        child: DailyReportSquareMenuTile(
                          icon: e.icon,
                          color: e.color,
                          title: e.title,
                          subtitle: e.subtitle,
                          onTap: () async {
                            await Navigator.push(context, MaterialPageRoute(builder: e.builder));
                            if (mounted) {
                              _loadPendingReceptions();
                              _loadPendingEggShipments();
                              _loadPendingInventoryRequests();
                            }
                          },
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
          const AdminDailyReportStartingValuesTab(),
          const AdminDailyReportSettingsTab(),
        ],
      ),
    );
  }

  /// Barre de navigation du bas : icône pleine + pastille verte sur l'onglet actif, icône
  /// contour sinon, pastille rouge du nombre d'éléments en attente sur « Accueil ».
  Widget _bottomNav() {
    final pending = _pendingReceptions + _pendingEggShipments + _pendingInventoryRequests;
    Widget icon(IconData data, {int badge = 0}) => Badge(
          isLabelVisible: badge > 0,
          label: Text(badge > 99 ? '99+' : '$badge'),
          backgroundColor: Colors.red.shade600,
          child: Icon(data),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: DailyReportColors.green900.withValues(alpha: 0.10),
            blurRadius: 14,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: Colors.white,
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          height: 68,
          indicatorColor: DailyReportColors.green100,
          indicatorShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
                size: 24,
                color: states.contains(WidgetState.selected)
                    ? DailyReportColors.green700
                    : DailyReportColors.grey500,
              )),
          labelTextStyle: WidgetStateProperty.resolveWith((states) => TextStyle(
                fontSize: 11.5,
                fontWeight: states.contains(WidgetState.selected) ? FontWeight.w800 : FontWeight.w600,
                color: states.contains(WidgetState.selected)
                    ? DailyReportColors.green900
                    : DailyReportColors.grey500,
              )),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          onDestinationSelected: (i) {
            if (i != _tab) {
              HapticFeedback.selectionClick();
              setState(() => _tab = i);
            }
          },
          destinations: [
            NavigationDestination(
              icon: icon(Icons.dashboard_outlined, badge: pending),
              selectedIcon: icon(Icons.dashboard_rounded, badge: pending),
              label: 'Accueil',
            ),
            NavigationDestination(
              icon: icon(Icons.flag_outlined),
              selectedIcon: icon(Icons.flag_rounded),
              label: 'Valeurs de départ',
            ),
            NavigationDestination(
              icon: icon(Icons.settings_outlined),
              selectedIcon: icon(Icons.settings_rounded),
              label: 'Paramètres',
            ),
          ],
        ),
      ),
    );
  }

  Widget _welcomeCard() {
    final dateStr = DateFormat('EEEE dd MMMM yyyy', 'fr_FR').format(_now);
    final timeStr = DateFormat('HH:mm:ss').format(_now);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: dailyReportHeaderGradient,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(color: DailyReportColors.green900.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Bienvenue, administrateur',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14),
                ),
                Text(
                  dateStr[0].toUpperCase() + dateStr.substring(1),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white.withValues(alpha: 0.82), fontSize: 11, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
          Text(
            timeStr,
            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 17, letterSpacing: 0.5),
          ),
        ],
      ),
    );
  }
}
