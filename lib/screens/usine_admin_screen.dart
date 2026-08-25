import 'package:flutter/material.dart';
import '../models/usine.dart';
import '../models/usine_user.dart';
import '../models/poste.dart';
import '../models/poste_assignment.dart';
import '../services/mongo_service.dart';
import 'usine_referentiel_screen.dart';
import 'usine_appro_screen.dart';
import 'usine_production_screen.dart';
import 'usine_simulation_screen.dart';
import 'usine_stock_livraison_screen.dart';
import 'usine_stats_screen.dart';

/// Administration transverse du module Usine Aliment (Partie 0) :
/// - Usines (comme les fermes, on peut en créer plusieurs)
/// - Utilisateurs usine : comptes propres à ce module, distincts des utilisateurs
///   du module Rapport Journalier (ceux-là restent rattachés à une ferme).
/// - Postes : nommés librement par l'admin ("Magasinier de l'usine", "Caissier"...),
///   chacun avec un jeu de permissions qui pilote l'accès aux écrans et le masquage
///   des coûts, plutôt qu'une liste de rôles figée dans le code.
/// - Affectations : un utilisateur usine peut cumuler plusieurs postes, chacun sur une
///   usine précise (pas de portée "toutes les usines" — l'utilisateur ne voit que
///   l'interface de son/ses usine(s) affectée(s)).
class UsineAdminScreen extends StatefulWidget {
  const UsineAdminScreen({super.key});

  @override
  State<UsineAdminScreen> createState() => _UsineAdminScreenState();
}

