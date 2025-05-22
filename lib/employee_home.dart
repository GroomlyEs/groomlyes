import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'auth_service.dart';
import 'clock_in_out_screen.dart';
import 'business_service.dart';

class EmployeeHomeScreen extends StatefulWidget {
  const EmployeeHomeScreen({Key? key}) : super(key: key);

  @override
  _EmployeeHomeScreenState createState() => _EmployeeHomeScreenState();
}

class _EmployeeHomeScreenState extends State<EmployeeHomeScreen> {
  DateTime _selectedDate = DateTime.now();
  final PageController _calendarPageController = PageController(
    initialPage: DateTime.now().month - 1,
  );

  List<Map<String, dynamic>> _appointments = [];
  bool _isLoading = false;
  String? _barberId;
  int _retryCount = 0;
  static const maxRetries = 3;
  Map<String, dynamic>? _currentClockStatus;

  @override
  void initState() {
    super.initState();
    _fetchBarberId();
    _loadClockStatus();
  }

  Future<void> _loadClockStatus() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final barberId = await authService.getBarberId();
    if (barberId == null) return;

    final businessService = Provider.of<BusinessService>(context, listen: false);
    final status = await businessService.getCurrentClockStatus(barberId);
    setState(() {
      _currentClockStatus = status;
    });
  }

  Future<void> _fetchBarberId() async {
    setState(() => _isLoading = true);
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      final user = await authService.getCurrentUser();

      final response = await Supabase.instance.client
          .from('barbers')
          .select('id')
          .eq('user_id', user!.id)
          .single();

      setState(() {
        _barberId = response['id'] as String;
      });

      if (_barberId != null) {
        await _fetchAppointments();
      }
    } catch (e) {
      debugPrint('Error fetching barber ID: $e');
      if (_retryCount < maxRetries) {
        _retryCount++;
        await Future.delayed(const Duration(seconds: 2));
        await _fetchBarberId();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error loading barber information')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _fetchAppointments() async {
    if (_barberId == null) return;

    setState(() => _isLoading = true);
    try {
      final startOfDay = DateTime(_selectedDate.year, _selectedDate.month, _selectedDate.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      final response = await Supabase.instance.client
          .from('appointments')
          .select('''
            id,
            starts_at,
            service:service_id(name, duration),
            barbershop:barbershop_id(name)
          ''')
          .eq('barber_id', _barberId!)
          .gte('starts_at', startOfDay.toIso8601String())
          .lt('starts_at', endOfDay.toIso8601String())
          .order('starts_at', ascending: true);

      if (response == null || response.isEmpty) {
        setState(() => _appointments = []);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No appointments found for the selected date.')),
        );
        return;
      }

      setState(() {
        _appointments = List<Map<String, dynamic>>.from(response);
        _retryCount = 0;
      });
    } catch (e) {
      debugPrint('Error fetching appointments: $e');
      if (_retryCount < maxRetries) {
        _retryCount++;
        await Future.delayed(const Duration(seconds: 2));
        await _fetchAppointments();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load appointments: ${e.toString()}')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Employee Calendar'),
        actions: [
          IconButton(
            icon: Stack(
              children: [
                const Icon(Icons.timer),
                if (_currentClockStatus != null)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      constraints: const BoxConstraints(
                        minWidth: 12,
                        minHeight: 12,
                      ),
                    ),
                  ),
              ],
            ),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ClockInOutScreen(),
                ),
              ).then((_) => _loadClockStatus());
            },
          ),
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () {
              setState(() {
                _selectedDate = DateTime.now();
                _calendarPageController.jumpToPage(
                  DateTime.now().month - 1,
                );
                _fetchAppointments();
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                _buildCalendarHeader(),
                _buildCalendarView(),
                _buildAppointmentsList(),
              ],
            ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildCalendarHeader() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            DateFormat('MMMM yyyy').format(_selectedDate),
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                onPressed: () => _calendarPageController.previousPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                onPressed: () => _calendarPageController.nextPage(
                  duration: const Duration(milliseconds: 300),
                  curve: Curves.easeInOut,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarView() {
    return SizedBox(
      height: 240,
      child: PageView.builder(
        controller: _calendarPageController,
        onPageChanged: (monthIndex) {
          final year = _selectedDate.year;
          final newMonth = monthIndex + 1;
          setState(() {
            _selectedDate = DateTime(
              year,
              newMonth,
              _selectedDate.day > DateTime(year, newMonth + 1, 0).day
                  ? DateTime(year, newMonth + 1, 0).day
                  : _selectedDate.day,
            );
            _fetchAppointments();
          });
        },
        itemBuilder: (context, monthIndex) {
          final year = _selectedDate.year;
          final month = monthIndex + 1;
          return _buildMonthCalendar(year, month);
        },
      ),
    );
  }

  Widget _buildMonthCalendar(int year, int month) {
    final firstDay = DateTime(year, month, 1);
    final lastDay = DateTime(year, month + 1, 0);
    final daysInMonth = lastDay.day;
    final startingWeekday = firstDay.weekday;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Text('S', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('M', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('T', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('W', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('T', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('F', style: TextStyle(fontWeight: FontWeight.bold)),
              Text('S', style: TextStyle(fontWeight: FontWeight.bold)),
            ],
          ),
          const SizedBox(height: 8),
          Expanded(
            child: GridView.builder(
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1,
              ),
              itemCount: daysInMonth + startingWeekday - 1,
              itemBuilder: (context, index) {
                if (index < startingWeekday - 1) return Container();

                final day = index - startingWeekday + 2;
                final currentDate = DateTime(year, month, day);
                final isSelected = _selectedDate.year == year &&
                    _selectedDate.month == month &&
                    _selectedDate.day == day;
                final hasAppointments = _appointments.any((appt) {
                  final apptDate = DateTime.parse(appt['starts_at'] as String);
                  return apptDate.year == year && 
                         apptDate.month == month && 
                         apptDate.day == day;
                });

                return GestureDetector(
                  onTap: () => setState(() {
                    _selectedDate = currentDate;
                    _fetchAppointments();
                  }),
                  child: Container(
                    margin: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: isSelected ? const Color(0xFF143E40) : null,
                      shape: BoxShape.circle,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            color: isSelected ? Colors.white : Colors.black,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (hasAppointments)
                          Container(
                            width: 6,
                            height: 6,
                            margin: const EdgeInsets.only(top: 2),
                            decoration: const BoxDecoration(
                              color: Colors.red,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppointmentsList() {
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              DateFormat('EEEE, MMMM d').format(_selectedDate),
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            if (_appointments.isEmpty)
              const Center(child: Text('No appointments for this day'))
            else
              Expanded(
                child: ListView.builder(
                  itemCount: _appointments.length,
                  itemBuilder: (context, index) {
                    final appointment = _appointments[index];
                    return _buildAppointmentCard(appointment);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

Widget _buildAppointmentCard(Map<String, dynamic> appointment) {
  final startsAt = DateTime.parse(appointment['starts_at'] as String);
  final time = DateFormat('h:mm a').format(startsAt);

  // Acceso más robusto a los datos anidados
  final service = appointment['service'] ?? appointment['service_id'];
  final barbershop = appointment['barbershop'] ?? appointment['barbershop_id'];

  final serviceName = service?['name']?.toString() ?? 'Unknown Service';
  final barbershopName = barbershop?['name']?.toString() ?? 'Unknown Barbershop';
  
  final duration = service?['duration'] != null
      ? '${service['duration']} min'
      : '';

  return Card(
    margin: const EdgeInsets.only(bottom: 12),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Container(
            width: 60,
            alignment: Alignment.center,
            child: Text(
              time,
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(serviceName, style: const TextStyle(fontWeight: FontWeight.bold)),
                Text(barbershopName),
              ],
            ),
          ),
          if (duration.isNotEmpty)
            Text(duration, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    ),
  );
}

  Widget _buildBottomNavigationBar() {
    return BottomNavigationBar(
      currentIndex: 0,
      type: BottomNavigationBarType.fixed,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.calendar_today),
          label: 'Calendar',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.access_time),
          label: 'Schedule',
        ),
        BottomNavigationBarItem(
          icon: Icon(Icons.settings),
          label: 'Settings',
        ),
      ],
      onTap: (index) {
        switch (index) {
          case 0:
            break;
          case 1:
            break;
          case 2:
            Navigator.pushNamed(context, '/account');
            break;
        }
      },
    );
  }
}