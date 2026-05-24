import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/user.dart';
import '../models/lot.dart';
import '../models/farm.dart';
import '../services/mongo_service.dart';

class NewWeighingScreen extends StatefulWidget {
  final User user;

  const NewWeighingScreen({super.key, required this.user});

  @override
  State<NewWeighingScreen> createState() => _NewWeighingScreenState();
}

class _NewWeighingScreenState extends State<NewWeighingScreen> {
  final MongoService _mongoService = MongoService();
  final _formKey = GlobalKey<FormState>();
  
  List<Lot> _availableLots = [];
  Lot? _selectedLot;
  Farm? _assignedFarm;
  String? _selectedRoom;
  bool _isLoading = true;
  late int _currentPrecision;

  // Form Controllers
  final TextEditingController _operatorController = TextEditingController();
  final TextEditingController _ageController = TextEditingController();
  final TextEditingController _lowerIntervalController = TextEditingController();
  final TextEditingController _upperIntervalController = TextEditingController();
  final String _currentDate = DateFormat('dd/MM/yyyy').format(DateTime.now());

  @override
  void initState() {
    super.initState();
    _operatorController.text = widget.user.name;
    _currentPrecision = widget.user.scalePrecision;
    _loadInitialData();
  }

  @override
  void dispose() {
    _operatorController.dispose();
    _ageController.dispose();
    _lowerIntervalController.dispose();
    _upperIntervalController.dispose();
    super.dispose();
  }

  void _loadInitialData() async {
    try {
      final lots = await _mongoService.getLots();
      Farm? farm;
      if (widget.user.farmId != null) {
        farm = await _mongoService.getFarmById(widget.user.farmId!);
      }
      
      setState(() {
        _availableLots = lots;
        _assignedFarm = farm;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur lors du chargement des données: $e')),
      );
    }
  }

  void _showChangePrecisionDialog() {
    final controller = TextEditingController(text: _currentPrecision.toString());
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Modifier la Précision', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Nombre de décimales',
            hintText: 'Ex: 2',
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Annuler', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            onPressed: () async {
              final newPrecision = int.tryParse(controller.text);
              if (newPrecision != null) {
                setState(() => _isLoading = true);
                await _mongoService.updateUserPreferences(widget.user.id!, widget.user.language, newPrecision);
                if (!mounted) return;
                setState(() {
                  _currentPrecision = newPrecision;
                  _isLoading = false;
                });
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Précision mise à jour')));
              }
            },
            child: const Text('Valider'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NOUVELLE PESÉE', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.orange))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('INFORMATIONS GÉNÉRALES'),
                  const SizedBox(height: 16),
                  
                  // Date (Automatic)
                  _buildReadOnlyField('Date de saisie', _currentDate, Icons.calendar_today),
                  const SizedBox(height: 16),

                  // Lot Selection
                  _buildDropdownLot(),
                  const SizedBox(height: 16),

                  // Operator
                  _buildTextField(_operatorController, 'Opérateur de saisie', Icons.person),
                  const SizedBox(height: 16),

                  _buildSectionTitle('LOCALISATION & AGE'),
                  const SizedBox(height: 16),
                  // Bâtiment (Production Site)
                  _buildReadOnlyField('Bâtiment (Site)', _assignedFarm?.name ?? 'Non assigné', Icons.business),
                  const SizedBox(height: 16),

                  // Salle Dropdown
                  _buildDropdownRoom(),
                  const SizedBox(height: 16),

                  _buildTextField(_ageController, 'Âge du lot (en semaines)', Icons.history, keyboardType: TextInputType.number),
                  
                  const SizedBox(height: 32),
                  _buildSectionTitle('INTERVALLES DE SAISIE (G)'),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(child: _buildTextField(_lowerIntervalController, 'Minimum', Icons.arrow_downward, keyboardType: TextInputType.number)),
                      const SizedBox(width: 16),
                      Expanded(child: _buildTextField(_upperIntervalController, 'Maximum', Icons.arrow_upward, keyboardType: TextInputType.number)),
                    ],
                  ),

                  const SizedBox(height: 32),
                  _buildPrecisionSetting(),

                  const SizedBox(height: 48),
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () {
                        if (_formKey.currentState!.validate()) {
                          // TODO: Next step
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Configuration validée. Passage à l\'étape suivante...')),
                          );
                        }
                      },
                      child: const Text('SUIVANT', style: TextStyle(letterSpacing: 1.2, fontSize: 16)),
                    ),
                  ),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: TextStyle(
        color: Colors.grey[700],
        fontSize: 12,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    );
  }

  Widget _buildReadOnlyField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.orange, size: 20),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
              Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTextField(TextEditingController controller, String label, IconData icon, {TextInputType keyboardType = TextInputType.text}) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.orange, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
      validator: (val) => val == null || val.isEmpty ? 'Champ requis' : null,
    );
  }

  Widget _buildDropdownLot() {
    return DropdownButtonFormField<Lot>(
      value: _selectedLot,
      decoration: InputDecoration(
        labelText: 'Sélectionner un lot',
        prefixIcon: const Icon(Icons.inventory_2, color: Colors.orange, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
      items: _availableLots.map((lot) => DropdownMenuItem(
        value: lot,
        child: Text(lot.number),
      )).toList(),
      onChanged: (val) => setState(() => _selectedLot = val),
      validator: (val) => val == null ? 'Veuillez sélectionner un lot' : null,
    );
  }

  Widget _buildDropdownRoom() {
    return DropdownButtonFormField<String>(
      value: _selectedRoom,
      decoration: InputDecoration(
        labelText: 'Sélectionner une salle',
        prefixIcon: const Icon(Icons.room, color: Colors.orange, size: 20),
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade300)),
      ),
      items: _assignedFarm?.rooms.map((room) => DropdownMenuItem(
        value: room,
        child: Text(room),
      )).toList() ?? [],
      onChanged: (val) => setState(() => _selectedRoom = val),
      validator: (val) => val == null ? 'Veuillez sélectionner une salle' : null,
    );
  }

  Widget _buildPrecisionSetting() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: Colors.orange.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              const Icon(Icons.scale, color: Colors.orange),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PRÉCISION ACTUELLE', style: TextStyle(color: Colors.grey, fontSize: 10, fontWeight: FontWeight.bold)),
                  Text('$_currentPrecision décimales', style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          TextButton(
            onPressed: _showChangePrecisionDialog,
            child: const Text('MODIFIER', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }
}
