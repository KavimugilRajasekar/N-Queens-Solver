import 'package:flutter/material.dart';
import '../../constants/colors.dart';
import '../../constants/region_colors.dart';

class BoardPalette extends StatelessWidget {
  final int boardSize;
  final int? selectedRegionId;
  final Function(int) onRegionSelected;

  const BoardPalette({
    super.key,
    required this.boardSize,
    required this.selectedRegionId,
    required this.onRegionSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.01,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.1), offset: const Offset(4, 4))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Pick Region Color:', style: TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, color: AppColors.navyBlue)),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: List.generate(boardSize + 1, (index) {
                  int id = index + 1;
                  bool isSelected = selectedRegionId == id;
                  return Padding(
                    padding: const EdgeInsets.only(right: 12),
                    child: GestureDetector(
                      onTap: () => onRegionSelected(id),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        width: 45,
                        height: 45,
                        decoration: BoxDecoration(
                          color: RegionColors.getRegionColor(id, boardSize),
                          shape: BoxShape.circle,
                          border: Border.all(color: isSelected ? AppColors.navyBlue : Colors.transparent, width: 3),
                          boxShadow: isSelected ? [BoxShadow(color: AppColors.navyBlue.withValues(alpha: 0.3), blurRadius: 8)] : [],
                        ),
                        child: Center(
                          child: Text(
                            '$id', 
                            style: TextStyle(
                              fontWeight: FontWeight.bold, 
                              color: isSelected ? AppColors.navyBlue : Colors.black54,
                              fontSize: 14,
                            )
                          )
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
