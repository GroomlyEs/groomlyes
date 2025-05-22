import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:groomlyes/business_service.dart' as business_service;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:geolocator/geolocator.dart';
import 'supabase_config.dart';
import 'auth_service.dart';
import 'login.dart';
import 'home.dart';
import 'signin.dart';
import 'business.dart';
import 'account.dart';
import 'reservations_history.dart';
import 'map_screen.dart';
import 'employee_home.dart';
import 'clock_in_out_screen.dart';

void main() async {
  await runZonedGuarded(() async {
    WidgetsFlutterBinding.ensureInitialized();
    
    // Configuración inicial con manejo de errores
    await _initializeApp();
    
    runApp(
      MultiProvider(
        providers: [
          Provider<AuthService>(create: (_) => AuthService()),
          Provider<business_service.BusinessService>(create: (_) => business_service.BusinessService()),
        ],
        child: const GroomlyESApp(),
      ),
    );
  }, (error, stack) {
    debugPrint('Uncaught error: $error, stack: $stack');
  });
}

Future<void> _initializeApp() async {
  // Configuración de Supabase
  await Supabase.initialize(
    url: SupabaseConfig.supabaseUrl,
    anonKey: SupabaseConfig.supabaseKey,
    authOptions: const FlutterAuthClientOptions(
      authFlowType: AuthFlowType.pkce,
    ),
  );

  // Configuraciones adicionales
  await initializeDateFormatting('es_ES', null);
  await _checkLocationPermissions();
}

Future<void> _checkLocationPermissions() async {
  final serviceEnabled = await Geolocator.isLocationServiceEnabled();
  if (!serviceEnabled) {
    throw Exception('Los servicios de ubicación están desactivados');
  }

  var permission = await Geolocator.checkPermission();
  if (permission == LocationPermission.denied) {
    permission = await Geolocator.requestPermission();
    if (permission == LocationPermission.denied) {
      throw Exception('Permisos de ubicación denegados');
    }
  }

  if (permission == LocationPermission.deniedForever) {
    throw Exception('Permisos de ubicación permanentemente denegados');
  }
}

class GroomlyESApp extends StatelessWidget {
  const GroomlyESApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Groomly ES',
      theme: _buildAppTheme(),
      locale: const Locale('es', 'ES'),
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('es', 'ES'), Locale('en', 'US')],
      home: const AuthWrapper(),
      routes: _buildAppRoutes(),
      onGenerateRoute: _handleUnknownRoutes,
    );
  }

  ThemeData _buildAppTheme() {
    return ThemeData(
      colorScheme: ColorScheme.light(
        primary: const Color(0xFF254155),
        secondary: const Color(0xFF254155),
        surface: Colors.white,
        background: Colors.white,
      ),
      scaffoldBackgroundColor: Colors.white,
      textTheme: GoogleFonts.poppinsTextTheme(),
      appBarTheme: const AppBarTheme(
        centerTitle: true,
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Color.fromARGB(255, 86, 27, 38)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey[100],
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Map<String, WidgetBuilder> _buildAppRoutes() {
    return {
      '/signin': (context) => const SignInScreen(),
      '/login': (context) => const LogInScreen(),
      '/home': (context) => const HomeScreen(),
      '/clock': (context) => const ClockInOutScreen(),
      '/employee_home': (context) => const EmployeeHomeScreen(),
      '/account': (context) => const AccountSettingsScreen(),
      '/business': (context) => const BusinessScreen(),
      '/reservations': (context) => const ReservationsHistoryScreen(),
      '/map': (context) => const MapScreen(), // Cambiado de ModernMapScreen a MapScreen
    };
  }

  Route<dynamic> _handleUnknownRoutes(RouteSettings settings) {
    return MaterialPageRoute(
      builder: (context) => Scaffold(
        appBar: AppBar(),
        body: Center(
          child: Text('Ruta ${settings.name} no encontrada'),
        ),
      ),
    );
  }
}

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Widget?>(
      future: _checkAuthStatus(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }
        return snapshot.data ?? const HomePageWidget();
      },
    );
  }

  static Future<Widget?> _checkAuthStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
    final accessToken = prefs.getString('access_token');
    final userRole = prefs.getString('user_role') ?? 'user';

    if (!isLoggedIn || accessToken == null) return null;

    try {
      final authService = AuthService();
      final session = await authService.getSession();
      
      if (session == null) {
        await authService.signOut();
        return null;
      }

      return userRole == 'employee' 
          ? const EmployeeHomeScreen() 
          : const HomeScreen();
    } catch (e) {
      debugPrint('Error verificando estado de autenticación: $e');
      await AuthService().signOut();
      return null;
    }
  }
}

