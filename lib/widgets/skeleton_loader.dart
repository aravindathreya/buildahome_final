import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import '../app_theme.dart';

/// Shared shimmer skeleton primitives used for page/list loading states.
class SkeletonBar extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBar({
    Key? key,
    this.width,
    this.height = 14,
    this.radius = 10,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimaryLight(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

class SkeletonCard extends StatelessWidget {
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  const SkeletonCard({
    Key? key,
    this.margin = const EdgeInsets.only(bottom: 16),
    this.padding = const EdgeInsets.all(20),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      padding: padding,
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              SkeletonBar(width: 40, height: 40, radius: 14),
              SizedBox(width: 12),
              Expanded(child: SkeletonBar(height: 18)),
            ],
          ),
          const SizedBox(height: 12),
          const SkeletonBar(width: 140, height: 12),
          const SizedBox(height: 8),
          const SkeletonBar(height: 10),
        ],
      ),
    );
  }
}

/// Full-page / body skeleton: title bars + summary chips + list cards.
class SkeletonListLoader extends StatelessWidget {
  final int cardCount;
  final bool showSummary;
  final EdgeInsetsGeometry padding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  const SkeletonListLoader({
    Key? key,
    this.cardCount = 3,
    this.showSummary = true,
    this.padding = const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
    this.shrinkWrap = false,
    this.physics,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final summaryWidth = (width - 60) / 2;

    return Shimmer.fromColors(
      baseColor: AppTheme.getBackgroundPrimaryLight(context),
      highlightColor: AppTheme.getBackgroundSecondary(context),
      child: ListView(
        shrinkWrap: shrinkWrap,
        physics: physics ??
            (shrinkWrap
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics()),
        padding: padding,
        children: [
          SkeletonBar(width: 200, height: 22),
          const SizedBox(height: 8),
          SkeletonBar(width: width * 0.65, height: 14),
          if (showSummary) ...[
            const SizedBox(height: 24),
            Wrap(
              spacing: 16,
              runSpacing: 16,
              children: List.generate(
                3,
                (_) => Container(
                  width: summaryWidth,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundSecondary(context),
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SkeletonBar(width: 120, height: 14),
                      SizedBox(height: 10),
                      SkeletonBar(width: 70, height: 22),
                    ],
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 28),
          ...List.generate(cardCount, (_) => const SkeletonCard()),
        ],
      ),
    );
  }
}

/// Compact skeleton for bottom sheets, dialogs, and pickers.
class SkeletonSheetLoader extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;
  final double itemHeight;

  const SkeletonSheetLoader({
    Key? key,
    this.itemCount = 6,
    this.padding = const EdgeInsets.all(16),
    this.itemHeight = 56,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.getBackgroundPrimaryLight(context),
      highlightColor: AppTheme.getBackgroundSecondary(context),
      child: ListView.builder(
        padding: padding,
        itemCount: itemCount,
        itemBuilder: (_, __) => Container(
          margin: const EdgeInsets.only(bottom: 12),
          height: itemHeight,
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}

/// Centered compact skeleton block (dialogs / modal waits).
class SkeletonBlockLoader extends StatelessWidget {
  final EdgeInsetsGeometry padding;

  const SkeletonBlockLoader({
    Key? key,
    this.padding = const EdgeInsets.all(20),
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Shimmer.fromColors(
        baseColor: AppTheme.getBackgroundPrimaryLight(context),
        highlightColor: AppTheme.getBackgroundSecondary(context),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SkeletonBar(width: 160, height: 16),
            const SizedBox(height: 16),
            ...List.generate(
              3,
              (_) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.getBackgroundSecondary(context),
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Rectangular media placeholder for image tiles / WebView overlays.
class SkeletonImage extends StatelessWidget {
  final double? width;
  final double? height;
  final double radius;

  const SkeletonImage({
    Key? key,
    this.width,
    this.height,
    this.radius = 12,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: AppTheme.getBackgroundPrimaryLight(context),
      highlightColor: AppTheme.getBackgroundSecondary(context),
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundPrimaryLight(context),
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }
}
