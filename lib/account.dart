import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:image_picker/image_picker.dart';
import 'dart:io';
import 'auth_service.dart';

class AccountSettingsScreen extends StatefulWidget {
  const AccountSettingsScreen({Key? key}) : super(key: key);

  @override
  _AccountSettingsScreenState createState() => _AccountSettingsScreenState();
}

class _AccountSettingsScreenState extends State<AccountSettingsScreen> {
  User? _currentUser;
  bool _isLoading = true;
  File? _selectedImage;
  
  // Controladores para formularios
  final _passwordController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  
  // Claves para formularios
  final _passwordFormKey = GlobalKey<FormState>();
  final _nameFormKey = GlobalKey<FormState>();
  final _emailFormKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  @override
  void dispose() {
    _passwordController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    _nameController.dispose();
    _emailController.dispose();
    super.dispose();
  }

  Future<void> _loadUserData() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    final user = await authService.getCurrentUser();
    
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isLoading = false;
        // Inicializar controladores con datos del usuario
        _nameController.text = '${_currentUser?.userMetadata?['first_name'] ?? ''} ${_currentUser?.userMetadata?['last_name'] ?? ''}'.trim();
        _emailController.text = _currentUser?.email ?? '';
      });
    }
  }

  Future<void> _logout(BuildContext context) async {
    try {
      final authService = Provider.of<AuthService>(context, listen: false);
      await authService.signOut();
      
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('rememberMe');
      
      Navigator.pushNamedAndRemoveUntil(
        context, 
        '/login', 
        (route) => false
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error al cerrar sesión: ${e.toString()}'))
      );
    }
  }

  Future<void> _changeProfilePicture() async {
    final picker = ImagePicker();
    try {
      final pickedFile = await picker.pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _selectedImage = File(pickedFile.path);
        });
        
        // Upload to Supabase Storage
        final supabase = Supabase.instance.client;
        final userId = _currentUser?.id ?? '';
        final fileExtension = pickedFile.path.split('.').last;
        final fileName = 'profile_$userId.${fileExtension}';
        
        // Upload file
        final fileBytes = await _selectedImage!.readAsBytes();
        await supabase.storage
          .from('avatars')
          .uploadBinary(fileName, fileBytes, fileOptions: FileOptions(
            contentType: 'image/$fileExtension',
            upsert: true,
          ));

        // uploadBinary throws on error, so no need to check for error property
        
        // Get public URL
        final imageUrlResponse = supabase.storage
          .from('avatars')
          .getPublicUrl(fileName);
        
        // Update user metadata
        final updateResponse = await supabase.auth.updateUser(
          UserAttributes(
            data: {'avatar_url': imageUrlResponse},
          ),
        );
        
        if (updateResponse.user == null) {
          throw Exception('Failed to update user profile');
        }
        
        // Update local state
        setState(() {
          _currentUser = updateResponse.user;
        });
        
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Foto de perfil actualizada correctamente'))
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error al cambiar la foto: ${e.toString()}'))
        );
      }
    }
  }

  Future<void> _showChangePasswordDialog() async {
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Cambiar contraseña',
            style: GoogleFonts.poppins(
              color: const Color(0xFF143E40),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Form(
            key: _passwordFormKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Contraseña actual',
                      labelStyle: GoogleFonts.poppins(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingrese su contraseña actual';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _newPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Nueva contraseña',
                      labelStyle: GoogleFonts.poppins(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingrese una nueva contraseña';
                      }
                      if (value.length < 8) {
                        return 'La contraseña debe tener al menos 8 caracteres';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _confirmPasswordController,
                    obscureText: true,
                    decoration: InputDecoration(
                      labelText: 'Confirmar nueva contraseña',
                      labelStyle: GoogleFonts.poppins(),
                    ),
                    validator: (value) {
                      if (value != _newPasswordController.text) {
                        return 'Las contraseñas no coinciden';
                      }
                      return null;
                    },
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancelar',
                style: GoogleFonts.poppins(
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_passwordFormKey.currentState!.validate()) {
                  try {
                    final supabase = Supabase.instance.client;
                    final response = await supabase.auth.updateUser(
                      UserAttributes(
                        password: _newPasswordController.text,
                      ),
                    );
                    
                    if (response.user != null) {
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Contraseña cambiada correctamente'))
                        );
                        // Limpiar campos después de éxito
                        _passwordController.clear();
                        _newPasswordController.clear();
                        _confirmPasswordController.clear();
                      }
                    } else {
                      throw Exception('Failed to update password');
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al cambiar la contraseña: ${e.toString()}'))
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF143E40),
              ),
              child: Text(
                'Guardar',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

Future<void> _showChangeNameDialog() async {
  // Pre-cargar el nombre actual si existe
  final currentName = _currentUser?.userMetadata?['first_name'] != null ||
          _currentUser?.userMetadata?['last_name'] != null
      ? '${_currentUser?.userMetadata?['first_name'] ?? ''} ${_currentUser?.userMetadata?['last_name'] ?? ''}'
      : '';
  _nameController.text = currentName.trim();

  return showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          'Cambiar nombre',
          style: GoogleFonts.poppins(
            color: const Color(0xFF143E40),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: _nameFormKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: 'Nombre completo',
                    labelStyle: GoogleFonts.poppins(),
                    hintText: 'Ej: Juan Pérez',
                  ),
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Por favor ingrese su nombre';
                    }
                    return null;
                  },
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Cancelar',
              style: GoogleFonts.poppins(
                color: Colors.grey,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              if (_nameFormKey.currentState!.validate()) {
                try {
                  final supabase = Supabase.instance.client;

                  // Separar nombre y apellido (simple)
                  final names = _nameController.text.trim().split(' ');
                  final firstName = names.isNotEmpty ? names.first : '';
                  final lastName = names.length > 1 ? names.sublist(1).join(' ') : '';

                  // Actualizar en Auth
                  final authResponse = await supabase.auth.updateUser(
                    UserAttributes(
                      data: {
                        'first_name': firstName,
                        'last_name': lastName,
                        'full_name': _nameController.text.trim(),
                      },
                    ),
                  );

                  if (authResponse.user != null) {
                    // Actualizar o insertar en user_profiles (upsert)
                    final userId = authResponse.user!.id;
                    await supabase
                        .from('user_profiles')
                        .upsert({
                          'user_id': userId,
                          'first_name': firstName,
                          'last_name': lastName,
                          'updated_at': DateTime.now().toIso8601String(),
                        }, onConflict: 'user_id');

                    if (mounted) {
                      Navigator.pop(context);
                      setState(() {
                        _currentUser = authResponse.user;
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Nombre actualizado correctamente'))
                      );
                    }
                  } else {
                    throw Exception('Error al actualizar el usuario');
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Error al cambiar el nombre: ${e.toString()}'))
                    );
                  }
                }
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF143E40),
            ),
            child: Text(
              'Guardar',
              style: GoogleFonts.poppins(
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    },
  );
}

  Future<void> _showChangeEmailDialog() async {
    _emailController.text = _currentUser?.email ?? '';

    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
            'Cambiar correo electrónico',
            style: GoogleFonts.poppins(
              color: const Color(0xFF143E40),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Form(
            key: _emailFormKey,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      labelText: 'Nuevo correo electrónico',
                      labelStyle: GoogleFonts.poppins(),
                      hintText: 'Ej: usuario@ejemplo.com',
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Por favor ingrese su correo electrónico';
                      }
                      if (!RegExp(r'^[\w-\.]+@([\w-]+\.)+[\w-]{2,4}$').hasMatch(value)) {
                        return 'Ingrese un correo electrónico válido';
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Se enviará un enlace de confirmación a tu nuevo correo electrónico.',
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: Colors.grey[600],
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                'Cancelar',
                style: GoogleFonts.poppins(
                  color: Colors.grey,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                if (_emailFormKey.currentState!.validate()) {
                  try {
                    final supabase = Supabase.instance.client;
                    final response = await supabase.auth.updateUser(
                      UserAttributes(
                        email: _emailController.text,
                      ),
                    );
                    
                    if (response.user != null) {
                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Se ha enviado un enlace de confirmación a tu nuevo correo electrónico'))
                        );
                      }
                    } else {
                      throw Exception('Failed to update email');
                    }
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Error al cambiar el correo: ${e.toString()}'))
                      );
                    }
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF143E40),
              ),
              child: Text(
                'Enviar',
                style: GoogleFonts.poppins(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final userName = (_currentUser?.userMetadata?['first_name'] ?? '') +
        (_currentUser?.userMetadata?['last_name'] != null
            ? ' ${_currentUser?.userMetadata?['last_name']}'
            : '');

    final displayName = userName.trim().isNotEmpty ? userName.trim() : 'Usuario';
    final userEmail = _currentUser?.email ?? '';
    final userPhoto = _currentUser?.userMetadata?['avatar_url'] as String?;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text(
          'Mi Cuenta',
          style: GoogleFonts.poppins(
            color: const Color(0xFF143E40),
            fontWeight: FontWeight.bold,
            fontSize: 20,
          ),
        ),
        centerTitle: true,
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Color(0xFF143E40)),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _changeProfilePicture,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 40,
                          backgroundColor: const Color(0xFF143E40).withOpacity(0.1),
                          backgroundImage: _selectedImage != null
                              ? FileImage(_selectedImage!)
                              : userPhoto != null 
                                  ? NetworkImage(userPhoto) 
                                  : null,
                          child: _selectedImage == null && userPhoto == null
                              ? Icon(Icons.person, size: 40, color: const Color(0xFF143E40))
                              : null,
                        ),
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: BoxDecoration(
                              color: const Color(0xFF143E40),
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.edit,
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: const Color(0xFF143E40),
                    ),
                  ),
                  if (userEmail.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      userEmail,
                      style: GoogleFonts.poppins(
                        color: Colors.grey[600],
                        fontSize: 14,
                      ),
                    ),
                  ],
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  _buildSettingItem(
                    icon: Icons.person,
                    title: 'Cambiar nombre',
                    onTap: _showChangeNameDialog,
                  ),
                  _buildSettingItem(
                    icon: Icons.email,
                    title: 'Cambiar correo electrónico',
                    onTap: _showChangeEmailDialog,
                  ),
                  _buildSettingItem(
                    icon: Icons.lock,
                    title: 'Cambiar contraseña',
                    onTap: _showChangePasswordDialog,
                  ),
                  _buildSettingItem(
                    icon: Icons.fingerprint,
                    title: 'Touch ID / Face ID',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Funcionalidad en desarrollo'))
                      );
                    },
                  ),
                  _buildSettingItem(
                    icon: Icons.language,
                    title: 'Idioma',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Funcionalidad en desarrollo'))
                      );
                    },
                  ),
                  _buildSettingItem(
                    icon: Icons.notifications,
                    title: 'Notificaciones',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Funcionalidad en desarrollo'))
                      );
                    },
                  ),
                  _buildSettingItem(
                    icon: Icons.help,
                    title: 'Ayuda y soporte',
                    subtitle: 'Centro de ayuda y preguntas frecuentes',
                    onTap: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Funcionalidad en desarrollo'))
                      );
                    },
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: ElevatedButton.icon(
                      icon: const Icon(Icons.logout, color: Colors.white),
                      label: Text(
                        'Cerrar sesión',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF143E40),
                        foregroundColor: Colors.white,
                        minimumSize: const Size(double.infinity, 50),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      onPressed: () => _logout(context),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingItem({
    required IconData icon,
    required String title,
    String? subtitle,
    required VoidCallback onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF143E40).withOpacity(0.1),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: const Color(0xFF143E40), size: 22),
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          fontWeight: FontWeight.w500,
          fontSize: 16,
          color: Colors.black87,
        ),
      ),
      subtitle: subtitle != null
          ? Text(
              subtitle,
              style: GoogleFonts.poppins(
                color: Colors.grey[600],
                fontSize: 12,
              ),
            )
          : null,
      trailing: const Icon(Icons.chevron_right, color: Colors.grey, size: 20),
      onTap: onTap,
    );
  }
}