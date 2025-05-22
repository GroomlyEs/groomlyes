import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:slide_to_act/slide_to_act.dart';
import 'business_service.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as GoogleMaps;

class ClockInOutScreen extends StatefulWidget {
  const ClockInOutScreen({Key? key}) : super(key: key);

  @override
  _ClockInOutScreenState createState() => _ClockInOutScreenState();
}

class _ClockInOutScreenState extends State<ClockInOutScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  late String? _barberId;
  bool _isLoading = true;
  bool _hasLocationPermission = false;
  Map<String, dynamic>? _currentClock;
  List<Map<String, dynamic>> _clockHistory = [];
  GoogleMaps.LatLng? _currentLocation;
  final GlobalKey<SlideActionState> _slideKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _fetchBarberId();
    _checkLocationPermission();
  }

  Future<void> _checkLocationPermission() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      setState(() => _hasLocationPermission = false);
      return;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        setState(() => _hasLocationPermission = false);
        return;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      setState(() => _hasLocationPermission = false);
      return;
    }

    setState(() => _hasLocationPermission = true);
    _getCurrentLocation();
  }

  Future<void> _getCurrentLocation() async {
    try {
      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.best,
      );
      setState(() {
        _currentLocation = GoogleMaps.LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      debugPrint('Error getting location: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo obtener la ubicación')),
      );
    }
  }

  Future<void> _fetchBarberId() async {
    try {
      final user = await _supabase.auth.currentUser;
      if (user == null) throw Exception('Usuario no autenticado');

      final response = await _supabase
          .from('barbers')
          .select('id')
          .eq('user_id', user.id)
          .single();

      setState(() {
        _barberId = response['id'] as String;
      });

      await _loadClockData();
    } catch (e) {
      debugPrint('Error fetching barber ID: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadClockData() async {
    if (_barberId == null) return;

    setState(() => _isLoading = true);
    try {
      final businessService = Provider.of<BusinessService>(context, listen: false);
      
      final currentClock = await businessService.getCurrentClockStatus(_barberId!);
      final history = await businessService.getClockHistory(
        _barberId!,
        start_date: DateTime.now().subtract(const Duration(days: 30)),
      );

      setState(() {
        _currentClock = currentClock;
        _clockHistory = history;
        _slideKey.currentState?.reset(); // Resetear el botón deslizante
      });
    } catch (e) {
      debugPrint('Error loading clock data: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando datos: ${e.toString()}')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleClockAction() async {
    if (_barberId == null) return;

    setState(() => _isLoading = true);
    try {
      final businessService = Provider.of<BusinessService>(context, listen: false);
      
      if (_currentClock != null) {
        await businessService.clockOut(
          _barberId!,
          _currentLocation != null
              ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
              : null,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Salida registrada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        await businessService.clockIn(
          _barberId!,
          _currentLocation != null
              ? LatLng(_currentLocation!.latitude, _currentLocation!.longitude)
              : null,
        );
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Entrada registrada correctamente'),
            backgroundColor: Colors.green,
          ),
        );
      }
      
      await _loadClockData();
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  String _formatDuration(String? duration) {
    if (duration == null) return '--:--';
    try {
      final parts = duration.split(':');
      return '${parts[0].padLeft(2, '0')}:${parts[1].padLeft(2, '0')}';
    } catch (e) {
      return duration;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Control de Asistencia',
          style: GoogleFonts.poppins(
            color: const Color(0xFF143E40),
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF143E40)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Sección de estado actual
                  Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.person,
                                color: Colors.grey[600],
                              ),
                              const SizedBox(width: 8),
                              Text(
                                'Deirdra', // Nombre del barbero
                                style: GoogleFonts.poppins(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Text(
                            _currentClock != null 
                                ? 'Turno activo'
                                : 'Nuevo turno',
                            style: GoogleFonts.poppins(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: const Color(0xFF143E40),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _currentClock != null 
                                ? 'Entrada: ${DateFormat('HH:mm').format(DateTime.parse(_currentClock!['clock_in']).toLocal())}'
                                : 'Desliza para comenzar turno',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              color: Colors.grey[600],
                            ),
                          ),
                          const SizedBox(height: 24),
                          if (!_hasLocationPermission)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Text(
                                'La localización está desactivada',
                                style: GoogleFonts.poppins(
                                  color: Colors.orange,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          // Botón de deslizamiento
                          SlideAction(
                            key: _slideKey,
                            onSubmit: _handleClockAction,
                            sliderButtonIcon: Icon(
                              _currentClock != null ? Icons.logout : Icons.login,
                              color: Colors.white,
                            ),
                            text: _currentClock != null 
                                ? 'Desliza para salir'
                                : 'Desliza para entrar',
                            textStyle: GoogleFonts.poppins(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            alignment: Alignment.center,
                            height: 60,
                            borderRadius: 12,
                            elevation: 0,
                            innerColor: const Color(0xFF143E40),
                            outerColor: Colors.grey[200],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  // Sección de historial
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text(
                      'Historial de Turnos',
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: const Color(0xFF143E40),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (_clockHistory.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'No hay registros de turnos',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                          ),
                        ),
                      ),
                    )
                  else
                    ListView.separated(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _clockHistory.length,
                      separatorBuilder: (context, index) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final record = _clockHistory[index];
                        final clockIn = DateTime.parse(record['clock_in']).toLocal();
                        final clockOut = record['clock_out'] != null 
                            ? DateTime.parse(record['clock_out']).toLocal()
                            : null;
                        final duration = record['duration'];

                        return Card(
                          elevation: 2,
                          margin: const EdgeInsets.symmetric(vertical: 4),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 8),
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: const Color(0xFF143E40).withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                clockOut != null ? Icons.check_circle : Icons.timer,
                                color: clockOut != null ? Colors.green : Colors.orange,
                              ),
                            ),
                            title: Text(
                              DateFormat('EEEE, d MMMM', 'es_ES').format(clockIn),
                              style: GoogleFonts.poppins(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${DateFormat('HH:mm').format(clockIn)} - ${clockOut != null ? DateFormat('HH:mm').format(clockOut) : '--:--'}',
                                  style: GoogleFonts.poppins(),
                                ),
                                if (duration != null)
                                  Text(
                                    'Duración: ${_formatDuration(duration)}',
                                    style: GoogleFonts.poppins(
                                      fontSize: 12,
                                      color: Colors.grey[600],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
    );
  }
}
