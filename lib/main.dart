import 'package:flutter/material.dart';
import 'services/mongo_service.dart';
import 'screens/login_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final mongoService = MongoService();
  try {
    await mongoService.connect();
    print("Connexion à MongoDB réussie");
  } catch (e) {
    print("Échec de la connexion à MongoDB : $e");
  }

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Pro-Avif',
      theme: ThemeData(
        brightness: Brightness.light,
        primaryColor: Colors.orange,
        scaffoldBackgroundColor: const Color(0xFFF5F5F5), // Light grey/white
        colorScheme: ColorScheme.light(
          primary: Colors.orange,
          secondary: Colors.orangeAccent,
          surface: Colors.white,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.orange,
          elevation: 1,
          titleTextStyle: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 20),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.orange,
            foregroundColor: Colors.white,
            textStyle: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        useMaterial3: true,
      ),
      home: LoginScreen(),
    );
  }
}
