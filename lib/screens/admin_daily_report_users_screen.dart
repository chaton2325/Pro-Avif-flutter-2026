import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../models/user.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';
import '../widgets/daily_report_widgets.dart';

enum _RoleFilter { all, redacteur, validateur }

/// Gestion des comptes du module Rapport Journalier, réunie en un seul endroit plutôt que
/// forcer l'admin à passer par le tableau de bord général (Pesées) : les rédacteurs (avec leur
/// accès "Expédier des œufs", voir User.canCreateEggShipments) et les validateurs — création
/// comme modification, sans quitter ce module. Les comptes "Administrateur" restent gérés
/// depuis le tableau de bord général, hors du périmètre de ce module.
class AdminDailyReportUsersScreen extends StatefulWidget {
  const AdminDailyReportUsersScreen({super.key});

  @override
  State<AdminDailyReportUsersScreen> createState() => _AdminDailyReportUsersScreenState();
}

class _AdminDailyReportUsersScreenState extends State<AdminDailyReportUsersScreen> {
  final MongoService _mongoService = MongoService();
  List<User> _users = [];
  Map<String, Farm> _farmsById = {};
  bool _loading = true;
  _RoleFilter _filter = _RoleFilter.all;
  final _searchController = TextEditingController();
  String _searchQuery = '';
  final Set<String> _pending = {}; // ids en cours de bascule (switch), pour désactiver le contrôle

