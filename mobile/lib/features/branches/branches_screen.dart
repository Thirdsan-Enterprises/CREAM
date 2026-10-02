import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/repositories/branch_reports_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../shared/formatters/currency_formatter.dart';
import 'branch_detail_screen.dart';
import 'branch_widgets.dart';

/// The owner's home: every branch's takings side by side for a chosen
/// period, with a chart of when the money came in. Tapping a branch opens
/// its full breakdown.
class BranchesScreen extends ConsumerStatefulWidget {
  const BranchesScreen({super.key});

  @override
  ConsumerState<BranchesScreen> createState() => _BranchesScreenState();
}

class _BranchesScreenState extends ConsumerState<BranchesScreen> {
  ReportRange _range = ReportRange.today;

  @override
  Widget build(BuildContext context) {
    final overview = ref.watch(branchesOverviewProvider(_range));

    return RefreshIndicator(
      color: AppColors.gold,
      onRefresh: () => ref.refresh(branchesOverviewProvider(_range).future),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          PeriodSelector(
            value: _range,
            onChanged: (range) => setState(() => _range = range),
          ),
          const SizedBox(height: 16),
          ...overview.when(
            skipLoadingOnRefresh: true,
            skipLoadingOnReload: false,
            loading: () => const [
              SizedBox(
                height: 320,
                child: Center(child: CircularProgressIndicator()),
              ),
            ],
            error: (error, _) => [
              _ErrorPanel(
                message: '$error',
                onRetry: () => ref.invalidate(branchesOverviewProvider(_range)),
              ),
            ],
            data: (data) => _content(context, data),
          ),
        ],
      ),
    );
  }

  List<Widget> _content(BuildContext context, BranchesOverview data) {
    final colorFor = {
      for (var i = 0; i < data.branches.length; i++)
        data.branches[i].storeId: branchColor(i),
    };
    final singleDay = data.days == 1;
    final series = singleDay ? tradingHours(data.hourly) : data.daily;

    return [
      _TotalHero(totals: data.totals, range: _range),
      const SizedBox(height: 14),
      SectionCard(
        title: singleDay ? 'Sales by hour' : 'Sales by day',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            RevenueBarChart(
              bars: [
                for (final point in series)
                  ChartBar(
                    label: singleDay
                        ? hourLabel(point.key)
                        : dayLabel(point.key, short: data.days <= 7),
                    segments: [
                      for (final branch in data.branches)
                        ChartSegment(
                          point.byStore[branch.storeId] ?? 0,
                          colorFor[branch.storeId]!,
                        ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 14,
              runSpacing: 6,
              children: [
                for (final branch in data.branches)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: colorFor[branch.storeId],
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        branch.storeName,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
              ],
            ),
          ],
        ),
      ),
      const SizedBox(height: 22),
      Text('Branches', style: Theme.of(context).textTheme.titleLarge),
      const SizedBox(height: 10),
      if (data.branches.isEmpty)
        const Text('No active branches yet. Add one in Settings.'),
      for (final branch in data.branches) ...[
        _BranchCard(
          branch: branch,
          color: colorFor[branch.storeId]!,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => BranchDetailScreen(
                storeId: branch.storeId,
                storeName: branch.storeName,
                initialRange: _range,
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
      ],
      const SizedBox(height: 6),
      Text(
        'Daily outlet sales only. Catering is tracked separately under Catering.',
        style: TextStyle(
          fontSize: 12,
          color: AppColors.creamDark.withValues(alpha: 0.6),
        ),
      ),
    ];
  }
}

class _TotalHero extends StatelessWidget {
  const _TotalHero({required this.totals, required this.range});

  final BranchTotals totals;
  final ReportRange range;

  @override
  Widget build(BuildContext context) {
    final mix = totals.revenue > 0 ? totals.plateRevenue / totals.revenue : 0.0;

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.gold.withValues(alpha: 0.35)),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2B2419), Color(0xFF15120E)],
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ALL BRANCHES · ${range.label.toUpperCase()}',
            style: const TextStyle(
              fontSize: 11.5,
              letterSpacing: 1.4,
              fontWeight: FontWeight.w800,
              color: AppColors.goldLight,
            ),
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              CurrencyFormatter.format(totals.revenue),
              style: const TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          const SizedBox(height: 2),
          ChangeBadge(
            changePct: totals.changePct,
            suffix: range.comparisonLabel,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: StatTile(label: 'Sales', value: '${totals.salesCount}'),
              ),
              Expanded(
                child: StatTile(label: 'Plates', value: qty(totals.platesSold)),
              ),
              Expanded(
                child: StatTile(label: 'Drinks', value: qty(totals.drinksSold)),
              ),
              Expanded(
                child: StatTile(
                  label: 'Avg sale',
                  value: compactUgx(totals.averageSale),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ProportionBar(fraction: mix, height: 8),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Plates ${CurrencyFormatter.format(totals.plateRevenue)}',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              Text(
                'Drinks ${CurrencyFormatter.format(totals.drinkRevenue)}',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.creamDark.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _BranchCard extends StatelessWidget {
  const _BranchCard({
    required this.branch,
    required this.color,
    required this.onTap,
  });

  final BranchSummary branch;
  final Color color;
  final VoidCallback onTap;

  static final _time = DateFormat('h:mm a');
  static final _dayTime = DateFormat('d MMM, h:mm a');

  String _lastSale() {
    final at = branch.lastSaleAt?.toLocal();
    if (at == null) return 'No sales recorded yet';
    final now = DateTime.now();
    final sameDay =
        at.year == now.year && at.month == now.month && at.day == now.day;
    return 'Last sale ${sameDay ? _time.format(at) : _dayTime.format(at)}';
  }

  @override
  Widget build(BuildContext context) {
    final totals = branch.totals;
    final muted = AppColors.creamDark.withValues(alpha: 0.7);

    return Material(
      color: Colors.white.withValues(alpha: 0.04),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    branch.storeName,
                    style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (branch.isMain) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.gold.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'MAIN',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: AppColors.goldLight,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Icon(Icons.chevron_right, color: muted),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                        CurrencyFormatter.format(totals.revenue),
                        style: const TextStyle(
                          fontSize: 24,
                          fontWeight: FontWeight.w800,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: ChangeBadge(
                      changePct: totals.changePct,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              ProportionBar(fraction: branch.sharePct / 100, color: color),
              const SizedBox(height: 4),
              Text(
                '${branch.sharePct.toStringAsFixed(0)}% of all branch sales',
                style: TextStyle(fontSize: 11.5, color: muted),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: StatTile(
                      label: 'Sales',
                      value: '${totals.salesCount}',
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: 'Plates',
                      value: qty(totals.platesSold),
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: 'Drinks',
                      value: compactUgx(totals.drinkRevenue),
                    ),
                  ),
                  Expanded(
                    child: StatTile(
                      label: 'Avg sale',
                      value: compactUgx(totals.averageSale),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(Icons.schedule, size: 14, color: muted),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      _lastSale(),
                      style: TextStyle(fontSize: 12, color: muted),
                    ),
                  ),
                  if (branch.reorderItemsCount > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.danger.withValues(alpha: 0.22),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${branch.reorderItemsCount} to re-order',
                        style: const TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFF0A08C),
                        ),
                      ),
                    )
                  else
                    const Text(
                      'Stock OK',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF8FC9A4),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: [
          const Icon(Icons.cloud_off_outlined, size: 40, color: AppColors.gold),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 12),
          ElevatedButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ),
    );
  }
}
