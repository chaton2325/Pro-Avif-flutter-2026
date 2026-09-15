import 'package:flutter/material.dart';
import '../models/farm.dart';
import '../models/lot_headcount.dart';
import '../services/mongo_service.dart';
import '../utils/daily_report_colors.dart';

/// Effectifs de départ d'un lot (réservé à l'admin — "l'admin peut tout faire") : saisis
/// une seule fois à la mise en place du lot, le rapport journalier reprend ensuite tout seul
/// l'effectif restant de la veille (voir routers/headcounts.py côté backend).
class AdminLotHeadcountsScreen extends StatefulWidget {
  const AdminLotHeadcountsScreen({super.key});

  @override
  State<AdminLotHeadcountsScreen> createState() => _AdminLotHeadcountsScreenState();
}

class _AdminLotHeadcountsScreenState extends State<AdminLotHeadcountsScreen> {
  final MongoService _mongoService = MongoService();
  List<Farm> _farms = [];
  Farm? _selectedFarm;
  final _lotController = TextEditingController();
  final _clinicFemaleController = TextEditingController(text: '0');
  final _clinicMaleController = TextEditingController(text: '0');
  final Map<String, TextEditingController> _femaleControllers = {};
  final Map<String, TextEditingController> _maleControllers = {};
  bool _loading = true;
  bool _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    _loadFarms();
  }

  Future<void> _loadFarms() async {
    final farms = await _mongoService.getFarms();
    if (!mounted) return;
    setState(() {
      _farms = farms;
      _loading = false;
    });
  }

  void _selectFarm(Farm? farm) {
    setState(() {
      _selectedFarm = farm;
      _femaleControllers.clear();
      _maleControllers.clear();
      for (final room in farm?.rooms ?? <String>[]) {
        _femaleControllers[room] = TextEditingController(text: '0');
        _maleControllers[room] = TextEditingController(text: '0');
      }
      _lotController.clear();
      _clinicFemaleController.text = '0';
      _clinicMaleController.text = '0';
      _message = null;
    });
  }

  Future<void> _loadExisting() async {
    if (_selectedFarm == null || _lotController.text.trim().isEmpty) return;
    final existing = await _mongoService.getLotHeadcount(_selectedFarm!.name, _lotController.text.trim());
    if (!mounted || existing == null) return;
    setState(() {
      for (final r in existing.rooms) {
        _femaleControllers[r.roomName]?.text = r.femaleCount.toString();
        _maleControllers[r.roomName]?.text = r.maleCount.toString();
      }
      _clinicFemaleController.text = existing.clinicFemaleCount.toString();
      _clinicMaleController.text = existing.clinicMaleCount.toString();
      _message = 'Valeurs existantes chargées — modification possible.';
    });
  }

  Future<void> _save() async {
    if (_selectedFarm == null || _lotController.text.trim().isEmpty) {
      setState(() => _message = 'Choisissez une ferme et un numéro de lot.');
      return;
    }
    setState(() {
      _saving = true;
      _message = null;
    });
    final headcount = LotHeadcount(
      farmName: _selectedFarm!.name,
      lotNumber: _lotController.text.trim(),
      rooms: _selectedFarm!.rooms
          .map((r) => RoomHeadcount(
                roomName: r,
                femaleCount: int.tryParse(_femaleControllers[r]!.text) ?? 0,
                maleCount: int.tryParse(_maleControllers[r]!.text) ?? 0,
              ))
          .toList(),
      clinicFemaleCount: int.tryParse(_clinicFemaleController.text) ?? 0,
      clinicMaleCount: int.tryParse(_clinicMaleController.text) ?? 0,
    );
    final result = await _mongoService.upsertLotHeadcount(headcount);
    if (!mounted) return;
    setState(() {
      _saving = false;
      _message = result.error ??
          'Enregistré : ${result.headcount!.totalFemale} F / ${result.headcount!.totalMale} M';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: DailyReportColors.surface,
      appBar: AppBar(
        backgroundColor: DailyReportColors.green900,
        foregroundColor: Colors.white,
        title: const Text('Effectifs de départ'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: DailyReportColors.green700))
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                DropdownButtonFormField<Farm>(
                  value: _selectedFarm,
                  decoration: const InputDecoration(labelText: 'Ferme', border: OutlineInputBorder()),
                  items: _farms.map((f) => DropdownMenuItem(value: f, child: Text(f.name))).toList(),
                  onChanged: _selectFarm,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _lotController,
                  decoration: InputDecoration(
                    labelText: 'Numéro de lot',
                    border: const OutlineInputBorder(),
                    suffixIcon: IconButton(icon: const Icon(Icons.search), onPressed: _loadExisting),
                  ),
                ),
                if (_selectedFarm != null) ...[
                  const SizedBox(height: 20),
                  Text('EFFECTIFS PAR SALLE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.grey.shade600)),
                  const SizedBox(height: 8),
                  for (final room in _selectedFarm!.rooms) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Row(
                        children: [
                          SizedBox(width: 90, child: Text(room, style: const TextStyle(fontWeight: FontWeight.w600))),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _femaleControllers[room],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Femelles', isDense: true, border: OutlineInputBorder()),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _maleControllers[room],
                              keyboardType: TextInputType.number,
                              decoration: const InputDecoration(labelText: 'Mâles', isDense: true, border: OutlineInputBorder()),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(width: 90, child: Text('Clinique', style: TextStyle(fontWeight: FontWeight.w600))),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _clinicFemaleController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Femelles', isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _clinicMaleController,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(labelText: 'Mâles', isDense: true, border: OutlineInputBorder()),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  if (_message != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Text(_message!, style: const TextStyle(color: DailyReportColors.green700)),
                    ),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(backgroundColor: DailyReportColors.green700, foregroundColor: Colors.white),
                      child: _saving
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Text('Enregistrer'),
                    ),
                  ),
                ],
              ],
            ),
    );
  }
}
