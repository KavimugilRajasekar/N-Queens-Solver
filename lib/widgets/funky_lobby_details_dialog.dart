import 'package:flutter/material.dart';
import '../constants/colors.dart';

class FunkyLobbyDetailsDialog extends StatelessWidget {
  final String title;
  final String opponentId;
  final String playerColor;
  final int matchCount;
  final List<String> boardSources;
  final List<int> selectedSizes;
  final List<Map<String, dynamic>?> selectedLibraryBoards;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;
  final double rotationAngle;

  const FunkyLobbyDetailsDialog({
    super.key,
    required this.opponentId,
    required this.playerColor,
    required this.matchCount,
    required this.boardSources,
    required this.selectedSizes,
    required this.selectedLibraryBoards,
    required this.onCancel,
    required this.onConfirm,
    this.title = "BATTLE DECK",
    this.rotationAngle = 0.01,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: Center(
        child: Transform.rotate(
          angle: rotationAngle,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 330,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: const Color(0xFFFAF9F5), // warm white paper
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: AppColors.navyBlue, width: 3.5),
                  boxShadow: const [
                    BoxShadow(color: AppColors.navyBlue, offset: Offset(8, 8)),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Red margin line like notebook paper
                    Container(
                      height: 4,
                      width: double.infinity,
                      color: Colors.redAccent.withOpacity(0.3),
                    ),
                    const SizedBox(height: 10),
                    // Funky Header Sticker
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Transform.rotate(
                          angle: -0.05,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: AppColors.navyBlue,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              title.toUpperCase(),
                              style: const TextStyle(
                                fontFamily: 'DynaPuff',
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                        // Mode capsule
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: AppColors.paperLine.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(15),
                            border: Border.all(color: AppColors.navyBlue, width: 1),
                          ),
                          child: Text(
                            "Best of $matchCount",
                            style: const TextStyle(
                              fontFamily: 'DynaPuff',
                              fontSize: 10,
                              color: AppColors.navyBlue,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    // Opponent Details Sticker
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFE8F5E9), // soft green
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.wifi_tethering_rounded, color: AppColors.navyBlue, size: 24),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "OPPONENT PLAYER",
                                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  "NQ-$opponentId",
                                  style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 15),
                    // Player Color Sticker
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: playerColor.toLowerCase() == 'blue' 
                            ? const Color(0xFFE0F7FA) 
                            : (playerColor.toLowerCase() == 'green' ? const Color(0xFFE8F5E9) : const Color(0xFFFFEBEE)),
                        borderRadius: BorderRadius.circular(15),
                        border: Border.all(color: AppColors.navyBlue, width: 2),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.favorite_rounded, 
                            color: playerColor.toLowerCase() == 'blue' 
                                ? Colors.blue 
                                : (playerColor.toLowerCase() == 'green' ? Colors.green : Colors.red),
                            size: 24,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  "YOUR NOTEBOOK COLOR",
                                  style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: AppColors.navyBlue, fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  playerColor.toUpperCase(),
                                  style: TextStyle(
                                    fontFamily: 'Comfortaa', 
                                    fontSize: 16, 
                                    fontWeight: FontWeight.bold, 
                                    color: playerColor.toLowerCase() == 'blue' 
                                        ? Colors.blue 
                                        : (playerColor.toLowerCase() == 'green' ? Colors.green : Colors.red),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      "PUZZLE CONFIGURATIONS:",
                      style: TextStyle(fontFamily: 'DynaPuff', fontSize: 10, color: AppColors.secondaryText, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    // Match configuration list rows
                    ...List.generate(matchCount, (i) {
                      final src = boardSources[i];
                      String sizeStr = "";
                      if (src == 'auto') {
                        sizeStr = "${selectedSizes[i]}x${selectedSizes[i]}";
                      } else if (src == 'library' && selectedLibraryBoards[i] != null) {
                        final boardObj = selectedLibraryBoards[i]!['board'];
                        if (boardObj is String) {
                          sizeStr = boardObj;
                        } else {
                          try {
                            sizeStr = (boardObj as dynamic).size;
                          } catch (_) {
                            sizeStr = boardObj.toString();
                          }
                        }
                      }
                      final name = src == 'library' && selectedLibraryBoards[i] != null ? "\"${selectedLibraryBoards[i]!['name']}\"" : "";
                      return Container(
                        margin: const EdgeInsets.only(bottom: 6),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.paperLine, width: 1.5),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              src == 'auto' ? Icons.auto_awesome : Icons.emoji_events_rounded,
                              size: 16,
                              color: src == 'auto' ? Colors.purple : AppColors.gold,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                "Match ${i + 1}: ${src == 'auto' ? 'Auto Generate ($sizeStr)' : 'Library $name'}",
                                style: const TextStyle(fontFamily: 'Comfortaa', fontSize: 11, color: AppColors.darkText, fontWeight: FontWeight.bold),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                    const SizedBox(height: 25),
                    // Actions buttons Row
                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: onCancel,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: AppColors.navyBlue, width: 2),
                                boxShadow: const [
                                  BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2)),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                "ABORT",
                                style: TextStyle(fontFamily: 'DynaPuff', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: onConfirm,
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              decoration: BoxDecoration(
                                color: AppColors.gold,
                                borderRadius: BorderRadius.circular(15),
                                border: Border.all(color: AppColors.navyBlue, width: 2),
                                boxShadow: const [
                                  BoxShadow(color: AppColors.navyBlue, offset: Offset(2, 2)),
                                ],
                              ),
                              alignment: Alignment.center,
                              child: const Text(
                                "LET'S GO!",
                                style: TextStyle(fontFamily: 'DynaPuff', fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.navyBlue),
                              ),
                            ),
                          ),
                        ),
                      ],
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