  List<User> get _visible {
    var list = _users;
    if (_filter == _RoleFilter.redacteur) list = list.where((u) => u.role == 'user').toList();
    if (_filter == _RoleFilter.validateur) list = list.where((u) => u.role == 'validateur').toList();
    if (_searchQuery.trim().isNotEmpty) {
      final q = _searchQuery.trim().toLowerCase();
      list = list.where((u) {
        final farmName = u.farmId != null ? _farmsById[u.farmId]?.name ?? '' : '';
        return u.name.toLowerCase().contains(q) || farmName.toLowerCase().contains(q);
      }).toList();
    }
    return List.of(list)..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  }

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final users = await _mongoService.getUsers();
    final farms = await _mongoService.getFarms();
    if (!mounted) return;
    setState(() {
      // Ce module ne gère que rédacteurs et validateurs — les comptes admin restent dans le
      // tableau de bord général pour ne pas donner l'impression qu'on peut en créer d'ici.
      _users = users.where((u) => u.role == 'user' || u.role == 'validateur').toList();
      _farmsById = {for (final f in farms) if (f.id != null) f.id!: f};
      _loading = false;
    });
  }

  Future<void> _toggleShipmentAccess(User user, bool value) async {
    setState(() => _pending.add(user.id!));
    final updated = User(
      id: user.id,
      name: user.name,
      password: user.password,
      role: user.role,
      farmId: user.farmId,
      isActive: user.isActive,
      language: user.language,
      scalePrecision: user.scalePrecision,
      canCreateEggShipments: value,
    );
    await _mongoService.updateUser(updated);
    if (!mounted) return;
    setState(() {
      _users = [for (final u in _users) if (u.id == user.id) updated else u];
      _pending.remove(user.id!);
    });
  }

  Future<void> _showUserDialog({User? existing}) async {
    final isEdit = existing != null;
    final nameController = TextEditingController(text: existing?.name ?? '');
    final passwordController = TextEditingController(text: isEdit ? '' : '');
    String selectedRole = existing?.role ?? 'user';
    String? selectedFarmId = existing?.farmId;
    bool canCreateEggShipments = existing?.canCreateEggShipments ?? true;
    final farms = List.of(_farmsById.values)
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            isEdit ? 'Modifier ${existing.name}' : 'Nouvel utilisateur',
            style: const TextStyle(color: DailyReportColors.green700, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(labelText: 'Nom', border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: passwordController,
                  decoration: InputDecoration(
                    labelText: isEdit ? 'Nouveau mot de passe (laisser vide si inchangé)' : 'Mot de passe',
                    border: const OutlineInputBorder(),
                  ),
                  obscureText: true,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: selectedRole,
                  decoration: const InputDecoration(labelText: 'Rôle', border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(value: 'user', child: Text('Rédacteur')),
                    DropdownMenuItem(value: 'validateur', child: Text('Validateur')),
                  ],
                  onChanged: (v) => setDialogState(() => selectedRole = v ?? 'user'),
                ),
                // Une ferme et l'accès expéditions n'ont de sens que pour un rédacteur : le
                // validateur supervise toutes les fermes, jamais une seule (voir
                // ValidatorOverviewScreen), et ne crée jamais d'expédition lui-même.
                if (selectedRole == 'user') ...[
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: farms.any((f) => f.id == selectedFarmId) ? selectedFarmId : null,
                    decoration: const InputDecoration(labelText: 'Ferme', border: OutlineInputBorder()),
                    items: [for (final f in farms) DropdownMenuItem(value: f.id, child: Text(f.name))],
                    onChanged: (v) => setDialogState(() => selectedFarmId = v),
                  ),
                  const SizedBox(height: 4),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    activeColor: DailyReportColors.green700,
                    title: const Text("Peut créer des expéditions d'œufs", style: TextStyle(fontSize: 13.5)),
                    value: canCreateEggShipments,
                    onChanged: (v) => setDialogState(() => canCreateEggShipments = v ?? true),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(color: DailyReportColors.purple600.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 16, color: DailyReportColors.purple600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Un validateur voit et valide les rapports de toutes les fermes — jamais rattaché à une seule.',
                            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Annuler')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
              onPressed: () async {
                if (nameController.text.trim().isEmpty ||
                    (!isEdit && passwordController.text.trim().isEmpty) ||
                    (selectedRole == 'user' && selectedFarmId == null)) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text(
                      selectedRole == 'user'
                          ? 'Nom, mot de passe et ferme sont obligatoires.'
                          : 'Nom et mot de passe sont obligatoires.',
                    )),
                  );
                  return;
                }
                final user = User(
                  id: existing?.id,
                  name: nameController.text.trim(),
                  password: passwordController.text.trim().isEmpty && isEdit
                      ? existing.password
                      : passwordController.text.trim(),
                  role: selectedRole,
                  farmId: selectedRole == 'user' ? selectedFarmId : null,
                  isActive: existing?.isActive ?? true,
                  language: existing?.language ?? 'fr',
                  scalePrecision: existing?.scalePrecision ?? 2,
                  canCreateEggShipments: selectedRole == 'user' ? canCreateEggShipments : true,
                );
                if (isEdit) {
                  await _mongoService.updateUser(user);
                } else {
                  await _mongoService.addUser(user);
                }
                if (!context.mounted) return;
                Navigator.pop(context, true);
              },
              child: Text(isEdit ? 'Enregistrer' : 'Créer'),
            ),
          ],
        ),
      ),
    );
    if (saved == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: dailyReportAppBar('Utilisateurs', subtitle: 'Rédacteurs & validateurs'),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showUserDialog(),
        backgroundColor: DailyReportColors.green700,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Nouvel utilisateur'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 90),
                children: [
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(color: DailyReportColors.purple600.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.info_outline_rounded, size: 18, color: DailyReportColors.purple600),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            "Les comptes Administrateur restent gérés depuis le tableau de bord général — ici, uniquement rédacteurs et validateurs.",
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade700),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _searchQuery = v),
                    decoration: InputDecoration(
                      hintText: 'Rechercher un nom ou une ferme…',
                      prefixIcon: const Icon(Icons.search, size: 20),
                      isDense: true,
                      filled: true,
                      fillColor: Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _filterChip('Tous', _RoleFilter.all),
                      const SizedBox(width: 6),
                      _filterChip('Rédacteurs', _RoleFilter.redacteur),
                      const SizedBox(width: 6),
                      _filterChip('Validateurs', _RoleFilter.validateur),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (_visible.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 40),
                      child: Center(
                        child: Text(
                          _users.isEmpty ? "Aucun utilisateur enregistré pour l'instant." : 'Aucun résultat.',
                          style: TextStyle(color: Colors.grey.shade500),
                        ),
                      ),
                    )
                  else
                    for (final u in _visible) _userCard(u),
                ],
              ),
            ),
    );
  }

  Widget _filterChip(String label, _RoleFilter value) {
    final selected = _filter == value;
    return ChoiceChip(
      label: Text(label, style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700)),
      selected: selected,
      backgroundColor: Colors.white,
      selectedColor: DailyReportColors.purple600,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(999),
        side: BorderSide(color: selected ? DailyReportColors.purple600 : Colors.grey.shade300),
      ),
      labelStyle: TextStyle(color: selected ? Colors.white : Colors.grey.shade700),
      onSelected: (_) => setState(() => _filter = value),
    );
  }

  Widget _userCard(User u) {
    final isValidateur = u.role == 'validateur';
    final farm = u.farmId != null ? _farmsById[u.farmId] : null;
    final isPending = _pending.contains(u.id);
    final accent = isValidateur
        ? DailyReportColors.blue600
        : (u.canCreateEggShipments ? DailyReportColors.green600 : Colors.grey.shade300);

    return DailyReportCard(
      accentColor: accent,
      margin: const EdgeInsets.only(bottom: 10),
      children: [
        InkWell(
          onTap: () => _showUserDialog(existing: u),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: accent.withValues(alpha: 0.15),
                child: Icon(
                  isValidateur ? Icons.fact_check_rounded : Icons.person_rounded,
                  color: isValidateur ? DailyReportColors.blue600 : (u.canCreateEggShipments ? DailyReportColors.green700 : Colors.grey.shade500),
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(u.name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
                    const SizedBox(height: 2),
                    if (isValidateur)
                      Row(
                        children: [
                          Icon(Icons.visibility_rounded, size: 13, color: Colors.grey.shade500),
                          const SizedBox(width: 4),
                          Text(
                            'Validateur · toutes les fermes',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                          ),
                        ],
                      )
                    else
                      Row(
                        children: [
                          Icon(
                            farm != null ? Icons.home_work_outlined : Icons.warning_amber_rounded,
                            size: 13,
                            color: farm != null ? Colors.grey.shade500 : DailyReportColors.yellow600,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            farm?.name ?? 'Aucune ferme assignée',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: farm != null ? Colors.grey.shade500 : DailyReportColors.yellow600,
                              fontWeight: farm != null ? FontWeight.w500 : FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
              if (!isValidateur)
                isPending
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: Padding(
                          padding: EdgeInsets.all(2),
                          child: CircularProgressIndicator(strokeWidth: 2.4, color: DailyReportColors.green700),
                        ),
                      )
                    : Switch(
                        value: u.canCreateEggShipments,
                        activeThumbColor: DailyReportColors.green700,
                        onChanged: u.id == null ? null : (v) => _toggleShipmentAccess(u, v),
                      )
              else
                Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400),
            ],
          ),
        ),
      ],
    );
  }
}
