import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import '../utils/storage_manager.dart';
import '../utils/board_processor.dart';
import '../constants/region_colors.dart';
import '../utils/board_generator.dart';

class CombineSolvingScreen extends StatefulWidget {
  const CombineSolvingScreen({super.key});

  @override
  State<CombineSolvingScreen> createState() => _CombineSolvingScreenState();
}

class _CombineSolvingScreenState extends State<CombineSolvingScreen> {
  final TextEditingController _opponentIdController = TextEditingController();
  
  // Selection states
  String? _selectedColor; // 'blue' or 'red'
  String _boardSource = 'auto'; // 'auto' or 'library'
  int _selectedSize = 8; // Default 8x8 size
  
  List<Map<String, dynamic>> _masteredBoards = [];
  Map<String, dynamic>? _selectedLibraryBoard;
  bool _isLoadingLibrary = false;
  
  int _matchCount = 3; // Default best of 3

  @override
  void initState() {
    super.initState();
    _loadMasteredBoards();
  }

  @override
  void dispose() {
    _opponentIdController.dispose();
    super.dispose();
  }

  Future<void> _loadMasteredBoards() async {
    setState(() => _isLoadingLibrary = true);
    try {
      final allBoards = await StorageManager.loadBoards();
      // Filter only those boards that have been manually solved (Mastered)
      final mastered = allBoards.where((b) {
        final data = b['board'] as BoardData;
        return data.isManuallySolved;
      }).toList();

      setState(() {
        _masteredBoards = mastered;
        if (_masteredBoards.isNotEmpty) {
          _selectedLibraryBoard = _masteredBoards.first;
        }
      });
    } catch (e) {
      debugPrint("Error loading mastered boards: $e");
    } finally {
      setState(() => _isLoadingLibrary = false);
    }
  }

