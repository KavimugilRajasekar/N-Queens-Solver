import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../utils/board_generator.dart';
import '../utils/storage_manager.dart';
import '../widgets/notebook_painter.dart';
import '../widgets/error_dialog.dart';
import '../widgets/success_dialog.dart';
import 'n_queens_board.dart';
import '../utils/board_processor.dart';

class GenerateBoardScreen extends StatefulWidget {
  const GenerateBoardScreen({super.key});

  @override
  State<GenerateBoardScreen> createState() => _GenerateBoardScreenState();
}

class _GenerateBoardScreenState extends State<GenerateBoardScreen> {
  int _size = 8;
  final TextEditingController _nameController = TextEditingController();
  bool _isGenerating = false;

  @override
  void initState() {
    super.initState();
    _nameController.text = 'AI Masterpiece';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _generateBoard() async {
    if (_nameController.text.trim().isEmpty) {
      FunkyErrorDialog.show(context, message: 'Give your masterpiece a name first!');
      return;
    }

    setState(() => _isGenerating = true);

    final board = await BoardGenerator.generateUniqueBoard(_size);

    if (mounted) {
      if (board != null) {
        // Save with the generated solution to ensure it's 100% solvable
        final finalBoard = BoardData(
          size: board.size,
          regionIds: board.regionIds,
          regions: board.regions,
          rawResponse: "AI Generated Puzzle",
          solution: board.solution, // Keep the valid solution!
          isManuallySolved: false,
        );

        final id = await StorageManager.saveBoard(finalBoard, name: _nameController.text.trim());
        
        await FunkySuccessDialog.show(
          context, 
          title: 'Board Ready!', 
          message: 'A brand new ${_size}x$_size puzzle has been generated just for you!',
        );

        if (mounted) {
          Navigator.pushReplacement(
            context, 
            MaterialPageRoute(builder: (context) => NQueensBoardScreen(boardData: finalBoard, isAlreadySaved: true, boardId: id))
          );
        }
      } else {
        FunkyErrorDialog.show(context, message: 'Could not generate a unique board. Try a different size!');
        setState(() => _isGenerating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(24.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFunkyBack(() => Navigator.pop(context)),
                    const SizedBox(height: 32),
                    const Text('Generate Board', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 32, fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
                    const Text('Let AI create a unique puzzle for you.', style: TextStyle(fontFamily: 'Comfortaa', fontSize: 16, color: AppColors.secondaryText)),
                    
                    const SizedBox(height: 40),
                    
                    // Board Name Input
                    const Text('Board Name', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 18, color: AppColors.navyBlue)),
                    const SizedBox(height: 12),
                    _buildFunkyInput(),
                    
                    const SizedBox(height: 32),
                    
                    // Size Picker
                    const Text('Pick a Size (NxN)', style: TextStyle(fontFamily: 'DynaPuff', fontSize: 18, color: AppColors.navyBlue)),
                    const SizedBox(height: 16),
                    _buildSizePicker(),
                    
                    const SizedBox(height: 60),
                    
                    // Generate Button
                    _buildGenerateButton(),
                  ],
                ),
              ),
            ),
          ),
          if (_isGenerating)
            Container(
              color: Colors.black26,
              child: const Center(child: CircularProgressIndicator(color: AppColors.gold)),
            ),
        ],
      ),
    );
  }

  Widget _buildFunkyInput() {
    return Transform.rotate(
      angle: -0.01,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: AppColors.navyBlue, width: 2),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.15), offset: const Offset(4, 4))],
        ),
        child: TextField(
          controller: _nameController,
          style: const TextStyle(fontFamily: 'Comfortaa', color: AppColors.navyBlue, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
            hintText: 'Enter board name...',
            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 18),
            border: InputBorder.none,
          ),
        ),
      ),
    );
  }

  Widget _buildSizePicker() {
    return Column(
      children: [
        Center(
          child: Text(
            '$_size x $_size', 
            style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 42, color: AppColors.navyBlue, fontWeight: FontWeight.bold)
          ),
        ),
        SliderTheme(
          data: SliderThemeData(
            activeTrackColor: AppColors.gold,
            inactiveTrackColor: AppColors.gold.withValues(alpha: 0.2),
            thumbColor: AppColors.gold,
            overlayColor: AppColors.gold.withValues(alpha: 0.1),
            valueIndicatorTextStyle: const TextStyle(fontFamily: 'DynaPuff', color: AppColors.navyBlue),
          ),
          child: Slider(
            value: _size.toDouble(),
            min: 4,
            max: 12,
            divisions: 8,
            label: _size.toString(),
            onChanged: (val) => setState(() => _size = val.toInt()),
          ),
        ),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('4', style: TextStyle(fontFamily: 'Comfortaa', fontSize: 12, color: Colors.grey)),
              Text('12', style: TextStyle(fontFamily: 'Comfortaa', fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton() {
    return Center(
      child: Transform.rotate(
        angle: 0.02,
        child: GestureDetector(
          onTap: _isGenerating ? null : _generateBoard,
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 20),
            decoration: BoxDecoration(
              color: AppColors.gold,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppColors.navyBlue, width: 3),
              boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.3), offset: const Offset(6, 6))],
            ),
            child: Center(
              child: Text(
                _isGenerating ? 'GENERATING...' : 'GENERATE BOARD!',
                style: const TextStyle(fontFamily: 'DynaPuff', fontSize: 22, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFunkyBack(VoidCallback onTap) {
    return Transform.rotate(
      angle: 0.05,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 55,
          height: 55,
          decoration: BoxDecoration(
            color: const Color(0xFFE3F2FD),
            borderRadius: BorderRadius.circular(15),
            border: Border.all(color: AppColors.navyBlue, width: 2.5),
            boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.3), offset: const Offset(4, 4))],
          ),
          child: const Icon(Icons.arrow_back_rounded, color: AppColors.navyBlue, size: 28),
        ),
      ),
    );
  }
}
