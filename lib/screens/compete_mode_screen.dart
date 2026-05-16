import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';

class CompeteModeScreen extends StatefulWidget {
  const CompeteModeScreen({super.key});

  @override
  State<CompeteModeScreen> createState() => _CompeteModeScreenState();
}

class _CompeteModeScreenState extends State<CompeteModeScreen> {
  final TextEditingController _nameController = TextEditingController();
  String _selectedIcon = 'assets/player_icons/crown.png';
  String _playerId = "GEN-0000-0000-0000";

  @override
  void initState() {
    super.initState();
    _generatePlayerId();
  }

  void _generatePlayerId() {
    // Standard-Logic mock for Permanent MAC Address based ID
    // In actual implementation, we would use a package like device_info_plus or get_mac_address
    const mockMac = "A1:B2:C3:D4:E5:F6"; 
    final hash = mockMac.hashCode.abs().toString().padLeft(8, '0');
    setState(() {
      _playerId = "ID-${hash.substring(0, 4)}-${hash.substring(4, 8)}";
    });
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
                    angle: -0.05,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.navyBlue, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navyBlue.withOpacity(0.2),
                              offset: const Offset(4, 4),
                              blurRadius: 0,
                            )
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navyBlue, size: 20),
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
                onTap: () => setState(() => _selectedIcon = icon),
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

  Widget _buildModeButton({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required String mode,
    required double rotation,
    bool isDark = false,
  }) {
    return Transform.rotate(
      angle: rotation,
      child: GestureDetector(
        onTap: () {
          // Placeholder navigation
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Joining $title... 🚀', style: const TextStyle(fontFamily: 'DynaPuff')),
              backgroundColor: isDark ? color : AppColors.navyBlue,
              behavior: SnackBarBehavior.floating,
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(25),
            border: Border.all(
              color: AppColors.navyBlue, 
              width: 3
            ),
            boxShadow: const [
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
                  color: Colors.white.withOpacity(0.3),
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
    );
  }


}
