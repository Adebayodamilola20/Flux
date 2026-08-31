import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Each provider's own mark, drawn as vector paths.
///
/// Drawn rather than bundled as image assets for two reasons: a path stays
/// crisp at any size on any Retina factor without shipping several rasters
/// each, and a single brand colour keeps it recognisable in compact UI. The
/// shapes follow each company's published mark so the card is recognisably
/// theirs.
///
/// These are trademarks of their respective owners, used here only to identify
/// the service a card connects to.
abstract final class ProviderLogos {
  /// The provider's brand colour in app chrome.
  static Color? brandColorFor(String providerId) {
    return switch (providerId) {
      'chatgpt' || 'codex' => const Color(0xFF10A37F),
      'openrouter' => const Color(0xFF6467F2),
      'claude' => const Color(0xFFD97757),
      'gemini' => const Color(0xFF9168F0),
      'antigravity' => const Color(0xFF4285F4),
      'reserved' => const Color(0xFF8A8A8E),
      _ => null,
    };
  }

  /// Returns the mark for a provider, or null when there is no drawn logo.
  static CustomPainter? painterFor(String providerId, Color color) {
    return switch (providerId) {
      'claude' => _SvgLogoPainter(
        pathData: _claudePath,
        viewBox: const Size(16, 16),
        color: color,
      ),
      'chatgpt' || 'codex' => _SvgLogoPainter(
        pathData: _openAiPath,
        viewBox: const Size(16, 16),
        color: color,
      ),
      'gemini' => _SvgLogoPainter(
        pathData: _geminiPath,
        viewBox: const Size(24, 24),
        color: color,
      ),
      'antigravity' => _AntigravityMark(color),
      _ => null,
    };
  }
}

// Brand paths from Bootstrap Icons/Simple Icons compatible sources. Trademarks
// remain the property of their owners; these marks identify the services.
const _claudePath =
    'm3.127 10.604 3.135-1.76.053-.153-.053-.085H6.11l-.525-.032-1.791-.048-1.554-.065-1.505-.08-.38-.081L0 7.832l.036-.234.32-.214.455.04 1.009.069 1.513.105 1.097.064 1.626.17h.259l.036-.105-.089-.065-.068-.064-1.566-1.062-1.695-1.121-.887-.646-.48-.327-.243-.306-.104-.67.435-.48.585.04.15.04.593.456 1.267.981 1.654 1.218.242.202.097-.068.012-.049-.109-.181-.9-1.626-.96-1.655-.428-.686-.113-.411a2 2 0 0 1-.068-.484l.496-.674L4.446 0l.662.089.279.242.411.94.666 1.48 1.033 2.014.302.597.162.553.06.17h.105v-.097l.085-1.134.157-1.392.154-1.792.052-.504.25-.605.497-.327.387.186.319.456-.045.294-.19 1.23-.37 1.93-.243 1.29h.142l.161-.16.654-.868 1.097-1.372.484-.545.565-.601.363-.287h.686l.505.751-.226.775-.707.895-.585.759-.839 1.13-.524.904.048.072.125-.012 1.897-.403 1.024-.186 1.223-.21.553.258.06.263-.218.536-1.307.323-1.533.307-2.284.54-.028.02.032.04 1.029.098.44.024h1.077l2.005.15.525.346.315.424-.053.323-.807.411-3.631-.863-.872-.218h-.12v.073l.726.71 1.331 1.202 1.667 1.55.084.383-.214.302-.226-.032-1.464-1.101-.565-.497-1.28-1.077h-.084v.113l.295.432 1.557 2.34.08.718-.112.234-.404.141-.444-.08-.911-1.28-.94-1.44-.759-1.291-.093.053-.448 4.821-.21.246-.484.186-.403-.307-.214-.496.214-.98.258-1.28.21-1.016.19-1.263.112-.42-.008-.028-.092.012-.953 1.307-1.448 1.957-1.146 1.227-.274.109-.477-.247.045-.44.266-.39 1.586-2.018.956-1.25.617-.723-.004-.105h-.036l-4.212 2.736-.75.096-.324-.302.04-.496.154-.162 1.267-.871z';

