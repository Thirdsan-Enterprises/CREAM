import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../core/api/repositories/branch_reports_repository.dart';
import '../../core/theme/app_colors.dart';

const paymentLabels = {
  'cash': 'Cash',
  'momo': 'MoMo',
  'airtel': 'Airtel',
  'account': 'Account',
  'lpo': 'LPO',
};

/// Distinct, brand-compatible colours for branches on the dark Back Office
/// surface. Assigned by position in the overview list, so Kira (listed
/// first as the main store) is always gold.
const branchPalette = [
  AppColors.gold,
  Color(0xFFE9DFCB),
  Color(0xFF8FB39A),
  Color(0xFFB98A5E),
  Color(0xFF9AA8C7),
  Color(0xFFCF8C7A),
];

Color branchColor(int index) => branchPalette[index % branchPalette.length];

final _compact = NumberFormat.compact(locale: 'en_US');
final _plain = NumberFormat.decimalPattern('en_US');

/// "1.2M" style, for chart labels and tight spaces.
String compactUgx(num value) => _compact.format(value);

/// "12" / "12.5" without trailing zeros, for quantities.
String qty(num value) =>
    value == value.roundToDouble() ? _plain.format(value) : value.toString();

class PeriodSelector extends StatelessWidget {
  const PeriodSelector({
    super.key,
    required this.value,
    required this.onChanged,
  });

  final ReportRange value;
  final ValueChanged<ReportRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final range in ReportRange.values)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(range.label),
                selected: range == value,
                showCheckmark: false,
                onSelected: (_) => onChanged(range),
                selectedColor: AppColors.gold,
                labelStyle: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: range == value ? AppColors.charcoal : AppColors.cream,
                ),
                backgroundColor: Colors.white.withValues(alpha: 0.06),
                side: BorderSide.none,
                shape: const StadiumBorder(),
              ),
            ),
        ],
      ),
    );
  }
}

/// "▲ 12%" in green or "▼ 4%" in red; "New" when there's nothing to
/// compare with.
class ChangeBadge extends StatelessWidget {
  const ChangeBadge({
    super.key,
    required this.changePct,
    this.suffix,
    this.textAlign,
  });

  final double? changePct;
  final String? suffix;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    final pct = changePct;
    final Color color;
    final String text;
    if (pct == null) {
      color = AppColors.creamDark.withValues(alpha: 0.7);
      text = 'No sales to compare';
    } else if (pct >= 0) {
      color = const Color(0xFF8FC9A4);
      text = '▲ ${pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0)}%';
    } else {
      color = const Color(0xFFE59A87);
      text = '▼ ${pct.abs().toStringAsFixed(pct.abs() < 10 ? 1 : 0)}%';
    }

    return Text.rich(
      TextSpan(
        children: [
          TextSpan(
            text: text,
            style: TextStyle(color: color, fontWeight: FontWeight.w800),
          ),
          if (suffix != null && pct != null)
            TextSpan(
              text: ' $suffix',
              style: TextStyle(
                color: AppColors.creamDark.withValues(alpha: 0.7),
              ),
            ),
        ],
      ),
      style: const TextStyle(fontSize: 13),
      textAlign: textAlign,
    );
  }
}

