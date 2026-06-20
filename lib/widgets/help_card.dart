import 'package:flutter/material.dart';
import '../constants/colors.dart';

/// Funky "How It Works" explainer card used at the bottom of mostly-empty
/// solver / create / generate screens. The card sticks to the app's
/// notebook-app theme: DynaPuff headlines, slight sticker rotation, sharp
/// navy shadow, Comfortaa body.
///
/// Pass [kind] to pick the variant; each variant ships with copy tuned to
/// the screen it lives on so users never feel they're reading generic
/// marketing fluff.
enum HelpKind {
  /// For the manual-solving / play screen — what N-Queens is, what the
  /// three big buttons do, how marks + queens work.
  play,

  /// For the AI-solver mode — what watching the algorithm looks like,
  /// what the timeline at the bottom means.
  aiSolver,

  /// For the create-board screen — what regions mean, why they matter.
  create,

  /// For the generate-board screen — what makes a generated puzzle fair.
  generate,
}

class HelpCard extends StatelessWidget {
  final HelpKind kind;

  /// Slight sticker tilt. Defaults to 0.01 so the card looks pasted-on
  /// rather than machine-rendered.
  final double rotation;

  /// When true the card is initially collapsed to just the title row.
  final bool initiallyCollapsed;

  const HelpCard({
    super.key,
    required this.kind,
    this.rotation = 0.01,
    this.initiallyCollapsed = false,
  });

  @override
  Widget build(BuildContext context) {
    return _HelpCardBody(
      kind: kind,
      rotation: rotation,
      initiallyCollapsed: initiallyCollapsed,
    );
  }
}

class _HelpCardBody extends StatefulWidget {
  final HelpKind kind;
  final double rotation;
  final bool initiallyCollapsed;

  const _HelpCardBody({
    required this.kind,
    required this.rotation,
    required this.initiallyCollapsed,
  });

  @override
  State<_HelpCardBody> createState() => _HelpCardBodyState();
}

class _HelpCardBodyState extends State<_HelpCardBody> {
  late bool _expanded;

  @override
  void initState() {
    super.initState();
    _expanded = !widget.initiallyCollapsed;
  }

  @override
  Widget build(BuildContext context) {
    final copy = _copyFor(widget.kind);
    return Transform.rotate(
      angle: widget.rotation,
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFFDE7), // warm paper yellow
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppColors.navyBlue, width: 2.5),
          boxShadow: [
            BoxShadow(
              color: AppColors.navyBlue.withValues(alpha: 0.18),
              offset: const Offset(5, 5),
              blurRadius: 0,
            ),
          ],
        ),
        child: Column(
          children: [
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => setState(() => _expanded = !_expanded),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: const BoxDecoration(
                        color: AppColors.gold,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(copy.icon, color: AppColors.navyBlue, size: 22),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        copy.title,
                        style: const TextStyle(
                          fontFamily: 'DynaPuff',
                          color: AppColors.navyBlue,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 200),
                      child: const Icon(
                        Icons.expand_more_rounded,
                        color: AppColors.navyBlue,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              alignment: Alignment.topCenter,
              child: _expanded
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Divider(color: Colors.black12, thickness: 1),
                          const SizedBox(height: 8),
                          ...copy.bullets.map(
                            (b) => Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: _BulletRow(bullet: b),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
          ],
        ),
      ),
    );
  }
}

class _Copy {
  final String title;
  final IconData icon;
  final List<_Bullet> bullets;

  _Copy({required this.title, required this.icon, required this.bullets});
}

class _Bullet {
  final String headline;
  final String body;

  _Bullet({required this.headline, required this.body});
}

class _BulletRow extends StatelessWidget {
  final _Bullet bullet;

  const _BulletRow({required this.bullet});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4, right: 8),
          child: Icon(Icons.fiber_manual_record, size: 8, color: AppColors.navyBlue),
        ),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Comfortaa',
                color: AppColors.darkText,
                fontSize: 13.5,
                height: 1.45,
              ),
              children: [
                TextSpan(
                  text: '${bullet.headline} ',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: AppColors.navyBlue,
                  ),
                ),
                TextSpan(text: bullet.body),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

_Copy _copyFor(HelpKind kind) {
  switch (kind) {
    case HelpKind.play:
      return _Copy(
        title: 'How this works',
        icon: Icons.help_outline_rounded,
        bullets: [
          _Bullet(
            headline: 'Goal —',
            body:
                'place exactly one queen in every row, every column, and every coloured region. No two queens may touch, even diagonally.',
          ),
          _Bullet(
            headline: 'Tap a cell —',
            body:
                'first tap puts an ✕ (cross-out), second tap puts the 👑 queen, third tap clears it. Use ✕ to mark ruled-out cells so you can see your thinking.',
          ),
          _Bullet(
            headline: 'Solve —',
            body:
                'watches the AI try every combination step by step. Use it when you\'re stuck, or fast-forward with the ⏩ button.',
          ),
          _Bullet(
            headline: 'Edit —',
            body:
                'repaints the regions if a cell shows a Funky-X. Each colour must form one connected shape covering the whole board.',
          ),
          _Bullet(
            headline: 'Do it —',
            body:
                'play the puzzle yourself on a timer. Pause any time, quit and come back later — your marks are saved automatically.',
          ),
        ],
      );
    case HelpKind.aiSolver:
      return _Copy(
        title: 'Watching the solver',
        icon: Icons.auto_awesome_rounded,
        bullets: [
          _Bullet(
            headline: 'Green steps —',
            body:
                'the algorithm placed a queen in a column it believes is safe.',
          ),
          _Bullet(
            headline: 'Red steps —',
            body:
                'a backtrack: the last queen was a dead-end so the solver popped it off and tried the next column.',
          ),
          _Bullet(
            headline: 'Timeline —',
            body:
                'the panel at the bottom lists every decision. Scroll it while the solver runs to follow along.',
          ),
          _Bullet(
            headline: 'Fast-forward —',
            body:
                'the ⏩ button collapses the per-step delay to almost zero so you can jump straight to the answer.',
          ),
        ],
      );
    case HelpKind.create:
      return _Copy(
        title: 'Designing your own board',
        icon: Icons.brush_rounded,
        bullets: [
          _Bullet(
            headline: 'Regions —',
            body:
                'group cells into coloured shapes. Each region must hold exactly one queen, so every colour needs exactly one cell in it.',
          ),
          _Bullet(
            headline: 'Pick a size —',
            body:
                'start small (5×5 or 6×6) for your first board — bigger boards need more regions and patience.',
          ),
          _Bullet(
            headline: 'Tap to paint —',
            body:
                'choose a colour on the palette, then tap each cell you want in that region. Tap Save when every cell has a colour.',
          ),
          _Bullet(
            headline: 'Connectivity —',
            body:
                'each region must be a single connected shape — you can\'t split a colour into two islands.',
          ),
        ],
      );
    case HelpKind.generate:
      return _Copy(
        title: 'How generation works',
        icon: Icons.shuffle_rounded,
        bullets: [
          _Bullet(
            headline: 'AI Masterpiece —',
            body:
                'we shuffle a known-good solution until every cell carries a unique colour, then hide the queen positions so you can solve it yourself.',
          ),
          _Bullet(
            headline: 'Pick a size —',
            body:
                'drag the slider between 4×4 (a quick warm-up) and 12×12 (a real brain-burner).',
          ),
          _Bullet(
            headline: 'Stuck? —',
            body:
                'the generated board is guaranteed solvable, so just press Solve on the next screen and watch the algorithm prove it.',
          ),
        ],
      );
  }
}
