import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../NavMenu.dart';
import 'dashboard_chrome.dart';

/// Shared app chrome so feature screens pick up the redesigned theme.
///
/// AppBar colors follow [DashboardChrome]: role-based dark color when opened
/// from Admin Dashboard, white when opened from User Dashboard (default).
class ThemedScaffold extends StatelessWidget {
  final String title;
  final Widget body;
  final List<Widget>? actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final bool showDrawer;
  final bool automaticallyImplyLeading;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final Widget? leading;
  final bool? centerTitle;

  const ThemedScaffold({
    super.key,
    required this.title,
    required this.body,
    this.actions,
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.showDrawer = false,
    this.automaticallyImplyLeading = true,
    this.bottom,
    this.backgroundColor,
    this.leading,
    this.centerTitle,
  });

  @override
  Widget build(BuildContext context) {
    final canPop = Navigator.of(context).canPop();
    final shouldImplyLeading = automaticallyImplyLeading && canPop;
    final isAdminChrome =
        DashboardChrome.of(context) == DashboardChromeStyle.admin;

    final Color appBarBg = isAdminChrome
        ? (DashboardChrome.appBarColorOf(context) ?? AppTheme.primaryColorConst)
        : Colors.white;
    final Color appBarFg =
        isAdminChrome ? Colors.white : AppTheme.navy;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: isAdminChrome
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: backgroundColor ?? const Color(0xFFF7F8FB),
        drawer: showDrawer ? NavMenuWidget() : null,
        appBar: AppBar(
          backgroundColor: appBarBg,
          foregroundColor: appBarFg,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: centerTitle ?? false,
          automaticallyImplyLeading: false,
          systemOverlayStyle: isAdminChrome
              ? SystemUiOverlayStyle.light
              : SystemUiOverlayStyle.dark,
          leading: leading ??
              (shouldImplyLeading
                  ? IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: appBarFg,
                      onPressed: () => Navigator.of(context).maybePop(),
                    )
                  : null),
          iconTheme: IconThemeData(color: appBarFg),
          actionsIconTheme: IconThemeData(color: appBarFg),
          title: Text(
            title,
            style: TextStyle(
              color: appBarFg,
              fontSize: 18,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.2,
            ),
          ),
          actions: actions,
          bottom: bottom,
        ),
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}
