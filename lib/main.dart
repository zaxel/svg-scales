import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lottie/lottie.dart';

void main() {
  runApp(const ScaleTestApp());
}

class ScaleTestApp extends StatelessWidget {
  const ScaleTestApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Balance Scale Test',
      theme: ThemeData(
        brightness: Brightness.light,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.black,
          brightness: Brightness.light,
        ),
        textTheme: const TextTheme(
          bodyMedium: TextStyle(color: Colors.black),
          bodySmall: TextStyle(color: Colors.black54),
        ),
      ),
      home: const ScaleTestPage(),
    );
  }
}

class ScaleTestPage extends StatefulWidget {
  const ScaleTestPage({super.key});

  @override
  State<ScaleTestPage> createState() => _ScaleTestPageState();
}

class _ScaleTestPageState extends State<ScaleTestPage>
    with TickerProviderStateMixin {
  int leftBalls = 3;
  int rightBalls = 3;

  // Counts at the start/end of the in-flight transition — used to fade
  // only the balls whose presence actually changed, while every
  // unaffected ball stays at a constant opacity.
  int _fromLeftBalls = 3;
  int _toLeftBalls = 3;
  int _fromRightBalls = 3;
  int _toRightBalls = 3;

  late final AnimationController _rotationController;
  late final AnimationController _opacityController;

  double _fromAngle = 0;
  double _toAngle = 0;

  // Safety ceiling, not a design target — while degreesPerBallDiff is
  // still being tuned, this just stops an extreme count difference from
  // sending the beam somewhere the artwork was never meant to render
  // (chains overlapping the base, plates swinging off-canvas). Raise it
  // if you deliberately want steeper tilts; it's not meant to be the
  // angle you're aiming for day to day.
  static const double maxAngle = 90.0;

  // Degrees of tilt per unit difference between left/right ball counts.
  // Currently being tuned — was 7.0, now 6.0.
  static const double degreesPerBallDiff = 5.0;

  // Beam fulcrum, in the same composition-pixel space as the Lottie JSON
  // (matches the "p"/"a" values on the BEAM / STATIC SCALE layers).
  static const Offset fulcrum = Offset(996.0, 227.65);

  // Distance from the fulcrum to where each chain actually attaches on
  // the beam. Approximated from the ball-cluster x-offsets in the JSON
  // (~714px) — verify against the real beam artwork and tune if the
  // plates don't line up under the beam ends when you eyeball it.
  static const double armRadius = 714.0;

  // Vertical drop from the fulcrum down to where each chain attaches.
  // The beam isn't flat — it peaks at the pole/fulcrum, so both
  // attachment points sit BELOW that peak by roughly the same amount.
  // This offset is what was missing: it's the same sign on both sides
  // (both attach points are below the peak), so when the beam rotates
  // it doesn't cancel out between left/right the way the horizontal
  // radius does — it's exactly what was producing the asymmetric X
  // shift. Starting guess — tune against the real artwork.
  static const double armVerticalOffset = 180.0;

  // Artistic exaggeration on top of the physically-correct X shift.
  // The real (1 - cos(angle)) term stays modest even at large tilts, so
  // this multiplies just the X component to make the sideways swing
  // read more dramatically on screen. This is a stylization knob, not
  // physics — 1.0 = true to the math, higher = more exaggerated swing.
  static const double xSwingExaggeration = 1.0;

  // Duration of the beam/plate/chain translation between positions.
  static const Duration positionDuration = Duration(milliseconds: 1100);

  // Duration of the ball fade in/out — deliberately much shorter than
  // positionDuration so balls appear/disappear quickly while the beam
  // is still easing into its new tilt.
  static const Duration opacityDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();

    _rotationController = AnimationController(
      vsync: this,
      duration: positionDuration,
      value: 1,
      // Without this, AnimationController.forward() checks the
      // platform's global "reduce motion" accessibility flag
      // (AccessibilityFeatures.disableAnimations) and, if it's set,
      // collapses the duration to near-zero — jumping straight to the
      // end value instead of interpolating. That's independent of
      // anything in the widget tree (a MediaQuery override doesn't
      // reach it), so this is the actual fix, not a workaround.
      animationBehavior: AnimationBehavior.preserve,
    );

    _rotationController.addListener(() {
      setState(() {});
    });

    _opacityController = AnimationController(
      vsync: this,
      duration: opacityDuration,
      value: 1,
      animationBehavior: AnimationBehavior.preserve,
    );

    _opacityController.addListener(() {
      setState(() {});
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _opacityController.dispose();
    super.dispose();
  }

  double get _t => Curves.easeOutQuint.transform(_rotationController.value);

  double get _tOpacity =>
      Curves.easeOut.transform(_opacityController.value);

  double get currentAngle {
    final t = _t;
    return _fromAngle + (_toAngle - _fromAngle) * t;
  }

  double angleForCounts(int left, int right) {
    final difference = right - left;
    final raw = difference * degreesPerBallDiff;
    return raw.clamp(-maxAngle, maxAngle);
  }

  /// Position of a plate that hangs on a chain from a beam attachment
  /// point `armDx` pixels horizontally from the fulcrum (negative =
  /// left, positive = right) and `armVerticalOffset` pixels below it
  /// (the beam peaks at the fulcrum rather than being flat), while the
  /// beam is tilted `angleDeg` degrees.
  ///
  /// The chain keeps the plate level under gravity — it never rotates.
  /// Only the attachment point moves: it's rigidly connected to the
  /// beam, so it swings through a full rotation of its
  /// (armDx, armVerticalOffset) offset around the fulcrum. The plate
  /// translates along whatever arc that traces.
  ///
  /// Because armVerticalOffset has the SAME sign on both sides (both
  /// attach points sit below the peak), it does not cancel out between
  /// left/right the way armDx's mirrored sign does — this is what
  /// produces a different-looking swing per side on a peaked beam,
  /// which is physically correct, not a bug.
  Offset _plateAttachPosition(double angleDeg, double armDx) {
    final theta = angleDeg * math.pi / 180.0;
    final cosT = math.cos(theta);
    final sinT = math.sin(theta);

    final rotatedX = armDx * cosT - armVerticalOffset * sinT;
    final rotatedY = armDx * sinT + armVerticalOffset * cosT;

    final dx = (rotatedX - armDx) * xSwingExaggeration;
    final dy = rotatedY - armVerticalOffset;

    return Offset(fulcrum.dx + dx, fulcrum.dy + dy);
  }

  /// Opacity (0-100) for ball `index` on one side, given that side's
  /// count is transitioning from `fromCount` to `toCount`. Balls whose
  /// presence didn't change hold steady; only the delta balls fade,
  /// on their own (shorter) timeline — independent of how long the
  /// beam/plate translation takes.
  ///
  /// transformOpacity expects an int (0-100, matching After Effects),
  /// so the eased fraction is rounded down here rather than left as a
  /// raw double.
  int _ballOpacity(int index, int fromCount, int toCount) {
    if (toCount >= fromCount) {
      if (index < fromCount) return 100;
      if (index < toCount) return (_tOpacity * 100).round();
      return 0;
    } else {
      if (index < toCount) return 100;
      if (index < fromCount) return ((1 - _tOpacity) * 100).round();
      return 0;
    }
  }

  void _setCounts({int? left, int? right}) {
    final newLeft = left ?? leftBalls;
    final newRight = right ?? rightBalls;

    final newAngle = angleForCounts(newLeft, newRight);

    _fromAngle = currentAngle;
    _toAngle = newAngle;

    _fromLeftBalls = leftBalls;
    _toLeftBalls = newLeft;
    _fromRightBalls = rightBalls;
    _toRightBalls = newRight;

    setState(() {
      leftBalls = newLeft;
      rightBalls = newRight;
    });

    _rotationController
      ..stop()
      ..value = 0
      ..forward();

    _opacityController
      ..stop()
      ..value = 0
      ..forward();
  }

  void _reset() {
    _setCounts(left: 0, right: 0);
  }

  @override
  Widget build(BuildContext context) {
    final angle = currentAngle;

    final leftPlatePos = _plateAttachPosition(angle, -armRadius);
    final rightPlatePos = _plateAttachPosition(angle, armRadius);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Balance Scale Test'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: AspectRatio(
                aspectRatio: 2000 / 1991,
                child: Lottie.asset(
                  'assets/lottie/balance_scale_runtime.json',
                  fit: BoxFit.contain,

                  // The JSON's own internal timeline is 1s (ip:0, op:60,
                  // fr:60) and, without this, plays once then stops
                  // ticking entirely — after which Lottie stops
                  // repainting on its own. Our delegate values (angle,
                  // plate position, ball opacity) keep changing every
                  // frame via _rotationController, but with no internal
                  // tick driving a repaint, those updates just sit
                  // unapplied until some unrelated repaint happens to
                  // fire — which is what read as "jumping" regardless
                  // of how long our own animation duration was set to.
                  // repeat: true keeps Lottie's internal clock (and
                  // therefore its repaint loop) running forever, so our
                  // externally-driven values actually animate smoothly.
                  repeat: true,

                  options: LottieOptions(enableApplyingOpacityToLayers: true),

                  delegates: LottieDelegates(
                    values: [
                      // Only the beam itself rotates around the fulcrum.
                      ValueDelegate.transformRotation(const [
                        'BEAM',
                      ], value: angle),

                      // Plates + chains never rotate — gravity keeps them
                      // plumb. They translate along the arc traced by
                      // their attachment point on the rotating beam.
                      // Balls are parented to these layers in the JSON,
                      // so they follow the same translation and also
                      // stay level.
                      ValueDelegate.transformPosition(const [
                        'LEFT PLATE + CHAINS',
                      ], value: leftPlatePos),
                      ValueDelegate.transformPosition(const [
                        'RIGHT PLATE + CHAINS',
                      ], value: rightPlatePos),

                      // Front-of-plate layer, rendered above the balls
                      // in the JSON's layer order so it occludes their
                      // bottom edge — that's what reads as "balls
                      // sitting inside the plate" rather than floating
                      // in front of it. It's not parented to the back
                      // plate layer, so it needs the exact same
                      // position value applied directly to stay in
                      // lockstep as one rigid plate.
                      ValueDelegate.transformPosition(const [
                        'LEFT PLATE FRONT',
                      ], value: leftPlatePos),
                      ValueDelegate.transformPosition(const [
                        'RIGHT PLATE FRONT',
                      ], value: rightPlatePos),

                      // Left balls — fade the delta balls in/out on the
                      // same eased timeline as the tilt/position.
                      ...List.generate(
                        6,
                        (i) => ValueDelegate.transformOpacity([
                          'BALL — LEFT ${i + 1}',
                        ], value: _ballOpacity(i, _fromLeftBalls, _toLeftBalls)),
                      ),

                      // Right balls.
                      ...List.generate(
                        6,
                        (i) => ValueDelegate.transformOpacity([
                          'BALL — RIGHT ${i + 1}',
                        ], value: _ballOpacity(i, _fromRightBalls, _toRightBalls)),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

          Container(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 24),
            child: Column(
              children: [
                _BallControl(
                  label: 'LEFT',
                  count: leftBalls,
                  onMinus: leftBalls > 0
                      ? () => _setCounts(left: leftBalls - 1)
                      : null,
                  onPlus: leftBalls < 6
                      ? () => _setCounts(left: leftBalls + 1)
                      : null,
                ),
                const SizedBox(height: 10),
                _BallControl(
                  label: 'RIGHT',
                  count: rightBalls,
                  onMinus: rightBalls > 0
                      ? () => _setCounts(right: rightBalls - 1)
                      : null,
                  onPlus: rightBalls < 6
                      ? () => _setCounts(right: rightBalls + 1)
                      : null,
                ),
                const SizedBox(height: 10),
                Text(
                  'Left: $leftBalls   Right: $rightBalls   '
                  'Angle: ${angle.toStringAsFixed(1)}°',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                OutlinedButton(onPressed: _reset, child: const Text('RESET')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BallControl extends StatelessWidget {
  final String label;
  final int count;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  const _BallControl({
    required this.label,
    required this.count,
    required this.onMinus,
    required this.onPlus,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 70,
          child: Text(
            label,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        IconButton(
          onPressed: onMinus,
          icon: const Icon(Icons.remove_circle_outline),
        ),
        SizedBox(
          width: 42,
          child: Center(
            child: Text(
              '$count',
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
          ),
        ),
        IconButton(
          onPressed: onPlus,
          icon: const Icon(Icons.add_circle_outline),
        ),
        const Spacer(),
        Text('$count / 6'),
      ],
    );
  }
}