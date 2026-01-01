import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_theme.dart';
import 'services/data_provider.dart';
import 'widgets/dark_mode_toggle.dart';

enum PaymentCategory {
  tender,
  nonTender,
}

class PaymentTaskWidget extends StatelessWidget {
  final PaymentCategory initialCategory;

  const PaymentTaskWidget({this.initialCategory = PaymentCategory.tender});

  @override
  Widget build(BuildContext context) {
    return PaymentsDashboard(initialCategory: initialCategory);
  }
}

class PaymentsDashboard extends StatefulWidget {
  final PaymentCategory initialCategory;

  const PaymentsDashboard({Key? key, required this.initialCategory}) : super(key: key);

  @override
  _PaymentsDashboardState createState() => _PaymentsDashboardState();
}

class _PaymentsDashboardState extends State<PaymentsDashboard> {
  PaymentCategory selectedCategory = PaymentCategory.tender;
  bool isLoading = true;
  bool isRefreshing = false;
  String? errorMessage;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _loadRequestId = 0;
  static const Duration _requestTimeout = Duration(seconds: 20);
  double _zoomLevel = 1.0; // Zoom level: 1.0 = 100%, base is smaller

  PaymentSummary tenderSummary = PaymentSummary.empty();
  PaymentSummary nonTenderSummary = PaymentSummary.empty();
  List<PaymentItem> tenderItems = [];
  List<PaymentItem> nonTenderItems = [];

  final currencyFormatter = NumberFormat.currency(locale: 'en_IN', symbol: '₹ ', decimalDigits: 0);

  @override
  void initState() {
    super.initState();
    print('[Payments] initState called');
    selectedCategory = widget.initialCategory;
    _loadData();
  }

  @override
  void dispose() {
    print('\n');
    print('╔════════════════════════════════════════════════════════════════╗');
    print('║  🔙 ANDROID BACK BUTTON PRESSED - PAYMENTS WIDGET DISPOSED    ║');
    print('╠════════════════════════════════════════════════════════════════╣');
    print('║  Widget: PaymentTaskWidget                                     ║');
    print('║  Status: Widget is being disposed                              ║');
    print('║  Reason: Android/system back button was pressed                ║');
    print('╚════════════════════════════════════════════════════════════════╝');
    print('\n');
    _searchController.dispose();
    _loadRequestId++;
    super.dispose();
  }