class _UsineAdminScreenState extends State<UsineAdminScreen>
    with SingleTickerProviderStateMixin {
  final MongoService _mongoService = MongoService();
  late TabController _tabController;

  List<Usine> _usines = [];
  List<Poste> _postes = [];
  List<PosteAssignment> _assignments = [];
  List<UsineUser> _usineUsers = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _refreshData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });
    try {
      final usines = await _mongoService.getUsines();
      final postes = await _mongoService.getPostes();
      final assignments = await _mongoService.getPosteAssignments();
      final usineUsers = await _mongoService.getUsineUsers();
      if (!mounted) return;
      setState(() {
        _usines = usines;
        _postes = postes;
        _assignments = assignments;
        _usineUsers = usineUsers;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = "Erreur de chargement : $e";
        _isLoading = false;
      });
    }
  }

  // ---------------------------------------------------------------- Usines

  void _showUsineDialog({Usine? usine}) {
    final nameController = TextEditingController(text: usine?.name ?? '');
    final addressController = TextEditingController(text: usine?.address ?? '');
    bool isActive = usine?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            usine == null ? 'Nouvelle usine' : 'Modifier l\'usine',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameController,
                  decoration: const InputDecoration(
                    labelText: "Nom de l'usine",
                    prefixIcon: Icon(Icons.factory_rounded),
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: addressController,
                  decoration: const InputDecoration(
                    labelText: 'Adresse (optionnel)',
                    prefixIcon: Icon(Icons.place_outlined),
                  ),
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active'),
                  value: isActive,
                  activeColor: Colors.orange,
                  onChanged: (v) => setDialogState(() => isActive = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final newUsine = Usine(
                  id: usine?.id,
                  name: nameController.text.trim(),
                  address: addressController.text.trim().isEmpty
                      ? null
                      : addressController.text.trim(),
                  isActive: isActive,
                );
                if (usine == null) {
                  await _mongoService.addUsine(newUsine);
                } else {
                  await _mongoService.updateUsine(newUsine);
                }
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsinesTab() {
    if (_usines.isEmpty)
      return const Center(
        child: Text(
          'Aucune usine. Ajoutez-en une avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _usines.length,
      itemBuilder: (context, index) {
        final usine = _usines[index];
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
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
            onTap: () => _showUsineActionsSheet(usine),
            leading: CircleAvatar(
              backgroundColor: (usine.isActive ? Colors.orange : Colors.grey)
                  .withValues(alpha: 0.1),
              child: Icon(
                Icons.factory_rounded,
                color: usine.isActive ? Colors.orange : Colors.grey,
              ),
            ),
            title: Text(
              usine.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              usine.address ?? (usine.isActive ? 'Active' : 'Inactive'),
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: const Icon(Icons.chevron_right, color: Colors.grey),
          ),
        );
      },
    );
  }

  /// Un seul point d'entrée, clairement libellé, pour naviguer vers les écrans propres à
  /// une usine — plutôt que de disperser ces raccourcis en icônes cryptiques dans chaque
  /// écran (ce qui rendait la barre du haut du référentiel illisible).
  void _showUsineActionsSheet(Usine usine) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.orange.withValues(alpha: 0.1),
                    child: const Icon(
                      Icons.factory_rounded,
                      color: Colors.orange,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    usine.name,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 17,
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(
                Icons.inventory_2_outlined,
                color: Colors.indigo,
              ),
              title: const Text('Référentiel'),
              subtitle: const Text(
                'Matières premières & formules',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineReferentielScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.teal,
              ),
              title: const Text('Approvisionnement'),
              subtitle: const Text(
                'Réceptions, lots, pertes, inventaire',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineApproScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.precision_manufacturing_outlined,
                color: Colors.deepPurple,
              ),
              title: const Text('Production'),
              subtitle: const Text(
                'Fabrication & coût de revient',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineProductionScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.local_shipping_outlined,
                color: Colors.teal,
              ),
              title: const Text('Stock & livraison'),
              subtitle: const Text(
                'Stock d\'aliment produit, livraisons',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineStockLivraisonScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.calculate_outlined,
                color: Colors.orange,
              ),
              title: const Text('Simulation'),
              subtitle: const Text(
                'Ce qu\'on peut produire, plan optimisé',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineSimulationScreen(usine: usine),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.bar_chart_rounded,
                color: Colors.blueGrey,
              ),
              title: const Text('Statistiques'),
              subtitle: const Text(
                'Consommation, traçabilité, budgets',
                style: TextStyle(fontSize: 12),
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => UsineStatsScreen(usine: usine),
                  ),
                );
              },
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.edit_rounded, color: Colors.blue),
              title: const Text('Modifier l\'usine'),
              onTap: () {
                Navigator.pop(context);
                _showUsineDialog(usine: usine);
              },
            ),
            ListTile(
              leading: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
              ),
              title: const Text('Supprimer l\'usine'),
              onTap: () async {
                Navigator.pop(context);
                await _mongoService.deleteUsine(usine.id!);
                _refreshData();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------- Postes

  void _showPosteDialog({Poste? poste}) {
    final nameController = TextEditingController(text: poste?.name ?? '');
    PostePermissions perms = poste?.permissions ?? const PostePermissions();
    bool isActive = poste?.isActive ?? true;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            poste == null ? 'Nouveau poste' : 'Modifier le poste',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Modèles rapides',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: posteTemplates
                        .map(
                          (t) => ActionChip(
                            label: Text(
                              t.name,
                              style: const TextStyle(fontSize: 12),
                            ),
                            backgroundColor: Colors.orange.shade50,
                            side: BorderSide(color: Colors.orange.shade200),
                            onPressed: () => setDialogState(() {
                              nameController.text = t.name;
                              perms = t.permissions;
                            }),
                          ),
                        )
                        .toList(),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText:
                          'Nom du poste (ex : Magasinier de l\'usine, Caissier)',
                      prefixIcon: Icon(Icons.badge_outlined),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Actif'),
                    value: isActive,
                    activeColor: Colors.orange,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                  const Divider(),
                  const Text(
                    'Permissions',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.grey,
                    ),
                  ),
                  ...PostePermissions.labels.map(
                    (entry) => CheckboxListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      controlAffinity: ListTileControlAffinity.leading,
                      activeColor: Colors.orange,
                      title: Text(
                        entry.value,
                        style: const TextStyle(fontSize: 13),
                      ),
                      value: perms[entry.key],
                      onChanged: (v) => setDialogState(
                        () => perms = perms.copyWith(entry.key, v ?? false),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                final newPoste = Poste(
                  id: poste?.id,
                  name: nameController.text.trim(),
                  permissions: perms,
                  isActive: isActive,
                );
                if (poste == null) {
                  await _mongoService.addPoste(newPoste);
                } else {
                  await _mongoService.updatePoste(newPoste);
                }
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPostesTab() {
    if (_postes.isEmpty)
      return const Center(
        child: Text(
          'Aucun poste. Créez-en un avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _postes.length,
      itemBuilder: (context, index) {
        final poste = _postes[index];
        final activeCount = PostePermissions.labels
            .where((e) => poste.permissions[e.key])
            .length;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
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
            leading: CircleAvatar(
              backgroundColor: Colors.indigo.withValues(alpha: 0.1),
              child: const Icon(Icons.badge_rounded, color: Colors.indigo),
            ),
            title: Text(
              poste.name,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '$activeCount permission(s) active(s)',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.edit_rounded,
                    color: Colors.blue,
                    size: 20,
                  ),
                  onPressed: () => _showPosteDialog(poste: poste),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: Colors.redAccent,
                    size: 20,
                  ),
                  onPressed: () async {
                    await _mongoService.deletePoste(poste.id!);
                    _refreshData();
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --------------------------------------------------------- Utilisateurs usine

  void _showUsineUserDialog({UsineUser? usineUser}) {
    final nameController = TextEditingController(text: usineUser?.name ?? '');
    final passwordController = TextEditingController();
    bool isActive = usineUser?.isActive ?? true;
    String? selectedPosteId = _postes.isNotEmpty ? _postes.first.id : null;
    String? selectedUsineId = _usines.isNotEmpty ? _usines.first.id : null;
    // Affectations existantes (édition uniquement) : gérées en direct dans ce même dialog,
    // pour que le crayon suffise — plus besoin d'un écran séparé pour poste/usine.
    List<PosteAssignment> currentAssignments = usineUser == null
        ? []
        : _assignments.where((a) => a.userId == usineUser.id).toList();

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            usineUser == null
                ? 'Nouvel utilisateur usine'
                : 'Modifier ${usineUser.name}',
            style: const TextStyle(
              color: Colors.orange,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 420,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    decoration: const InputDecoration(
                      labelText: 'Nom',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: usineUser == null
                          ? 'Mot de passe'
                          : 'Nouveau mot de passe (laisser vide si inchangé)',
                      prefixIcon: const Icon(Icons.lock_outline),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Actif'),
                    value: isActive,
                    activeColor: Colors.orange,
                    onChanged: (v) => setDialogState(() => isActive = v),
                  ),
                  const Divider(),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Postes & usines',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (usineUser != null) ...[
                    if (currentAssignments.isEmpty)
                      const Text(
                        'Aucune affectation pour le moment.',
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      )
                    else
                      ...currentAssignments.map((a) {
                        final posteName =
                            _postes
                                .cast<Poste?>()
                                .firstWhere(
                                  (p) => p?.id == a.posteId,
                                  orElse: () => null,
                                )
                                ?.name ??
                            '?';
                        final usineName =
                            _usines
                                .cast<Usine?>()
                                .firstWhere(
                                  (us) => us?.id == a.usineId,
                                  orElse: () => null,
                                )
                                ?.name ??
                            '?';
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(
                            '$posteName · $usineName',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          trailing: IconButton(
                            icon: const Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: Colors.redAccent,
                            ),
                            onPressed: () async {
                              await _mongoService.deletePosteAssignment(a.id!);
                              final updated = await _mongoService
                                  .getPosteAssignments(userId: usineUser.id);
                              setDialogState(
                                () => currentAssignments = updated,
                              );
                              _refreshData();
                            },
                          ),
                        );
                      }),
                    const SizedBox(height: 8),
                  ],
                  if (_postes.isEmpty || _usines.isEmpty)
                    Text(
                      _postes.isEmpty
                          ? 'Créez d\'abord un poste (onglet Postes).'
                          : 'Créez d\'abord une usine (onglet Usines).',
                      style: const TextStyle(
                        color: Colors.orange,
                        fontSize: 12,
                      ),
                    )
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Poste'),
                          value: selectedPosteId,
                          items: _postes
                              .where((p) => p.id != null)
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    p.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedPosteId = v),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Usine'),
                          value: selectedUsineId,
                          items: _usines
                              .where((u) => u.id != null)
                              .map(
                                (u) => DropdownMenuItem(
                                  value: u.id,
                                  child: Text(
                                    u.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) =>
                              setDialogState(() => selectedUsineId = v),
                        ),
                        if (usineUser != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(
                              Icons.add_circle_outline,
                              color: Colors.orange,
                            ),
                            label: const Text(
                              'Ajouter cette affectation',
                              style: TextStyle(color: Colors.orange),
                            ),
                            onPressed: () async {
                              if (selectedPosteId == null ||
                                  selectedUsineId == null)
                                return;
                              await _mongoService.addPosteAssignment(
                                PosteAssignment(
                                  userId: usineUser.id!,
                                  posteId: selectedPosteId!,
                                  usineId: selectedUsineId!,
                                ),
                              );
                              final updated = await _mongoService
                                  .getPosteAssignments(userId: usineUser.id);
                              setDialogState(
                                () => currentAssignments = updated,
                              );
                              _refreshData();
                            },
                          ),
                        ],
                      ],
                    ),
                  if (usineUser == null &&
                      (_postes.isNotEmpty && _usines.isNotEmpty))
                    const Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: Text(
                        'Cette affectation sera créée avec l\'utilisateur.',
                        style: TextStyle(color: Colors.grey, fontSize: 11),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameController.text.trim().isEmpty) return;
                if (usineUser == null && passwordController.text.isEmpty)
                  return;
                final newUser = UsineUser(
                  id: usineUser?.id,
                  name: nameController.text.trim(),
                  password: passwordController.text.isEmpty
                      ? usineUser!.password
                      : passwordController.text,
                  isActive: isActive,
                );
                if (usineUser == null) {
                  final created = await _mongoService.addUsineUser(newUser);
                  if (created?.id != null &&
                      selectedPosteId != null &&
                      selectedUsineId != null) {
                    await _mongoService.addPosteAssignment(
                      PosteAssignment(
                        userId: created!.id!,
                        posteId: selectedPosteId!,
                        usineId: selectedUsineId!,
                      ),
                    );
                  }
                } else {
                  await _mongoService.updateUsineUser(newUser);
                }
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Enregistrer'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUsineUsersTab() {
    if (_usineUsers.isEmpty)
      return const Center(
        child: Text(
          'Aucun utilisateur usine. Ajoutez-en un avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _usineUsers.length,
      itemBuilder: (context, index) {
        final u = _usineUsers[index];
        final userAssignments = _assignments
            .where((a) => a.userId == u.id)
            .toList();
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.symmetric(vertical: 4),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
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
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: (u.isActive ? Colors.purple : Colors.grey)
                      .withValues(alpha: 0.1),
                  child: Icon(
                    Icons.person_rounded,
                    color: u.isActive ? Colors.purple : Colors.grey,
                  ),
                ),
                title: Text(
                  u.name,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
                subtitle: Text(
                  u.isActive ? 'Actif' : 'Inactif',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.edit_rounded,
                        color: Colors.blue,
                        size: 20,
                      ),
                      onPressed: () => _showUsineUserDialog(usineUser: u),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: Colors.redAccent,
                        size: 20,
                      ),
                      onPressed: () async {
                        await _mongoService.deleteUsineUser(u.id!);
                        _refreshData();
                      },
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: userAssignments.isEmpty
                    ? GestureDetector(
                        onTap: () => _showUsineUserDialog(usineUser: u),
                        child: const Text(
                          '⚠ Aucune usine ni poste affecté — toucher pour affecter',
                          style: TextStyle(
                            color: Colors.orange,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      )
                    : Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: userAssignments.map((a) {
                          final posteName =
                              _postes
                                  .cast<Poste?>()
                                  .firstWhere(
                                    (p) => p?.id == a.posteId,
                                    orElse: () => null,
                                  )
                                  ?.name ??
                              '?';
                          final usineName =
                              _usines
                                  .cast<Usine?>()
                                  .firstWhere(
                                    (us) => us?.id == a.usineId,
                                    orElse: () => null,
                                  )
                                  ?.name ??
                              '?';
                          return Chip(
                            visualDensity: VisualDensity.compact,
                            backgroundColor: Colors.teal.shade50,
                            label: Text(
                              '$posteName · $usineName',
                              style: const TextStyle(fontSize: 11),
                            ),
                            onDeleted: () async {
                              await _mongoService.deletePosteAssignment(a.id!);
                              _refreshData();
                            },
                          );
                        }).toList(),
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------- Affectations

  void _showAssignmentDialog({String? presetUserId}) {
    if (_usineUsers.isEmpty || _postes.isEmpty || _usines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Il faut au moins un utilisateur usine, un poste et une usine.',
          ),
        ),
      );
      return;
    }
    String? selectedUserId = presetUserId ?? _usineUsers.first.id;
    String? selectedPosteId = _postes.first.id;
    String? selectedUsineId = _usines.first.id;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Affecter un poste',
            style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Utilisateur usine',
                  ),
                  value: selectedUserId,
                  items: _usineUsers
                      .where((u) => u.id != null)
                      .map(
                        (u) =>
                            DropdownMenuItem(value: u.id, child: Text(u.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedUserId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Poste'),
                  value: selectedPosteId,
                  items: _postes
                      .where((p) => p.id != null)
                      .map(
                        (p) =>
                            DropdownMenuItem(value: p.id, child: Text(p.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedPosteId = v),
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Usine'),
                  value: selectedUsineId,
                  items: _usines
                      .where((u) => u.id != null)
                      .map(
                        (u) =>
                            DropdownMenuItem(value: u.id, child: Text(u.name)),
                      )
                      .toList(),
                  onChanged: (v) => setDialogState(() => selectedUsineId = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Annuler',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (selectedUserId == null ||
                    selectedPosteId == null ||
                    selectedUsineId == null)
                  return;
                await _mongoService.addPosteAssignment(
                  PosteAssignment(
                    userId: selectedUserId!,
                    posteId: selectedPosteId!,
                    usineId: selectedUsineId!,
                  ),
                );
                await _refreshData();
                if (!context.mounted) return;
                Navigator.pop(context);
              },
              child: const Text('Affecter'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAssignmentsTab() {
    if (_assignments.isEmpty)
      return const Center(
        child: Text(
          'Aucune affectation. Ajoutez-en une avec le bouton +.',
          style: TextStyle(color: Colors.grey),
        ),
      );
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
      itemCount: _assignments.length,
      itemBuilder: (context, index) {
        final a = _assignments[index];
        final userName =
            _usineUsers
                .cast<UsineUser?>()
                .firstWhere((u) => u?.id == a.userId, orElse: () => null)
                ?.name ??
            a.userId;
        final posteName =
            _postes
                .cast<Poste?>()
                .firstWhere((p) => p?.id == a.posteId, orElse: () => null)
                ?.name ??
            a.posteId;
        final usineName =
            _usines
                .cast<Usine?>()
                .firstWhere((u) => u?.id == a.usineId, orElse: () => null)
                ?.name ??
            a.usineId;
        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
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
            leading: CircleAvatar(
              backgroundColor: Colors.teal.withValues(alpha: 0.1),
              child: const Icon(
                Icons.assignment_ind_rounded,
                color: Colors.teal,
              ),
            ),
            title: Text(
              userName,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            subtitle: Text(
              '$posteName · $usineName',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
            ),
            trailing: IconButton(
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.redAccent,
                size: 20,
              ),
              onPressed: () async {
                await _mongoService.deletePosteAssignment(a.id!);
                _refreshData();
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'USINE ALIMENT — ADMIN',
          style: TextStyle(
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
            icon: const Icon(Icons.refresh, color: Colors.orange),
            onPressed: _refreshData,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          labelColor: Colors.orange,
          unselectedLabelColor: Colors.grey,
          indicatorColor: Colors.orange,
          tabs: const [
            Tab(text: 'Usines'),
            Tab(text: 'Postes'),
            Tab(text: 'Utilisateurs'),
            Tab(text: 'Affectations'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: Colors.orange))
          : _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Text(
                  _error!,
                  style: const TextStyle(color: Colors.red),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          : TabBarView(
              controller: _tabController,
              children: [
                _buildUsinesTab(),
                _buildPostesTab(),
                _buildUsineUsersTab(),
                _buildAssignmentsTab(),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: Colors.orange,
        onPressed: () {
          if (_tabController.index == 0)
            _showUsineDialog();
          else if (_tabController.index == 1)
            _showPosteDialog();
          else if (_tabController.index == 2)
            _showUsineUserDialog();
          else
            _showAssignmentDialog();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
