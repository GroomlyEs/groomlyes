import 'dart:math';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class LatLng {
  final double latitude;
  final double longitude;

  LatLng(this.latitude, this.longitude);
}

class BusinessService {
  final SupabaseClient _supabase = Supabase.instance.client;

  String _formatDate(DateTime date) {
    // Returns date as 'yyyy-MM-dd'
    return '${date.year.toString().padLeft(4, '0')}-'
           '${date.month.toString().padLeft(2, '0')}-'
           '${date.day.toString().padLeft(2, '0')}';
  }

  Future<List<Map<String, dynamic>>> getBusinesses() async {
    try {
      final response = await _supabase
          .from('barbershops')
          .select('id, name, address, city, logo_url, cover_url, rating')
          .order('name', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error al obtener negocios: ${e.toString()}');
      throw Exception('Error al obtener negocios: ${e.toString()}');
    }
  }

  Future<Map<String, dynamic>> getBusinessDetails(String businessId) async {
    try {
      final response = await _supabase
          .from('barbershops')
          .select(''' 
            *, 
            opening_hours:opening_hours(day_of_week, opens_at, closes_at),
            barbers(id, name, avatar_url),
            services(id, name, price)
          ''')
          .eq('id', businessId)
          .single();

      return response;
    } catch (e) {
      debugPrint('Error al obtener detalles del negocio: ${e.toString()}');
      throw Exception('Error al obtener detalles del negocio: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getBusinessGallery(String businessId) async {
    try {
      final response = await _supabase
          .from('barbershop_gallery')
          .select('*')
          .eq('barbershop_id', businessId)
          .order('created_at', ascending: false);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error al obtener galería del negocio: ${e.toString()}');
      throw Exception('Error al obtener galería del negocio: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getBarbers(String businessId) async {
    try {
      final response = await _supabase
          .from('barbers')
          .select('*')
          .eq('barbershop_id', businessId)
          .eq('is_active', true)
          .order('name', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error al obtener barberos: ${e.toString()}');
      throw Exception('Error al obtener barberos: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getServices(String businessId) async {
    try {
      final response = await _supabase
          .from('services')
          .select('*')
          .eq('barbershop_id', businessId)
          .eq('is_active', true)
          .order('price', ascending: true);

      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      debugPrint('Error al obtener servicios: ${e.toString()}');
      throw Exception('Error al obtener servicios: ${e.toString()}');
    }
  }

// Método createOrder actualizado
Future<String> createOrder({
  required String businessId,
  required String userId,
  required String barberId,
  required List<Map<String, dynamic>> services,
  required DateTime appointmentTime,
  String? notes,
}) async {
  try {
    final totalDuration = services.fold(0, (sum, service) {
      final duration = service['duration'];
      return sum + (duration is int ? duration : int.parse(duration.toString()));
    });

    final appointmentResponse = await _supabase
        .from('appointments')
        .insert({
          'user_id': userId,
          'barbershop_id': businessId,
          'barber_id': barberId,
          'starts_at': appointmentTime.toIso8601String(),
          'duration': totalDuration,
          'status': 'confirmed',
          'notes': notes,
        })
        .select()
        .single();

    final appointmentId = appointmentResponse['id'] as String;

    for (final service in services) {
      await _supabase.from('appointment_services').insert({
        'appointment_id': appointmentId,
        'service_id': service['id'],
        'price': service['price'],
        'duration': service['duration'] is int 
            ? service['duration'] 
            : int.parse(service['duration'].toString()),
      });
    }

    return appointmentId;
  } catch (e) {
    debugPrint('Error al crear la reserva: ${e.toString()}');
    throw Exception('Error al crear la reserva: ${e.toString()}');
  }
}

// Método getAvailableTimeSlots actualizado
Future<List<Map<String, dynamic>>> getAvailableTimeSlots(
  String barberId, 
  DateTime date,
  int serviceDuration,
) async {
  try {
    debugPrint('Obteniendo horarios para barbero $barberId en fecha ${date.toString()}');

    // 1. Obtener horario del barbero
    final scheduleResponse = await _supabase
        .from('barber_schedule')
        .select('opens_at, closes_at, break_start, break_end')
        .eq('barber_id', barberId)
        .eq('day_of_week', date.weekday);

    if (scheduleResponse.isEmpty) {
      debugPrint('El barbero no tiene horario para este día');
      throw Exception('El barbero no tiene horario para este día');
    }

    final schedule = scheduleResponse[0];
    if (schedule['opens_at'] == null || schedule['closes_at'] == null) {
      debugPrint('Horario incompleto en la base de datos');
      throw Exception('Horario incompleto en la base de datos');
    }

    // Validar y parsear los tiempos
    final opensAtTime = _parseTimeString(schedule['opens_at'].toString());
    final closesAtTime = _parseTimeString(schedule['closes_at'].toString());
    final breakStartTime = schedule['break_start'] != null 
        ? _parseTimeString(schedule['break_start'].toString()) : null;
    final breakEndTime = schedule['break_end'] != null 
        ? _parseTimeString(schedule['break_end'].toString()) : null;

    debugPrint('Horario: $opensAtTime - $closesAtTime, Break: $breakStartTime - $breakEndTime');

    // 2. Obtener citas existentes
    final startOfDay = DateTime(date.year, date.month, date.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    final existingAppointmentsResponse = await _supabase
        .from('appointments')
        .select('starts_at, duration')
        .eq('barber_id', barberId)
        .gte('starts_at', startOfDay.toIso8601String())
        .lt('starts_at', endOfDay.toIso8601String())
        .neq('status', 'cancelled');

    final bookedSlots = (existingAppointmentsResponse as List).map((appt) {
      final duration = appt['duration'] is int 
          ? appt['duration'] 
          : int.parse(appt['duration'].toString());
      final start = DateTime.parse(appt['starts_at'].toString());
      return {'start': start, 'end': start.add(Duration(minutes: duration))};
    }).toList();

    debugPrint('Citas existentes: ${bookedSlots.length}');

    // 3. Calcular horarios disponibles
    final availableSlots = <Map<String, dynamic>>[];
    DateTime currentSlot = DateTime(
      date.year, date.month, date.day,
      opensAtTime.hour, opensAtTime.minute
    );
    final closingDateTime = DateTime(
      date.year, date.month, date.day,
      closesAtTime.hour, closesAtTime.minute
    );

    debugPrint('Calculando horarios desde $currentSlot hasta $closingDateTime');

    while (currentSlot.add(Duration(minutes: serviceDuration)).isBefore(closingDateTime)) {
      final slotEnd = currentSlot.add(Duration(minutes: serviceDuration));

      // Verificar si está durante el break
      bool isDuringBreak = false;
      if (breakStartTime != null && breakEndTime != null) {
        final breakStart = DateTime(
          date.year, date.month, date.day, 
          breakStartTime.hour, breakStartTime.minute
        );
        final breakEnd = DateTime(
          date.year, date.month, date.day, 
          breakEndTime.hour, breakEndTime.minute
        );
        isDuringBreak = currentSlot.isBefore(breakEnd) && slotEnd.isAfter(breakStart);
      }

      // Verificar disponibilidad
      bool isAvailable = !isDuringBreak;
      for (final booked in bookedSlots) {
        if (currentSlot.isBefore(booked['end']!) && slotEnd.isAfter(booked['start']!)) {
          isAvailable = false;
          break;
        }
      }

      if (isAvailable) {
        availableSlots.add({
          'hour': currentSlot.hour,
          'minute': currentSlot.minute,
          'formatted': '${currentSlot.hour.toString().padLeft(2, '0')}:${currentSlot.minute.toString().padLeft(2, '0')}',
          'datetime': currentSlot,
        });
      }

      currentSlot = currentSlot.add(const Duration(minutes: 30));
    }

    debugPrint('Horarios disponibles encontrados: ${availableSlots.length}');
    return availableSlots;
  } catch (e) {
    debugPrint('Error en getAvailableTimeSlots: ${e.toString()}');
    throw Exception('Error al obtener horarios disponibles: ${e.toString()}');
  }
}

  Future<void> cancelAppointment(String appointmentId) async {
    try {
      await _supabase
          .from('appointments')
          .update({'status': 'cancelled'})
          .eq('id', appointmentId);
    } catch (e) {
      debugPrint('Error al cancelar la cita: ${e.toString()}');
      throw Exception('Error al cancelar la cita: ${e.toString()}');
    }
  }

  Future<List<Map<String, dynamic>>> getUserActiveAppointments(String userId) async {
    try {
      final appointments = await _supabase
          .from('appointments')
          .select('*, barbers(name)')
          .eq('user_id', userId)
          .gte('starts_at', DateTime.now().toIso8601String())
          .neq('status', 'cancelled')
          .order('starts_at', ascending: true);

      final result = <Map<String, dynamic>>[];
      for (final appointment in appointments) {
        final services = await _supabase
            .from('appointment_services')
            .select('*, services(name)')
            .eq('appointment_id', appointment['id']);

        result.add({
          ...appointment,
          'appointment_services': services,
        });
      }

      return result;
    } catch (e) {
      debugPrint('Error al obtener citas activas: ${e.toString()}');
      throw Exception('Error al obtener citas activas del usuario: ${e.toString()}');
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
          // Manejar ambos formatos:
          // 1. Formato actual "lat,lon" (ej: "41.3917, 2.1649")
          // 2. Formato PostGIS "POINT(lon lat)"
          
          // Intenta parsear como "lat,lon" primero
          if (locationStr.contains(',')) {
            final parts = locationStr.split(',');
            business['latitude'] = double.parse(parts[0].trim());
            business['longitude'] = double.parse(parts[1].trim());
          } 
          // Si no, intenta parsear como POINT
          else if (locationStr.startsWith('POINT')) {
            final regex = RegExp(r'POINT\(([-\d.]+) ([-\d.]+)\)');
            final match = regex.firstMatch(locationStr);
            if (match != null && match.groupCount >= 2) {
              business['longitude'] = double.parse(match.group(1)!);
              business['latitude'] = double.parse(match.group(2)!);
            }
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

  Future<List<Map<String, dynamic>>> getNearbyBusinesses(
    double latitude,
    double longitude,
    int radiusKm,
  ) async {
    try {
      final allBusinesses = await getBusinessesWithLocations();
      
      return allBusinesses.where((business) {
        if (business['latitude'] == null || business['longitude'] == null) {
          return false;
        }
        
        final distance = _calculateDistance(
          latitude, 
          longitude, 
          business['latitude'], 
          business['longitude']
        );
        
        business['distance'] = distance;
        return distance <= radiusKm;
      }).toList();
    } catch (e) {
      debugPrint('Error al buscar negocios cercanos: ${e.toString()}');
      throw Exception('Error al buscar negocios cercanos: ${e.toString()}');
    }
  }

  Future<double> getDistanceToBusiness(
    double userLat,
    double userLon,
    String businessId,
  ) async {
    try {
      final response = await _supabase
          .from('barbershops')
          .select('location')
          .eq('id', businessId)
          .single();

      if (response['location'] == null) {
        throw Exception('El negocio no tiene ubicación registrada');
      }

      try {
        final locationStr = response['location'].toString();
        final regex = RegExp(r'POINT\(([-\d.]+) ([-\d.]+)\)');
        final match = regex.firstMatch(locationStr);
        
        if (match == null || match.groupCount < 2) {
          throw Exception('Formato de ubicación no válido');
        }

        final businessLon = double.parse(match.group(1)!);
        final businessLat = double.parse(match.group(2)!);

        return _calculateDistance(userLat, userLon, businessLat, businessLon);
      } catch (e) {
        debugPrint('Error al parsear ubicación: ${e.toString()}');
        throw Exception('Error al parsear ubicación: ${e.toString()}');
      }
    } catch (e) {
      debugPrint('Error al calcular distancia: ${e.toString()}');
      throw Exception('Error al calcular distancia: ${e.toString()}');
    }
  }

Future<void> clockIn(String barberId, LatLng? location) async {
  try {
    final position = location != null
        ? 'POINT(${location.longitude} ${location.latitude})'
        : null;

    // Verificar si ya hay un fichaje activo
    final currentStatus = await getCurrentClockStatus(barberId);
    if (currentStatus != null) {
      throw Exception('Ya tienes un fichaje de entrada activo');
    }

    await _supabase.from('clock_in_out').insert({
      'barber_id': barberId,
      'clock_in': DateTime.now().toIso8601String(),
      'location': position,
      'status': 'active',
    });
  } catch (e) {
    debugPrint('Error al registrar entrada: ${e.toString()}');
    throw Exception('Error al registrar entrada: ${e.toString()}');
  }
}

Future<void> clockOut(String barberId, LatLng? location) async {
  try {
    final position = location != null
        ? 'POINT(${location.longitude} ${location.latitude})'
        : null;

    // Obtener el último fichaje de entrada sin salida
    final lastClockIn = await _supabase
        .from('clock_in_out')
        .select()
        .eq('barber_id', barberId)
        .filter('clock_out', 'is', null) // Verificar NULL correctamente
        .order('clock_in', ascending: false)
        .limit(1)
        .maybeSingle();

    if (lastClockIn == null) {
      throw Exception('No hay fichaje de entrada pendiente');
    }

    final now = DateTime.now();

    await _supabase
        .from('clock_in_out')
        .update({
          'clock_out': now.toIso8601String(),
          'location': position,
          'status': 'completed',
          'updated_at': now.toIso8601String(),
        })
        .eq('id', lastClockIn['id']);
  } catch (e) {
    debugPrint('Error al registrar salida: ${e.toString()}');
    throw Exception('Error al registrar salida: ${e.toString()}');
  }
}

Future<Map<String, dynamic>?> getCurrentClockStatus(String barberId) async {
  try {
    final response = await _supabase
        .from('clock_in_out')
        .select()
        .eq('barber_id', barberId)
        .filter('clock_out', 'is', null) // Forma correcta de verificar NULL
        .order('clock_in', ascending: false)
        .limit(1)
        .maybeSingle();

    return response;
  } catch (e) {
    debugPrint('Error al obtener el estado de la entrada: ${e.toString()}');
    throw Exception('Error al obtener el estado de la entrada: ${e.toString()}');
  }
}

Future<List<Map<String, dynamic>>> getClockHistory(String barberId, {required DateTime start_date}) async {
  try {
    final response = await _supabase
        .from('clock_in_out')
        .select('*')
        .eq('barber_id', barberId)
        .gte('clock_in', start_date.toIso8601String())
        .order('clock_in', ascending: false);

    return List<Map<String, dynamic>>.from(response);
  } catch (e) {
    debugPrint('Error al obtener historial de entradas y salidas: ${e.toString()}');
    throw Exception('Error al obtener historial de entradas y salidas: ${e.toString()}');
  }
}
  double _calculateDistance(double lat1, double lon1, double lat2, double lon2) {
    const earthRadius = 6371; // Radio de la Tierra en km
    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);
    final a = 
        sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) * cos(_degreesToRadians(lat2)) *
        sin(dLon / 2) * sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180;
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

  Future<Map<String, dynamic>> getBarberAvailability(String barberId) async {
  try {
    final startDate = DateTime.now();
    final endDate = startDate.add(const Duration(days: 60));
    
    // 1. Obtener horario del barbero
    final scheduleResponse = await _supabase
        .from('barber_schedule')
        .select('day_of_week, opens_at, closes_at, break_start, break_end')
        .eq('barber_id', barberId);

    if (scheduleResponse.isEmpty) {
      throw Exception('El barbero no tiene horario definido');
    }

    // 2. Obtener citas existentes
    final appointmentsResponse = await _supabase
        .from('appointments')
        .select('starts_at, duration')
        .eq('barber_id', barberId)
        .gte('starts_at', startDate.toIso8601String())
        .lte('starts_at', endDate.toIso8601String())
        .neq('status', 'cancelled');

    // 3. Calcular disponibilidad
    final availability = <String, dynamic>{};
    
    for (var i = 0; i <= endDate.difference(startDate).inDays; i++) {
      final currentDate = startDate.add(Duration(days: i));
      final weekday = currentDate.weekday;
      
      final daySchedule = scheduleResponse.firstWhere(
        (s) => s['day_of_week'] == weekday,
        orElse: () => {},
      );

      if (daySchedule.isEmpty) {
        availability[_formatDate(currentDate)] = {
          'demand_level': 'unavailable',
          'available_slots': 0
        };
        continue;
      }

      final opensAt = _parseTimeString(daySchedule['opens_at'].toString());
      final closesAt = _parseTimeString(daySchedule['closes_at'].toString());
      final breakStart = daySchedule['break_start'] != null 
          ? _parseTimeString(daySchedule['break_start'].toString()) : null;
      final breakEnd = daySchedule['break_end'] != null 
          ? _parseTimeString(daySchedule['break_end'].toString()) : null;

      // Calcular slots disponibles
      int availableSlots = 0;
      DateTime slotTime = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
        opensAt.hour,
        opensAt.minute,
      );

      final closingTime = DateTime(
        currentDate.year,
        currentDate.month,
        currentDate.day,
        closesAt.hour,
        closesAt.minute,
      );

      while (slotTime.add(const Duration(minutes: 30)).isBefore(closingTime)) {
        final slotEnd = slotTime.add(const Duration(minutes: 30));
        
        // Verificar si está en horario de break
        bool isDuringBreak = false;
        if (breakStart != null && breakEnd != null) {
          final breakStartTime = DateTime(
            currentDate.year,
            currentDate.month,
            currentDate.day,
            breakStart.hour,
            breakStart.minute,
          );
          final breakEndTime = DateTime(
            currentDate.year,
            currentDate.month,
            currentDate.day,
            breakEnd.hour,
            breakEnd.minute,
          );
          isDuringBreak = slotTime.isBefore(breakEndTime) && 
                          slotEnd.isAfter(breakStartTime);
        }

        // Verificar disponibilidad
        bool isAvailable = !isDuringBreak;
        for (final appt in appointmentsResponse) {
          final apptStart = DateTime.parse(appt['starts_at'].toString());
          final apptEnd = apptStart.add(Duration(minutes: appt['duration']));
          
          if (slotTime.isBefore(apptEnd) && slotEnd.isAfter(apptStart)) {
            isAvailable = false;
            break;
          }
        }

        if (isAvailable) availableSlots++;
        slotTime = slotTime.add(const Duration(minutes: 30));
      }

      // Determinar nivel de demanda
      String demandLevel;
      if (availableSlots == 0) {
        demandLevel = 'unavailable';
      } else if (availableSlots <= 3) {
        demandLevel = 'high'; // Rojo
      } else if (availableSlots <= 6) {
        demandLevel = 'medium'; // Amarillo
      } else {
        demandLevel = 'low'; // Verde
      }

      availability[_formatDate(currentDate)] = {
        'demand_level': demandLevel,
        'available_slots': availableSlots
      };
    }

    return availability;
  } catch (e) {
    debugPrint('Error en getBarberAvailability: $e');
    throw Exception('Error al obtener disponibilidad: $e');
  }
}

// Método actualizado en BusinessService
Future<bool> isSlotTaken({
  required String barberId,
  required DateTime appointmentTime,
}) async {
  try {
    final response = await _supabase
        .from('appointments')
        .select()
        .eq('barber_id', barberId)
        .eq('starts_at', appointmentTime.toIso8601String())
        .neq('status', 'cancelled')
        .maybeSingle();

    return response != null;
  } catch (e) {
    debugPrint('Error checking slot: $e');
    throw Exception('Error al verificar disponibilidad');
  }
}
}