const _openAiPath =
    'M14.949 6.547a3.94 3.94 0 0 0-.348-3.273 4.11 4.11 0 0 0-4.4-1.934A4.1 4.1 0 0 0 8.423.2 4.15 4.15 0 0 0 6.305.086a4.1 4.1 0 0 0-1.891.948 4.04 4.04 0 0 0-1.158 1.753 4.1 4.1 0 0 0-1.563.679A4 4 0 0 0 .554 4.72a3.99 3.99 0 0 0 .502 4.731 3.94 3.94 0 0 0 .346 3.274 4.11 4.11 0 0 0 4.402 1.933c.382.425.852.764 1.377.995.526.231 1.095.35 1.67.346 1.78.002 3.358-1.132 3.901-2.804a4.1 4.1 0 0 0 1.563-.68 4 4 0 0 0 1.14-1.253 3.99 3.99 0 0 0-.506-4.716m-6.097 8.406a3.05 3.05 0 0 1-1.945-.694l.096-.054 3.23-1.838a.53.53 0 0 0 .265-.455v-4.49l1.366.778q.02.011.025.035v3.722c-.003 1.653-1.361 2.992-3.037 2.996m-6.53-2.75a2.95 2.95 0 0 1-.36-2.01l.095.057L5.29 12.09a.53.53 0 0 0 .527 0l3.949-2.246v1.555a.05.05 0 0 1-.022.041L6.473 13.3c-1.454.826-3.311.335-4.15-1.098m-.85-6.94A3.02 3.02 0 0 1 3.07 3.949v3.785a.51.51 0 0 0 .262.451l3.93 2.237-1.366.779a.05.05 0 0 1-.048 0L2.585 9.342a2.98 2.98 0 0 1-1.113-4.094zm11.216 2.571L8.747 5.576l1.362-.776a.05.05 0 0 1 .048 0l3.265 1.86a3 3 0 0 1 1.173 1.207 2.96 2.96 0 0 1-.27 3.2 3.05 3.05 0 0 1-1.36.997V8.279a.52.52 0 0 0-.276-.445m1.36-2.015-.097-.057-3.226-1.855a.53.53 0 0 0-.53 0L6.249 6.153V4.598a.04.04 0 0 1 .019-.04L9.533 2.7a3.07 3.07 0 0 1 3.257.139c.474.325.843.778 1.066 1.303.223.526.289 1.103.191 1.664zM5.503 8.575 4.139 7.8a.05.05 0 0 1-.026-.037V4.049c0-.57.166-1.127.476-1.607s.752-.864 1.275-1.105a3.08 3.08 0 0 1 3.234.41l-.096.054-3.23 1.838a.53.53 0 0 0-.265.455zm.742-1.577 1.758-1 1.762 1v2l-1.755 1-1.762-1z';

const _geminiPath =
    'M11.04 19.32Q12 21.51 12 24q0-2.49.93-4.68.96-2.19 2.58-3.81t3.81-2.55Q21.51 12 24 12q-2.49 0-4.68-.93a12.3 12.3 0 0 1-3.81-2.58 12.3 12.3 0 0 1-2.58-3.81Q12 2.49 12 0q0 2.49-.96 4.68-.93 2.19-2.55 3.81a12.3 12.3 0 0 1-3.81 2.58Q2.49 12 0 12q2.49 0 4.68.96 2.19.93 3.81 2.55t2.55 3.81';

class _SvgLogoPainter extends CustomPainter {
  const _SvgLogoPainter({
    required this.pathData,
    required this.viewBox,
    required this.color,
  });