class SectionCard extends StatelessWidget {
  const SectionCard({
    super.key,
    required this.title,
    required this.child,
    this.trailing,
  });

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(
                    fontSize: 11.5,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.goldLight,
                  ),
                ),
              ),
              ?trailing,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class StatTile extends StatelessWidget {
  const StatTile({super.key, required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: AppColors.creamDark.withValues(alpha: 0.7),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

/// A thin proportional bar, e.g. a branch's share of revenue.
class ProportionBar extends StatelessWidget {
  const ProportionBar({
    super.key,
    required this.fraction,
    this.color = AppColors.gold,
    this.height = 6,
  });

  final double fraction;
  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(height),
      child: Stack(
        children: [
          Container(
            height: height,
            color: Colors.white.withValues(alpha: 0.08),
          ),
          FractionallySizedBox(
            widthFactor: fraction.clamp(0, 1).toDouble(),
            child: Container(height: height, color: color),
          ),
        ],
      ),
    );
  }
}

class ChartSegment {
  const ChartSegment(this.value, this.color);

  final double value;
  final Color color;
}

class ChartBar {
  const ChartBar({required this.label, required this.segments});

  final String label;
  final List<ChartSegment> segments;

  double get total => segments.fold(0, (sum, s) => sum + s.value);
}

/// Revenue bars, optionally stacked by branch. Built from plain widgets
/// rather than a chart package: the shapes are simple and it keeps the
/// app's dependency list short.
class RevenueBarChart extends StatelessWidget {
  const RevenueBarChart({super.key, required this.bars, this.height = 150});

  final List<ChartBar> bars;
  final double height;

  @override
  Widget build(BuildContext context) {
    final max = bars.fold<double>(0, (m, b) => b.total > m ? b.total : m);
    if (max <= 0) {
      return SizedBox(
        height: height,
        child: Center(
          child: Text(
            'No sales in this period yet.',
            style: TextStyle(color: AppColors.creamDark.withValues(alpha: 0.7)),
          ),
        ),
      );
    }

    final peakIndex = bars.indexWhere((b) => b.total == max);
    // Keep labels legible: show at most ~8 along the axis.
    final labelEvery = (bars.length / 8).ceil().clamp(1, bars.length);
    final gap = bars.length > 20 ? 2.0 : 4.0;

    return Column(
      children: [
        SizedBox(
          height: 18,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final slot = constraints.maxWidth / bars.length;
              final left = (slot * peakIndex + slot / 2 - 40).clamp(
                0.0,
                (constraints.maxWidth - 80).clamp(0.0, double.infinity),
              );
              return Stack(
                children: [
                  Positioned(
                    left: left,
                    width: 80,
                    child: Text(
                      compactUgx(max),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: AppColors.goldLight,
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
        SizedBox(
          height: height,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bar in bars)
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: gap / 2),
                    child: _Bar(bar: bar, max: max, height: height),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (var i = 0; i < bars.length; i++)
              Expanded(
                child: Text(
                  i % labelEvery == 0 ? bars[i].label : '',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.visible,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 10,
                    color: AppColors.creamDark.withValues(alpha: 0.6),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}

class _Bar extends StatelessWidget {
  const _Bar({required this.bar, required this.max, required this.height});

  final ChartBar bar;
  final double max;
  final double height;

  @override
  Widget build(BuildContext context) {
    final total = bar.total;
    if (total <= 0) {
      return Container(
        height: 2,
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(1),
        ),
      );
    }

    final barHeight = (total / max * height).clamp(3.0, height);
    return Tooltip(
      message: '${bar.label}: UGX ${_plain.format(total)}',
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
        child: SizedBox(
          height: barHeight,
          child: Column(
            children: [
              for (final segment in bar.segments.reversed)
                if (segment.value > 0)
                  Expanded(
                    flex: (segment.value / total * 1000).round().clamp(1, 1000),
                    child: Container(color: segment.color),
                  ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Hourly series trimmed to trading hours: from the first hour with a sale
/// (or 7am) to the last (or 9pm), so the chart isn't mostly empty night.
List<SeriesPoint> tradingHours(List<SeriesPoint> hourly) {
  var first = 7;
  var last = 21;
  for (final point in hourly) {
    if (point.revenue <= 0) continue;
    final hour = int.parse(point.key);
    if (hour < first) first = hour;
    if (hour > last) last = hour;
  }
  return hourly.where((p) {
    final hour = int.parse(p.key);
    return hour >= first && hour <= last;
  }).toList();
}

String hourLabel(String key) {
  final hour = int.parse(key);
  if (hour == 0) return '12a';
  if (hour == 12) return '12p';
  return hour < 12 ? '${hour}a' : '${hour - 12}p';
}

final _dayLabel = DateFormat('d MMM');
final _weekdayLabel = DateFormat('EEE');

String dayLabel(String key, {required bool short}) {
  final date = DateTime.parse(key);
  return short ? _weekdayLabel.format(date) : _dayLabel.format(date);
}
