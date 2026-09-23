import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/usine.dart';
import '../models/usine_user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';
import 'egg_shipment_history_screen.dart';
import 'login_screen.dart';

/// Accueil du validateur d'expéditions d'œufs (module Rapport Journalier) —
/// accessible aux utilisateurs usine ayant la permission `validateEggShipments`.
/// Affiche : expéditions en attente (badge), mes validations, tout l'historique.
class DailyReportValidatorHomeScreen extends StatefulWidget {
  final UsineUser usineUser;
  final Usine usine;

  const DailyReportValidatorHomeScreen({
    super.key,
    required this.usineUser,
    required this.usine,
  });

  @override
  State<DailyReportValidatorHomeScreen> createState() =>
      _DailyReportValidatorHomeScreenState();
}

class _DailyReportValidatorHomeScreenState
    extends State<DailyReportValidatorHomeScreen> {
  final MongoService _mongoService = MongoService();
  late DateTime _now;
  Timer? _clockTimer;
  int _pendingCount = 0;
  int _myValidationsCount = 0;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
    _loadCounts();
  }

  Future<void> _loadCounts() async {
    try {
      final pending = await _mongoService.getPendingEggShipmentsCount();
      final myValidations = await _mongoService.getEggShipments(
        validatedBy: widget.usineUser.name,
        status: 'valide',
        limit: 1,
      );
      if (!mounted) return;
      setState(() {
        _pendingCount = pending;
        _myValidationsCount = myValidations.totalCount;
      });
    } catch (e) {
      // Silencieux
    }
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    super.dispose();
  }

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
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar(
        'Validation Expéditions Œufs',
        subtitle: widget.usine.name,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _logout(context),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _loadCounts,
        color: DailyReportColors.purple600,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            _heroCard(),
            const SizedBox(height: 22),
            _SectionHeader('Actions rapides', DailyReportColors.purple600),
            const SizedBox(height: 8),
            _ActionCard(
              icon: Icons.hourglass_top_rounded,
              color: DailyReportColors.yellow600,
              title: 'Expéditions en attente',
              subtitle: 'À valider ou rejeter (toutes fermes)',
              badgeCount: _pendingCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EggShipmentHistoryScreen(
                      farmName: null, // toutes fermes
                      isAdmin: true, // peut valider/rejeter
                    ),
                  ),
                );
                _loadCounts();
              },
            ),
            const SizedBox(height: 10),
            _ActionCard(
              icon: Icons.check_circle_outline_rounded,
              color: DailyReportColors.green700,
              title: 'Mes validations',
              subtitle: 'Expéditions que j\'ai validées (paginé)',
              badgeCount: _myValidationsCount,
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EggShipmentHistoryScreen(
                      farmName: null,
                      isAdmin: true,
                      initialFilter: 'valide',
                      validatorName: widget.usineUser.name,
                    ),
                  ),
                );
                _loadCounts();
              },
            ),
            const SizedBox(height: 22),
            _SectionHeader('Historique complet', DailyReportColors.purple600),
            const SizedBox(height: 8),
            _ActionCard(
              icon: Icons.history_rounded,
              color: DailyReportColors.blue600,
              title: 'Toutes les expéditions',
              subtitle: 'Filtres par statut, ferme, période (paginé)',
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => EggShipmentHistoryScreen(
                      farmName: null,
                      isAdmin: true,
                    ),
                  ),
                );
                _loadCounts();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _heroCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [DailyReportColors.purple600, DailyReportColors.purple600.withValues(alpha: 0.8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: DailyReportColors.purple600.withValues(alpha: 0.3),
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
                    'Validateur expéditions œufs',
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
                    DateFormat('HH:mm:ss').format(_now),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                    ),
                  ),
                  Text(
                    DateFormat('dd/MM/yyyy').format(_now),
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
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color color;

  const _SectionHeader(this.title, this.color);

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 14,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title.toUpperCase(),
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
            color: color,
            letterSpacing: 0.5,
          ),
        ),
      ],
    );
  }
}

class _ActionCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final int badgeCount;
  final VoidCallback onTap;

  const _ActionCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.badgeCount = 0,
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
        child: Row(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.1),
                  radius: 22,
                  child: Icon(icon, color: color, size: 22),
                ),
                if (badgeCount > 0)
                  Positioned(
                    right: -4,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      constraints: const BoxConstraints(minWidth: 20),
                      decoration: BoxDecoration(
                        color: Colors.redAccent,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: Colors.white, width: 1.5),
                      ),
                      child: Text(
                        badgeCount > 99 ? '99+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
            const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
          ],
        ),
      ),
    );
  }
}