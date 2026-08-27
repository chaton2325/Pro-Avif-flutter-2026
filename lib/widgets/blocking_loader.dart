import 'package:flutter/material.dart';

/// Exécute [action] en affichant une superposition modale bloquante
/// (non cliquable, non fermable) par-dessus tout l'écran courant.
///
/// Empêche qu'un double-appui sur un bouton (ex: "Créer") ne déclenche
/// deux fois la même action réseau avant que la première ne soit terminée.
Future<T> runBlocking<T>(
  BuildContext context,
  Future<T> Function() action,
) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    useRootNavigator: true,
    builder: (_) => const PopScope(
      canPop: false,
      child: Center(child: CircularProgressIndicator()),
    ),
  );
  try {
    return await action();
  } finally {
    navigator.pop();
  }
}
