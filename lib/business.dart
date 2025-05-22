import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'business_service.dart';

class BusinessScreen extends StatefulWidget {
  const BusinessScreen({Key? key}) : super(key: key);

  @override
  _BusinessScreenState createState() => _BusinessScreenState();
}

class _BusinessScreenState extends State<BusinessScreen> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  // Dependencias y controladores
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _notesController = TextEditingController();
  
  // Para el slider de imágenes
  final PageController _imageController = PageController(viewportFraction: 0.98);
  final ValueNotifier<int> _currentImageNotifier = ValueNotifier<int>(0);
  List<String> _cachedImages = [];

  // Para el dropdown de barberos
  final LayerLink _barberDropdownLink = LayerLink();
  OverlayEntry? _barberDropdownEntry;
  bool _isBarberDropdownOpen = false;
  final _barberDropdownKey = GlobalKey();

  // Estado del negocio
  late String _businessId;
  late Future<Map<String, dynamic>> _businessFuture;
  late Future<List<Map<String, dynamic>>> _barbersFuture;
  late Future<List<Map<String, dynamic>>> _servicesFuture;
  late Future<List<Map<String, dynamic>>> _galleryFuture;
  late Future<Map<String, dynamic>>? _availabilityFuture;
  
  // Estado de la reserva
  DateTime? _selectedDate;
  TimeOfDay? _selectedTime;
  String? _selectedBarberId;
  final Map<String, Map<String, dynamic>> _selectedServices = {};
  int _totalDuration = 0;
  double _totalPrice = 0.0;
  
  // Estado UI
  bool _isSubmitting = false;
  int _activeReservationsCount = 0;
  Map<DateTime, String> _availabilityMap = {}; // Mapa de disponibilidad por fecha

  @override
  void initState() {
    super.initState();
    _loadActiveReservationsCount();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final args = ModalRoute.of(context)!.settings.arguments;
    if (args is String) {
      _businessId = args;
      _loadData();
    } else {
      Navigator.pop(context);
    }
  }

  @override
  void dispose() {
    _imageController.dispose();
    _currentImageNotifier.dispose();
    _notesController.dispose();
    _removeBarberDropdown();
    super.dispose();
  }

  void _removeBarberDropdown() {
    _barberDropdownEntry?.remove();
    _barberDropdownEntry = null;
    _isBarberDropdownOpen = false;
  }

  void _toggleBarberDropdown(List<Map<String, dynamic>> barbers) {
    if (_isBarberDropdownOpen) {
      _removeBarberDropdown();
      return;
    }

    final renderBox = _barberDropdownKey.currentContext?.findRenderObject() as RenderBox?;
    final size = renderBox?.size ?? Size.zero;
    final offset = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;

    _barberDropdownEntry = OverlayEntry(
      builder: (context) => GestureDetector(
        onTap: _removeBarberDropdown,
        child: Container(
          color: Colors.transparent,
          child: Stack(
            children: [
              Positioned(
                width: size.width,
                left: offset.dx,
                top: offset.dy + size.height + 5,
                child: CompositedTransformFollower(
                  link: _barberDropdownLink,
                  showWhenUnlinked: false,
                  offset: Offset(0, size.height + 5),
                  child: Material(
                    elevation: 4,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.grey.withOpacity(0.2),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      constraints: BoxConstraints(
                        maxHeight: MediaQuery.of(context).size.height * 0.4,
                      ),
                      child: ListView.builder(
                        padding: EdgeInsets.zero,
                        shrinkWrap: true,
                        itemCount: barbers.length,
                        itemBuilder: (context, index) {
                          final barber = barbers[index];
                          return InkWell(
                            onTap: () {
                              setState(() {
                                _selectedBarberId = barber['id'];
                                _selectedDate = null;
                                _selectedTime = null;
                                // Cargar disponibilidad cuando se selecciona un barbero
                                _availabilityFuture = Provider.of<BusinessService>(context, listen: false)
                                  .getBarberAvailability(barber['id']);
                                _availabilityFuture?.then((availability) {
                                  setState(() {
                                    _availabilityMap = {};
                                    availability.forEach((dateStr, data) {
                                      final date = DateTime.parse(dateStr);
                                      _availabilityMap[date] = data['demand_level'];
                                    });
                                  });
                                });
                              });
                              _removeBarberDropdown();
                            },
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 12,
                              ),
                              child: Text(
                                barber['name'] ?? 'Desconocido',
                                style: GoogleFonts.poppins(),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_barberDropdownEntry!);
    _isBarberDropdownOpen = true;
  }

  Future<void> _loadActiveReservationsCount() async {
    final session = _supabase.auth.currentSession;
    if (session != null) {
      final businessService = Provider.of<BusinessService>(context, listen: false);
      final appointments = await businessService.getUserActiveAppointments(session.user.id);
      setState(() {
        _activeReservationsCount = appointments.length;
      });
    }
  }

  void _loadData() {
    final businessService = Provider.of<BusinessService>(context, listen: false);
    setState(() {
      _businessFuture = businessService.getBusinessDetails(_businessId);
      _barbersFuture = businessService.getBarbers(_businessId);
      _servicesFuture = businessService.getServices(_businessId);
      _galleryFuture = businessService.getBusinessGallery(_businessId);
    });
  }

Future<void> _selectDate(BuildContext context) async {
  if (_selectedBarberId == null) {
    _showSnackBar('Selecciona un barbero primero');
    return;
  }

  DateTime initialDate = _selectedDate ?? DateTime.now();

  // Busca el primer día seleccionable si el actual no lo es
  bool isSelectable(DateTime day) {
    if (_availabilityMap.isEmpty) return true;
    final availability = _availabilityMap[DateTime(day.year, day.month, day.day)];
    return availability != 'unavailable';
  }

  // Si el initialDate no es seleccionable, busca el siguiente
  int tries = 0;
  while (!isSelectable(initialDate) && tries < 60) {
    initialDate = initialDate.add(const Duration(days: 1));
    tries++;
  }

  final DateTime? picked = await showDatePicker(
    context: context,
    initialDate: initialDate,
    firstDate: DateTime.now(),
    lastDate: DateTime.now().add(const Duration(days: 60)),
    locale: const Locale('es', 'ES'),
    builder: (context, child) => Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF254155),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        dialogBackgroundColor: Colors.white,
        textTheme: TextTheme(
          titleMedium: GoogleFonts.poppins(),
          bodyMedium: GoogleFonts.poppins(),
        ),
      ),
      child: child!,
    ),
    selectableDayPredicate: isSelectable,
  );

  if (picked != null) {
    setState(() {
      _selectedDate = picked;
      _selectedTime = null;
    });
  }
}

  Future<void> _selectTime(BuildContext context) async {
    if (_selectedBarberId == null) return _showSnackBar('Selecciona un barbero');
    if (_selectedDate == null) return _showSnackBar('Selecciona una fecha');
    if (_selectedServices.isEmpty) return _showSnackBar('Agrega al menos un servicio');

    try {
      final businessService = Provider.of<BusinessService>(context, listen: false);
      
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final availableSlots = await businessService.getAvailableTimeSlots(
        _selectedBarberId!,
        _selectedDate!,
        _totalDuration,
      );

      Navigator.of(context).pop();

      if (availableSlots.isEmpty) {
        return _showSnackBar('No hay horarios disponibles');
      }

      final TimeOfDay? pickedTime = await showTimePicker(
        context: context,
        initialTime: _selectedTime ?? _findClosestAvailableTime(
          availableSlots.map((slot) => TimeOfDay(
            hour: slot['hour'], 
            minute: slot['minute'],
          )).toList(),
        ),
        builder: (context, child) => _buildPickerTheme(child!),
      );

      if (pickedTime != null) {
        final isTimeValid = availableSlots.any((slot) => 
          slot['hour'] == pickedTime.hour && slot['minute'] == pickedTime.minute);
        
        if (isTimeValid) {
          setState(() => _selectedTime = pickedTime);
        } else {
          _showSnackBar('Selecciona una hora disponible');
        }
      }
    } catch (e) {
      Navigator.of(context).pop();
      _showSnackBar('Error al obtener horarios: ${e.toString()}');
    }
  }

  void _toggleServiceSelection(Map<String, dynamic> service) {
    setState(() {
      if (_selectedServices.containsKey(service['id'])) {
        _selectedServices.remove(service['id']);
        _totalDuration -= (service['duration'] as num).toInt();
        _totalPrice -= (service['price'] as num).toDouble();
      } else {
        _selectedServices[service['id']] = service;
        _totalDuration += (service['duration'] as num).toInt();
        _totalPrice += (service['price'] as num).toDouble();
      }
      _selectedTime = null;
    });
  }

Future<void> _confirmOrder() async {
  if (_selectedDate == null || _selectedTime == null || 
      _selectedBarberId == null || _selectedServices.isEmpty) {
    return _showSnackBar('Completa todos los campos');
  }

  final session = _supabase.auth.currentSession;
  if (session == null) return _showSnackBar('Debes iniciar sesión');

  setState(() => _isSubmitting = true);

  try {
    final appointmentTime = DateTime(
      _selectedDate!.year,
      _selectedDate!.month,
      _selectedDate!.day,
      _selectedTime!.hour,
      _selectedTime!.minute,
    );

    final businessService = Provider.of<BusinessService>(context, listen: false);
    final userId = session.user.id;
    
    // Verificar si el slot está ocupado
    final slotTaken = await businessService.isSlotTaken(
      barberId: _selectedBarberId!,
      appointmentTime: appointmentTime,
    );
    
    if (slotTaken) {
      _showErrorSnackBar('El horario seleccionado ya está ocupado. Por favor, elige otro.');
      setState(() => _isSubmitting = false);
      return;
    }

    // Verificar reservas activas del usuario
    final activeAppointments = await businessService.getUserActiveAppointments(userId);

    // Validar si ya tiene reserva ese día
    final hasSameDayReservation = activeAppointments.any((appointment) {
      final appointmentDate = DateTime.parse(
        appointment['appointment_time'] ?? appointment['starts_at'] ?? ''
      );
      return appointmentDate.year == _selectedDate!.year &&
             appointmentDate.month == _selectedDate!.month &&
             appointmentDate.day == _selectedDate!.day;
    });

    if (hasSameDayReservation) {
      _showErrorSnackBar('Ya tienes una reserva para este día.');
      setState(() => _isSubmitting = false);
      return;
    }

    if (activeAppointments.isNotEmpty) {
      final confirm = await _showConfirmationDialog(
        title: 'Reserva existente',
        content: 'Ya tienes una reserva activa. ¿Deseas crear una nueva?',
      );
      if (confirm != true) {
        setState(() => _isSubmitting = false);
        return;
      }
    }

    // Mostrar diálogo de confirmación
    final confirm = await _showReservationDetailsDialog(appointmentTime);
    if (confirm == true) {
      // Limpiar los servicios para evitar nulls y errores de tipo
      final cleanedServices = _selectedServices.values.map((service) {
        return {
          'id': (service['id'] ?? '').toString(),
          'name': (service['name'] ?? '').toString(),
          'duration': service['duration'] is int
              ? service['duration']
              : int.tryParse(service['duration']?.toString() ?? '0') ?? 0,
          'price': service['price'] is double
              ? service['price']
              : double.tryParse(service['price']?.toString() ?? '0.0') ?? 0.0,
        };
      }).toList();

      await businessService.createOrder(
        businessId: _businessId,
        userId: userId,
        barberId: _selectedBarberId!,
        services: cleanedServices,
        appointmentTime: appointmentTime,
        notes: _notesController.text,
      );

      _showSuccessSnackBar('¡Reserva confirmada!');
      await _loadActiveReservationsCount();
      _resetForm();
    }
  } catch (e) {
    _showErrorSnackBar('Error al confirmar la reserva: ${e.toString()}');
  } finally {
    setState(() => _isSubmitting = false);
  }
}

  TimeOfDay _findClosestAvailableTime(List<TimeOfDay> availableTimes) {
    final now = TimeOfDay.now();
    for (final time in availableTimes) {
      if (time.hour > now.hour || (time.hour == now.hour && time.minute >= now.minute)) {
        return time;
      }
    }
    return availableTimes.first;
  }

  void _resetForm() {
    setState(() {
      _selectedDate = null;
      _selectedTime = null;
      _selectedBarberId = null;
      _selectedServices.clear();
      _totalDuration = 0;
      _totalPrice = 0.0;
      _notesController.clear();
      _availabilityMap.clear();
    });
  }

  Theme _buildPickerTheme(Widget child) {
    return Theme(
      data: Theme.of(context).copyWith(
        colorScheme: const ColorScheme.light(
          primary: Color(0xFF254155),
          onPrimary: Colors.white,
          surface: Colors.white,
          onSurface: Colors.black,
        ),
        dialogBackgroundColor: Colors.white,
      ),
      child: MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          FutureBuilder(
            future: Future.wait([_businessFuture, _galleryFuture]),
            builder: (context, AsyncSnapshot<List<dynamic>> snapshot) {
              if (snapshot.connectionState == ConnectionState.waiting) {
                return const Center(child: CircularProgressIndicator());
              }
              if (snapshot.hasError) {
                return Center(child: Text('Error: ${snapshot.error}'));
              }

              final business = snapshot.data![0] as Map<String, dynamic>;
              final gallery = snapshot.data![1] as List<Map<String, dynamic>>;

              final businessImages = [
                business['cover_url'],
                business['logo_url'],
              ].whereType<String>().toList();

              final galleryImages = gallery.map((img) => img['image_url'] as String).toList();

              return SingleChildScrollView(
                padding: const EdgeInsets.only(bottom: 100),
                child: Column(
                  children: [
                    if (businessImages.isNotEmpty || galleryImages.isNotEmpty)
                      _buildImageGallery(businessImages, galleryImages),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildBusinessHeader(business),
                          const SizedBox(height: 24),
                          _buildReservationForm(),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: _buildBottomActionBar(),
          ),
        ],
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFF143E40)),
        onPressed: () => Navigator.pop(context),
      ),
      title: FutureBuilder<Map<String, dynamic>>(
        future: _businessFuture,
        builder: (context, snapshot) {
          return Text(
            snapshot.data?['name'] ?? 'Negocio',
            style: GoogleFonts.poppins(
              color: const Color(0xFF254155),
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          );
        },
      ),
      centerTitle: true,
      actions: [
        Stack(
          children: [
            IconButton(
              icon: const Icon(Icons.calendar_today, color: Color(0xFF143E40)),
              onPressed: () => Navigator.pushNamed(context, '/reservations'),
            ),
            if (_activeReservationsCount > 0)
              Positioned(
                right: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16, minHeight: 16),
                  child: Text(
                    '$_activeReservationsCount',
                    style: const TextStyle(color: Colors.white, fontSize: 10),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildImageGallery(List<String> businessImages, List<String> galleryImages) {
    _cachedImages = [...businessImages, ...galleryImages];
    
    if (_cachedImages.isEmpty) {
      return const Center(
        child: Text('No hay imágenes disponibles', style: TextStyle(color: Colors.grey)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            height: 220,
            child: NotificationListener<ScrollNotification>(
              onNotification: (notification) {
                if (notification is ScrollUpdateNotification) {
                  final page = _imageController.page?.round() ?? 0;
                  if (_currentImageNotifier.value != page) {
                    _currentImageNotifier.value = page;
                  }
                }
                return false;
              },
              child: PageView.builder(
                controller: _imageController,
                itemCount: _cachedImages.length,
                itemBuilder: (context, index) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: _cachedImages[index],
                        fit: BoxFit.cover,
                        placeholder: (context, url) => Container(
                          color: Colors.grey[200],
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                        errorWidget: (context, url, error) => Container(
                          color: Colors.grey[200],
                          child: const Icon(Icons.broken_image, color: Colors.grey),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          ValueListenableBuilder<int>(
            valueListenable: _currentImageNotifier,
            builder: (context, value, child) {
              return Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _cachedImages.length,
                  (index) => GestureDetector(
                    onTap: () => _imageController.animateToPage(
                      index,
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeInOut,
                    ),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: value == index 
                            ? const Color(0xFF143E40)
                            : Colors.grey.withOpacity(0.4),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

Widget _buildBusinessHeader(Map<String, dynamic> business) {
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        business['name'] ?? 'Sin nombre',
        style: GoogleFonts.poppins(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: const Color(0xFF254155),
        ),
      ),
      const SizedBox(height: 8),
      Row(
        children: [
          const Icon(Icons.location_on, size: 16, color: Colors.grey),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              business['address'] ?? 'Sin dirección',
              style: GoogleFonts.poppins(
                color: Colors.grey[600],
                fontSize: 14,
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF143E40).withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              'ABIERTO',
              style: GoogleFonts.poppins(
                color: const Color(0xFF254155),
                fontWeight: FontWeight.bold,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Divider(color: Colors.grey[300]),
    ],
  );
}

  Widget _buildReservationForm() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionTitle('Selecciona tu barbero'),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _barbersFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return _buildBarberDropdown(snapshot.data ?? []);
          },
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('Selecciona servicios'),
        const SizedBox(height: 12),
        FutureBuilder<List<Map<String, dynamic>>>(
          future: _servicesFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return Text('Error: ${snapshot.error}');
            }
            return _buildServicesList(snapshot.data ?? []);
          },
        ),
        const SizedBox(height: 24),
        _buildSectionTitle('Elige fecha y hora'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _buildDateSelector(),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTimeSelector(),
            ),
          ],
        ),
        if (_selectedBarberId != null && _selectedDate != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: FutureBuilder<Map<String, dynamic>>(
              future: _availabilityFuture,
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                
                if (snapshot.hasData) {
                  final dateStr = DateFormat('yyyy-MM-dd').format(_selectedDate!);
                  final availability = snapshot.data![dateStr];
                  
                  if (availability != null) {
                    Color availabilityColor = Colors.grey;
                    String availabilityText = '';
                    
                    switch (availability['demand_level']) {
                      case 'low':
                        availabilityColor = Colors.green;
                        availabilityText = 'Alta disponibilidad';
                        break;
                      case 'medium':
                        availabilityColor = Colors.orange;
                        availabilityText = 'Disponibilidad media';
                        break;
                      case 'high':
                        availabilityColor = Colors.red;
                        availabilityText = 'Baja disponibilidad';
                        break;
                      default:
                        availabilityText = 'No disponible';
                    }
                    
                    return Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: availabilityColor),
                        const SizedBox(width: 8),
                        Text(
                          availabilityText,
                          style: GoogleFonts.poppins(
                            color: availabilityColor,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    );
                  }
                }
                return const SizedBox();
              },
            ),
          ),
        const SizedBox(height: 24),
        _buildSectionTitle('Notas adicionales'),
        const SizedBox(height: 12),
        _buildNotesField(),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: GoogleFonts.poppins(
        color: const Color(0xFF254155),
        fontWeight: FontWeight.w600,
        fontSize: 16,
      ),
    );
  }

Widget _buildBarberDropdown(List<Map<String, dynamic>> barbers) {
  return CompositedTransformTarget(
    link: _barberDropdownLink,
    child: Container(
      key: _barberDropdownKey,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: InkWell(
        onTap: () => _toggleBarberDropdown(barbers),
        child: Row(
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _selectedBarberId != null
                      ? barbers.firstWhere(
                          (b) => b['id'] == _selectedBarberId,
                          orElse: () => {'name': 'Seleccionar barbero'},
                        )['name']?.toString() ?? 'Seleccionar barbero'
                      : 'Seleccionar barbero',
                  style: GoogleFonts.poppins(
                    color: _selectedBarberId != null ? Colors.black : Colors.grey[600],
                  ),
                ),
              ),
            ),
            Icon(
              _isBarberDropdownOpen ? Icons.arrow_drop_up : Icons.arrow_drop_down,
              color: Colors.grey,
            ),
          ],
        ),
      ),
    ),
  );
}

  Widget _buildDateSelector() {
    return InkWell(
      onTap: () => _selectDate(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_today, size: 20, color: Color(0xFF143E40)),
            const SizedBox(width: 12),
            Text(
              _selectedDate != null
                  ? DateFormat('EEE, d MMM', 'es_ES').format(_selectedDate!)
                  : 'Fecha',
              style: GoogleFonts.poppins(
                color: _selectedDate != null ? Colors.black : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimeSelector() {
    return InkWell(
      onTap: () => _selectTime(context),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.grey[300]!),
          boxShadow: [
            BoxShadow(
              color: Colors.grey.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            const Icon(Icons.access_time, size: 20, color: Color(0xFF143E40)),
            const SizedBox(width: 12),
            Text(
              _selectedTime != null
                  ? _selectedTime!.format(context)
                  : 'Hora',
              style: GoogleFonts.poppins(
                color: _selectedTime != null ? Colors.black : Colors.grey[600],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildServicesList(List<Map<String, dynamic>> services) {
    if (services.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Text('No hay servicios disponibles'),
      );
    }

    return Column(
      children: services.map((service) {
        final isSelected = _selectedServices.containsKey(service['id']);
        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: InkWell(
            onTap: () => _toggleServiceSelection(service),
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected 
                    ? const Color(0xFF143E40).withOpacity(0.05)
                    : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isSelected 
                      ? const Color(0xFF143E40)
                      : Colors.grey[300]!,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.grey.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: isSelected 
                            ? const Color(0xFF143E40)
                            : Colors.grey[400]!,
                      ),
                      borderRadius: BorderRadius.circular(6),
                      color: isSelected 
                          ? const Color(0xFF143E40).withOpacity(0.2)
                          : Colors.transparent,
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, size: 16, color: Color(0xFF143E40))
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          service['name'] ?? 'Sin nombre',
                          style: GoogleFonts.poppins(
                            color: const Color(0xFF254155),
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        Text(
                          '${service['duration']} min',
                          style: GoogleFonts.poppins(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '${(service['price'] as num).toStringAsFixed(2)}€',
                    style: GoogleFonts.poppins(
                      color: const Color(0xFF254155),
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildNotesField() {
    return TextField(
      controller: _notesController,
      maxLines: 3,
      decoration: InputDecoration(
        hintText: 'Escribe aquí cualquier requerimiento especial...',
        hintStyle: GoogleFonts.poppins(color: Colors.grey[500]),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey[300]!),
        ),
        filled: true,
        fillColor: Colors.white,
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildBottomActionBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          top: BorderSide(color: Colors.grey[200]!),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        children: [
          if (_selectedServices.isNotEmpty) ...[
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total',
                  style: GoogleFonts.poppins(
                    color: Colors.grey[600],
                    fontSize: 12,
                  ),
                ),
                Text(
                  '${_totalPrice.toStringAsFixed(2)}€',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: const Color(0xFF254155),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
          ],
          Expanded(
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _confirmOrder,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF254155),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                elevation: 0,
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      'CONFIRMAR RESERVA',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showConfirmationDialog({required String title, required String content}) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          title,
          style: GoogleFonts.poppins(
            color: const Color(0xFF254155),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(content, style: GoogleFonts.poppins()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.poppins(color: const Color(0xFF143E40)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Continuar',
              style: GoogleFonts.poppins(
                color: const Color(0xFF254155),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

    Future<bool?> _showReservationDetailsDialog(DateTime appointmentTime) async {
    return await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Confirmar Reserva',
          style: GoogleFonts.poppins(
            color: const Color(0xFF254155),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Detalles:', style: GoogleFonts.poppins(fontWeight: FontWeight.w500)),
            const SizedBox(height: 12),
            _buildDetailRow(Icons.calendar_today, 
              DateFormat('EEE, d MMM yyyy', 'es_ES').format(_selectedDate!)),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.access_time, _selectedTime!.format(context)),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.timer, '$_totalDuration minutos'),
            const SizedBox(height: 8),
            _buildDetailRow(Icons.attach_money, '${_totalPrice.toStringAsFixed(2)}€'),
            if (_notesController.text.isNotEmpty) ...[
              const SizedBox(height: 8),
              _buildDetailRow(Icons.note, _notesController.text),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(
              'Cancelar',
              style: GoogleFonts.poppins(color: const Color(0xFF143E40)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(
              'Confirmar',
              style: GoogleFonts.poppins(
                color: const Color(0xFF254155),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(IconData icon, String text) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: const Color(0xFF143E40)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: GoogleFonts.poppins(),
            overflow: TextOverflow.visible,
          ),
        ),
      ],
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }
}