  void _startCombineSolving() {
    final opponentId = _opponentIdController.text.trim();
    if (opponentId.isEmpty) {
      _showWarningDialog("Who are we fighting?", "Type your opponent's 6-digit Player ID to invite them to the solve session!");
      return;
    }
    if (opponentId.length < 4) {
      _showWarningDialog("Short ID", "Please enter a valid opponent Player ID!");
      return;
    }
    if (_selectedColor == null) {
      _showWarningDialog("Pick Your Colors!", "Select either Red or Blue to represent your side of the notebook!");
      return;
    }
    if (_boardSource == 'library' && _selectedLibraryBoard == null) {
      _showWarningDialog("Empty Library", "You must select a mastered board from your library or choose another board source.");
      return;
    }

    // Prepare battle parameters
    final Map<String, dynamic> sessionDetails = {
      'opponentId': opponentId,
      'playerColor': _selectedColor,
      'boardSource': _boardSource,
      'boardSize': _boardSource == 'auto' 
          ? '$_selectedSize x $_selectedSize' 
          : (_boardSource == 'library' ? (_selectedLibraryBoard!['board'] as BoardData).size : 'Auto Select'),
      'selectedLibraryBoardId': _boardSource == 'library' ? _selectedLibraryBoard!['id'] : null,
      'matchCount': _matchCount,
    };

    // Show a funky co-op initiation popup
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
            Icon(Icons.wifi_tethering_rounded, color: AppColors.navyBlue, size: 28),
            SizedBox(width: 10),
            Text(
              "Initiating Solving!",
              style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 20, color: AppColors.navyBlue),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Inviting Player: ID-$opponentId",
              style: const TextStyle(fontFamily: 'Comfortaa', fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.navyBlue),
            ),
            const SizedBox(height: 10),
            Text(
              "You are playing as: ${_selectedColor!.toUpperCase()}",
              style: TextStyle(
                fontFamily: 'Comfortaa', 
                fontWeight: FontWeight.bold, 
                fontSize: 14, 
                color: _selectedColor == 'blue' ? Colors.blue : Colors.red
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Configuration: ${_boardSource == 'auto' ? 'Auto Generated $_selectedSize x $_selectedSize' : 'Mastered Board: \"${_selectedLibraryBoard!['name']}\"'}",
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.darkText),
            ),
            const SizedBox(height: 10),
            Text(
              "Match Mode: Best of $_matchCount Matches",
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.secondaryText),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("CANCEL", style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.secondaryText)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              
              // If Auto Generate is selected, generate the board using board_generator logic!
              BoardData? generatedBoard;
              if (_boardSource == 'auto') {
                // Show a funky progress loader
                showDialog(
                  context: context,
                  barrierDismissible: false,
                  builder: (context) => AlertDialog(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: AppColors.navyBlue, width: 3),
                    ),
                    backgroundColor: Colors.white,
                    content: const Row(
                      children: [
                        CircularProgressIndicator(color: AppColors.navyBlue),
                        SizedBox(width: 20),
                        Expanded(
                          child: Text(
                            "Weaving solvable board grids...",
                            style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
                
                try {
                  generatedBoard = await BoardGenerator.generateUniqueBoard(_selectedSize);
                } catch (e) {
                  debugPrint("Error generating board: $e");
                } finally {
                  if (context.mounted) {
                    Navigator.pop(context); // close loader dialog
                  }
                }
              }

              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    backgroundColor: AppColors.navyBlue,
                    content: Text(
                      _boardSource == 'auto'
                          ? (generatedBoard != null 
                              ? "Solvable ${_selectedSize}x${_selectedSize} Board Generated! Connecting to NQ-$opponentId..." 
                              : "Generated solvable board! Connecting to NQ-$opponentId...")
                          : "Connecting to NQ-$opponentId... Room synchronized!",
                      style: const TextStyle(fontFamily: 'Comfortaa', fontWeight: FontWeight.bold),
                    ),
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.gold,
              foregroundColor: AppColors.navyBlue,
              side: const BorderSide(color: AppColors.navyBlue, width: 2),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            child: const Text("LET'S GO", style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _showWarningDialog(String title, String message) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: AppColors.navyBlue, width: 3),
        ),
        backgroundColor: Colors.white,
        title: Text(
          title,
          style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, color: Colors.redAccent),
        ),
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 14, color: AppColors.darkText),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Classic Notebook Lines Background
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 30.0),
              physics: const BouncingScrollPhysics(),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Back button sticker
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
                            )
                          ],
                        ),
                        child: const Icon(Icons.arrow_back_ios_new_rounded, color: AppColors.navyBlue, size: 20),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),

                  // Header
                  _buildHeader(),
                  const SizedBox(height: 30),

                  // Card 1: Opponent ID
                  _buildOpponentInputCard(),
                  const SizedBox(height: 25),

                  // Card 2: Color Picker
                  _buildColorSelectorCard(),
                  const SizedBox(height: 25),

                  // Card 3: Board Choice
                  _buildBoardSelectorCard(),
                  const SizedBox(height: 25),

                  // Card 4: Match Count
                  _buildMatchCountCard(),
                  const SizedBox(height: 40),

                  // Start Battle!
                  _buildSubmitButton(),
                  const SizedBox(height: 50),
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
          'MULTIPLAYER ARENA',
          style: TextStyle(
            fontFamily: 'DynaPuff',
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: AppColors.navyBlue,
            letterSpacing: 2,
          ),
        ),
        Text(
          'Combine Solving',
          style: Theme.of(context).textTheme.displayLarge?.copyWith(
            fontSize: 32, 
            color: AppColors.darkText,
            fontFamily: 'PlaywriteUSModern',
          ),
        ),
      ],
    );
  }

  Widget _buildOpponentInputCard() {
    return Transform.rotate(
      angle: 0.008,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2.5),
          boxShadow: [
            BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(6, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.person_search_rounded, color: AppColors.navyBlue, size: 20),
                SizedBox(width: 8),
                Text(
                  'OPPONENT PLAYER ID',
                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 13, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _opponentIdController,
              keyboardType: TextInputType.number,
              maxLength: 6,
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 18, fontWeight: FontWeight.bold, letterSpacing: 2),
              decoration: const InputDecoration(
                hintText: 'Enter 6-digit ID...',
                counterText: "",
                border: InputBorder.none,
                hintStyle: TextStyle(color: Colors.grey, fontWeight: FontWeight.normal, letterSpacing: 1),
                isDense: true,
              ),
            ),
            const Divider(color: AppColors.paperLine, thickness: 2),
            const SizedBox(height: 5),
            const Text(
              "Type in your partner's game lobby key to link screens for simultaneous solving.",
              style: TextStyle(fontFamily: 'Comfortaa', fontSize: 11, color: AppColors.secondaryText),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorSelectorCard() {
    return Transform.rotate(
      angle: -0.008,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2.5),
          boxShadow: [
            BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(6, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.palette_rounded, color: AppColors.navyBlue, size: 20),
                SizedBox(width: 8),
                Text(
                  'YOUR SIDE COLOR',
                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 13, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              children: [
                // Blue option
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedColor = 'blue'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: _selectedColor == 'blue' ? const Color(0xFF00E5FF) : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: AppColors.navyBlue, 
                          width: _selectedColor == 'blue' ? 3.0 : 1.5
                        ),
                        boxShadow: _selectedColor == 'blue' 
                            ? [const BoxShadow(color: AppColors.navyBlue, offset: Offset(4, 4))] 
                            : null,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 28,
                            color: _selectedColor == 'blue' ? Colors.white : const Color(0xFF00E5FF),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "BLUE",
                            style: TextStyle(
                              fontFamily: 'DynaPuff',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _selectedColor == 'blue' ? Colors.white : AppColors.navyBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 15),
                // Red option
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedColor = 'red'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: _selectedColor == 'red' ? const Color(0xFFFF1744) : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: AppColors.navyBlue, 
                          width: _selectedColor == 'red' ? 3.0 : 1.5
                        ),
                        boxShadow: _selectedColor == 'red' 
                            ? [const BoxShadow(color: AppColors.navyBlue, offset: Offset(4, 4))] 
                            : null,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 28,
                            color: _selectedColor == 'red' ? Colors.white : const Color(0xFFFF1744),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            "RED",
                            style: TextStyle(
                              fontFamily: 'DynaPuff',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _selectedColor == 'red' ? Colors.white : AppColors.navyBlue,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBoardSelectorCard() {
    return Transform.rotate(
      angle: 0.005,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2.5),
          boxShadow: [
            BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(6, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.dashboard_rounded, color: AppColors.navyBlue, size: 20),
                SizedBox(width: 8),
                Text(
                  'CHOOSE PUZZLE BOARD',
                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 13, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 15),

            // Tab bar options (Auto Generate and My Library)
            Container(
              decoration: BoxDecoration(
                color: AppColors.paperLine.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.navyBlue, width: 1.5),
              ),
              child: Row(
                children: [
                  _buildSourceTab('auto', 'Auto Generate'),
                  _buildSourceTab('library', 'My Library'),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // Source option display
            _buildSourceConfigurator(),
          ],
        ),
      ),
    );
  }

  Widget _buildSourceTab(String key, String label) {
    final isSelected = _boardSource == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _boardSource = key),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.navyBlue : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'DynaPuff',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.white : AppColors.navyBlue,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourceConfigurator() {
    if (_boardSource == 'auto') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: const Color(0xFFF1F8E9),
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.navyBlue, width: 1.5),
            ),
            child: const Row(
              children: [
                Icon(Icons.auto_awesome, color: AppColors.navyBlue, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    "We will generate a guaranteed solvable region board of your chosen size using a randomized BFS seed-growth algorithm.",
                    style: TextStyle(fontFamily: 'Comfortaa', fontSize: 12, color: AppColors.navyBlue, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          // Board Size option under Auto Generate
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(15),
              border: Border.all(color: AppColors.paperLine, width: 2),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.grid_on_rounded, size: 18, color: AppColors.navyBlue),
                        SizedBox(width: 8),
                        Text(
                          "BOARD SIZE",
                          style: TextStyle(fontFamily: 'DynaPuff', fontSize: 12, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Text(
                      "${_selectedSize}x${_selectedSize}",
                      style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 14, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 15),
                const Divider(color: AppColors.paperLine, thickness: 1),
                const SizedBox(height: 5),
                const Text(
                  "CHOOSE FIXED GENERATED SIZE",
                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: AppColors.secondaryText),
                ),
                const SizedBox(height: 5),
                SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: AppColors.navyBlue,
                    inactiveTrackColor: AppColors.paperLine,
                    thumbColor: AppColors.gold,
                    overlayColor: AppColors.gold.withOpacity(0.2),
                    valueIndicatorColor: AppColors.navyBlue,
                    valueIndicatorTextStyle: const TextStyle(fontFamily: 'DynaPuff'),
                  ),
                  child: Slider(
                    value: _selectedSize.toDouble(),
                    min: 4,
                    max: 12,
                    divisions: 8,
                    label: "${_selectedSize}x${_selectedSize}",
                    onChanged: (val) => setState(() => _selectedSize = val.toInt()),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      // Library mode
      if (_isLoadingLibrary) {
        return const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 20.0),
            child: CircularProgressIndicator(color: AppColors.navyBlue),
          ),
        );
      }

      if (_masteredBoards.isEmpty) {
        return Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3E0),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: Colors.orange, width: 1.5),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.lock_rounded, color: Colors.orange, size: 24),
                  SizedBox(width: 10),
                  Text("LOCKED OPTION", style: TextStyle(fontFamily: 'DynaPuff', fontSize: 13, color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
              SizedBox(height: 8),
              Text(
                "You don't have any Mastered boards in your library. Solve a puzzle manually on the board editor to receive a trophy and unlock it here!",
                style: TextStyle(fontFamily: 'Comfortaa', fontSize: 11, color: AppColors.darkText, height: 1.4),
              ),
            ],
          ),
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("SELECT A MASTERED BOARD", style: TextStyle(fontFamily: 'DynaPuff', fontSize: 11, color: AppColors.secondaryText)),
          const SizedBox(height: 10),
          Container(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _masteredBoards.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final boardMap = _masteredBoards[index];
                final board = boardMap['board'] as BoardData;
                final isSelected = _selectedLibraryBoard?['id'] == boardMap['id'];

                return GestureDetector(
                  onTap: () => setState(() => _selectedLibraryBoard = boardMap),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    margin: const EdgeInsets.only(right: 12, bottom: 8),
                    padding: const EdgeInsets.all(12),
                    width: 140,
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.gold : Colors.white,
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                        color: AppColors.navyBlue, 
                        width: isSelected ? 2.5 : 1.2
                      ),
                      boxShadow: isSelected 
                          ? [const BoxShadow(color: AppColors.navyBlue, offset: Offset(3, 3))]
                          : null,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          boardMap['name'] ?? 'Unnamed',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 12, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${board.size}x${board.size}",
                              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 11, color: AppColors.secondaryText, fontWeight: FontWeight.bold),
                            ),
                            const Icon(Icons.emoji_events_rounded, color: Colors.orange, size: 16),
                          ],
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      );
    }
  }

  Widget _buildMatchCountCard() {
    return Transform.rotate(
      angle: -0.005,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2.5),
          boxShadow: [
            BoxShadow(color: AppColors.navyBlue.withOpacity(0.15), offset: const Offset(6, 6)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.emoji_events_outlined, color: AppColors.navyBlue, size: 20),
                SizedBox(width: 8),
                Text(
                  'HOW MANY MATCHES?',
                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 13, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 15),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildMatchSelector(1, "1 Match"),
                _buildMatchSelector(3, "Best of 3"),
                _buildMatchSelector(5, "Best of 5"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMatchSelector(int count, String label) {
    final isSelected = _matchCount == count;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _matchCount = count),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? AppColors.gold : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.navyBlue, 
              width: isSelected ? 2.5 : 1.2
            ),
            boxShadow: isSelected 
                ? [const BoxShadow(color: AppColors.navyBlue, offset: Offset(3, 3))] 
                : null,
          ),
          alignment: Alignment.center,
          child: Text(
            label,
            style: TextStyle(
              fontFamily: 'DynaPuff',
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: AppColors.navyBlue,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSubmitButton() {
    return Transform.rotate(
      angle: -0.02,
      child: GestureDetector(
        onTap: _startCombineSolving,
        child: Container(
          width: double.infinity,
          height: 75,
          decoration: BoxDecoration(
            color: const Color(0xFFF1F8E9), // Fresh Mint
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppColors.navyBlue, width: 3.5),
            boxShadow: const [
              BoxShadow(color: AppColors.navyBlue, offset: Offset(8, 8)),
            ],
          ),
          child: const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.wifi_rounded, size: 30, color: AppColors.navyBlue),
              SizedBox(width: 15),
              Text(
                'INITIATE SESSION',
                style: TextStyle(
                  fontFamily: 'DynaPuff', 
                  fontWeight: FontWeight.bold, 
                  fontSize: 22, 
                  color: AppColors.navyBlue,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
