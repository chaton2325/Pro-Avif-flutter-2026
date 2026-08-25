import 'package:flutter/material.dart';
import '../models/usine.dart';
import '../models/usine_user.dart';
import '../models/poste.dart';
import '../services/mongo_service.dart';
import 'login_screen.dart';
import 'usine_appro_screen.dart';
import 'usine_production_screen.dart';
import 'usine_referentiel_screen.dart';
import 'usine_stock_livraison_screen.dart';
import 'usine_stats_screen.dart';

/// Accueil d'un utilisateur usine connecté : n'affiche que les sections que ses postes
/// autorisent sur CETTE usine — c'est ici que le cloisonnement par poste (magasinier vs
/// comptable vs production...) devient réel, pas juste préparé côté données.
class UsineHomeScreen extends StatelessWidget {
  final Usine usine;
  final UsineUser usineUser;
  final PostePermissions permissions;

  const UsineHomeScreen({
    super.key,
    required this.usine,
    required this.usineUser,
    required this.permissions,
  });

  void _logout(BuildContext context) {
    MongoService().logoutUsineUser();
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  @override
  Widget build(BuildContext context) {
    final canAppro =
        permissions.manageReception ||
        permissions.setPrice ||
        permissions.adjustCost ||
        permissions.seeCosts;
    final canProduction =
        permissions.manageProduction || permissions.validateCost;
    final canStockLivraison = permissions.manageDelivery;
    final canAdmin = permissions.manageAdmin;
    final canStats = permissions.viewStats;

    final cards = <Widget>[
      if (canAppro)
        _SectionCard(
          icon: Icons.local_shipping_outlined,
          color: Colors.teal,
          title: 'Approvisionnement',
          subtitle: 'Réceptions, lots, pertes, inventaire',
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) =>
                  UsineApproScreen(usine: usine, permissions: permissions),
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
      if (canStockLivraison)
        _SectionCard(
          icon: Icons.local_shipping_outlined,
          color: Colors.teal,
          title: 'Stock & livraison',
          subtitle: "Stock d'aliment produit, livraisons",
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
    ];

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
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Bonjour, ${usineUser.name}',
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Connecté à ${usine.name}',
                style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
              ),
              const SizedBox(height: 24),
              if (cards.isEmpty)
                const Padding(
                  padding: EdgeInsets.only(top: 40),
                  child: Center(
                    child: Text(
                      "Aucun accès n'est encore configuré pour votre poste. Contactez l'administrateur.",
                      style: TextStyle(color: Colors.orange),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              else
                Expanded(child: ListView(children: cards)),
            ],
          ),
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
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 18,
          vertical: 10,
        ),
        onTap: onTap,
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          radius: 24,
          child: Icon(icon, color: color, size: 26),
        ),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        trailing: const Icon(Icons.chevron_right, color: Colors.grey),
      ),
    );
  }
}