  final String pathData;
  final Size viewBox;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || viewBox.isEmpty) return;

    final scale = math.min(
      size.width / viewBox.width,
      size.height / viewBox.height,
    );
    final dx = (size.width - viewBox.width * scale) / 2;
    final dy = (size.height - viewBox.height * scale) / 2;

    canvas
      ..save()
      ..translate(dx, dy)
      ..scale(scale);
    canvas.drawPath(_SvgPathData.parse(pathData), Paint()..color = color);
    canvas.restore();
  }

  @override
  bool shouldRepaint(_SvgLogoPainter old) =>
      old.pathData != pathData || old.viewBox != viewBox || old.color != color;
}

class _SvgPathData {
  _SvgPathData(String data) : _tokens = _tokenize(data);

  final List<String> _tokens;
  var _index = 0;
  var _x = 0.0;
  var _y = 0.0;
  var _subpathX = 0.0;
  var _subpathY = 0.0;
  String? _command;
  Offset? _lastCubicControl;
  Offset? _lastQuadControl;

  static Path parse(String data) => _SvgPathData(data)._parse();

  static final _tokenPattern = RegExp(
    r'[MmZzLlHhVvCcSsQqTtAa]|[-+]?(?:(?:\d+\.?\d*)|(?:\.\d+))(?:[eE][-+]?\d+)?',
  );

  static List<String> _tokenize(String data) =>
      _tokenPattern.allMatches(data).map((m) => m.group(0)!).toList();

  bool get _done => _index >= _tokens.length;
  bool get _hasNumber => !_done && !_isCommand(_tokens[_index]);

  static bool _isCommand(String token) =>
      token.length == 1 && RegExp(r'[A-Za-z]').hasMatch(token);

  double _nextNumber() => double.parse(_tokens[_index++]);

  bool _nextFlag() => _nextNumber() != 0;

  Path _parse() {
    final path = Path();

    while (!_done) {
      if (_isCommand(_tokens[_index])) {
        _command = _tokens[_index++];
      }
      final command = _command;
      if (command == null) break;

      switch (command) {
        case 'M':
        case 'm':
          _move(path, command == 'm');
          break;
        case 'L':
        case 'l':
          _line(path, command == 'l');
          break;
        case 'H':
        case 'h':
          _horizontal(path, command == 'h');
          break;
        case 'V':
        case 'v':
          _vertical(path, command == 'v');
          break;
        case 'C':
        case 'c':
          _cubic(path, command == 'c');
          break;
        case 'S':
        case 's':
          _smoothCubic(path, command == 's');
          break;
        case 'Q':
        case 'q':
          _quadratic(path, command == 'q');
          break;
        case 'T':
        case 't':
          _smoothQuadratic(path, command == 't');
          break;
        case 'A':
        case 'a':
          _arc(path, command == 'a');
          break;
        case 'Z':
        case 'z':
          path.close();
          _x = _subpathX;
          _y = _subpathY;
          _clearControls();
          break;
        default:
          _index++;
          break;
      }
    }

    return path;
  }

  void _move(Path path, bool relative) {
    if (!_hasNumber) return;
    final p = _point(relative);
    path.moveTo(p.dx, p.dy);
    _x = _subpathX = p.dx;
    _y = _subpathY = p.dy;
    _clearControls();

    while (_hasNumber) {
      final line = _point(relative);
      path.lineTo(line.dx, line.dy);
      _x = line.dx;
      _y = line.dy;
    }
    _command = relative ? 'l' : 'L';
  }

  void _line(Path path, bool relative) {
    while (_hasNumber) {
      final p = _point(relative);
      path.lineTo(p.dx, p.dy);
      _x = p.dx;
      _y = p.dy;
      _clearControls();
    }
  }

  void _horizontal(Path path, bool relative) {
    while (_hasNumber) {
      final x = _nextNumber() + (relative ? _x : 0);
      path.lineTo(x, _y);
      _x = x;
      _clearControls();
    }
  }

  void _vertical(Path path, bool relative) {
    while (_hasNumber) {
      final y = _nextNumber() + (relative ? _y : 0);
      path.lineTo(_x, y);
      _y = y;
      _clearControls();
    }
  }

