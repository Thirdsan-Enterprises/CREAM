import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api/repositories/branch_reports_repository.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_theme.dart';
import '../../shared/formatters/currency_formatter.dart';
import 'branch_widgets.dart';

/// Everything about one branch for a period: takings and trend, when it
/// sells, how customers pay, who is selling, which drinks move, what stock
/// it used and what it needs, and the latest sales.
class BranchDetailScreen extends ConsumerStatefulWidget {
  const BranchDetailScreen({
    super.key,
    required this.storeId,
    required this.storeName,
    this.initialRange = ReportRange.today,
  });

  final int storeId;
  final String storeName;
  final ReportRange initialRange;

  @override
  ConsumerState<BranchDetailScreen> createState() => _BranchDetailScreenState();
}

class _BranchDetailScreenState extends ConsumerState<BranchDetailScreen> {
  late ReportRange _range = widget.initialRange;

  @override
  Widget build(BuildContext context) {
    final args = (storeId: widget.storeId, range: _range);
    final detail = ref.watch(branchDetailProvider(args));

    return Theme(
      data: AppTheme.backOffice(),
      child: Scaffold(
        appBar: AppBar(title: Text(widget.storeName)),
        body: RefreshIndicator(
          color: AppColors.gold,
          onRefresh: () => ref.refresh(branchDetailProvider(args).future),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
            children: [
              PeriodSelector(
                value: _range,
                onChanged: (range) => setState(() => _range = range),
              ),
              const SizedBox(height: 16),
              ...detail.when(
                skipLoadingOnRefresh: true,
                skipLoadingOnReload: false,
                loading: () => const [
                  SizedBox(
                    height: 320,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                ],
                error: (error, _) => [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 60),
                    child: Column(
                      children: [
                        Text('$error', textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: () =>
                              ref.invalidate(branchDetailProvider(args)),
                          child: const Text('Try again'),
                        ),
                      ],
                    ),
                  ),
                ],
                data: (data) => _content(data),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _content(BranchDetail data) {
    final totals = data.totals;
    final singleDay = data.days == 1;
    final series = singleDay ? tradingHours(data.hourly) : data.daily;
    final muted = AppColors.creamDark.withValues(alpha: 0.7);
    const gap = SizedBox(height: 14);

    return [
      // Takings
      Container(
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
              '${widget.storeName.toUpperCase()} · ${_range.label.toUpperCase()}',
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
            ChangeBadge(
              changePct: totals.changePct,
              suffix: _range.comparisonLabel,
            ),
            const SizedBox(height: 16),
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
                    label: 'Average sale',
                    value: CurrencyFormatter.format(totals.averageSale),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Plates sold',
                    value:
                        '${qty(totals.platesSold)} · ${compactUgx(totals.plateRevenue)}',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Drinks sold',
                    value:
                        '${qty(totals.drinksSold)} · ${compactUgx(totals.drinkRevenue)}',
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      gap,
      SectionCard(
        title: singleDay ? 'Sales by hour' : 'Sales by day',
        child: RevenueBarChart(
          bars: [
            for (final point in series)
              ChartBar(
                label: singleDay
                    ? hourLabel(point.key)
                    : dayLabel(point.key, short: data.days <= 7),
                segments: [ChartSegment(point.revenue, AppColors.gold)],
              ),
          ],
        ),
      ),
      gap,
      SectionCard(
        title: 'How customers paid',
        child: data.paymentMethods.isEmpty
            ? Text('No sales yet.', style: TextStyle(color: muted))
            : Column(
                children: [
                  for (final method in data.paymentMethods) ...[
                    _AmountRow(
                      title: paymentLabels[method.name] ?? method.name,
                      subtitle: '${qty(method.count)} sales',
                      amount: method.revenue,
                      fraction: totals.revenue > 0
                          ? method.revenue / totals.revenue
                          : 0,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
      gap,
      SectionCard(
        title: 'Sales by staff',
        child: data.cashiers.isEmpty
            ? Text('No sales yet.', style: TextStyle(color: muted))
            : Column(
                children: [
                  for (final cashier in data.cashiers) ...[
                    _AmountRow(
                      title: cashier.name,
                      subtitle:
                          '${qty(cashier.count)} sales · ${qty(cashier.extra)} plates',
                      amount: cashier.revenue,
                      fraction: totals.revenue > 0
                          ? cashier.revenue / totals.revenue
                          : 0,
                    ),
                    const SizedBox(height: 12),
                  ],
                ],
              ),
      ),
      gap,
      SectionCard(
        title: 'Drinks sold',
        child: data.drinks.isEmpty
            ? Text('No drinks sold yet.', style: TextStyle(color: muted))
            : Column(
                children: [
                  for (final drink in data.drinks)
                    _LineRow(
                      leading: qty(drink.count),
                      title: drink.name,
                      trailing: CurrencyFormatter.format(drink.revenue),
                    ),
                ],
              ),
      ),
      gap,
      SectionCard(
        title: 'Stock',
        trailing: Text(
          '${data.reorderCount} re-order · ${data.sufficientCount} OK',
          style: TextStyle(fontSize: 12, color: muted),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: StatTile(
                    label: 'Transfers in',
                    value: '${data.transfersReceived}',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'Short on arrival',
                    value: '${data.transfersWithDiscrepancy}',
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: 'To confirm',
                    value: '${data.transfersAwaiting}',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            if (data.reorderItems.isEmpty)
              Text(
                'Every item is above its safety level.',
                style: TextStyle(color: muted),
              )
            else
              for (final item in data.reorderItems)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          Text(
                            '${qty(item.balance)} left · level ${qty(item.safetyStock)}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFFF0A08C),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 5),
                      ProportionBar(
                        fraction: item.safetyStock > 0
                            ? item.balance / item.safetyStock
                            : 0,
                        color: AppColors.danger,
                        height: 5,
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
      gap,
      SectionCard(
        title: 'Stock used',
        child: data.stockUsed.isEmpty
            ? Text(
                'No stock usage recorded in this period.',
                style: TextStyle(color: muted),
              )
            : Column(
                children: [
                  for (final use in data.stockUsed.take(12))
                    _LineRow(
                      leading: qty(use.qty),
                      title: use.name,
                      trailing: use.unit,
                    ),
                ],
              ),
      ),
      gap,
      SectionCard(
        title: 'Latest sales',
        child: data.recentSales.isEmpty
            ? Text('No sales yet.', style: TextStyle(color: muted))
            : Column(
                children: [
                  for (final sale in data.recentSales) _SaleRow(sale: sale),
                ],
              ),
      ),
    ];
  }
}

class _AmountRow extends StatelessWidget {
  const _AmountRow({
    required this.title,
    required this.subtitle,
    required this.amount,
    required this.fraction,
  });

  final String title;
  final String subtitle;
  final double amount;
  final double fraction;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 11.5,
                      color: AppColors.creamDark.withValues(alpha: 0.7),
                    ),
                  ),
                ],
              ),
            ),
            Text(
              CurrencyFormatter.format(amount),
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        ProportionBar(fraction: fraction, height: 5),
      ],
    );
  }
}

class _LineRow extends StatelessWidget {
  const _LineRow({
    required this.leading,
    required this.title,
    required this.trailing,
  });

  final String leading;
  final String title;
  final String trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 48,
            child: Text(
              leading,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: AppColors.goldLight,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
          Expanded(child: Text(title)),
          Text(
            trailing,
            style: TextStyle(
              color: AppColors.creamDark.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }
}

class _SaleRow extends StatelessWidget {
  const _SaleRow({required this.sale});

  final RecentSale sale;

  static final _time = DateFormat('d MMM, h:mm a');

  @override
  Widget build(BuildContext context) {
    final muted = AppColors.creamDark.withValues(alpha: 0.7);
    final method = paymentLabels[sale.paymentMethod] ?? sale.paymentMethod;
    final details = [
      _time.format(sale.soldAt.toLocal()),
      ?sale.soldBy,
      sale.customer != null ? '$method · ${sale.customer}' : method,
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  sale.summary.isEmpty ? 'Sale #${sale.id}' : sale.summary,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 2),
                Text(details, style: TextStyle(fontSize: 11.5, color: muted)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            CurrencyFormatter.format(sale.total),
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
