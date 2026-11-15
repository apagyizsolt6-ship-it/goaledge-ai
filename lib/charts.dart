import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'models.dart';

class TeamLogoBadge extends StatelessWidget {
  final int? teamId;
  final String teamName;
  final String baseUrl;
  final String apiKey;
  final double size;

  const TeamLogoBadge({
    super.key,
    required this.teamId,
    required this.teamName,
    required this.baseUrl,
    required this.apiKey,
    this.size = 24,
  });

  String get _initials {
    final parts = teamName.trim().split(' ');
    if (parts.length >= 2 && parts[0].isNotEmpty && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return teamName.length >= 2 ? teamName.substring(0, 2).toUpperCase() : 'FC';
  }

  Widget _fallback() {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFF1F2937),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFF374151), width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        _initials,
        style: TextStyle(fontSize: size * 0.38, fontWeight: FontWeight.bold, color: const Color(0xFF9CA3AF)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (teamId == null || teamId == 0 || apiKey.trim().isEmpty) {
      return _fallback();
    }
    final cleanBase = baseUrl.trim().replaceAll(RegExp(r'/$'), '');
    final logoUrl = '$cleanBase/teams/$teamId/logo';

    return ClipOval(
      child: Image.network(
        logoUrl,
        width: size,
        height: size,
        fit: BoxFit.contain,
        headers: {'X-Api-Key': apiKey.trim()},
        errorBuilder: (_, __, ___) => _fallback(),
      ),
    );
  }
}

class WdlStrip extends StatelessWidget {
  final StringList codes;

