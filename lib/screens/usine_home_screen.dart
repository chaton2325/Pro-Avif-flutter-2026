import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/usine_user.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import 'login_screen.dart';
import 'usine_appro_screen.dart';
import 'usine_daily_report_screen.dart';
import 'usine_production_screen.dart';
import 'usine_referentiel_screen.dart';
import 'usine_stock_inventory_screen.dart';
import 'usine_stock_livraison_screen.dart';
import 'usine_stats_screen.dart';

/// Accueil d'un utilisateur usine connecté : n'affiche que les sections que ses postes
/// autorisent sur CETTE usine — c'est ici que le cloisonnement par poste (magasinier vs
/// comptable vs production...) devient réel, pas juste préparé côté données.
class UsineHomeScreen extends StatefulWidget {
  final Usine usine;
  final UsineUser usineUser;
  final PostePermissions permissions;

  const UsineHomeScreen({
    super.key,
    required this.usine,
    required this.usineUser,
    required this.permissions,
  });

  @override
  State<UsineHomeScreen> createState() => _UsineHomeScreenState();
}

class _UsineHomeScreenState extends State<UsineHomeScreen> {
  late Timer _clockTimer;
  String _currentTime = '';
  String _currentDateStr = '';

  @override
  void initState() {
    super.initState();
    _updateClock();
    _clockTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => _updateClock(),
    );
  }

  @override
  void dispose() {
    _clockTimer.cancel();
    super.dispose();
  }

  void _updateClock() {
    final now = DateTime.now();
    if (!mounted) return;
    setState(() {
      _currentTime = DateFormat('HH:mm:ss').format(now);
      _currentDateStr = DateFormat('dd/MM/yyyy').format(now);
    });
  }

  void _logout(BuildContext context) {
    MongoService().logoutUsineUser();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  /// Carte héros orange — même langage visuel que l'accueil du module Rapport Journalier
  /// (user_dashboard.dart) et l'onglet Aperçu des Statistiques : nom + heure/date en
  /// direct, puis l'usine bien en évidence. Sans elle, l'écran n'était que du texte brut.
  Widget _buildHeroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.orange.shade600,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Bonjour,',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    widget.usineUser.name,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _currentTime,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    _currentDateStr,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 32),
          const Text(
            'CONNECTÉ À',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 10,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.usine.name,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final permissions = widget.permissions;
    final usine = widget.usine;
    final canAppro =
        permissions.manageReception ||
        permissions.setPrice ||
        permissions.adjustCost ||
        permissions.seeCosts;
    final canStockInventory =
        permissions.manageReception ||
        permissions.manageDelivery ||
        permissions.manageInventory ||
        permissions.viewStock ||
        permissions.seeCosts;
    // Même règle que les onglets de l'écran cible : un poste sans l'une ni l'autre
    // permission dédiée (ex. Logistique, entré via manageDelivery) voit les deux, comme
    // avant — la séparation stricte ne s'applique qu'une fois l'une des deux cochée.
    final showStockTab = permissions.viewStock || !permissions.manageInventory;
    final showInventoryTab =
        permissions.manageInventory || !permissions.viewStock;
    final stockInventoryTitle = showStockTab && showInventoryTab
        ? 'Stock & Inventaire'
        : showStockTab
        ? 'Stock'
        : 'Inventaire';
    final stockInventorySubtitle = showStockTab && showInventoryTab
        ? 'Stock et inventaire, matières & aliments'
        : showStockTab
        ? 'Stock, matières & aliments'
        : 'Inventaire, matières & aliments';
    final canLivraisons =
        permissions.manageDelivery || permissions.validateDelivery;
    final canProduction =
        permissions.manageProduction || permissions.validateCost;
    final canAdmin = permissions.manageAdmin;
    final canStats = permissions.viewStats;

    final cards = <Widget>[
      if (canAppro)
        _SectionCard(
          icon: Icons.local_shipping_outlined,
          color: Colors.teal,
          title: 'Approvisionnement',
          subtitle: 'Réceptions, pertes, historique',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  UsineApproScreen(usine: usine, permissions: permissions),
            ),
          ),
        ),
      if (canStockInventory)
        _SectionCard(
          icon: Icons.warehouse_outlined,
          color: Colors.orange,
          title: stockInventoryTitle,
          subtitle: stockInventorySubtitle,
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsineStockInventoryScreen(
                usine: usine,
                permissions: permissions,
              ),
            ),
          ),
        ),
      if (canLivraisons)
        _SectionCard(
          icon: Icons.local_shipping_outlined,
          color: Colors.blue,
          title: 'Livraisons',
          subtitle: 'Création et validation des livraisons',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsineStockLivraisonScreen(
                usine: usine,
                permissions: permissions,
              ),
            ),
          ),
        ),
      if (canProduction)
        _SectionCard(
          icon: Icons.precision_manufacturing_outlined,
          color: Colors.deepPurple,
          title: 'Production',
          subtitle: 'Fabrication & coût de revient',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  UsineProductionScreen(usine: usine, permissions: permissions),
            ),
          ),
        ),
      if (canAdmin)
        _SectionCard(
          icon: Icons.inventory_2_outlined,
          color: Colors.indigo,
          title: 'Référentiel',
          subtitle: 'Matières premières & formules',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsineReferentielScreen(usine: usine),
            ),
          ),
        ),
      if (canStats)
        _SectionCard(
          icon: Icons.bar_chart_rounded,
          color: Colors.blueGrey,
          title: 'Statistiques',
          subtitle: 'Consommation, traçabilité, budgets',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  UsineStatsScreen(usine: usine, permissions: permissions),
            ),
          ),
        ),
      if (canProduction || canStats)
        _SectionCard(
          icon: Icons.summarize_outlined,
          color: Colors.brown,
          title: 'Rapport de production',
          subtitle: 'Matière, production, livraison — format WhatsApp',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => UsineDailyReportScreen(
                usine: usine,
                permissions: permissions,
              ),
            ),
          ),
        ),
    ];

    // Deux cartes par ligne plutôt qu'empilées verticalement une par une.
    final cardRows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      cardRows.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: cards[i]),
              const SizedBox(width: 12),
              Expanded(
                child: i + 1 < cards.length ? cards[i + 1] : const SizedBox(),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      appBar: AppBar(
        title: Text(
          usine.name.toUpperCase(),
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            letterSpacing: 1,
            fontSize: 15,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.orange),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            _buildHeroCard(),
            const SizedBox(height: 28),
            if (cards.isEmpty)
              const Padding(
                padding: EdgeInsets.only(top: 20),
                child: Center(
                  child: Text(
                    "Aucun accès n'est encore configuré pour votre poste. Contactez l'administrateur.",
                    style: TextStyle(color: Colors.orange),
                    textAlign: TextAlign.center,
                  ),
                ),
              )
            else ...[
              const Text(
                'MODULES',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  color: Colors.grey,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 12),
              ...cardRows,
            ],
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _SectionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.grey.shade100),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: color.withValues(alpha: 0.1),
              radius: 22,
              child: Icon(icon, color: color, size: 22),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 14.5,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.grey.shade600, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}
