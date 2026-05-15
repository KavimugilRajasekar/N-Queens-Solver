import 'package:flutter/material.dart';
import '../../utils/board_processor.dart';
import '../../constants/colors.dart';
import '../../constants/region_colors.dart';

class BoardGrid extends StatelessWidget {
  final double boardScale;
  final BoardData boardData;
  final bool isEditing;
  final bool isManualMode;
  final bool isPaused;
  final Map<int, Point> queenPositions;
  final Map<String, int> manualGrid;
  final List<List<int>>? tempGrid;
  final Map<String, dynamic> conflicts;
  final Function(int, int) onCellTap;
  final VoidCallback onPanEnd;

  const BoardGrid({
    super.key,
    required this.boardScale,
    required this.boardData,
    required this.isEditing,
    required this.isManualMode,
    required this.isPaused,
    required this.queenPositions,
    required this.manualGrid,
    required this.tempGrid,
    required this.conflicts,
    required this.onCellTap,
    required this.onPanEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isEditing ? AppColors.gold : AppColors.navyBlue, width: 3),
          boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.2), offset: const Offset(8, 8))],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: SizedBox(
            width: MediaQuery.of(context).size.width * boardScale,
            height: MediaQuery.of(context).size.width * boardScale,
            child: GestureDetector(
              onPanEnd: isManualMode ? (_) => onPanEnd() : null,
              child: GridView.builder(
                padding: EdgeInsets.zero,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: boardData.size),
                itemCount: boardData.size * boardData.size,
                itemBuilder: (context, index) {
                  int r = index ~/ boardData.size;
                  int c = index % boardData.size;
                  
                  bool hasQueen = isManualMode 
                      ? (manualGrid["$r,$c"] == 2)
                      : queenPositions.values.any((p) => p.x - 1 == r && p.y - 1 == c);
                  
                  bool hasX = isManualMode && (manualGrid["$r,$c"] == 1);
                  
                  int id = isEditing ? tempGrid![r][c] : boardData.regionIds[r][c];
                  bool isInvalid = id > boardData.size;
  
                  final Set<int> rowConflicts = conflicts['rows'] as Set<int>;
                  final Set<int> colConflicts = conflicts['cols'] as Set<int>;
                  final Set<int> regionConflicts = conflicts['regions'] as Set<int>;
                  final Set<String> queenConflicts = conflicts['queens'] as Set<String>;

                  bool isRowConflict = rowConflicts.contains(r);
                  bool isColConflict = colConflicts.contains(c);
                  bool isRegionConflict = regionConflicts.contains(id);
                  bool isQueenConflict = queenConflicts.contains("$r,$c");
                  bool isNeighborhoodConflict = (conflicts['neighborhood'] as Set<String>).contains("$r,$c");
  
                  return GestureDetector(
                    onTap: () => onCellTap(r, c),
                    child: Container(
                      decoration: BoxDecoration(
                        color: RegionColors.getRegionColor(id, boardData.size),
                        border: Border.all(color: Colors.black.withOpacity(0.05), width: 0.5)
                      ),
                      child: Stack(
                        children: [
                          // Conflict Tints
                          if (isRowConflict || isColConflict)
                            Container(color: Colors.red.withOpacity(0.1)),
                          
                          if (isRegionConflict || isRowConflict || isColConflict || isQueenConflict || isNeighborhoodConflict)
                            Center(
                              child: Opacity(
                                opacity: 0.2,
                                child: Icon(
                                  Icons.close_rounded, 
                                  color: Colors.red.shade900, 
                                  size: (MediaQuery.of(context).size.width * boardScale) / boardData.size
                                ),
                              ),
                            ),

                          if (isEditing && id > 0)
                            Center(
                              child: Text(
                                '$id', 
                                style: TextStyle(
                                  fontFamily: 'DynaPuff', 
                                  fontSize: (MediaQuery.of(context).size.width * boardScale * 0.3) / boardData.size, 
                                  color: Colors.black.withOpacity(0.15), 
                                  fontWeight: FontWeight.bold
                                )
                              )
                            ),
                          if (hasQueen) 
                            Center(
                              child: Icon(
                                Icons.stars_rounded, 
                                color: isQueenConflict ? Colors.red.shade900 : AppColors.navyBlue, 
                                size: (MediaQuery.of(context).size.width * boardScale * 0.8) / boardData.size
                              ),
                            ),
                          if (hasX)
                            Center(child: Text('x', style: TextStyle(fontFamily: 'Comfortaa', fontSize: (MediaQuery.of(context).size.width * boardScale * 0.5) / boardData.size, color: AppColors.navyBlue.withOpacity(0.4), fontWeight: FontWeight.bold))),
                          if (!hasQueen && !hasX && isInvalid)
                            Center(
                              child: Transform.rotate(
                                angle: 0.1,
                                child: Icon(
                                  Icons.close_rounded, 
                                  color: AppColors.navyBlue.withOpacity(0.3), 
                                  size: (MediaQuery.of(context).size.width * boardScale * 0.6) / boardData.size
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}
