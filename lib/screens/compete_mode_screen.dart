import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'combine_solving_screen.dart';

class CompeteModeScreen extends StatefulWidget {
  const CompeteModeScreen({super.key});

  @override
  State<CompeteModeScreen> createState() => _CompeteModeScreenState();
}

class _CompeteModeScreenState extends State<CompeteModeScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedIcon = 'assets/player_icons/crown.png';
  String _playerId = "Loading Arena...";

  @override
  void initState() {
    super.initState();
    _generatePlayerId();
    _nameController.addListener(() {
      setState(() {});
      _savePlayerNickname();
    });
  }

  Future<void> _savePlayerNickname() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('player_nickname', _nameController.text.trim());
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generatePlayerId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load stored player nickname
      final storedName = prefs.getString('player_nickname');
      if (storedName != null && storedName.isNotEmpty) {
        _nameController.text = storedName;
      }
      
      // Load stored icon selection
      final storedIcon = prefs.getString('player_icon');
      if (storedIcon != null && storedIcon.isNotEmpty) {
        if (mounted) setState(() => _selectedIcon = storedIcon);
      }

      String? storedId = prefs.getString('player_unique_id_v2'); // New version for 6-digit ID

      if (storedId != null) {
        if (mounted) setState(() => _playerId = storedId);
        return;
      }

      // Generate a new ID based on hardware info (The modern equivalent of MAC logic)
      String seed = "";
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        seed = "${androidInfo.id}-${androidInfo.model}-${androidInfo.manufacturer}";
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        seed = iosInfo.identifierForVendor ?? "IOS-${DateTime.now().millisecondsSinceEpoch}";
      }

      // Fallback for unexpected platform/empty seed
      if (seed.isEmpty || seed.length < 5) {
        seed = "DEVICE-${DateTime.now().millisecondsSinceEpoch}";
      }

      // Create a 6-digit unique hash (Standard Logic)
      final hash = (seed.hashCode.abs() % 900000) + 100000; // Ensures exactly 6 digits (100000-999999)
      final finalId = "NQ-$hash";
      
      await prefs.setString('player_unique_id_v2', finalId);
      if (mounted) setState(() => _playerId = finalId);
    } catch (e) {
      // Final fallback to ensure the app never hangs
      final fallbackHash = (DateTime.now().millisecondsSinceEpoch % 900000) + 100000;
      if (mounted) setState(() => _playerId = "NQ-$fallbackHash");
    }
  }

  final List<String> _icons = [
    'assets/player_icons/crown.png',
    'assets/player_icons/unicorn.png',
    'assets/player_icons/dinosaur.png',
    'assets/player_icons/alien.png',
    'assets/player_icons/startup.png',
    'assets/player_icons/diamond.png',
    'assets/player_icons/torch.png',
    'assets/player_icons/pizza.png',
    'assets/player_icons/cat.png',
    'assets/player_icons/kitty.png',
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 40.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Transform.rotate(
                    angle: 0.05,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 55,
                        height: 55,
                        decoration: BoxDecoration(
                          color: const Color(0xFFE3F2FD),
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: AppColors.navyBlue, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navyBlue.withOpacity(0.3),
                              offset: const Offset(4, 4),
                            )
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_rounded, color: AppColors.navyBlue, size: 28),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildHeader(),
                  const SizedBox(height: 40),
                  _buildNameInput(),
                  const SizedBox(height: 40),
                  _buildIconSelector(),
                  const SizedBox(height: 60),
                  _buildModeSelection(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'ARENA SETUP',
          style: TextStyle(
            fontFamily: 'DynaPuff',
            fontSize: 14,
            fontWeight: FontWeight.bold,
            color: AppColors.navyBlue,
            letterSpacing: 2,
          ),
        ),
        Text(
          'Choose Your Avatar',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 32, color: AppColors.darkText),
        ),
      ],
    );
  }

  Widget _buildNameInput() {
    return Transform.rotate(
      angle: -0.01,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2),
          boxShadow: [
            BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(6, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'PLAYER NAME',
              style: TextStyle(fontFamily: 'DynaPuff', fontSize: 12, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
            ),
            TextField(
              controller: _nameController,
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 18, fontWeight: FontWeight.bold),
              decoration: const InputDecoration(
                hintText: 'Enter funky nickname...',
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey, fontWeight: FontWeight.normal),
                isDense: true,
              ),
            ),
            const Divider(color: AppColors.paperLine, thickness: 1),
            const SizedBox(height: 5),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'PLAYER ID',
                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: AppColors.secondaryText, fontWeight: FontWeight.bold),
                ),
                SelectableText(
                  _playerId,
                  style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIconSelector() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(left: 8.0, bottom: 12),
          child: Text(
            'SELECT ICON',
            style: TextStyle(fontFamily: 'DynaPuff', fontSize: 12, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
          ),
        ),
        SizedBox(
          height: 70,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _icons.length,
            itemBuilder: (context, index) {
              final icon = _icons[index];
              final isSelected = _selectedIcon == icon;
              return GestureDetector(
                onTap: () async {
                  setState(() => _selectedIcon = icon);
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('player_icon', icon);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.only(right: 15),
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: isSelected ? AppColors.gold : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(color: AppColors.navyBlue, width: isSelected ? 3 : 1.5),
                    boxShadow: isSelected ? [BoxShadow(color: AppColors.navyBlue.withOpacity(0.3), offset: const Offset(4, 4))] : null,
                  ),
                  alignment: Alignment.center,
                  child: Padding(
                    padding: const EdgeInsets.all(10.0),
                    child: Image.asset(
                      icon, 
                      fit: BoxFit.contain,
                      errorBuilder: (context, error, stackTrace) => const Icon(Icons.person_rounded, color: AppColors.navyBlue),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelection() {
    return Column(
      children: [
        _buildModeButton(
          title: 'COMBINE SOLVING',
          subtitle: 'Collaborate with a friend',
          icon: Icons.group_work_rounded,
          color: const Color(0xFFF1F8E9), // Light Green
          mode: 'combine',
          rotation: -0.015,
        ),
        const SizedBox(height: 25),
        _buildModeButton(
          title: 'COMPETING',
          subtitle: 'Battle for the crown',
          icon: Icons.bolt_rounded,
          color: const Color(0xFFFF4081), // Neon Pink
          mode: 'compete',
          rotation: 0.02,
          isDark: true,
        ),
      ],
    );
  }

  void _showNameWarningDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(25),
          side: const BorderSide(color: AppColors.navyBlue, width: 3),
        ),
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(Icons.edit_note_rounded, color: Colors.orange, size: 28),
            SizedBox(width: 10),
            Text(
              "Identity Crisis!",
              style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.navyBlue),
            ),
          ],
        ),
        content: const Text(
          "Every player needs a name written in the margins of their notebook! Please enter a funky player name to activate the solving modes.",
          style: TextStyle(fontFamily: 'Comfortaa', fontSize: 14, color: AppColors.darkText),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.navyBlue,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("GOT IT", style: TextStyle(fontFamily: 'DynaPuff')),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String mode,
    required double rotation,
    bool isDark = false,
  }) {
    final isNameEmpty = _nameController.text.trim().isEmpty;

    return Transform.rotate(
      angle: rotation,
      child: GestureDetector(
        onTap: () {
          if (isNameEmpty) {
            _showNameWarningDialog();
            return;
          }
          if (mode == 'combine') {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const CombineSolvingScreen()),
            );
          }
        },
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isNameEmpty ? 0.5 : 1.0,
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isNameEmpty ? Colors.grey[200] : color,
              borderRadius: BorderRadius.circular(25),
              border: Border.all(
                color: AppColors.navyBlue, 
                width: 3
              ),
              boxShadow: isNameEmpty 
                ? const [
                    BoxShadow(
                      color: AppColors.navyBlue, 
                      offset: Offset(2, 2)
                    ),
                  ]
                : const [
                    BoxShadow(
                      color: AppColors.navyBlue, 
                      offset: Offset(6, 6)
                    ),
                  ],
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withOpacity(0.3) : AppColors.navyBlue.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(icon, color: isDark ? Colors.white : AppColors.navyBlue, size: 30),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontFamily: 'DynaPuff',
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: isDark ? Colors.white : AppColors.navyBlue,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontFamily: 'Comfortaa',
                          fontSize: 14,
                          color: (isDark ? Colors.white : AppColors.navyBlue).withOpacity(0.8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }


}
