import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../app_theme.dart';
import '../NavMenu.dart';
import 'dashboard_chrome.dart';

/// Shared app chrome so feature screens pick up the redesigned theme.
///
/// AppBar colors follow [DashboardChrome]: role-based dark color when opened
/// from Admin Dashboard, darker surface when opened from User Dashboard.
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

  /// Extra space between the status bar and the title row.
  final double headerDrop;

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
    this.headerDrop = 0,
  });

  @override
  Widget build(BuildContext context) {
    // Always show a back control when requested so screens opened from Home
    // are never missing a way back (canPop can be briefly wrong on rebuild).
    final shouldImplyLeading = automaticallyImplyLeading;
    final isAdminChrome =
        DashboardChrome.of(context) == DashboardChromeStyle.admin;

    final Color appBarBg = isAdminChrome
        ? (DashboardChrome.appBarColorOf(context) ?? AppTheme.primaryColorConst)
        : AppTheme.darkBackgroundSecondary;
    final Color appBarFg = Colors.white;

    final appBar = AppBar(
      primary: headerDrop <= 0,
      backgroundColor: appBarBg,
      foregroundColor: appBarFg,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: centerTitle ?? false,
      automaticallyImplyLeading: false,
      systemOverlayStyle: SystemUiOverlayStyle.light,
      leading: leading ??
          (shouldImplyLeading
              ? IconButton(
                  icon: const Icon(Icons.arrow_back_rounded),
                  color: appBarFg,
                  tooltip: 'Back',
                  onPressed: () {
                    final nav = Navigator.of(context);
                    if (nav.canPop()) {
                      nav.pop();
                    } else {
                      nav.popUntil((route) => route.isFirst);
                    }
                  },
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
      bottom: headerDrop <= 0 ? bottom : null,
    );

    final PreferredSizeWidget chrome = headerDrop <= 0
        ? appBar
        : PreferredSize(
            preferredSize: Size.fromHeight(
              MediaQuery.paddingOf(context).top +
                  headerDrop +
                  kToolbarHeight +
                  (bottom?.preferredSize.height ?? 0),
            ),
            child: ColoredBox(
              color: appBarBg,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: MediaQuery.paddingOf(context).top + headerDrop,
                  ),
                  SizedBox(
                    height: kToolbarHeight,
                    width: double.infinity,
                    child: appBar,
                  ),
                  if (bottom != null)
                    SizedBox(
                      height: bottom!.preferredSize.height,
                      width: double.infinity,
                      child: bottom,
                    ),
                ],
              ),
            ),
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
        backgroundColor:
            backgroundColor ?? AppTheme.darkBackgroundPrimary,
        drawer: showDrawer ? NavMenuWidget() : null,
        appBar: chrome,
        body: body,
        floatingActionButton: floatingActionButton,
        bottomNavigationBar: bottomNavigationBar,
      ),
    );
  }
}
