import 'package:flutter/material.dart';

import 'Payments.dart';

/// Entry point used by the user dashboard. Delegates to the unified
/// payments dashboard with the non-tender filter pre-selected.
class NonTenderTaskWidget extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PaymentTaskWidget(initialCategory: PaymentCategory.nonTender);
  }
}

/// Legacy class kept for backwards compatibility (e.g. references from
/// older navigation stacks). Internally this now reuses the modern
/// payments experience so both screens stay in sync.
class NTPaymentTasksClass extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return PaymentTaskWidget(initialCategory: PaymentCategory.nonTender);
  }
}

