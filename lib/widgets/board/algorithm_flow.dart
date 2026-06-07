import 'package:flutter/material.dart';
import '../../utils/solver_logic.dart';
import '../../utils/board_processor.dart';
import '../../constants/colors.dart';
import '../../constants/region_colors.dart';

class AlgorithmFlow extends StatelessWidget {
  final List<SolverStep> solverSteps;
  final ScrollController scrollController;
  final BoardData boardData;

  const AlgorithmFlow({
    super.key,
    required this.solverSteps,
    required this.scrollController,
    required this.boardData,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: 0.01,
      child: Container(
        width: double.infinity,
        height: 450,
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(25),
          border: Border.all(color: AppColors.navyBlue.withValues(alpha: 0.5), width: 2.5),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.1), offset: const Offset(6, 6))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.history_edu_rounded, color: AppColors.navyBlue),
                SizedBox(width: 10),
                Text('Solving Timeline', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, color: AppColors.navyBlue, fontSize: 20)),
              ],
            ),
            const Divider(thickness: 1.5),
            Expanded(
              child: ListView.builder(
                controller: scrollController,
                itemCount: solverSteps.length,
                itemBuilder: (context, index) => _StepItem(step: solverSteps[index], boardData: boardData),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepItem extends StatelessWidget {
  final SolverStep step;
  final BoardData boardData;

  const _StepItem({required this.step, required this.boardData});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: step.isBacktrack ? Colors.red.withValues(alpha: 0.3) : AppColors.navyBlue.withValues(alpha: 0.1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.02), offset: const Offset(2, 2))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 140,
                height: 140,
                decoration: BoxDecoration(color: Colors.white, border: Border.all(color: AppColors.navyBlue, width: 2), borderRadius: BorderRadius.circular(8)),
                child: GridView.builder(
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: boardData.size),
                  itemCount: boardData.size * boardData.size,
                  itemBuilder: (context, i) {
                    int r = i ~/ boardData.size;
                    int c = i % boardData.size;
                    bool hasQueen = step.queenPositions.values.any((p) => p.x - 1 == r && p.y - 1 == c);
                    bool isValidDomain = false;
                    for (var entry in boardData.regions.entries) {
                      if (entry.value.coordinates.any((p) => p.x - 1 == r && p.y - 1 == c)) {
                        isValidDomain = step.domains[entry.key]?.any((p) => p.x - 1 == r && p.y - 1 == c) ?? false;
                        break;
                      }
                    }
                    Color cellColor = RegionColors.getRegionColor(boardData.regionIds[r][c], boardData.size);
                    return Container(
                      decoration: BoxDecoration(
                        color: isValidDomain ? cellColor : cellColor.withValues(alpha: 0.15),
                        border: Border.all(color: Colors.black.withValues(alpha: 0.03), width: 0.2),
                      ),
                      child: hasQueen ? const Center(child: Icon(Icons.stars_rounded, size: 10, color: AppColors.navyBlue)) : null,
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(step.isBacktrack ? "RETREATING" : "ACTION", style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: step.isBacktrack ? Colors.red : Colors.green, letterSpacing: 1.2, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 4),
                    Text(step.message, style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 13, color: AppColors.darkText, height: 1.4, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