  void _cubic(Path path, bool relative) {
    while (_hasNumber) {
      final c1 = _point(relative);
      final c2 = _point(relative);
      final p = _point(relative);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
      _x = p.dx;
      _y = p.dy;
      _lastCubicControl = c2;
      _lastQuadControl = null;
    }
  }

  void _smoothCubic(Path path, bool relative) {
    while (_hasNumber) {
      final c1 = _lastCubicControl == null
          ? Offset(_x, _y)
          : Offset(
              _x * 2 - _lastCubicControl!.dx,
              _y * 2 - _lastCubicControl!.dy,
            );
      final c2 = _point(relative);
      final p = _point(relative);
      path.cubicTo(c1.dx, c1.dy, c2.dx, c2.dy, p.dx, p.dy);
      _x = p.dx;
      _y = p.dy;
      _lastCubicControl = c2;
      _lastQuadControl = null;
    }
  }

  void _quadratic(Path path, bool relative) {
    while (_hasNumber) {
      final c = _point(relative);
      final p = _point(relative);
      path.quadraticBezierTo(c.dx, c.dy, p.dx, p.dy);
      _x = p.dx;
      _y = p.dy;
      _lastQuadControl = c;
      _lastCubicControl = null;
    }
  }

  void _smoothQuadratic(Path path, bool relative) {
    while (_hasNumber) {
      final c = _lastQuadControl == null
          ? Offset(_x, _y)
          : Offset(
              _x * 2 - _lastQuadControl!.dx,
              _y * 2 - _lastQuadControl!.dy,
            );
      final p = _point(relative);
      path.quadraticBezierTo(c.dx, c.dy, p.dx, p.dy);
      _x = p.dx;
      _y = p.dy;
      _lastQuadControl = c;
      _lastCubicControl = null;
    }
  }

  void _arc(Path path, bool relative) {
    while (_hasNumber) {
      final rx = _nextNumber();
      final ry = _nextNumber();
      final rotation = _nextNumber();
      final largeArc = _nextFlag();
      final sweep = _nextFlag();
      final end = _point(relative);

      _drawArc(path, rx, ry, rotation, largeArc, sweep, end.dx, end.dy);
      _x = end.dx;
      _y = end.dy;
      _clearControls();
    }
  }

  Offset _point(bool relative) {
    final x = _nextNumber();
    final y = _nextNumber();
    return Offset(x + (relative ? _x : 0), y + (relative ? _y : 0));
  }

  void _clearControls() {
    _lastCubicControl = null;
    _lastQuadControl = null;
  }

  void _drawArc(
    Path path,
    double rx,
    double ry,
    double rotation,
    bool largeArc,
    bool sweep,
    double endX,
    double endY,
  ) {
    final startX = _x;
    final startY = _y;

    if ((startX - endX).abs() < 1e-10 && (startY - endY).abs() < 1e-10) {
      return;
    }
    rx = rx.abs();
    ry = ry.abs();
    if (rx == 0 || ry == 0) {
      path.lineTo(endX, endY);
      return;
    }

    final phi = rotation * math.pi / 180;
    final cosPhi = math.cos(phi);
    final sinPhi = math.sin(phi);
    final dx = (startX - endX) / 2;
    final dy = (startY - endY) / 2;
    final x1p = cosPhi * dx + sinPhi * dy;
    final y1p = -sinPhi * dx + cosPhi * dy;

    final radiusScale = x1p * x1p / (rx * rx) + y1p * y1p / (ry * ry);
    if (radiusScale > 1) {
      final scale = math.sqrt(radiusScale);
      rx *= scale;
      ry *= scale;
    }

    final rx2 = rx * rx;
    final ry2 = ry * ry;
    final x1p2 = x1p * x1p;
    final y1p2 = y1p * y1p;
    final numerator = math.max(0, rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2);
    final denominator = rx2 * y1p2 + ry2 * x1p2;
    final sign = largeArc == sweep ? -1.0 : 1.0;
    final coef = denominator == 0
        ? 0.0
        : sign * math.sqrt(numerator / denominator);
    final cxp = coef * (rx * y1p / ry);
    final cyp = coef * (-ry * x1p / rx);
    final cx = cosPhi * cxp - sinPhi * cyp + (startX + endX) / 2;
    final cy = sinPhi * cxp + cosPhi * cyp + (startY + endY) / 2;

    final startVector = Offset((x1p - cxp) / rx, (y1p - cyp) / ry);
    final endVector = Offset((-x1p - cxp) / rx, (-y1p - cyp) / ry);
    final startAngle = _vectorAngle(const Offset(1, 0), startVector);
    var sweepAngle = _vectorAngle(startVector, endVector);

    if (!sweep && sweepAngle > 0) sweepAngle -= 2 * math.pi;
    if (sweep && sweepAngle < 0) sweepAngle += 2 * math.pi;

    final segments = math.max(1, (sweepAngle.abs() / (math.pi / 2)).ceil());
    final step = sweepAngle / segments;
    for (var i = 0; i < segments; i++) {
      final a1 = startAngle + i * step;
      final a2 = a1 + step;
      _arcSegmentTo(path, cx, cy, rx, ry, cosPhi, sinPhi, a1, a2);
    }
  }