  Future<void> _loadData({bool showLoader = true}) async {
    final int requestId = ++_loadRequestId;

    if (showLoader) {
      _safeSetState(() {
        isLoading = true;
        errorMessage = null;
      });
    } else {
      _safeSetState(() {
        isRefreshing = true;
        errorMessage = null;
      });
    }

    try {
      final projectId = await _ensureProjectId();
      if (projectId == null) {
        throw Exception('Project not selected. Please reopen the project and try again.');
      }

      // Check cache for non-Client users
      final dataProvider = DataProvider();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      
      Map<String, dynamic>? cachedPaymentData;
      List<dynamic>? cachedTenderData;
      
      if (role != null && role != 'Client' && dataProvider.cachedPayments != null) {
        cachedPaymentData = dataProvider.cachedPayments;
        // Tender data can be obtained from cached schedule
        cachedTenderData = dataProvider.cachedSchedule;
      }

      // Use cache if available and not initial load
      if (cachedPaymentData != null && !showLoader) {
        _processPaymentData(cachedPaymentData, cachedTenderData ?? [], [], requestId);
        
        // Still refresh in background
        _fetchPaymentsFromApi(projectId, dataProvider, role, requestId);
        return;
      }

      // Fetch from API
      await _fetchPaymentsFromApi(projectId, dataProvider, role, requestId);
    } catch (e) {
      print('[Payments] Error while loading data: $e');
      if (_shouldIgnoreLoad(requestId)) return;

      _safeSetState(() {
        errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (_shouldIgnoreLoad(requestId)) return;

      _safeSetState(() {
        isLoading = false;
        isRefreshing = false;
      });
    }
  }

  Future<void> _fetchPaymentsFromApi(String projectId, DataProvider dataProvider, String? userRole, int requestId) async {
    try {
      final paymentUrl = 'https://office1.buildahome.in/API/get_payment?project_id=$projectId';
      final tenderUrl = 'https://office1.buildahome.in/API/get_all_tasks?project_id=$projectId&nt_toggle=0';
      final nonTenderUrl = 'https://office1.buildahome.in/API/get_all_non_tender?project_id=$projectId';

      print('[Payments] Loading data for project $projectId');

      final paymentResponse = await _fetchWithLogging('payment', paymentUrl);
      print('[Payments] Payment response: ${paymentResponse.body}');
      if (paymentResponse.statusCode != 200) {
        throw Exception('Unable to load payment summary right now.');
      }

      List<dynamic> tenderData = [];
      List<dynamic> nonTenderData = [];

      try {
        final tenderResponse = await _fetchWithLogging('tender', tenderUrl);
        if (tenderResponse.statusCode == 200) {
          final decoded = jsonDecode(tenderResponse.body);
          if (decoded is List) {
            tenderData = decoded;
          }
        } else {
          print('[Payments] Tender request failed with status ${tenderResponse.statusCode}');
        }
      } catch (e) {
        print('[Payments] Tender request error: $e');
      }

      try {
        final nonTenderResponse = await _fetchWithLogging('non-tender', nonTenderUrl);
        if (nonTenderResponse.statusCode == 200) {
          final decoded = jsonDecode(nonTenderResponse.body);
          if (decoded is List) {
            nonTenderData = decoded;
          }
        } else {
          print('[Payments] Non-tender request failed with status ${nonTenderResponse.statusCode}');
        }
      } catch (e) {
        print('[Payments] Non-tender request error: $e');
      }

      final paymentDetails = jsonDecode(paymentResponse.body);
      final summary = (paymentDetails is List && paymentDetails.isNotEmpty) ? paymentDetails[0] : {};

      // Update cache for non-Client users
      if (userRole != null && userRole != 'Client') {
        dataProvider.cachedPayments = summary;
        dataProvider.lastPaymentsLoad = DateTime.now();
      }

      _processPaymentData(summary, tenderData, nonTenderData, requestId);
    } catch (e) {
      rethrow;
    }
  }

  void _processPaymentData(Map<String, dynamic> summary, List<dynamic> tenderData, List<dynamic> nonTenderData, int requestId) {
    if (_shouldIgnoreLoad(requestId)) return;

    _safeSetState(() {
      tenderSummary = PaymentSummary(
        value: (summary['value'] ?? '0').toString(),
        totalPaid: (summary['total_paid'] ?? '0').toString(),
        outstanding: (summary['outstanding'] ?? '0').toString(),
      );

      nonTenderSummary = PaymentSummary(
        value: (summary['nt_value'] ?? summary['value'] ?? '0').toString(),
        totalPaid: (summary['nt_total_paid'] ?? '0').toString(),
        outstanding: (summary['nt_outstanding'] ?? '0').toString(),
      );

      tenderItems = tenderData
          .map<PaymentItem>((item) => PaymentItem(
                name: (item['task_name'] ?? 'Milestone').toString(),
                percentage: _toDouble(item['payment']),
                status: (item['paid'] ?? '').toString(),
                note: item['p_note']?.toString(),
                startDate: item['start_date']?.toString(),
                endDate: item['end_date']?.toString(),
                markedAsDueOn: item['marked_as_due_on']?.toString(),
                markedAsPaidOn: item['marked_as_paid_on']?.toString(),
                isTender: true,
              ))
          .toList();

      nonTenderItems = nonTenderData
          .map<PaymentItem>((item) => PaymentItem(
                name: (item['task_name'] ?? 'Non tender item').toString(),
                percentage: _toDouble(item['payment']),
                status: (item['paid'] ?? '').toString(),
                markedAsDueOn: item['marked_as_due_on']?.toString(),
                markedAsPaidOn: item['marked_as_paid_on']?.toString(),
                isTender: false,
                amountOverride: _toDouble(item['payment']),
              ))
          .toList();
    });
  }

  void _safeSetState(VoidCallback fn) {
    if (!mounted) return;
    setState(fn);
  }

  bool _shouldIgnoreLoad(int requestId) {
    return !mounted || requestId != _loadRequestId;
  }

  Future<String?> _ensureProjectId({int retries = 5, Duration delay = const Duration(milliseconds: 300)}) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    String? projectId = prefs.getString('project_id');
    int attempts = 0;

    while ((projectId == null || projectId.isEmpty) && attempts < retries) {
      await Future.delayed(delay);
      prefs = await SharedPreferences.getInstance();
      projectId = prefs.getString('project_id');
      attempts++;
    }

    if (projectId == null || projectId.isEmpty) {
      print('[Payments] Project ID unavailable after ${attempts + 1} attempts');
      return null;
    }

    return projectId;
  }

  Future<http.Response> _fetchWithLogging(String label, String url) async {
    try {
      print('[Payments] GET $label → $url');
      final response = await http.get(Uri.parse(url)).timeout(_requestTimeout);
      print('[Payments] $label response: ${response.statusCode}, bytes=${response.bodyBytes.length}');
      return response;
    } on TimeoutException catch (e) {
      print('[Payments] $label request timeout: $e');
      rethrow;
    } catch (e) {
      print('[Payments] $label request failed: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Route's willPop() handles back button logging - no need for PopScope
    return Scaffold(
        backgroundColor: AppTheme.getBackgroundPrimary(context),
        appBar: AppBar(
          backgroundColor: AppTheme.getBackgroundSecondary(context),
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: AppTheme.getTextPrimary(context)),
            onPressed: () {
              print('[Payments] ========== AppBar back button pressed ==========');
              print('[Payments] canPop: ${Navigator.of(context).canPop()}');
              print('[Payments] Calling maybePop()...');
              // Always pop back to UserDashboard
              Navigator.of(context).maybePop();
              print('[Payments] maybePop() called');
              print('[Payments] =================================================');
            },
          ),
          title: Text(
            'Payments',
            style: TextStyle(
              color: AppTheme.getTextPrimary(context),
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: [
            DarkModeToggle(showLabel: false),
            SizedBox(width: 8),
          ],
        ),
        body: Stack(
          children: [
            // Background image with opacity
            Positioned.fill(
              child: Opacity(
                opacity: 0.1,
                child: Image.asset(
                  'assets/images/See details.jpg',
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container();
                  },
                ),
              ),
            ),
            // Content on top
            SafeArea(
              child: AnimatedSwitcher(
                duration: Duration(milliseconds: 300),
                child: _buildBody(),
              ),
            ),
          ],
        ),
      );
  }

  Widget _buildBody() {
    if (isLoading) {
      return _buildLoader('Loading payment details…');
    }

    if (errorMessage != null) {
      return _buildError();
    }

    return RefreshIndicator(
      onRefresh: () => _loadData(showLoader: false),
      color: AppTheme.getPrimaryColor(context),
      child: ListView(
        physics: AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          _buildHeader(),
          SizedBox(height: 16),
          _buildFilterChips(),
          SizedBox(height: 16),
          _buildSummaryCards(_currentSummary),
          SizedBox(height: 24),
          _buildSearchField(),
          SizedBox(height: 20),
          _buildPaymentList(_filteredItems, _currentSummary, isSearching: _isSearching),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Track your project payments',
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.bold,
            color: AppTheme.getTextPrimary(context),
          ),
        ),
        SizedBox(height: 6),
        Text(
          'Switch between project and non tender payments using the filters below.',
          style: TextStyle(
            color: AppTheme.getTextSecondary(context),
            fontSize: 14,
          ),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
     Text('Filter by'),
     SizedBox(height: 12),
      Wrap(
      spacing: 12,
      children: [
        _buildChip('Project Payments', PaymentCategory.tender),
        _buildChip('Non Tender Payments', PaymentCategory.nonTender),
      ],
    )
    ],);
  }

  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() => _searchQuery = value),
      decoration: InputDecoration(
        hintText: 'Search payments, notes or status',
        prefixIcon: Icon(Icons.search, color: AppTheme.getTextSecondary(context)),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: AppTheme.getTextSecondary(context)),
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
              ),
        filled: true,
        fillColor: AppTheme.getBackgroundSecondary(context),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide.none,
        ),
      ),
    );
  }

  Widget _buildChip(String label, PaymentCategory category) {
    final bool isSelected = selectedCategory == category;
    return ChoiceChip(
      label: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
      selected: isSelected,
      selectedColor: AppTheme.getPrimaryColor(context),
      backgroundColor: Theme.of(context).colorScheme.surface,
          labelStyle: TextStyle(
        color: isSelected ? Colors.white : AppTheme.getTextPrimary(context),
        fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
      ),
      onSelected: (value) {
        if (value) {
          setState(() {
            selectedCategory = category;
          });
        }
      },
    );
  }

  Widget _buildSummaryCards(PaymentSummary summary) {
    final bool isNonTender = selectedCategory == PaymentCategory.nonTender;
    
    // Calculate total percentage or total amount based on category
    double totalPercentageOrAmount = 0.0;
    if (isNonTender) {
      // For non-tender: calculate total amount from items that are paid or pending
      totalPercentageOrAmount = _currentItems.fold(0.0, (sum, item) {
        final status = item.status.toLowerCase().trim();
        if (status == 'paid' || status == 'pending') {
          final amount = item.amountOverride ?? (summary.valueNumeric * (item.percentage / 100));
          return sum + amount;
        }
        return sum;
      });
    } else {
      // For tender: calculate total percentage
      totalPercentageOrAmount = _currentItems.fold(0.0, (sum, item) {
        final status = item.status.toLowerCase().trim();
        if (status == 'paid' || status == 'pending') {
          return sum + item.percentage;
        }
        return sum;
      });
    }
    
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        _SummaryCard(
          title: isNonTender ? 'NT Value' : 'Contract Value',
          subtitle: 'Total budgeted amount',
          value: _formatCurrency(summary.valueNumeric),
          icon: Icons.account_balance_wallet,
          gradient: [
            Color(0xFFE3F2FD),
            Color(0xFFBBDEFB),
          ],
        ),
        _SummaryCard(
          title: 'Paid till date',
          subtitle: 'Approved & released',
          value: _formatCurrency(summary.totalPaidNumeric),
          icon: Icons.check_circle_outline,
          valueColor: Colors.green[700],
          gradient: [
            Color(0xFFE8F5E9),
            Color(0xFFC8E6C9),
          ],
        ),
        _SummaryCard(
          title: 'Outstanding',
          subtitle: 'Pending payment',
          value: _formatCurrency(summary.outstandingNumeric),
          icon: Icons.pending_actions,
          valueColor: Colors.red[700],
          gradient: [
            Color(0xFFFFEBEE),
            Color(0xFFFFCDD2),
          ],
        ),
        _SummaryCard(
          title: isNonTender ? 'Total Amount' : 'Total Percentage',
          subtitle: isNonTender ? 'Total amount billed' : 'Total percentage billed',
          value: isNonTender 
              ? _formatCurrency(totalPercentageOrAmount)
              : '${totalPercentageOrAmount.toStringAsFixed(1)}%',
          icon: isNonTender ? Icons.currency_rupee : Icons.percent,
          valueColor: AppTheme.getPrimaryColor(context),
          gradient: [
            AppTheme.getPrimaryColor(context).withOpacity(0.15),
            AppTheme.getPrimaryColor(context).withOpacity(0.08),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentList(List<PaymentItem> items, PaymentSummary summary, {bool isSearching = false}) {
    if (items.isEmpty) {
      return Container(
        padding: EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: AppTheme.getBackgroundSecondary(context),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.1)),
        ),
        child: Column(
          children: [
            Icon(Icons.inbox_outlined, color: AppTheme.getTextSecondary(context), size: 44),
            SizedBox(height: 12),
            Text(
              isSearching ? 'No payments match your search' : 'No payments yet',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            SizedBox(height: 4),
            Text(
              isSearching ? 'Try a different keyword or clear the search.' : 'Once payments are scheduled, they will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
          ],
        ),
      );
    }

    // Calculate total percentage billed - only include tasks that are paid or pending
    double totalPercentage = items.fold(0.0, (sum, item) {
      final status = item.status.toLowerCase().trim();
      if (status == 'paid' || status == 'pending') {
        return sum + item.percentage;
      }
      return sum;
    });

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              selectedCategory == PaymentCategory.tender ? 'Milestone payments' : 'Non tender payments',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            _buildZoomControls(),
          ],
        ),
        SizedBox(height: 16),
        _buildPaymentTable(items, summary, totalPercentage),
      ],
    );
  }

  Widget _buildZoomControls() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: Icon(Icons.zoom_out, color: AppTheme.getTextSecondary(context), size: 20),
          onPressed: _zoomLevel > 0.8
              ? () {
                  setState(() {
                    _zoomLevel = (_zoomLevel - 0.1).clamp(0.8, 1.5);
                  });
                }
              : null,
          tooltip: 'Zoom out',
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
        ),
        Container(
          padding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppTheme.getBackgroundSecondary(context),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.2)),
          ),
          child: Text(
            '${(_zoomLevel * 100).toStringAsFixed(0)}%',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppTheme.getTextPrimary(context),
            ),
          ),
        ),
        IconButton(
          icon: Icon(Icons.zoom_in, color: AppTheme.getTextSecondary(context), size: 20),
          onPressed: _zoomLevel < 1.5
              ? () {
                  setState(() {
                    _zoomLevel = (_zoomLevel + 0.1).clamp(0.8, 1.5);
                  });
                }
              : null,
          tooltip: 'Zoom in',
          padding: EdgeInsets.all(4),
          constraints: BoxConstraints(),
        ),
      ],
    );
  }

  double _getScaledFontSize(double baseSize) {
    return baseSize * _zoomLevel;
  }

  Widget _buildPaymentTable(List<PaymentItem> items, PaymentSummary summary, double totalPercentage) {
    final headerFontSize = _getScaledFontSize(11);
    final cellFontSize = _getScaledFontSize(11);
    final noteFontSize = _getScaledFontSize(10);
    final statusFontSize = _getScaledFontSize(10);
    final paddingVertical = 10 * _zoomLevel;
    final paddingHorizontal = 12 * _zoomLevel;
    final bool isNonTender = selectedCategory == PaymentCategory.nonTender;
    
    final tableContent = Container(
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.1)),
      ),
      child: Column(
        children: [
          // Table Header
          Container(
            padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
            decoration: BoxDecoration(
              color: AppTheme.getPrimaryColor(context).withOpacity(0.1),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(12),
                topRight: Radius.circular(12),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: Text(
                    'Stage',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Status',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                if (!isNonTender)
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Percentage',
                      style: TextStyle(
                        fontSize: headerFontSize,
                        fontWeight: FontWeight.bold,
                        color: AppTheme.getTextPrimary(context),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'Value',
                    style: TextStyle(
                      fontSize: headerFontSize,
                      fontWeight: FontWeight.bold,
                      color: AppTheme.getTextPrimary(context),
                    ),
                    textAlign: TextAlign.right,
                  ),
                ),
              ],
            ),
          ),
          // Table Rows
          ...items.map((item) {
            final double amount = item.amountOverride ?? (summary.valueNumeric * (item.percentage / 100));
            final amountText = amount > 0 ? currencyFormatter.format(amount) : '—';
            final style = _statusStyle(item.status);

            return Container(
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: AppTheme.getPrimaryColor(context).withOpacity(0.05),
                    width: 1,
                  ),
                ),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: paddingHorizontal, vertical: paddingVertical),
                child: Row(
                  children: [
                    Expanded(
                      flex: 3,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: TextStyle(
                              fontSize: cellFontSize,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.getTextPrimary(context),
                            ),
                          ),
                          if (item.note != null && item.note!.trim().isNotEmpty) ...[
                            SizedBox(height: 2 * _zoomLevel),
                            Text(
                              item.note!.trim(),
                              style: TextStyle(
                                fontSize: noteFontSize,
                                color: AppTheme.getTextSecondary(context),
                              ),
                            ),
                          ],
                          if (item.markedAsDueOn != null && item.markedAsDueOn!.isNotEmpty && item.markedAsDueOn != 'null') ...[
                            SizedBox(height: 4 * _zoomLevel),
                            Text(
                              'Due on: ${item.markedAsDueOn!}',
                              style: TextStyle(
                                fontSize: noteFontSize - 1,
                                color: AppTheme.getTextSecondary(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                          if (item.markedAsPaidOn != null && item.markedAsPaidOn!.isNotEmpty && item.markedAsPaidOn != 'null') ...[
                            SizedBox(height: 4 * _zoomLevel),
                            Text(
                              'Paid on: ${item.markedAsPaidOn!}',
                              style: TextStyle(
                                fontSize: noteFontSize - 1,
                                color: AppTheme.getTextSecondary(context),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Expanded(
                      flex: 2,
                      child: Center(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                            horizontal: 8 * _zoomLevel,
                            vertical: 4 * _zoomLevel,
                          ),
                          decoration: BoxDecoration(
                            color: style.background,
                            borderRadius: BorderRadius.circular(10 * _zoomLevel),
                          ),
                          child: Text(
                            style.label,
                            style: TextStyle(
                              color: style.foreground,
                              fontWeight: FontWeight.w600,
                              fontSize: statusFontSize,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (!isNonTender)
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${item.percentage.toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: cellFontSize,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.getTextPrimary(context),
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    Expanded(
                      flex: 2,
                      child: Text(
                        amountText,
                        style: TextStyle(
                          fontSize: cellFontSize,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.getTextPrimary(context),
                        ),
                        textAlign: TextAlign.right,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );

    return tableContent;
  }


  _StatusStyle _statusStyle(String status) {
    final normalized = status.toLowerCase().trim();
    if (normalized == 'paid') {
      return _StatusStyle(
        label: 'Paid',
        background: Colors.green.withOpacity(0.15),
        foreground: Colors.green[800]!,
      );
    }
    if (normalized == 'not due' || normalized == 'wip') {
      return _StatusStyle(
        label: 'Scheduled',
        background: Colors.amber.withOpacity(0.2),
        foreground: Colors.amber[800]!,
      );
    }
    return _StatusStyle(
      label: 'Pending',
      background: Colors.red.withOpacity(0.15),
      foreground: Colors.red[700]!,
    );
  }

  Widget _buildLoader(String message) {
    final width = MediaQuery.of(context).size.width;
    final summaryWidth = (width - 60) / 2;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      children: [
        _skeletonBar(width: 200, height: 22),
        const SizedBox(height: 8),
        _skeletonBar(width: width * 0.7, height: 14),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _skeletonBar(width: 120, height: 14),
                  const SizedBox(height: 10),
                  _skeletonBar(width: 90, height: 22),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 28),
        ...List.generate(3, (_) => _buildSkeletonPaymentCard()),
      ],
    );
  }

  Widget _buildSkeletonPaymentCard() {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _skeletonBar(width: 48, height: 48, radius: 16),
              const SizedBox(width: 12),
              Expanded(child: _skeletonBar(height: 18)),
            ],
          ),
          const SizedBox(height: 16),
          _skeletonBar(height: 12),
          const SizedBox(height: 6),
          _skeletonBar(width: 160, height: 12),
        ],
      ),
    );
  }

  Widget _skeletonBar({double? width, double height = 16, double radius = 10}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundPrimaryLight(context),
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
            SizedBox(height: 12),
            Text(
              'Something went wrong',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: AppTheme.getTextPrimary(context),
              ),
            ),
            SizedBox(height: 8),
            Text(
              errorMessage ?? 'Please try again later.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppTheme.getTextSecondary(context)),
            ),
            SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadData,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.getPrimaryColor(context),
                foregroundColor: Colors.white,
              ),
              child: Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  List<PaymentItem> get _currentItems => selectedCategory == PaymentCategory.tender ? tenderItems : nonTenderItems;

  PaymentSummary get _currentSummary => selectedCategory == PaymentCategory.tender ? tenderSummary : nonTenderSummary;

  bool get _isSearching => _searchQuery.trim().isNotEmpty;

  List<PaymentItem> get _filteredItems {
    if (!_isSearching) return _currentItems;
    final query = _searchQuery.trim().toLowerCase();
    final currentSummary = _currentSummary;
    return _currentItems.where((item) {
      final note = item.note?.toLowerCase() ?? '';
      final status = item.status.toLowerCase();
      final percentage = '${item.percentage.toStringAsFixed(1)}%'.toLowerCase();
      final amount = item.amountOverride ?? (currentSummary.valueNumeric * (item.percentage / 100));
      final amountText = amount > 0 ? currencyFormatter.format(amount).toLowerCase() : '';
      return item.name.toLowerCase().contains(query) ||
          note.contains(query) ||
          status.contains(query) ||
          percentage.contains(query) ||
          amountText.contains(query.replaceAll(RegExp(r'[₹,\s]'), ''));
    }).toList();
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(RegExp('[^0-9\\.]'), '')) ?? 0;
  }

  String _formatCurrency(double amount) {
    if (amount == 0) return '₹ 0';
    return currencyFormatter.format(amount);
  }
}

class PaymentSummary {
  final String value;
  final String totalPaid;
  final String outstanding;

  const PaymentSummary({
    required this.value,
    required this.totalPaid,
    required this.outstanding,
  });

  static PaymentSummary empty() => PaymentSummary(value: '0', totalPaid: '0', outstanding: '0');

  double get valueNumeric => _parse(value);

  double get totalPaidNumeric => _parse(totalPaid);

  double get outstandingNumeric => _parse(outstanding);

  static double _parse(String input) {
    return double.tryParse(input.replaceAll(RegExp('[^0-9\\.]'), '')) ?? 0;
  }
}

class PaymentItem {
  final String name;
  final double percentage;
  final String status;
  final bool isTender;
  final String? note;
  final String? startDate;
  final String? endDate;
  final String? markedAsDueOn;
  final String? markedAsPaidOn;
  final double? amountOverride;

  const PaymentItem({
    required this.name,
    required this.percentage,
    required this.status,
    required this.isTender,
    this.note,
    this.startDate,
    this.endDate,
    this.markedAsDueOn,
    this.markedAsPaidOn,
    this.amountOverride,
  });
}

class _SummaryCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final String value;
  final IconData icon;
  final List<Color> gradient;
  final Color? valueColor;

  const _SummaryCard({
    required this.title,
    required this.subtitle,
    required this.value,
    required this.icon,
    required this.gradient,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      width: (MediaQuery.of(context).size.width - 60) / 2,
      padding: EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.getBackgroundSecondary(context),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppTheme.getPrimaryColor(context).withOpacity(0.1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppTheme.getTextSecondary(context)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    color: AppTheme.getTextPrimary(context),
                    fontSize: 12
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: valueColor ?? AppTheme.getTextPrimary(context),
            ),
          ),
          SizedBox(height: 4),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              color: AppTheme.getTextSecondary(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusStyle {
  final String label;
  final Color background;
  final Color foreground;

  _StatusStyle({
    required this.label,
    required this.background,
    required this.foreground,
  });
}

class TaskItem extends StatefulWidget {
  final String _taskName;
  final _icon = Icons.home; // ignore: unused_field
  final _startDate; // ignore: unused_field
  final _endDate; // ignore: unused_field
  final _height = 0.0; // ignore: unused_field
  final _color = Colors.white;
  final _paymentPercentage;
  final status;
  final note;
  final projectValue;
  final markedAsDueOn;
  final markedAsPaidOn;

  TaskItem(this._taskName, this._startDate, this._endDate, this._paymentPercentage, this.status, this.note, this.projectValue, {this.markedAsDueOn, this.markedAsPaidOn});

  @override
  TaskItemWidget createState() {
    return TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._color, this._height, this._paymentPercentage, this.status, this.note, this.projectValue, markedAsDueOn: markedAsDueOn, markedAsPaidOn: markedAsPaidOn);
  }
}

class TaskItemWidget extends State<TaskItem> with SingleTickerProviderStateMixin {
  String _taskName;
  var _icon = Icons.home; // ignore: unused_field
  var _startDate; // ignore: unused_field
  var _endDate; // ignore: unused_field
  var _color;
  var vis = false;
  var _paymentPercentage;
  var _textColor = Colors.black;
  var _height = 50.0; // ignore: unused_field
  var sprRadius = 1.0;
  var pad = 10.0;
  var valueStr;
  var value = 0;
  var status;
  var amt;
  var note;
  var gradient;
  var projectValue;
  var markedAsDueOn;
  var markedAsPaidOn;

  @override
  void initState() {
    super.initState();
    _setValue();
    _progress();
  }

  _setValue() async {
    if(this._paymentPercentage.toString().trim() == '') {
      this._paymentPercentage = '0';
    }
    setState(() {
      amt = ((int.parse(this._paymentPercentage)) / 100) * int.parse(this.projectValue);
    });
  }

  _progress() {
    if (this.status == 'not due') {
      this._color = Colors.white;
      this._textColor = Colors.black;
      this.gradient = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        stops: [0.1, 0.9],
        colors: [
          Colors.white,
          Colors.white,
        ],
      );
    } else if (this.status == 'paid') {
      this._color = Colors.green;
      this._textColor = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.3, 0.7],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Color(0xff009900),
          Color(0xff33cc00),
        ],
      );
    } else {
      this._color = Colors.deepOrange;
      this._textColor = Colors.white;
      this.gradient = LinearGradient(
        // Where the linear gradient begins and ends
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,

        // Add one stop for each color. Stops should increase from 0 to 1
        stops: [0.3, 0.7],
        colors: [
          // Colors are easy thanks to Flutter's Colors class.

          Color(0xFF7b0909),
          Color(0xFFd51010),
        ],
      );
    }
  }

  var view = Icons.expand_more;

  _expandCollapse() {
    setState(() {
      if (vis == false) {
        vis = true;
        view = Icons.expand_less;
        sprRadius = 1.0;
      } else if (vis == true) {
        vis = false;
        view = Icons.expand_more;
        sprRadius = 1.0;
      }
    });
  }

  TaskItemWidget(this._taskName, this._icon, this._startDate, this._endDate, this._color, this._height, this._paymentPercentage, this.status, this.note, this.projectValue, {this.markedAsDueOn, this.markedAsPaidOn});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            return Transform.scale(
              scale: 0.95 + (0.05 * value),
              child: Opacity(
                opacity: value,
                child: Container(
                  margin: EdgeInsets.only(left: 15, top: 10, right: 15, bottom: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppTheme.getBackgroundSecondary(context),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.05),
                        blurRadius: 8,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _expandCollapse,
                      borderRadius: BorderRadius.circular(16),
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: 300),
                        padding: EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: this.gradient,
                        ),
                        child: Column(children: <Widget>[
                          Row(
                            children: <Widget>[
                              TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.0, end: 1.0),
                                duration: Duration(milliseconds: 400),
                                curve: Curves.elasticOut,
                                builder: (context, scaleValue, child) {
                                  return Transform.scale(
                                    scale: scaleValue,
                                    child: this._color == Colors.green
                                        ? Container(
                                            height: 50,
                                            width: 50,
                                            alignment: Alignment.center,
                                            decoration: BoxDecoration(
                                              color: Colors.green[900],
                                              borderRadius: BorderRadius.circular(12),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.green.withOpacity(0.3),
                                                  blurRadius: 8,
                                                  offset: Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Text(
                                              'PAID',
                                              style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                            ),
                                          )
                                        : this._color == Colors.white
                                            ? Container(
                                                height: 50,
                                                width: 50,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.yellow[700],
                                                  borderRadius: BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.yellow.withOpacity(0.3),
                                                      blurRadius: 8,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  'WIP',
                                                  style: TextStyle(color: const Color.fromARGB(255, 0, 0, 0), fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              )
                                            : Container(
                                                height: 50,
                                                width: 50,
                                                alignment: Alignment.center,
                                                decoration: BoxDecoration(
                                                  color: Colors.red[700],
                                                  borderRadius: BorderRadius.circular(12),
                                                  boxShadow: [
                                                    BoxShadow(
                                                      color: Colors.red.withOpacity(0.3),
                                                      blurRadius: 8,
                                                      offset: Offset(0, 2),
                                                    ),
                                                  ],
                                                ),
                                                child: Text(
                                                  'DUE',
                                                  style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                                                ),
                                              ),
                                  );
                                },
                              ),
                              SizedBox(width: 15),
                              Expanded(
                                child: Text(
                                  this._taskName,
                                  textAlign: TextAlign.left,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: this._textColor,
                                  ),
                                ),
                              ),
                              AnimatedRotation(
                                turns: this.vis ? 0.5 : 0.0,
                                duration: Duration(milliseconds: 300),
                                curve: Curves.easeInOut,
                                child: Icon(
                                  Icons.expand_more,
                                  color: this._textColor,
                                  size: 24,
                                ),
                              ),
                            ],
                          ),
                          AnimatedSize(
                            duration: Duration(milliseconds: 300),
                            curve: Curves.easeInOut,
                            child: this.vis
                                ? Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      SizedBox(height: 12),
                                      Container(
                                        padding: EdgeInsets.all(12),
                                        decoration: BoxDecoration(
                                          color: Colors.white.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(12),
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                          children: <Widget>[
                                            Text(
                                              this._paymentPercentage + "%",
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: this._textColor,
                                              ),
                                            ),
                                            Text(
                                              "₹ " + ((amt != null) ? amt.toStringAsFixed(2) : ''),
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: this._textColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (this.note.trim() != '')
                                        Container(
                                          margin: EdgeInsets.only(top: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Text(
                                            this.note.trim(),
                                            style: TextStyle(
                                              color: this._textColor,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ),
                                      if (this.markedAsDueOn != null && this.markedAsDueOn.toString().isNotEmpty && this.markedAsDueOn.toString() != 'null')
                                        Container(
                                          margin: EdgeInsets.only(top: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.event_note, size: 14, color: this._textColor),
                                              SizedBox(width: 8),
                                              Text(
                                                "Due on: ${this.markedAsDueOn}",
                                                style: TextStyle(
                                                  color: this._textColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      if (this.markedAsPaidOn != null && this.markedAsPaidOn.toString().isNotEmpty && this.markedAsPaidOn.toString() != 'null')
                                        Container(
                                          margin: EdgeInsets.only(top: 8),
                                          padding: EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.2),
                                            borderRadius: BorderRadius.circular(12),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(Icons.event_available, size: 14, color: this._textColor),
                                              SizedBox(width: 8),
                                              Text(
                                                "Paid on: ${this.markedAsPaidOn}",
                                                style: TextStyle(
                                                  color: this._textColor,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                    ],
                                  )
                                : SizedBox.shrink(),
                          ),
                        ]),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class PaymentTasksClass extends StatefulWidget {
  @override
  PaymentTasks createState() {
    return PaymentTasks();
  }
}

class PaymentTasks extends State<PaymentTasksClass> {
  var body;
  var tasks = [];
  var projectValue = "";
  var outstanding = "";
  var totalPaid = "";

  @override
  void initState() {
    super.initState();
    call();
    print('call');
  }

  call() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var id = prefs.getString('project_id');
    var url = 'https://office1.buildahome.in/API/get_all_tasks?project_id=$id&nt_toggle=0';
    var response = await http.get(Uri.parse(url));
    body = jsonDecode(response.body);

    var url1 = 'https://office1.buildahome.in/API/get_payment?project_id=$id';
    var response1 = await http.get(Uri.parse(url1));
    var details = jsonDecode(response1.body);
    outstanding = details[0]['outstanding'];
    totalPaid = double.parse(details[0]['total_paid'].toString().trim()).toString();
    projectValue = details[0]['value'];

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color.fromARGB(255, 250, 250, 255),
            Color.fromARGB(255, 233, 233, 233),
          ],
        ),
      ),
      child: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: 1),
            child: ListView(children: <Widget>[
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 400),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, -20 * (1 - value)),
                      child: Container(
                        margin: EdgeInsets.only(top: 20, left: 20, bottom: 10),
                        child: Text(
                          "Project Payments",
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Color.fromARGB(255, 13, 17, 65),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 500),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.scale(
                    scale: value,
                    child: Opacity(
                      opacity: value,
                      child: Container(
                        height: 3,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              Color.fromARGB(255, 13, 17, 65),
                              Color.fromARGB(255, 20, 25, 80),
                            ],
                          ),
                          borderRadius: BorderRadius.circular(2),
                        ),
                        width: 100,
                        margin: EdgeInsets.only(left: 20, right: 250, bottom: 20),
                      ),
                    ),
                  );
                },
              ),
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.0, end: 1.0),
                duration: Duration(milliseconds: 600),
                curve: Curves.easeOut,
                builder: (context, value, child) {
                  return Opacity(
                    opacity: value,
                    child: Transform.translate(
                      offset: Offset(0, 30 * (1 - value)),
                      child: Container(
                        margin: EdgeInsets.symmetric(vertical: 10, horizontal: 15),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: <Widget>[
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 400),
                              curve: Curves.easeOutBack,
                              builder: (context, scaleValue, child) {
                                return Transform.scale(
                                  scale: scaleValue,
                                  child: Container(
                                    width: (MediaQuery.of(context).size.width - 50) / 2,
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.fromARGB(255, 240, 255, 242),
                                          Color.fromARGB(255, 220, 245, 225),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.account_balance_wallet, size: 18, color: Color.fromARGB(255, 13, 17, 65)),
                                            SizedBox(width: 6),
                                            Text(
                                              "Project Value",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color.fromARGB(255, 100, 100, 100),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "₹ " + projectValue,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Color.fromARGB(255, 13, 17, 65),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 500),
                              curve: Curves.easeOutBack,
                              builder: (context, scaleValue, child) {
                                return Transform.scale(
                                  scale: scaleValue,
                                  child: Container(
                                    width: (MediaQuery.of(context).size.width - 50) / 2,
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.fromARGB(255, 255, 237, 237),
                                          Color.fromARGB(255, 255, 220, 220),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.check_circle, size: 18, color: Colors.green[700]),
                                            SizedBox(width: 6),
                                            Text(
                                              "Paid till date",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color.fromARGB(255, 100, 100, 100),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "₹ " + totalPaid,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.green[700],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                            TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.0, end: 1.0),
                              duration: Duration(milliseconds: 600),
                              curve: Curves.easeOutBack,
                              builder: (context, scaleValue, child) {
                                return Transform.scale(
                                  scale: scaleValue,
                                  child: Container(
                                    width: (MediaQuery.of(context).size.width - 50) / 2,
                                    padding: EdgeInsets.all(16),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        begin: Alignment.topLeft,
                                        end: Alignment.bottomRight,
                                        colors: [
                                          Color.fromARGB(255, 246, 248, 225),
                                          Color.fromARGB(255, 240, 242, 200),
                                        ],
                                      ),
                                      borderRadius: BorderRadius.circular(16),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black.withOpacity(0.08),
                                          blurRadius: 10,
                                          offset: Offset(0, 4),
                                        ),
                                      ],
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Icon(Icons.pending_actions, size: 18, color: Colors.red[500]),
                                            SizedBox(width: 6),
                                            Text(
                                              "Current Outstanding",
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Color.fromARGB(255, 100, 100, 100),
                                              ),
                                            ),
                                          ],
                                        ),
                                        SizedBox(height: 8),
                                        Text(
                                          "₹ " + outstanding,
                                          style: TextStyle(
                                            fontSize: 18,
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red[500],
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            new ListView.builder(
                shrinkWrap: true,
                physics: BouncingScrollPhysics(),
                itemCount: body == null ? 0 : body.length,
                itemBuilder: (BuildContext ctxt, int index) {
                  return AnimatedWidgetSlide(
                      direction: index % 2 == 0 ? SlideDirection.leftToRight : SlideDirection.rightToLeft, // Specify the slide direction
                      duration: Duration(milliseconds: 300),
                      child: Container(
                        child: TaskItem(
                            body[index]['task_name'].toString(),
                            body[index]['start_date'].toString(),
                            body[index]['end_date'].toString(),
                            body[index]['payment'].toString(),
                            body[index]['paid'].toString(),
                            body[index]['p_note'].toString(),
                            projectValue,
                            markedAsDueOn: body[index]['marked_as_due_on']?.toString(),
                            markedAsPaidOn: body[index]['marked_as_paid_on']?.toString()),
                      ));
                }),
            ]),
          ),
        ],
      ),
    );
  }
}

enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  AnimatedWidgetSlide({
    required this.child,
    required this.direction,
    required this.duration,
  });

  @override
  _AnimatedWidgetSlideState createState() => _AnimatedWidgetSlideState();
}

class _AnimatedWidgetSlideState extends State<AnimatedWidgetSlide> with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    switch (widget.direction) {
      case SlideDirection.leftToRight:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(-1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInSine,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.topToBottom:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, -1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
      case SlideDirection.bottomToTop:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(0.0, 1.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeInOut,
        ));
        break;
    }

    _animationController.forward();
  }

  @override
  Widget build(BuildContext context) {
    return SlideTransition(
      position: _slideAnimation,
      child: widget.child,
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }
}
