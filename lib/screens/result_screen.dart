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
      backgroundColor: AppColors.background,
      body: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: NotebookPainter())),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 30),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Transform.rotate(
                        angle: -0.05,
                        child: IconButton(
                          icon: const Icon(Icons.arrow_back_rounded, color: AppColors.navyBlue),
                          onPressed: () => Navigator.pop(context),
                          style: IconButton.styleFrom(
                            backgroundColor: Colors.white,
                            elevation: 4,
                            shadowColor: AppColors.navyBlue.withOpacity(0.2),
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Transform.rotate(
                        angle: 0.02,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: AppColors.navyBlue, width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.navyBlue.withOpacity(0.2),
                                offset: const Offset(4, 4),
                              ),
                            ],
                          ),
                          child: Text(
                            'ANALYSIS',
                            style: Theme.of(context).textTheme.displayLarge?.copyWith(
                              fontSize: 24,
                              fontFamily: 'DynaPuff',
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 40),
                  
                  // Reconstructed Board (Funky Container)
                  Center(
                    child: Transform.rotate(
                      angle: -0.01,
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: AppColors.navyBlue, width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: AppColors.navyBlue.withOpacity(0.2),
                              offset: const Offset(8, 8),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: MediaQuery.of(context).size.width * 0.75,
                            height: MediaQuery.of(context).size.width * 0.75,
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
                                    border: Border.all(color: Colors.black.withOpacity(0.05), width: 0.5),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 50),
                  
                  // Output Section
                  Transform.rotate(
                    angle: 0.01,
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navyBlue.withOpacity(0.15),
                            offset: const Offset(6, 6),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Regions Mapping',
                            style: TextStyle(
                              fontFamily: 'DynaPuff',
                              fontSize: 18,
                              color: AppColors.navyBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 16),
                          SelectableText(
                            _formatOutput(),
                            style: const TextStyle(
                              fontFamily: 'Comfortaa',
                              fontSize: 14,
                              color: AppColors.darkText,
                              fontWeight: FontWeight.bold,
                              height: 1.8,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  
                  const SizedBox(height: 60),
                  
                  // Funky Action Button
                  Transform.rotate(
                    angle: -0.02,
                    child: Container(
                      width: double.infinity,
                      height: 65,
                      decoration: BoxDecoration(
                        color: AppColors.gold,
                        borderRadius: BorderRadius.circular(15),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.navyBlue.withOpacity(0.2),
                            offset: const Offset(5, 5),
                          ),
                        ],
                        border: Border.all(color: AppColors.navyBlue, width: 2.5),
                      ),
                      child: ElevatedButton.icon(
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.refresh_rounded, size: 28),
                        label: const Text(
                          'Scan Another',
                          style: TextStyle(
                            fontFamily: 'DynaPuff',
                            fontWeight: FontWeight.bold,
                            fontSize: 20,
                          ),
                        ),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          foregroundColor: AppColors.navyBlue,
                          shadowColor: Colors.transparent,
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 40),
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
      buffer.write(region.coordinates.join(', '));
      buffer.write(']\n');
    });
    return buffer.toString();
  }
}