  static double _vectorAngle(Offset u, Offset v) {
    final dot = u.dx * v.dx + u.dy * v.dy;
    final len = math.sqrt(
      (u.dx * u.dx + u.dy * u.dy) * (v.dx * v.dx + v.dy * v.dy),
    );
    final ratio = len == 0 ? 0.0 : (dot / len).clamp(-1.0, 1.0);
    final sign = u.dx * v.dy - u.dy * v.dx < 0 ? -1.0 : 1.0;
    return sign * math.acos(ratio);
  }

  static void _arcSegmentTo(
    Path path,
    double cx,
    double cy,
    double rx,
    double ry,
    double cosPhi,
    double sinPhi,
    double a1,
    double a2,
  ) {
    final delta = a2 - a1;
    final alpha = 4 / 3 * math.tan(delta / 4);

    Offset point(double angle) => Offset(
      cx + rx * cosPhi * math.cos(angle) - ry * sinPhi * math.sin(angle),
      cy + rx * sinPhi * math.cos(angle) + ry * cosPhi * math.sin(angle),
    );

    Offset derivative(double angle) => Offset(
      -rx * cosPhi * math.sin(angle) - ry * sinPhi * math.cos(angle),
      -rx * sinPhi * math.sin(angle) + ry * cosPhi * math.cos(angle),
    );

    final p1 = point(a1);
    final p2 = point(a2);
    final d1 = derivative(a1);
    final d2 = derivative(a2);

    path.cubicTo(
      p1.dx + alpha * d1.dx,
      p1.dy + alpha * d1.dy,
      p2.dx - alpha * d2.dx,
      p2.dy - alpha * d2.dy,
      p2.dx,
      p2.dy,
    );
  }
}

/// Antigravity's mark: an upward chevron over a base, drawn as an outline.
class _AntigravityMark extends CustomPainter {
  const _AntigravityMark(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    if (w <= 0 || h <= 0) return;

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.13
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // A rising chevron: the "anti-gravity" idea, and distinct at a glance from
    // the other three marks in the stack.
    canvas
      ..drawPath(
        Path()
          ..moveTo(w * 0.16, h * 0.56)
          ..lineTo(w * 0.5, h * 0.16)
          ..lineTo(w * 0.84, h * 0.56),
        paint,
      )
      ..drawPath(
        Path()
          ..moveTo(w * 0.16, h * 0.86)
          ..lineTo(w * 0.5, h * 0.46)
          ..lineTo(w * 0.84, h * 0.86),
        paint,
      );
  }

  @override
  bool shouldRepaint(_AntigravityMark old) => old.color != color;
}
