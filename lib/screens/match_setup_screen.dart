import 'package:flutter/material.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants/colors.dart';
import '../widgets/notebook_painter.dart';
import '../utils/storage_manager.dart';
import '../utils/board_processor.dart';
import '../utils/board_generator.dart';
import '../widgets/funky_loader_dialog.dart';
import '../widgets/funky_lobby_details_dialog.dart';
import 'peers_play_screen.dart';
import '../utils/firebase_game_manager.dart';

class MatchSetupScreen extends StatefulWidget {
  final bool isCompeteMode;

  const MatchSetupScreen({super.key, required this.isCompeteMode});

  @override
  State<MatchSetupScreen> createState() => _MatchSetupScreenState();
}

class _MatchSetupScreenState extends State<MatchSetupScreen> {
  final TextEditingController _opponentIdController = TextEditingController();
  
  // Selection states
  String? _selectedColor; // 'blue' or 'red'
  
  // Per-match Board Configurations (up to 5 matches supported)
  final List<String> _boardSources = List.generate(5, (_) => 'auto');
  final List<int> _selectedSizes = List.generate(5, (_) => 8);
  final List<Map<String, dynamic>?> _selectedLibraryBoards = List.generate(5, (_) => null);
  
  int _currentEditingMatchIndex = 0; // Index of match currently being configured
  
  List<Map<String, dynamic>> _masteredBoards = [];
  bool _isLoadingLibrary = false;
  
  int _matchCount = 3; // Default best of 3
  bool _isConnecting = false;

  List<Map<String, String>> _recentOpponents = [];

  @override
  void initState() {
    super.initState();
    _loadMasteredBoards();
    _loadRecentOpponents();
    // In Compete Mode, Library is forbidden, so force auto-generate configuration
    if (widget.isCompeteMode) {
      for (int i = 0; i < 5; i++) {
        _boardSources[i] = 'auto';
      }
    }
    // Start mailbox polling dynamically when entering match setup screen
    FirebaseGameManager.instance.startMailboxPolling();
  }

  @override
  void dispose() {
    _opponentIdController.dispose();
    // Stop mailbox polling when user leaves match setup screen
    FirebaseGameManager.instance.stopMailboxPolling();
    super.dispose();
  }

  Future<void> _loadRecentOpponents() async {
    final prefs = await SharedPreferences.getInstance();
    final jsonStr = prefs.getString('recent_opponents');
    if (jsonStr != null) {
      final List<dynamic> decoded = jsonDecode(jsonStr);
      setState(() {
        _recentOpponents = decoded.map((e) => Map<String, String>.from(e)).toList();
      });
    }
  }

  Future<void> _saveRecentOpponent(String id, String nickname) async {
    final prefs = await SharedPreferences.getInstance();
    _recentOpponents.removeWhere((o) => o['id'] == id);
    _recentOpponents.insert(0, {'id': id, 'nickname': nickname});
    if (_recentOpponents.length > 10) _recentOpponents = _recentOpponents.sublist(0, 10);
    await prefs.setString('recent_opponents', jsonEncode(_recentOpponents));
    if (mounted) setState(() {});
  }