  const WdlStrip({super.key, required this.codes});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: codes.take(5).map((c) {
        final up = c.toUpperCase();
        Color bg = const Color(0xFF374151);
        String hu = 'D';
        if (up == 'W') {
          bg = const Color(0xFF10B981);
          hu = 'GY';
        } else if (up == 'L') {
          bg = const Color(0xFFEF4444);
          hu = 'V';
        }
        return Container(
          margin: const EdgeInsets.only(right: 3),
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
          child: Text(
            hu,
            style: TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.bold,
              color: up == 'W' ? Colors.black : Colors.white,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class OddsHistoryPainter extends CustomPainter {
  final DoubleList values;
  final double fairOdds;

  OddsHistoryPainter(this.values, this.fairOdds);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final pts = values.length == 1 ? [values.first, values.first] : values;

    double minVal = math.min(fairOdds, pts.reduce((a, b) => a < b ? a : b)) - 0.05;
    double maxVal = math.max(fairOdds, pts.reduce((a, b) => a > b ? a : b)) + 0.05;
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final fairY = size.height - (((fairOdds - minVal) / range) * size.height);
    final fairPaint = Paint()
      ..color = const Color(0xFF3B82F6)
      ..strokeWidth = 1.2;
    for (double x = 0; x < size.width; x += 8) {
      canvas.drawLine(Offset(x, fairY), Offset(math.min(x + 4, size.width), fairY), fairPaint);
    }

    final dropping = pts.last <= pts.first;
    final linePaint = Paint()
      ..color = dropping ? const Color(0xFF10B981) : const Color(0xFFF59E0B)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;

    final dotPaint = Paint()
      ..color = dropping ? const Color(0xFF10B981) : const Color(0xFFF59E0B)
      ..style = PaintingStyle.fill;

    final path = Path();
    for (int i = 0; i < pts.length; i++) {
      final x = (i / (pts.length - 1)) * size.width;
      final y = size.height - (((pts[i] - minVal) / range) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      canvas.drawCircle(Offset(x, y), 3.0, dotPaint);
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class RoiCurvePainter extends CustomPainter {
  final DoubleList values;

  RoiCurvePainter(this.values);

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final minVal = math.min(0.0, values.reduce((a, b) => a < b ? a : b));
    final maxVal = math.max(0.0, values.reduce((a, b) => a > b ? a : b));
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final zeroY = size.height - (((0.0 - minVal) / range) * size.height);
    final zeroPaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, zeroY), Offset(size.width, zeroY), zeroPaint);

    final isPositive = values.last >= 0;
    final linePaint = Paint()
      ..color = isPositive ? const Color(0xFF10B981) : const Color(0xFFEF4444)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;

    final path = Path();
    for (int i = 0; i < values.length; i++) {
      final x = (i / (values.length - 1)) * size.width;
      final y = size.height - (((values[i] - minVal) / range) * size.height);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, linePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class DailyProfitBarPainter extends CustomPainter {
  final DoubleList dailyProfits;

  DailyProfitBarPainter(this.dailyProfits);

  @override
  void paint(Canvas canvas, Size size) {
    if (dailyProfits.isEmpty) return;
    double maxAbs = 100.0;
    for (final v in dailyProfits) {
      if (v.abs() > maxAbs) maxAbs = v.abs();
    }

    final midY = size.height / 2.0;
    final axisPaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, midY), Offset(size.width, midY), axisPaint);

    final n = dailyProfits.length;
    final slotWidth = size.width / math.max(n, 6);
    final barWidth = (slotWidth * 0.62).clamp(6.0, 26.0);

    for (int i = 0; i < n; i++) {
      final val = dailyProfits[i];
      final h = ((val.abs() / maxAbs) * (midY - 4)).clamp(2.0, midY - 2);
      final left = (i * slotWidth) + ((slotWidth - barWidth) / 2);
      final paint = Paint()
        ..color = val >= 0 ? const Color(0xFF10B981) : const Color(0xFFEF4444)
        ..style = PaintingStyle.fill;

      final rect = val >= 0
          ? Rect.fromLTWH(left, midY - h, barWidth, h)
          : Rect.fromLTWH(left, midY, barWidth, h);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, const Radius.circular(3)), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}

class MonteCarloPainter extends CustomPainter {
  final CurveList curves;
  final double initialBankroll;

  MonteCarloPainter(this.curves, this.initialBankroll);

  @override
  void paint(Canvas canvas, Size size) {
    if (curves.isEmpty || curves.first.length < 2) return;

    double minVal = initialBankroll;
    double maxVal = initialBankroll;
    for (final c in curves) {
      for (final v in c) {
        if (v < minVal) minVal = v;
        if (v > maxVal) maxVal = v;
      }
    }
    final range = (maxVal - minVal) == 0 ? 1.0 : (maxVal - minVal);

    final baseY = size.height - (((initialBankroll - minVal) / range) * size.height);
    final basePaint = Paint()
      ..color = const Color(0xFF374151)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, baseY), Offset(size.width, baseY), basePaint);

    final faintPaint = Paint()
      ..color = const Color.fromRGBO(59, 130, 246, 0.22)
      ..strokeWidth = 1.1
      ..style = PaintingStyle.stroke;

    final sortedCurves = List<DoubleList>.from(curves)
      ..sort((a, b) => a.last.compareTo(b.last));

    for (final c in sortedCurves) {
      final path = Path();
      for (int i = 0; i < c.length; i++) {
        final x = (i / (c.length - 1)) * size.width;
        final y = size.height - (((c[i] - minVal) / range) * size.height);
        if (i == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, faintPaint);
    }

    final medianCurve = sortedCurves[sortedCurves.length ~/ 2];
    final medPaint = Paint()
      ..color = const Color(0xFF10B981)
      ..strokeWidth = 2.6
      ..style = PaintingStyle.stroke;
    final medPath = Path();
    for (int i = 0; i < medianCurve.length; i++) {
      final x = (i / (medianCurve.length - 1)) * size.width;
      final y = size.height - (((medianCurve[i] - minVal) / range) * size.height);
      if (i == 0) {
        medPath.moveTo(x, y);
      } else {
        medPath.lineTo(x, y);
      }
    }
    canvas.drawPath(medPath, medPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
