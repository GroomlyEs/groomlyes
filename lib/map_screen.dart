import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'business.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({Key? key}) : super(key: key);

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  late GoogleMapController _mapController;
  LatLng _currentPosition = const LatLng(41.3851, 2.1734);
  bool _isLoading = true;
  final Set<Marker> _markers = {};
  final BusinessService _businessService = BusinessService();
  List<Map<String, dynamic>> _topBarbershops = [];
  bool _showTopBarbersPopup = false;
  String _currentProvince = 'Barcelona';
  Map<String, bool> _barbershopsOpenStatus = {};

  @override
  void initState() {
    super.initState();
    _initializeMap();
  }

  Future<void> _initializeMap() async {
    await _getCurrentLocation();
    await _loadBusinessMarkers();
    await _loadTopBarbershops();
  }

  Future<void> _getCurrentLocation() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _isLoading = false);
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission != LocationPermission.whileInUse) {
          setState(() => _isLoading = false);
          return;
        }
      }

      Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
      );

      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
        _markers.add(
          Marker(
            markerId: const MarkerId('current_location'),
          ),
        );
      });
    } catch (e) {
      debugPrint('Error obteniendo ubicación: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadBusinessMarkers() async {
    try {
      final businesses = await _businessService.getBusinessesWithLocations();
      
      // Verificar estado de apertura para cada barbería
      for (var business in businesses) {
        final id = business['id'].toString();
        _barbershopsOpenStatus[id] = await _businessService.isBusinessOpenNow(id);
      }

      for (var business in businesses) {
        if (business['latitude'] != null && business['longitude'] != null) {
          final id = business['id'].toString();
          final marker = Marker(
            markerId: MarkerId(id),
            position: LatLng(business['latitude'], business['longitude']),
            infoWindow: InfoWindow(
              title: business['name'],
              snippet: '⭐ ${business['rating']?.toStringAsFixed(1) ?? 'N/A'} • ${_barbershopsOpenStatus[id] ?? false ? 'Abierto' : 'Cerrado'}',
            ),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              _barbershopsOpenStatus[id] ?? false 
                ? BitmapDescriptor.hueGreen 
                : BitmapDescriptor.hueRed,
            ),
            onTap: () {
              _showBarbershopDetails(context, business);
            },
          );
          
          setState(() {
            _markers.add(marker);
          });
        }
      }
      
      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error cargando marcadores de negocios: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadTopBarbershops() async {
    try {
      final barbershops = await _businessService.getTopBarbershopsByProvince(_currentProvince);
      
      // Precargar estado de apertura para las top barberías
      for (var barbershop in barbershops) {
        final id = barbershop['id'].toString();
        _barbershopsOpenStatus[id] = await _businessService.isBusinessOpenNow(id);
      }
      
      setState(() {
        _topBarbershops = barbershops;
        _showTopBarbersPopup = true;
      });
    } catch (e) {
      debugPrint('Error cargando barberías top: $e');
    }
  }

  void _centerMapOnBarbershop(Map<String, dynamic> barbershop) {
    if (barbershop['latitude'] != null && barbershop['longitude'] != null) {
      final position = LatLng(barbershop['latitude'], barbershop['longitude']);
      _mapController.animateCamera(
        CameraUpdate.newLatLngZoom(position, 16), // Zoom ajustado para ver el negocio
      );
    } else {
      debugPrint('La ubicación del negocio no está disponible.');
    }
  }

  void _showBarbershopDetails(BuildContext context, Map<String, dynamic> barbershop) {
    final id = barbershop['id'].toString();
    final isOpen = _barbershopsOpenStatus[id] ?? false;

    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (barbershop['logo_url'] != null)
                    Container(
                      width: 80,
                      height: 80,
                      margin: const EdgeInsets.only(right: 16),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        image: DecorationImage(
                          image: NetworkImage(barbershop['logo_url']),
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          barbershop['name'] ?? 'Sin nombre',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const Icon(Icons.star, color: Colors.amber, size: 20),
                            const SizedBox(width: 4),
                            Text(
                              barbershop['rating']?.toStringAsFixed(1) ?? 'N/A',
                              style: const TextStyle(fontSize: 16),
                            ),
                            const SizedBox(width: 16),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: isOpen ? Colors.green[100] : Colors.red[100],
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                isOpen ? 'Abierto' : 'Cerrado',
                                style: TextStyle(
                                  color: isOpen ? Colors.green[800] : Colors.red[800],
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          barbershop['address'] ?? '',
                          style: TextStyle(color: Colors.grey[600]),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        side: const BorderSide(color: Color(0xFF143E40)),
                      ),
                      child: const Text(
                        'Cerrar',
                        style: TextStyle(color: Color(0xFF143E40)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context); // Cerrar el modal
                        _navigateToBusinessScreen(context, barbershop['id']);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF143E40),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                      ),
                      child: const Text(
                        'Visitar sitio',
                        style: TextStyle(color: Colors.white),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void _navigateToBusinessScreen(BuildContext context, String businessId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => BusinessScreen(),
        settings: RouteSettings(arguments: businessId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mapa de Barberías'),
        backgroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.star, color: Colors.amber),
            onPressed: () {
              setState(() {
                _showTopBarbersPopup = !_showTopBarbersPopup;
              });
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          _isLoading
              ? const Center(child: CircularProgressIndicator())
              : GoogleMap(
                  onMapCreated: (controller) {
                    _mapController = controller;
                  },
                  initialCameraPosition: CameraPosition(
                    target: _currentPosition,
                    zoom: 14.0,
                  ),
                  markers: _markers,
                  myLocationEnabled: true,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  onTap: (LatLng position) {
                    setState(() {
                      _showTopBarbersPopup = false;
                    });
                  },
                ),
          if (_showTopBarbersPopup && _topBarbershops.isNotEmpty)
            Positioned(
              top: 80,
              left: 16,
              right: 16,
              child: TopBarbershopsPopup(
                barbershops: _topBarbershops,
                openStatus: _barbershopsOpenStatus,
                onBarbershopTap: (barbershop) {
                  _centerMapOnBarbershop(barbershop); // Centrar el mapa en el negocio
                  _showBarbershopDetails(context, barbershop); // Mostrar detalles
                },
                onClose: () {
                  setState(() {
                    _showTopBarbersPopup = false;
                  });
                },
              ),
            ),
          Positioned(
            bottom: 20,
            right: 20,
            child: Column(
              children: [
                FloatingActionButton(
                  onPressed: () {
                    _mapController.animateCamera(
                      CameraUpdate.newLatLngZoom(_currentPosition, 14),
                    );
                  },
                  backgroundColor: const Color(0xFF143E40),
                  child: const Icon(Icons.my_location, color: Colors.white),
                ),
                const SizedBox(height: 10),
                FloatingActionButton(
                  onPressed: () async {
                    await _loadTopBarbershops();
                  },
                  backgroundColor: const Color(0xFF143E40),
                  child: const Icon(Icons.refresh, color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class BusinessPage extends StatelessWidget {
  final String barbershopId;

  const BusinessPage({Key? key, required this.barbershopId}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Detalle de Barbería'),
      ),
      body: Center(
        child: Text('Página de la barbería $barbershopId'),
      ),
    );
  }
}

class TopBarbershopsPopup extends StatelessWidget {
  final List<Map<String, dynamic>> barbershops;
  final Map<String, bool>? openStatus;
  final Function(Map<String, dynamic>) onBarbershopTap;
  final VoidCallback onClose;

  const TopBarbershopsPopup({
    Key? key,
    required this.barbershops,
    required this.onBarbershopTap,
    required this.onClose,
    this.openStatus,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Top Barberías',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: onClose,
                ),
              ],
            ),
            const SizedBox(height: 8),
            SizedBox(
              height: 200,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                itemCount: barbershops.length,
                itemBuilder: (context, index) {
                  final barbershop = barbershops[index];
                  final id = barbershop['id'].toString();
                  final isOpen = openStatus?[id] ?? false;
                  
                  return GestureDetector(
                    onTap: () => onBarbershopTap(barbershop),
                    child: Container(
                      width: 180,
                      margin: const EdgeInsets.only(right: 12),
                      child: Card(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (barbershop['logo_url'] != null)
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: Image.network(
                                    barbershop['logo_url'],
                                    height: 60,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Container(
                                        height: 60,
                                        color: Colors.grey[200],
                                        child: const Icon(Icons.cut),
                                      );
                                    },
                                  ),
                                )
                              else
                                Container(
                                  height: 60,
                                  color: Colors.grey[200],
                                  child: const Center(child: Icon(Icons.cut)),
                                ),
                              const SizedBox(height: 8),
                              Text(
                                barbershop['name'],
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(
                                    Icons.star,
                                    color: Colors.amber[600],
                                    size: 16,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    barbershop['rating']?.toStringAsFixed(1) ?? '0.0',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                  const Spacer(),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: isOpen ? Colors.green[100] : Colors.red[100],
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isOpen ? 'Abierto' : 'Cerrado',
                                      style: TextStyle(
                                        color: isOpen ? Colors.green[800] : Colors.red[800],
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                barbershop['address'] ?? '',
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: Colors.grey,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class BusinessService {
  final SupabaseClient _supabase = Supabase.instance.client;

  Future<List<Map<String, dynamic>>> getBusinessesWithLocations() async {
    try {
      final response = await _supabase
          .from('barbershops')
          .select('id, name, address, city, cover_url, logo_url, rating, location')
          .not('location', 'is', null)
          .order('name', ascending: true);

      final businesses = List<Map<String, dynamic>>.from(response);

      return businesses.map((business) {
        if (business['location'] != null) {
          try {
            final locationStr = business['location'].toString();
            final regex = RegExp(r'POINT\(([-\d.]+) ([-\d.]+)\)');
            final match = regex.firstMatch(locationStr);
            
            if (match != null && match.groupCount >= 2) {
              business['longitude'] = double.parse(match.group(1)!);
              business['latitude'] = double.parse(match.group(2)!);
            }
          } catch (e) {
            debugPrint('Error al parsear ubicación: $e');
          }
        }
        return business;
      }).toList();
    } catch (e) {
      debugPrint('Error al obtener negocios con ubicación: ${e.toString()}');
      throw Exception('Error al obtener negocios con ubicación: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getTopBarbershopsByProvince(String province) async {
    try {
      final response = await _supabase
          .from('barbershops')
          .select('id, name, address, city, logo_url, rating, location')
          .ilike('city', '%$province%')
          .order('rating', ascending: false)
          .limit(5);

      final businesses = List<Map<String, dynamic>>.from(response);

      return businesses.map((business) {
        if (business['location'] != null) {
          try {
            final locationStr = business['location'].toString();
            final regex = RegExp(r'POINT\(([-\d.]+) ([-\d.]+)\)');
            final match = regex.firstMatch(locationStr);
            
            if (match != null && match.groupCount >= 2) {
              business['longitude'] = double.parse(match.group(1)!);
              business['latitude'] = double.parse(match.group(2)!);
            }
          } catch (e) {
            debugPrint('Error al parsear ubicación: $e');
          }
        }
        return business;
      }).toList();
    } catch (e) {
      debugPrint('Error al obtener top barberías: ${e.toString()}');
      throw Exception('Error al obtener top barberías: ${e.toString()}');
    }
  }

  Future<bool> isBusinessOpenNow(String barbershopId) async {
    try {
      final now = DateTime.now();
      final weekday = now.weekday; // 1 (Monday) - 7 (Sunday)

      final response = await _supabase
          .from('opening_hours')
          .select('open_at, close_at')
          .eq('barbershop_id', barbershopId)
          .eq('day_of_week', weekday)
          .maybeSingle();

      if (response == null) return false;

      final openAt = _parseTimeString(response['open_at'].toString());
      final closeAt = _parseTimeString(response['close_at'].toString());

      final currentTime = TimeOfDay.fromDateTime(now);
      
      return currentTime.hour > openAt.hour || 
             (currentTime.hour == openAt.hour && currentTime.minute >= openAt.minute) &&
             (currentTime.hour < closeAt.hour || 
             (currentTime.hour == closeAt.hour && currentTime.minute < closeAt.minute));
    } catch (e) {
      debugPrint('Error verificando horario: ${e.toString()}');
      return false;
    }
  }

  TimeOfDay _parseTimeString(String timeString) {
    try {
      final parts = timeString.split(':');
      if (parts.length < 2) {
        throw FormatException('Formato de tiempo inválido: $timeString');
      }
      return TimeOfDay(
        hour: int.parse(parts[0]),
        minute: int.parse(parts[1]),
      );
    } catch (e) {
      debugPrint('Error al parsear tiempo: $timeString. ${e.toString()}');
      throw Exception('Error al parsear tiempo: $timeString. ${e.toString()}');
    }
  }
}