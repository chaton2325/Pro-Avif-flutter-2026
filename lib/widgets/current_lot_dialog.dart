import 'package:flutter/material.dart';
import '../services/mongo_service.dart';

/// Boîte de dialogue admin : définir le lot en cours d'une ferme (utile tant qu'aucune pesée
/// n'a été faite, ou pour corriger). Une pesée plus récente reprend ensuite la main.
/// Retourne true si le lot a été modifié.
Future<bool> showCurrentLotDialog(
  BuildContext context, {
  required String farmId,
  required String farmName,
  String? currentLot,
}) async {
  final mongo = MongoService();
  final lots = await mongo.getLots();
  if (!context.mounted) return false;
  final numbers = lots.map((l) => l.number).toSet().toList()..sort();
  String? selected = numbers.contains(currentLot) ? currentLot : null;

  final saved = await showDialog<bool>(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (ctx, setLocal) => AlertDialog(
        title: Text('Lot en cours — $farmName'),
        content: DropdownButtonFormField<String?>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Lot'),
          items: [
            const DropdownMenuItem<String?>(value: null, child: Text('Automatique (dernière pesée)')),
            for (final n in numbers) DropdownMenuItem<String?>(value: n, child: Text(n)),
          ],
          onChanged: (v) => setLocal(() => selected = v),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuler')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Enregistrer')),
        ],
      ),
    ),
  );
  if (saved != true) return false;

  final ok = await mongo.setFarmCurrentLot(farmId, selected);
  if (context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(ok ? 'Lot en cours mis à jour.' : 'Échec de la mise à jour du lot.')),
    );
  }
  return ok;
}
