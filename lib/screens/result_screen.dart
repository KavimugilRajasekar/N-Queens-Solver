import 'package:flutter/material.dart';
import '../constants/colors.dart';
import '../utils/board_processor.dart';
import '../widgets/notebook_painter.dart';

class ResultScreen extends StatelessWidget {
  final BoardData boardData;

  const ResultScreen({super.key, required this.boardData});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back, color: AppColors.navyBlue),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'Board Analysis',
                        style: Theme.of(context).textTheme.displayLarge?.copyWith(fontSize: 28),
                      ),
                    ],
                  ),
                  const SizedBox(height: 30),
                  
                  // Reconstructed Board
                  Center(
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.navyBlue,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.1),
                            blurRadius: 10,
                            offset: const Offset(0, 5),
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: SizedBox(
                          width: MediaQuery.of(context).size.width * 0.85,
                          height: MediaQuery.of(context).size.width * 0.85,
                          child: GridView.builder(
                            padding: EdgeInsets.zero,
                            physics: const NeverScrollableScrollPhysics(),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: boardData.size,
                            ),
                            itemCount: boardData.size * boardData.size,
                            itemBuilder: (context, index) {
                              int r = index ~/ boardData.size;
                              int c = index % boardData.size;
                              return Container(
                                decoration: BoxDecoration(
                                  color: boardData.grid[r][c],
                                  border: Border.all(color: Colors.black.withOpacity(0.1), width: 0.5),
                                ),
                              );
                            },
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Output Section
                  Text(
                    'Regions Mapping',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: AppColors.paperLine, width: 2),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.02),
                          blurRadius: 10,
                        ),
                      ],
                    ),
                    child: SelectableText(
                      _formatOutput(),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                        color: AppColors.darkText,
                        height: 1.5,
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 40),
                  
                  // Reset Button
                  SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.navyBlue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: const Text('Back to Scanner', style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatOutput() {
    StringBuffer buffer = StringBuffer();
    boardData.regions.forEach((id, region) {
      buffer.write('Q$id = [');
      buffer.write(region.coordinates.join(','));
      buffer.write(']\n');
    });
    return buffer.toString();
  }
}
