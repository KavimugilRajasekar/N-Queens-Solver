import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';
import '../../constants/colors.dart';
import '../../constants/region_colors.dart';
import '../../utils/board_processor.dart';
import '../../screens/n_queens_board.dart';

class LibraryBoardCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onToggleSelection;
  final VoidCallback onRename;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;

  final int? selectionIndex;

  const LibraryBoardCard({
    super.key,
    required this.data,
    required this.isSelectionMode,
    required this.isSelected,
    this.selectionIndex,
    required this.onToggleSelection,
    required this.onRename,
    required this.onDelete,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final BoardData board = data['board'];
    // A board is solvable if it has a solution OR if it was manually solved
    final bool isSolvable = board.solution != null || board.isManuallySolved;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.navyBlue.withOpacity(0.2), width: 1.5),
        boxShadow: [BoxShadow(color: AppColors.navyBlue.withOpacity(0.05), offset: const Offset(4, 4))],
      ),
      child: Stack(
        children: [
          ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: _buildBoardPreview(board),
            title: Text(data['name'], style: const TextStyle(fontFamily: 'DynaPuff', fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text(
              '${board.size}x${board.size} • ${data['date'].year}-${data['date'].month.toString().padLeft(2, '0')}-${data['date'].day.toString().padLeft(2, '0')}', 
              style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 12)
            ),
            onTap: () async {
              if (isSelectionMode) {
                if (isSolvable) onToggleSelection();
              } else {
                await Navigator.push(context, MaterialPageRoute(builder: (context) => NQueensBoardScreen(boardData: board, isAlreadySaved: true, boardId: data['id'])));
                onRefresh();
              }
            },
          ),
          
          if (isSelectionMode && !isSolvable)
            Positioned.fill(
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.6),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Center(
                  child: Icon(Icons.lock_outline_rounded, color: Colors.grey, size: 30),
                ),
              ),
            ),

          if (isSelectionMode && isSolvable)
            Positioned(
              top: 12,
              right: 12,
              child: Container(
                width: 26,
                height: 26,
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.navyBlue : Colors.white,
                  shape: BoxShape.circle,
                  border: Border.all(color: AppColors.navyBlue, width: 2),
                  boxShadow: isSelected ? [BoxShadow(color: AppColors.navyBlue.withOpacity(0.3), blurRadius: 4, offset: const Offset(2, 2))] : null,
                ),
                child: Center(
                  child: isSelected 
                    ? Text(
                        selectionIndex != null ? (selectionIndex! + 1).toString() : '', 
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold, fontFamily: 'DynaPuff')
                      )
                    : null,
                ),
              ),
            ),

          if (board.isManuallySolved)
            Positioned(
              top: 2,
              left: 2,
              child: SizedBox(
                width: 42,
                height: 42,
                child: Lottie.asset('assets/json/winner_badge.json', repeat: true),
              ),
            ),

          if (!isSelectionMode)
            Positioned(
              bottom: 4,
              right: 4,
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, color: AppColors.navyBlue, size: 18),
                    onPressed: onRename,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 18),
                    onPressed: onDelete,
                    constraints: const BoxConstraints(),
                    padding: const EdgeInsets.all(8),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBoardPreview(BoardData board) {
    return Container(
      width: 60,
      height: 60,
      decoration: BoxDecoration(
        color: AppColors.background, 
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.navyBlue.withOpacity(0.1)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GridView.builder(
          padding: EdgeInsets.zero,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: board.size),
          itemCount: board.size * board.size,
          itemBuilder: (context, i) {
            int r = i ~/ board.size;
            int c = i % board.size;
            int id = board.regionIds[r][c];
            bool hasQueen = board.solution?.values.any((p) => p.x - 1 == r && p.y - 1 == c) ?? false;
            bool isInvalid = id > board.size;
            
            return Container(
              color: RegionColors.getRegionColor(id, board.size),
              child: Stack(
                children: [
                  if (hasQueen) 
                    const Center(child: Icon(Icons.stars_rounded, size: 6, color: AppColors.navyBlue)),
                  if (isInvalid && !hasQueen)
                    const Center(child: Icon(Icons.close_rounded, size: 8, color: Colors.black26)),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