class SplashScreen extends StatelessWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF254155),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Spacer(),
            Image.asset(
              'assets/logo.png',
              width: 150,
              height: 150,
              errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 100, color: Colors.white),
            ),
            const SizedBox(height: 30),
            const CircularProgressIndicator(color: Colors.white),
            const Spacer(),
            Text(
              'Cargando...',
              style: GoogleFonts.poppins(
                color: Colors.white,
                fontSize: 16,
              ),
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}

class HomePageWidget extends StatefulWidget {
  const HomePageWidget({Key? key}) : super(key: key);

  @override
  State<HomePageWidget> createState() => _HomePageWidgetState();
}

class _HomePageWidgetState extends State<HomePageWidget> {
  bool _isLoading = false;

  Future<void> _handleNavigation(Future<void> Function() navigation) async {
    setState(() => _isLoading = true);
    await navigation();
    if (mounted) setState(() => _isLoading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF254155),
      body: Stack(
        children: [
          _buildMainContent(),
          if (_isLoading) _buildLoadingOverlay(),
        ],
      ),
    );
  }

  Widget _buildMainContent() {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // const SizedBox(height: 40),
              // _buildAppLogo(),
              const SizedBox(height: 20),
              _buildAppTitle(),
              _buildAppDescription(),
              const SizedBox(height: 40),
              _buildAuthButtons(),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }

  // Widget _buildAppLogo() {
  //   return Image.asset(
  //     'assets/images/groomly_logo.png',
  //     width: 120,
  //     height: 120,
  //     errorBuilder: (_, __, ___) => const Icon(Icons.pets, size: 80, color: Colors.white),
  //   );
  // }

  Widget _buildAppTitle() {
    return Text(
      'GROOMLY ES',
      style: GoogleFonts.poppins(
        fontSize: 45,
        color: Colors.white,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.5,
      ),
    );
  }

  Widget _buildAppDescription() {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      child: Text(
        'Conoce nuestros competidores dentro del sector y encuentra tu estilo.',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 15,
          color: Color.fromARGB(237, 255, 255, 255),
        ),
      ),
    );
  }
  
  Widget _buildAuthButtons() {
    return Column(
      children: [
        _buildAuthButton(
          text: 'Iniciar Sesión',
          onPressed: () => _handleNavigation(() => Navigator.pushNamed(context, '/login')),
          isPrimary: false,
        ),
        const SizedBox(height: 16),
        _buildAuthButton(
          text: 'Registrarse',
          onPressed: () => _handleNavigation(() => Navigator.pushNamed(context, '/signin')),
          isPrimary: true,
        ),
      ],
    );
  }

  Widget _buildAuthButton({
    required String text,
    required VoidCallback onPressed,
    required bool isPrimary,
  }) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: isPrimary ? Colors.white : Colors.transparent,
          foregroundColor: isPrimary ? const Color(0xFF254155) : Colors.white,
          minimumSize: const Size(double.infinity, 52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(50),
            side: isPrimary ? BorderSide.none : const BorderSide(color: Colors.white),
          ),
          elevation: isPrimary ? 2 : 0,
        ),
        child: Text(
          text,
          style: GoogleFonts.poppins(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }
}