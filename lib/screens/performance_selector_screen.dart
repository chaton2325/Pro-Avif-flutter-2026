import 'package:flutter/material.dart';
import '../services/mongo_service.dart';
import '../models/farm.dart';
import '../models/lot.dart';
import 'performance_comparison_screen.dart';

class AdminPerformanceSelectorScreen extends StatefulWidget {
  const AdminPerformanceSelectorScreen({super.key});

  @override
  State<AdminPerformanceSelectorScreen> createState() => _AdminPerformanceSelectorScreenState();
}

class _AdminPerformanceSelectorScreenState extends State<AdminPerformanceSelectorScreen> {
  final MongoService _mongoService = MongoService();
  
  List<Farm> _farms = [];
  List<Lot> _allLots = [];
  bool _isLoading = true;

  String? _selectedFarm;
  String? _selectedRoom;
  String? _selectedLot;
  String _selectedSex = 'Mâle';

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    setState(() => _isLoading = true);
    try {
      final results = await Future.wait([
        _mongoService.getFarms(),
        _mongoService.getLots(),
      ]);
      setState(() {
        _farms = results[0] as List<Farm>;
        _allLots = results[1] as List<Lot>;
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: $e'), backgroundColor: Colors.red),
      );
    }
  }

  List<String> _getRoomsForFarm(String farmName) {
    final farm = _farms.firstWhere((f) => f.name == farmName, orElse: () => Farm(name: '', rooms: []));
    return farm.rooms;
  }

  List<Lot> _getLotsForFarm(String farmName) {
    // Note: Assuming Lot model has a way to relate to farm or room. 
    // If not, we show all lots or filter by some logic.
    // Looking at common patterns, we'll show lots matching the farm if available.
    return _allLots; 
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text('ANALYSE PAR LOT', 
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16)),
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        foregroundColor: Colors.indigo.shade900,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator(color: Colors.indigo))
        : SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSectionTitle('1. Sélectionner l\'exploitation'),
                const SizedBox(height: 12),
                _buildDropdown<String>(
                  value: _selectedFarm,
                  hint: 'Choisir un bâtiment',
                  items: _farms.map((f) => f.name).toList(),
                  onChanged: (val) {
                    setState(() {
                      _selectedFarm = val;
                      _selectedRoom = null;
                      _selectedLot = null;
                    });
                  },
                  icon: Icons.agriculture_rounded,
                ),

                if (_selectedFarm != null) ...[
                  const SizedBox(height: 24),
                  _buildSectionTitle('2. Sélectionner la salle'),
                  const SizedBox(height: 12),
                  _buildDropdown<String>(
                    value: _selectedRoom,
                    hint: 'Choisir une salle',
                    items: _getRoomsForFarm(_selectedFarm!),
                    onChanged: (val) => setState(() => _selectedRoom = val),
                    icon: Icons.meeting_room_rounded,
                  ),
                ],

                const SizedBox(height: 24),
                _buildSectionTitle('3. Identifier le Lot (Optionnel)'),
                const SizedBox(height: 12),
                _buildDropdown<String>(
                  value: _selectedLot,
                  hint: 'Tous les lots ou choisir...',
                  items: _allLots.map((l) => l.number).toList(),
                  onChanged: (val) => setState(() => _selectedLot = val),
                  icon: Icons.inventory_2_rounded,
                ),

                const SizedBox(height: 24),
                _buildSectionTitle('4. Sexe'),
                const SizedBox(height: 12),
                _buildSexSelector(),

                const SizedBox(height: 48),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: (_selectedFarm != null && _selectedRoom != null) 
                      ? _navigateToPerformance 
                      : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.indigo,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                    child: const Text('VOIR L\'ÉVOLUTION', 
                      style: TextStyle(fontWeight: FontWeight.bold, letterSpacing: 1)),
                  ),
                ),
              ],
            ),
          ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title, 
      style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.indigo.shade300, letterSpacing: 0.5));
  }

  Widget _buildDropdown<T>({
    required T? value,
    required String hint,
    required List<T> items,
    required Function(T?) onChanged,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<T>(
          value: value,
          hint: Text(hint, style: TextStyle(color: Colors.grey.shade400, fontSize: 14)),
          isExpanded: true,
          icon: Icon(Icons.arrow_drop_down_circle_outlined, color: Colors.indigo.shade200),
          items: items.map((item) => DropdownMenuItem<T>(
            value: item,
            child: Row(
              children: [
                Icon(icon, size: 18, color: Colors.indigo.shade400),
                const SizedBox(width: 12),
                Text(item.toString(), style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ],
            ),
          )).toList(),
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _buildSexSelector() {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
      ),
      child: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'Mâle', label: Text('Mâles'), icon: Icon(Icons.male)),
          ButtonSegment(value: 'Femelle', label: Text('Femelles'), icon: Icon(Icons.female)),
        ],
        selected: {_selectedSex},
        onSelectionChanged: (Set<String> newSelection) {
          setState(() => _selectedSex = newSelection.first);
        },
        style: ButtonStyle(
          side: WidgetStateProperty.all(BorderSide.none),
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) return Colors.indigo;
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) return Colors.white;
            return Colors.indigo.shade900;
          }),
        ),
      ),
    );
  }

  void _navigateToPerformance() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PerformanceComparisonScreen(
          farmName: _selectedFarm!,
          roomName: _selectedRoom!,
          sex: _selectedSex,
          lotNumber: _selectedLot,
        ),
      ),
    );
  }
}
