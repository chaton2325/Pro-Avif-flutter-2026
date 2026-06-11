import 'package:flutter/material.dart';
import '../models/user.dart';
import '../models/lot.dart';
import '../services/session_storage.dart';
import 'weighing_summary_screen.dart';

class WeightEntryScreen extends StatefulWidget {
  final User user;
  final Lot lot;
  final String operator;
  final String building;
  final String room;
  final int age;
  final String? sex;
  final double minWeight;
  final double maxWeight;
  final int precision;
  final List<double>? initialWeights;

  const WeightEntryScreen({
    super.key,
    required this.user,
    required this.lot,
    required this.operator,
    required this.building,
    required this.room,
    required this.age,
    this.sex,
    required this.minWeight,
    required this.maxWeight,
    required this.precision,
    this.initialWeights,
  });

  @override
  State<WeightEntryScreen> createState() => _WeightEntryScreenState();
}

class _WeightEntryScreenState extends State<WeightEntryScreen> {
  final TextEditingController _weightController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  late List<double> _weights;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _weights = widget.initialWeights != null ? List.from(widget.initialWeights!) : [];
  }

  void _persistLocally() {
    SessionStorage.saveSession(
      user: widget.user,
      lot: widget.lot,
      operator: widget.operator,
      building: widget.building,
      room: widget.room,
      sex: widget.sex,
      lowerInterval: widget.minWeight,
      upperInterval: widget.maxWeight,
      age: widget.age,
      minWeight: widget.minWeight,
      maxWeight: widget.maxWeight,
      precision: widget.precision,
      weights: _weights,
    );
  }

  void _addWeight() {
    final String valueStr = _weightController.text.trim();
    if (valueStr.isEmpty) return;

    final double? weight = double.tryParse(valueStr);
    
    if (weight == null) {
      _setTemporaryError("Format invalide");
      return;
    }

    if (weight < widget.minWeight || weight > widget.maxWeight) {
      _setTemporaryError("Hors intervalle (${widget.minWeight} - ${widget.maxWeight})");
      return;
    }

    if (weight % widget.precision != 0) {
      _setTemporaryError("Doit être un multiple de ${widget.precision}");
      return;
    }

    setState(() {
      _weights.add(weight);
      _weightController.clear();
      _errorMessage = null;
    });

    _persistLocally();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _navigateToSummary() {
    if (_weights.isEmpty) return;
    
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => WeighingSummaryScreen(
          user: widget.user,
          lot: widget.lot,
          operator: widget.operator,
          building: widget.building,
          room: widget.room,
          age: widget.age,
          sex: widget.sex,
          lowerInterval: widget.minWeight,
          upperInterval: widget.maxWeight,
          weights: _weights,
        ),
      ),
    );
  }

  void _setTemporaryError(String msg) {
    setState(() {
      _errorMessage = msg;
    });
  }

  void _removeWeight(int index) {
    setState(() {
      _weights.removeAt(index);
    });
    _persistLocally();
  }

  @override
  void dispose() {
    _weightController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('SAISIE DES POIDS', style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // Info Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            color: Colors.orange.withValues(alpha: 0.05),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _buildHeaderInfo("Lot", widget.lot.number),
                    _buildHeaderInfo("Salle", widget.room),
                    _buildHeaderInfo("Précision", "${widget.precision}g"),
                  ],
                ),
                const Divider(),
                Text(
                  "Intervalle : ${widget.minWeight}g - ${widget.maxWeight}g",
                  style: TextStyle(color: Colors.grey[600], fontSize: 12, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Weights Area (Scrollable)
          Expanded(
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.grey[50],
                border: Border.symmetric(horizontal: BorderSide(color: Colors.grey.shade200)),
              ),
              child: SingleChildScrollView(
                controller: _scrollController,
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _weights.asMap().entries.map((entry) {
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black,
                        borderRadius: BorderRadius.circular(6),
                        boxShadow: [
                          BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 2, offset: const Offset(0, 1)),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.value.toStringAsFixed(0),
                            style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(width: 4),
                          GestureDetector(
                            onTap: () => _removeWeight(entry.key),
                            child: const Icon(Icons.close, size: 12, color: Colors.white60),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ),
          ),

          // Input Area (Fixed above keyboard)
          Container(
            padding: const EdgeInsets.fromLTRB(20, 15, 20, 10),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, -5)),
              ],
            ),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        keyboardType: TextInputType.number,
                        autofocus: true,
                        style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                        decoration: InputDecoration(
                          labelText: 'Entrer un poids (g)',
                          errorText: _errorMessage,
                          errorStyle: const TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                        onSubmitted: (_) => _addWeight(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      height: 55,
                      width: 55,
                      child: ElevatedButton(
                        onPressed: _addWeight,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.orange,
                          padding: EdgeInsets.zero,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Icon(Icons.add, color: Colors.white, size: 30),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  "Nombre de pesées : ${_weights.length}",
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.orange, fontSize: 13),
                ),
              ],
            ),
          ),

          // Footer Action
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _weights.isEmpty ? null : _navigateToSummary,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('SUIVANT (RÉSUMÉ)', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderInfo(String label, String value) {
    return Column(
      children: [
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }
}