  Future<void> _loadMasteredBoards() async {
    if (widget.isCompeteMode) return; // Skip loading library boards in Compete Mode
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
          for (int i = 0; i < 5; i++) {
            _selectedLibraryBoards[i] = _masteredBoards.first;
          }
        }
      });
    } catch (e) {
      debugPrint("Error loading mastered boards: $e");
    } finally {
      setState(() => _isLoadingLibrary = false);
    }
  }

  void _startMatch() async {
    final opponentId = _opponentIdController.text.trim();
    if (opponentId.isEmpty) {
      _showWarningDialog("Who are we fighting?", "Type your opponent's 6-digit Player ID to invite them to the battle session!");
      return;
    }
    if (opponentId.length < 4) {
      _showWarningDialog("Short ID", "Please enter a valid opponent Player ID!");
      return;
    }
    if (_selectedColor == null) {
      _showWarningDialog(
        "Pick Your Colors!",
        widget.isCompeteMode 
            ? "Select either Red or Blue to represent your side of the notebook!"
            : "Select either Green or Blue to represent your side of the notebook!",
      );
      return;
    }
    
    // Validate each match configuration in the series
    for (int i = 0; i < _matchCount; i++) {
      if (_boardSources[i] == 'library' && _selectedLibraryBoards[i] == null) {
        _showWarningDialog("Empty Library Selection", "You selected 'My Library' for Match ${i + 1}, but haven't chosen a mastered board! Please select a board for Match ${i + 1}.");
        return;
      }
    }

    // --- STEP 1: VALIDATE PEER ID EXISTENCE ---
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (checkCtx) => const Center(
        child: Card(
          color: Colors.white,
          child: Padding(
            padding: EdgeInsets.all(20.0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                CircularProgressIndicator(color: AppColors.navyBlue),
                SizedBox(width: 20),
                Text("Searching Arena for Opponent...", style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue)),
              ],
            ),
          ),
        ),
      ),
    );

    final peerProfile = await FirebaseGameManager.instance.checkPeerValid(opponentId);
    
    if (mounted) {
      Navigator.pop(context); // Close search dialog
    }

    if (peerProfile == null) {
      _showWarningDialog(
        "Opponent Not Found!", 
        "Player ID 'NQ-$opponentId' does not exist in our arena database!\n\nMake sure the ID is correct and they have launched the app at least once to register."
      );
      return;
    }

    await _saveRecentOpponent(opponentId, peerProfile['nickname'] ?? 'Player');

    // --- STEP 2: SHOW LOBBY CONFIRMATION ---
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => FunkyLobbyDetailsDialog(
        title: widget.isCompeteMode ? "BATTLE DECK" : "CO-OP BOARD",
        opponentId: opponentId,
        playerColor: _selectedColor!,
        matchCount: _matchCount,
        boardSources: _boardSources,
        selectedSizes: _selectedSizes,
        selectedLibraryBoards: _selectedLibraryBoards,
        onCancel: () => Navigator.pop(dialogCtx),
        onConfirm: () async {
          if (_isConnecting) return;
          _isConnecting = true;
          Navigator.pop(dialogCtx); // close confirmation dialog
          
          final List<BoardData> validMatchBoards = [];
          
          // Show board weaving dialog
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (weaveCtx) => const Center(
              child: Card(
                color: Colors.white,
                child: Padding(
                  padding: EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.navyBlue),
                      SizedBox(height: 15),
                      Text("Weaving Solvable Puzzles...", style: TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue)),
                    ],
                  ),
                ),
              ),
            ),
          );

          try {
            for (int i = 0; i < _matchCount; i++) {
              if (_boardSources[i] == 'auto') {
                final board = await BoardGenerator.generateUniqueBoard(_selectedSizes[i]);
                if (board != null) {
                  validMatchBoards.add(board);
                }
              } else if (_boardSources[i] == 'library' && _selectedLibraryBoards[i] != null) {
                validMatchBoards.add(_selectedLibraryBoards[i]!['board'] as BoardData);
              }
            }
          } catch (e) {
            debugPrint("Error generating board series: $e");
          }

          if (mounted) {
            Navigator.pop(context); // Close weave dialog
          }

          if (validMatchBoards.length < _matchCount) {
            _showWarningDialog("Generation Failed", "Failed to generate solvable boards. Please try again.");
            return;
          }

          // --- STEP 3: ESTABLISH FIREBASE CONNECTION ---
          bool connectionEstablished = false;
          void Function()? connListener;
          
          showDialog(
            context: context,
            barrierDismissible: false,
            builder: (loaderCtx) {
              connListener = () {
                final state = FirebaseGameManager.instance.connectionState.value;
                if (state == 'connected' && !connectionEstablished) {
                  connectionEstablished = true;
                  FirebaseGameManager.instance.connectionState.removeListener(connListener!);
                  
                  Navigator.pop(loaderCtx); // pop loader dialog

                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        widget.isCompeteMode ? "DUEL ACTIVE! Firebase connected." : "LOBBY CONNECTED! Co-op synchronized.",
                        style: const TextStyle(fontFamily: 'DynaPuff', color: Colors.white, fontSize: 16),
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.navyBlue,
                      margin: const EdgeInsets.only(bottom: 105, left: 40, right: 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: const BorderSide(color: Colors.white24, width: 1),
                      ),
                    ),
                  );

                  // Transition AUTOMATICALLY directly to PeersPlayScreen without asking manual confirmation
                  Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                      builder: (context) => PeersPlayScreen(
                        isCompeteMode: widget.isCompeteMode,
                        opponentId: opponentId,
                        playerColor: _selectedColor!,
                        matchCount: _matchCount,
                        matchBoards: validMatchBoards,
                      ),
                    ),
                  );
                } else if (state == 'failed') {
                  _isConnecting = false;
                  FirebaseGameManager.instance.connectionState.removeListener(connListener!);
                  Navigator.pop(loaderCtx);
                  FirebaseGameManager.instance.disconnect();
                  _showWarningDialog("Connection Failed", "Failed to establish connection with opponent. They might have declined or timed out.");
                }
              };
              
              FirebaseGameManager.instance.connectionState.addListener(connListener!);

              return FunkyLoaderDialog(
                title: widget.isCompeteMode ? "TRANSMITTING COMPETE..." : "TRANSMITTING CO-OP...",
                statusSteps: widget.isCompeteMode 
                  ? const [
                      "Locking board templates... ",
                      "Transmitting Duel Invite... ",
                      "Waiting for opponent to accept... ",
                      "Connecting via Firebase... ",
                    ]
                  : const [
                      "Syncing puzzle blueprints... ",
                      "Transmitting Lobby Invite... ",
                      "Waiting for partner to accept... ",
                      "Connecting via Firebase... ",
                    ],
                cancelLabel: "CANCEL INVITE",
                totalDuration: const Duration(minutes: 5), // Wait until connection or cancel
                stepDuration: const Duration(seconds: 3),
                onComplete: () {}, // Handled by manual listener instead
                onCancel: () {
                  _isConnecting = false;
                  if (connListener != null) {
                    FirebaseGameManager.instance.connectionState.removeListener(connListener!);
                  }
                  FirebaseGameManager.instance.disconnect();
                  Navigator.pop(loaderCtx); // close loader
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text(
                        "Multiplayer invite cancelled!",
                        style: TextStyle(fontFamily: 'DynaPuff', color: Colors.white, fontSize: 16),
                      ),
                      duration: const Duration(seconds: 1),
                      behavior: SnackBarBehavior.floating,
                      backgroundColor: AppColors.navyBlue,
                      margin: const EdgeInsets.only(bottom: 105, left: 40, right: 40),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: const BorderSide(color: Colors.white24, width: 1),
                      ),
                    ),
                  );
                },
              );
            },
          );

          // Launch host Firebase session
          try {
            await FirebaseGameManager.instance.hostConnection(
              opponentId,
              widget.isCompeteMode,
              _matchCount,
              validMatchBoards,
              hostColor: _selectedColor ?? 'blue',
            );
          } catch (e) {
            _isConnecting = false;
            if (connListener != null) {
              try {
                FirebaseGameManager.instance.connectionState.removeListener(connListener!);
              } catch (_) {}
            }
            Navigator.pop(context); // Dismiss loading if open
            FirebaseGameManager.instance.disconnect();
            _showWarningDialog("Invite Failed", e.toString());
          }
        },
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
                    angle: 0.05,
                    child: GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        width: 55,
                        height: 55,
                        decoration: BoxDecoration(
                          color: widget.isCompeteMode ? const Color(0xFFFFEBEE) : const Color(0xFFE8F5E9), // Red vs Green back button box!
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: AppColors.navyBlue, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navyBlue.withValues(alpha: 0.3),
                              offset: const Offset(4, 4),
                            )
                          ],
                        ),
                        child: Icon(
                          Icons.arrow_back_rounded, 
                          color: widget.isCompeteMode ? Colors.redAccent.shade700 : Colors.green.shade700, 
                          size: 28,
                        ),
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
          widget.isCompeteMode ? 'Compete Battle' : 'Combine Solving',
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
            BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(6, 6)),
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
              decoration: InputDecoration(
                hintText: 'Enter 6-digit ID...',
                counterText: "",
                border: InputBorder.none,
                hintStyle: const TextStyle(color: Colors.grey, fontWeight: FontWeight.normal, letterSpacing: 1),
                isDense: true,
                suffixIcon: _recentOpponents.isEmpty ? null : PopupMenuButton<String>(
                  icon: const Icon(Icons.history_rounded, color: AppColors.navyBlue),
                  tooltip: 'Recent Opponents',
                  onSelected: (String id) {
                    setState(() {
                      _opponentIdController.text = id;
                    });
                  },
                  itemBuilder: (BuildContext context) {
                    return _recentOpponents.map((opponent) {
                      return PopupMenuItem<String>(
                        value: opponent['id']!.replaceAll('NQ-', ''), // just digits
                        child: Text('${opponent['nickname']} (${opponent['id']})', style: const TextStyle(fontFamily: 'Comfortaa')),
                      );
                    }).toList();
                  },
                ),
              ),
            ),
            const Divider(color: AppColors.paperLine, thickness: 2),
            const SizedBox(height: 5),
            Text(
              widget.isCompeteMode 
                ? "Type in your rival's game lobby key to link screens for mutual head-to-head compete dueling."
                : "Type in your partner's game lobby key to link screens for simultaneous co-op solving.",
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 11, color: AppColors.secondaryText),
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
            BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(6, 6)),
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
                // Red/Green option
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _selectedColor = widget.isCompeteMode ? 'red' : 'green'),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: _selectedColor == (widget.isCompeteMode ? 'red' : 'green') 
                            ? (widget.isCompeteMode ? const Color(0xFFFF1744) : const Color(0xFF00E676)) 
                            : Colors.white,
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(
                          color: AppColors.navyBlue, 
                          width: _selectedColor == (widget.isCompeteMode ? 'red' : 'green') ? 3.0 : 1.5
                        ),
                        boxShadow: _selectedColor == (widget.isCompeteMode ? 'red' : 'green') 
                            ? [const BoxShadow(color: AppColors.navyBlue, offset: Offset(4, 4))] 
                            : null,
                      ),
                      child: Column(
                        children: [
                          Icon(
                            Icons.favorite_rounded,
                            size: 28,
                            color: _selectedColor == (widget.isCompeteMode ? 'red' : 'green') 
                                ? Colors.white 
                                : (widget.isCompeteMode ? const Color(0xFFFF1744) : const Color(0xFF00E676)),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            widget.isCompeteMode ? "RED" : "GREEN",
                            style: TextStyle(
                              fontFamily: 'DynaPuff',
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: _selectedColor == (widget.isCompeteMode ? 'red' : 'green') ? Colors.white : AppColors.navyBlue,
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
            BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(6, 6)),
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

            // If we have more than 1 match in series, show funky Match selector tabs
            if (_matchCount > 1) ...[
              const Text(
                'CONFIGURE BOARDS FOR SERIES:',
                style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: AppColors.secondaryText),
              ),
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_matchCount, (index) {
                  final isSelected = _currentEditingMatchIndex == index;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _currentEditingMatchIndex = index),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        decoration: BoxDecoration(
                          color: isSelected ? AppColors.navyBlue : Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.navyBlue, width: isSelected ? 2.5 : 1.2),
                          boxShadow: isSelected
                              ? [const BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2))]
                              : null,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          _matchCount == 5 ? "${index + 1}" : "Match ${index + 1}",
                          style: TextStyle(
                            fontFamily: 'DynaPuff',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected ? Colors.white : AppColors.navyBlue,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 15),
              const Divider(color: AppColors.paperLine, thickness: 1.5),
              const SizedBox(height: 10),
            ],

            // Tab bar options (Auto Generate and My Library)
            if (widget.isCompeteMode)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppColors.navyBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                alignment: Alignment.center,
                child: const Text(
                  'AUTO GENERATED PUZZLES ONLY',
                  style: TextStyle(
                    fontFamily: 'DynaPuff',
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                ),
              )
            else
              Container(
                decoration: BoxDecoration(
                  color: AppColors.paperLine.withValues(alpha: 0.5),
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
    final isSelected = _boardSources[_currentEditingMatchIndex] == key;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _boardSources[_currentEditingMatchIndex] = key),
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
    final currentSource = _boardSources[_currentEditingMatchIndex];
    final currentSize = _selectedSizes[_currentEditingMatchIndex];
    final currentLibraryBoard = _selectedLibraryBoards[_currentEditingMatchIndex];

    if (currentSource == 'auto') {
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
                      "${currentSize}x$currentSize",
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
                    overlayColor: AppColors.gold.withValues(alpha: 0.2),
                    valueIndicatorColor: AppColors.navyBlue,
                    valueIndicatorTextStyle: const TextStyle(fontFamily: 'DynaPuff'),
                  ),
                  child: Slider(
                    value: currentSize.toDouble(),
                    min: 4,
                    max: 12,
                    divisions: 8,
                    label: "${currentSize}x$currentSize",
                    onChanged: (val) => setState(() => _selectedSizes[_currentEditingMatchIndex] = val.toInt()),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
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
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _masteredBoards.length,
              physics: const BouncingScrollPhysics(),
              itemBuilder: (context, index) {
                final boardMap = _masteredBoards[index];
                final board = boardMap['board'] as BoardData;
                final isSelected = currentLibraryBoard?['id'] == boardMap['id'];

                return GestureDetector(
                  onTap: () => setState(() => _selectedLibraryBoards[_currentEditingMatchIndex] = boardMap),
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
                        Row(
                          children: [
                            const Icon(Icons.emoji_events_rounded, color: Colors.orange, size: 16),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                boardMap['name'] ?? 'Unnamed',
                                style: const TextStyle(
                                  fontFamily: 'DynaPuff',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.navyBlue,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Text(
                          "Grid: ${board.size}x${board.size}",
                          style: const TextStyle(
                            fontFamily: 'Comfortaa',
                            fontSize: 10,
                            color: AppColors.secondaryText,
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
            BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(6, 6)),
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
        onTap: () {
          setState(() {
            _matchCount = count;
            if (_currentEditingMatchIndex >= _matchCount) {
              _currentEditingMatchIndex = _matchCount - 1;
            }
          });
        },
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
            style: const TextStyle(
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
        onTap: _startMatch,
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
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.wifi_rounded, size: 30, color: AppColors.navyBlue),
              const SizedBox(width: 15),
              Text(
                widget.isCompeteMode ? 'INITIATE DUEL' : 'INITIATE SESSION',
                style: const TextStyle(
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
