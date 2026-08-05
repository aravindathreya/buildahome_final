// Built in packages
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_spinkit/flutter_spinkit.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

// Custom dart files
import '../AdminDashboard.dart';
import '../UserHome.dart';
import '../services/data_provider.dart';
import '../services/profile_picture_service.dart';

class LoginScreenNew extends StatefulWidget {
  @override
  LoginScreenNewState createState() => LoginScreenNewState();
}

class LoginScreenNewState extends State<LoginScreenNew>
    with TickerProviderStateMixin {
  static const Color _navy = Color(0xFF1B254B);
  static const Color _muted = Color(0xFF8A94A6);
  static const Color _border = Color(0xFFE8ECF1);
  static const String _authBase = 'https://office1.buildahome.in';

  static const int _otpLength = 6;
  static const int _resendCooldownSeconds = 30;

  var showLoginForm = false;
  var showSplash = true;
  var imageContainerShrinked = false;
  var showPhoneField = false;
  var showOtpField = false;
  var formBeingSubmitted = false;
  var showPhoneError = false;
  var showOtpError = false;
  String? errorMessage;

  final phoneFocusNode = FocusNode();
  final phoneTextController = TextEditingController();
  final List<TextEditingController> _otpControllers =
      List.generate(_otpLength, (_) => TextEditingController());
  final List<FocusNode> _otpFocusNodes =
      List.generate(_otpLength, (_) => FocusNode());

  String? _normalizedPhone;
  Timer? _resendTimer;
  int _resendSecondsLeft = 0;

  late AnimationController _splashFadeController;
  late AnimationController _formFadeController;
  late Animation<double> _splashFade;
  late Animation<double> _formFade;

  @override
  void initState() {
    super.initState();
    _splashFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    );
    _splashFade = CurvedAnimation(
      parent: _splashFadeController,
      curve: Curves.easeOutCubic,
    );

    _formFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    );
    _formFade = CurvedAnimation(
      parent: _formFadeController,
      curve: Curves.easeOutCubic,
    );

    // Smooth fade-in as soon as the Flutter splash appears.
    _splashFadeController.forward();
    checkIfAlreadyLoggedIn();
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _splashFadeController.dispose();
    _formFadeController.dispose();
    phoneFocusNode.dispose();
    phoneTextController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _revealLoginForm() async {
    if (!mounted) return;
    // Soft fade-out of splash, then fade-in form.
    await _splashFadeController.reverse();
    if (!mounted) return;
    setState(() {
      showSplash = false;
      showLoginForm = true;
    });
    await _formFadeController.forward(from: 0);
  }

  checkIfAlreadyLoggedIn() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    var username = prefs.getString('username');
    var role = prefs.getString('role');
    var token = prefs.getString('api_token');

    if (username != null &&
        username.isNotEmpty &&
        token != null &&
        token.isNotEmpty) {
      if (mounted) {
        setState(() {
          showLoginForm = false;
          showSplash = true;
        });
      }
      await ProfilePictureService.getStoredPath();
      await DataProvider().initializeData(force: true);
      if (!mounted) return;
      if (role == 'Client') {
        await _openAppScreen(Home());
      } else {
        await _openAppScreen(AdminDashboard());
      }
    } else {
      // Keep splash visible briefly so the fade-in can be seen, then reveal form.
      await Future.delayed(const Duration(milliseconds: 350));
      await _revealLoginForm();
    }
  }

  Future<void> _openAppScreen(Widget destination) async {
    _dismissKeyboard();

    // Fade the login/splash out first so the handoff is always visible.
    if (showLoginForm && _formFadeController.value > 0) {
      await _formFadeController.reverse();
    } else if (showSplash && _splashFadeController.value > 0) {
      await _splashFadeController.reverse();
    }
    if (!mounted) return;

    await Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => destination,
        transitionDuration: const Duration(milliseconds: 520),
        reverseTransitionDuration: const Duration(milliseconds: 320),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          final fade = CurvedAnimation(
            parent: animation,
            curve: const Interval(0.0, 0.7, curve: Curves.easeOutCubic),
          );
          final slide = Tween<Offset>(
            begin: const Offset(0.18, 0),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));
          return FadeTransition(
            opacity: fade,
            child: SlideTransition(
              position: slide,
              child: child,
            ),
          );
        },
      ),
      (route) => false,
    );
  }

  /// Normalize to E.164-style +91XXXXXXXXXX for Indian numbers.
  String? normalizePhone(String raw) {
    final digits = raw.replaceAll(RegExp(r'[^\d+]'), '').trim();
    if (digits.isEmpty) return null;

    String cleaned = digits;
    if (cleaned.startsWith('+')) {
      cleaned = cleaned.substring(1);
    }

    if (cleaned.length == 10 && RegExp(r'^[6-9]\d{9}$').hasMatch(cleaned)) {
      return '+91$cleaned';
    }
    if (cleaned.length == 12 && cleaned.startsWith('91')) {
      final local = cleaned.substring(2);
      if (RegExp(r'^[6-9]\d{9}$').hasMatch(local)) {
        return '+$cleaned';
      }
    }
    if (cleaned.length >= 11 && cleaned.length <= 15) {
      return '+$cleaned';
    }
    return null;
  }

  String getCTAButtonText() {
    if (showOtpField) return 'Verify & sign in';
    if (showPhoneField) return 'Send OTP';
    return 'Get started';
  }

  Future<void> setSharedPrefs({
    required String username,
    required String role,
    required dynamic userId,
    required String? apiToken,
    String? phone,
    String? email,
    String? accessLevel,
    String? profilePicture,
  }) async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString('username', username);
    await prefs.setString('role', role);
    await prefs.setString('userId', userId.toString());
    await prefs.setString('user_id', userId.toString());
    await prefs.setString('api_token', apiToken?.toString().trim() ?? '');
    if (phone != null && phone.isNotEmpty) {
      await prefs.setString('phone', phone);
    }
    if (email != null && email.isNotEmpty) {
      await prefs.setString('email', email);
    }
    if (accessLevel != null && accessLevel.isNotEmpty) {
      await prefs.setString('access_level', accessLevel);
    }
    // Login verify `user.profile_picture` is the source of truth for whether
    // a picture is set (prompt on app start when missing/empty).
    final picture = profilePicture?.trim() ?? '';
    if (picture.isNotEmpty) {
      await ProfilePictureService.savePath(picture);
    } else {
      await ProfilePictureService.clearStored();
    }
  }

  void _startResendCooldown() {
    _resendTimer?.cancel();
    setState(() => _resendSecondsLeft = _resendCooldownSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSecondsLeft <= 1) {
        timer.cancel();
        setState(() => _resendSecondsLeft = 0);
      } else {
        setState(() => _resendSecondsLeft -= 1);
      }
    });
  }

  void _clearOtpFields() {
    for (final c in _otpControllers) {
      c.clear();
    }
  }

  String _currentOtp() {
    return _otpControllers.map((c) => c.text).join();
  }

  Future<void> sendOtp({bool isResend = false}) async {
    final normalized = normalizePhone(phoneTextController.text);
    if (normalized == null) {
      setState(() {
        showPhoneError = true;
        errorMessage = 'Enter a valid phone number';
        formBeingSubmitted = false;
      });
      return;
    }

    setState(() {
      formBeingSubmitted = true;
      showPhoneError = false;
      showOtpError = false;
      errorMessage = null;
      _normalizedPhone = normalized;
    });

    try {
      final Map<String, dynamic> payload = {
        'phone_number': normalized,
      };
      if (kDebugMode) {
        payload['debugger'] = true;
      }

      final response = await http
          .post(
            Uri.parse('$_authBase/api/auth/send-whatsapp-otp'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 25));

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {
        body = null;
      }

      if (response.statusCode == 200 && (body?['success'] == true)) {
        setState(() {
          formBeingSubmitted = false;
          showPhoneField = false;
          showOtpField = true;
          imageContainerShrinked = true;
          if (!isResend) _clearOtpFields();
        });
        _startResendCooldown();
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted) _otpFocusNodes.first.requestFocus();
        });
        return;
      }

      String message;
      switch (response.statusCode) {
        case 400:
          message = body?['message']?.toString() ?? 'Invalid phone number';
          break;
        case 404:
          message = body?['message']?.toString() ?? 'User not found';
          break;
        case 502:
          message = body?['message']?.toString() ??
              'Failed to send OTP. Please try again later.';
          break;
        default:
          message = body?['message']?.toString() ??
              'Unable to send OTP. Please try again.';
      }

      setState(() {
        formBeingSubmitted = false;
        showPhoneError = !showOtpField;
        showOtpError = showOtpField;
        errorMessage = message;
        if (!isResend) {
          showPhoneField = true;
          showOtpField = false;
        }
      });
    } catch (e) {
      setState(() {
        formBeingSubmitted = false;
        showPhoneError = !showOtpField;
        showOtpError = showOtpField;
        errorMessage = 'Network error. Please try again.';
      });
    }
  }

  Future<void> verifyOtpAndLogin() async {
    final phone = _normalizedPhone ?? normalizePhone(phoneTextController.text);
    final otp = _currentOtp();

    if (phone == null) {
      setState(() {
        showOtpError = true;
        errorMessage = 'Invalid phone number';
        formBeingSubmitted = false;
      });
      return;
    }
    if (otp.length != _otpLength) {
      setState(() {
        showOtpError = true;
        errorMessage = 'Enter the 6-digit OTP';
        formBeingSubmitted = false;
      });
      return;
    }

    setState(() {
      formBeingSubmitted = true;
      showOtpError = false;
      errorMessage = null;
    });

    try {
      final response = await http
          .post(
            Uri.parse('$_authBase/api/auth/verify-whatsapp-otp'),
            headers: {
              'Content-Type': 'application/json',
              'Accept': 'application/json',
            },
            body: jsonEncode({
              'phone_number': phone,
              'otp': otp,
            }),
          )
          .timeout(const Duration(seconds: 25));

      Map<String, dynamic>? body;
      try {
        body = jsonDecode(response.body) as Map<String, dynamic>?;
      } catch (_) {
        body = null;
      }

      if (response.statusCode == 200 &&
          body != null &&
          (body['success'] == true || body['token'] != null)) {
        final token = body['token']?.toString();
        final user = body['user'] is Map
            ? Map<String, dynamic>.from(body['user'] as Map)
            : <String, dynamic>{};

        final role = user['role']?.toString() ?? '';
        final name = user['name']?.toString() ??
            user['email']?.toString() ??
            phoneTextController.text.trim();
        final userId = user['user_id'] ?? user['id'] ?? '';

        await setSharedPrefs(
          username: name,
          role: role,
          userId: userId,
          apiToken: token,
          phone: user['phone']?.toString() ?? phone,
          email: user['email']?.toString(),
          accessLevel: user['access_level']?.toString(),
          profilePicture: user['profile_picture']?.toString(),
        );

        await DataProvider().initializeData(force: true);

        if (!mounted) return;
        if (role == 'Client') {
          await _openAppScreen(Home());
        } else {
          await _openAppScreen(AdminDashboard());
        }
        return;
      }

      String message;
      final apiMessage = body?['message']?.toString() ?? '';
      if (response.statusCode == 404) {
        message = apiMessage.isNotEmpty ? apiMessage : 'User not found';
      } else if (response.statusCode == 400) {
        if (apiMessage.toLowerCase().contains('expired')) {
          message = 'OTP expired. Please request a new one.';
        } else if (apiMessage.toLowerCase().contains('phone')) {
          message = apiMessage;
        } else {
          message = apiMessage.isNotEmpty ? apiMessage : 'Invalid OTP';
        }
      } else {
        message = apiMessage.isNotEmpty
            ? apiMessage
            : 'Unable to verify OTP. Please try again.';
      }

      setState(() {
        formBeingSubmitted = false;
        showOtpError = true;
        errorMessage = message;
      });
    } catch (e) {
      setState(() {
        formBeingSubmitted = false;
        showOtpError = true;
        errorMessage = 'Network error. Please try again.';
      });
    }
  }

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
    SystemChannels.textInput.invokeMethod('TextInput.hide');
  }

  void _goBackToIntro() {
    if (formBeingSubmitted) return;
    _dismissKeyboard();
    setState(() {
      imageContainerShrinked = false;
      showPhoneField = false;
      showOtpField = false;
      showPhoneError = false;
      showOtpError = false;
      errorMessage = null;
      _clearOtpFields();
    });
  }

  Widget _backRow({required String label, required VoidCallback? onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: Row(
          children: [
            const Icon(
              Icons.arrow_back_ios_new_rounded,
              size: 14,
              color: _navy,
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(
                color: _navy,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _animatedStep({required Widget child}) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 420),
        reverseDuration: const Duration(milliseconds: 300),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeInCubic,
        transitionBuilder: (child, animation) {
          final slide = Tween<Offset>(
            begin: const Offset(0.16, 0.04),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ));
          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slide,
              child: child,
            ),
          );
        },
        layoutBuilder: (currentChild, previousChildren) {
          return Stack(
            alignment: Alignment.topCenter,
            children: <Widget>[
              ...previousChildren,
              if (currentChild != null) currentChild,
            ],
          );
        },
        child: child,
      ),
    );
  }

  Widget _animatedLabel({
    required String text,
    required TextStyle style,
  }) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 360),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      transitionBuilder: (child, animation) {
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.2),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      },
      child: Text(
        text,
        key: ValueKey<String>(text),
        style: style,
      ),
    );
  }

  void _onPrimaryTap() {
    if (formBeingSubmitted) return;

    if (!imageContainerShrinked) {
      setState(() {
        imageContainerShrinked = true;
        showPhoneField = true;
        errorMessage = null;
      });
      // Wait for step animation before opening the keyboard.
      Future.delayed(const Duration(milliseconds: 420), () {
        if (mounted) phoneFocusNode.requestFocus();
      });
      return;
    }

    if (showPhoneField) {
      if (phoneTextController.text.trim().isEmpty ||
          normalizePhone(phoneTextController.text) == null) {
        setState(() {
          showPhoneError = true;
          errorMessage = 'Enter a valid phone number';
        });
        phoneFocusNode.requestFocus();
        return;
      }
      sendOtp();
      return;
    }

    if (showOtpField) {
      verifyOtpAndLogin();
    }
  }

  void _onOtpChanged(int index, String value) {
    if (value.length > 1) {
      // Paste support
      final digits = value.replaceAll(RegExp(r'\D'), '');
      for (var i = 0; i < _otpLength; i++) {
        _otpControllers[i].text =
            i < digits.length ? digits[i] : '';
      }
      final focusIndex =
          digits.length >= _otpLength ? _otpLength - 1 : digits.length;
      _otpFocusNodes[focusIndex.clamp(0, _otpLength - 1)].requestFocus();
      setState(() {
        showOtpError = false;
        errorMessage = null;
      });
      if (digits.length >= _otpLength) {
        verifyOtpAndLogin();
      }
      return;
    }

    if (value.isNotEmpty && index < _otpLength - 1) {
      _otpFocusNodes[index + 1].requestFocus();
    }
    setState(() {
      showOtpError = false;
      errorMessage = null;
    });
    if (_currentOtp().length == _otpLength) {
      verifyOtpAndLogin();
    }
  }

  InputDecoration _fieldDecoration({
    required String hint,
    required IconData icon,
    Widget? suffix,
    String? prefixText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(
        color: _muted,
        fontWeight: FontWeight.w500,
      ),
      prefixIcon: Icon(icon, color: _navy),
      prefixText: prefixText,
      prefixStyle: const TextStyle(
        color: _navy,
        fontSize: 15,
        fontWeight: FontWeight.w700,
      ),
      suffixIcon: suffix,
      filled: true,
      fillColor: const Color(0xFFF7F8FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: _navy, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    );
  }

  Widget _errorRow(String message) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, left: 4),
      child: Row(
        children: [
          Icon(Icons.error_outline, size: 16, color: Colors.red[600]),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.red[600],
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _otpInputRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(_otpLength, (index) {
        return SizedBox(
          width: 46,
          height: 54,
          child: TextField(
            controller: _otpControllers[index],
            focusNode: _otpFocusNodes[index],
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _navy,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(_otpLength),
            ],
            decoration: InputDecoration(
              filled: true,
              fillColor: const Color(0xFFF7F8FB),
              contentPadding: EdgeInsets.zero,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: showOtpError ? Colors.red.shade300 : _border,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: _navy, width: 1.5),
              ),
            ),
            onChanged: (value) => _onOtpChanged(index, value),
            onSubmitted: (_) => _dismissKeyboard(),
            onTapOutside: (_) => _dismissKeyboard(),
            onTap: () {
              _otpControllers[index].selection = TextSelection(
                baseOffset: 0,
                extentOffset: _otpControllers[index].text.length,
              );
            },
          ),
        );
      }),
    );
  }

  String get _maskedPhone {
    final phone = _normalizedPhone ?? phoneTextController.text.trim();
    if (phone.length < 4) return phone;
    final last4 = phone.substring(phone.length - 4);
    return '••••••$last4';
  }

  @override
  Widget build(BuildContext context) {
    final topPad = MediaQuery.of(context).padding.top;
    // Keep branding (logo / title) fully on solid navy.
    // Extra buffer avoids gaps while header content animates.
    final headerHeight =
        imageContainerShrinked ? topPad + 168 : topPad + 260;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light,
      child: Scaffold(
      backgroundColor: const Color(0xFFF7F8FB),
      body: GestureDetector(
        onTap: _dismissKeyboard,
        behavior: HitTestBehavior.translucent,
        child: Stack(
        children: [
          // Solid navy header — avoids white-on-light and muddy fade gradients.
          if (showLoginForm || showSplash)
            AnimatedPositioned(
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeInOutCubic,
              top: 0,
              left: 0,
              right: 0,
              height: showSplash
                  ? MediaQuery.of(context).size.height
                  : headerHeight,
              child: Container(
                decoration: BoxDecoration(
                  color: _navy,
                  borderRadius: showSplash
                      ? BorderRadius.zero
                      : const BorderRadius.only(
                          bottomLeft: Radius.circular(28),
                          bottomRight: Radius.circular(28),
                        ),
                ),
                child: showLoginForm
                    ? Align(
                        alignment: Alignment.topRight,
                        child: Padding(
                          padding: const EdgeInsets.only(top: 24, right: 8),
                          child: Icon(
                            Icons.home_work_outlined,
                            size: imageContainerShrinked ? 120 : 160,
                            color: Colors.white.withValues(alpha: 0.06),
                          ),
                        ),
                      )
                    : null,
              ),
            ),
          if (showLoginForm)
            FadeTransition(
              opacity: _formFade,
              child: SafeArea(
              child: SingleChildScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                padding: EdgeInsets.fromLTRB(20, topPad > 0 ? 8 : 20, 20, 28),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AnimatedSize(
                      duration: const Duration(milliseconds: 420),
                      curve: Curves.easeInOutCubic,
                      alignment: Alignment.topLeft,
                      clipBehavior: Clip.hardEdge,
                      child: Column(
                        key: ValueKey<String>(
                          imageContainerShrinked
                              ? (showOtpField ? 'otp-header' : 'phone-header')
                              : 'intro-header',
                        ),
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Image.asset(
                            'assets/images/LOGO WHITE.png',
                            height: imageContainerShrinked ? 36 : 44,
                            fit: BoxFit.contain,
                            filterQuality: FilterQuality.high,
                            errorBuilder: (_, __, ___) => const Text(
                              'buildAhome',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 26,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 14),
                          Text(
                            imageContainerShrinked
                                ? (showOtpField
                                    ? 'Verify WhatsApp OTP'
                                    : 'Welcome back')
                                : 'Building homes,\nbeautifully managed.',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: imageContainerShrinked ? 22 : 28,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: -0.4,
                            ),
                          ),
                          if (!imageContainerShrinked) ...[
                            const SizedBox(height: 8),
                            Text(
                              'Sign in with WhatsApp OTP to track projects and site progress.',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.72),
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 22),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(18, 20, 18, 18),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _border),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x14000000),
                            blurRadius: 24,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _animatedLabel(
                            text: showOtpField
                                ? 'Enter OTP'
                                : showPhoneField
                                    ? 'Phone number'
                                    : 'WhatsApp login',
                            style: const TextStyle(
                              color: _navy,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 6),
                          _animatedLabel(
                            text: showOtpField
                                ? 'We sent a 6-digit code to $_maskedPhone on WhatsApp'
                                : showPhoneField
                                    ? 'Use the mobile number linked to your account'
                                    : 'Verify your number to access your workspace',
                            style: const TextStyle(
                              color: _muted,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(height: 18),
                          _animatedStep(
                            child: showPhoneField
                                ? Column(
                                    key: const ValueKey('phone'),
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      _backRow(
                                        label: 'Back',
                                        onTap: formBeingSubmitted
                                            ? null
                                            : _goBackToIntro,
                                      ),
                                      TextField(
                                        controller: phoneTextController,
                                        focusNode: phoneFocusNode,
                                        keyboardType: TextInputType.phone,
                                        textInputAction: TextInputAction.done,
                                        onSubmitted: (_) => _dismissKeyboard(),
                                        onTapOutside: (_) =>
                                            _dismissKeyboard(),
                                        inputFormatters: [
                                          FilteringTextInputFormatter.allow(
                                            RegExp(r'[0-9+\s-]'),
                                          ),
                                          LengthLimitingTextInputFormatter(15),
                                        ],
                                        style: const TextStyle(
                                          color: _navy,
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                        ),
                                        decoration: _fieldDecoration(
                                          hint: '9876543210',
                                          icon: Icons.phone_iphone_rounded,
                                        ),
                                      ),
                                      if (showPhoneError &&
                                          errorMessage != null)
                                        _errorRow(errorMessage!),
                                    ],
                                  )
                                : showOtpField
                                    ? Column(
                                        key: const ValueKey('otp'),
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          _backRow(
                                            label: 'Change phone number',
                                            onTap: formBeingSubmitted
                                                ? null
                                                : () {
                                                    _dismissKeyboard();
                                                    setState(() {
                                                      showOtpField = false;
                                                      showPhoneField = true;
                                                      showOtpError = false;
                                                      errorMessage = null;
                                                      _clearOtpFields();
                                                    });
                                                  },
                                          ),
                                          _otpInputRow(),
                                          if (showOtpError &&
                                              errorMessage != null)
                                            _errorRow(errorMessage!),
                                          const SizedBox(height: 14),
                                          Row(
                                            children: [
                                              const Icon(
                                                Icons.chat_rounded,
                                                size: 16,
                                                color: Color(0xFF25D366),
                                              ),
                                              const SizedBox(width: 6),
                                              const Expanded(
                                                child: Text(
                                                  'OTP sent via WhatsApp',
                                                  style: TextStyle(
                                                    color: _muted,
                                                    fontSize: 12.5,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                              TextButton(
                                                onPressed: (_resendSecondsLeft >
                                                            0 ||
                                                        formBeingSubmitted)
                                                    ? null
                                                    : () =>
                                                        sendOtp(isResend: true),
                                                style: TextButton.styleFrom(
                                                  foregroundColor: _navy,
                                                  disabledForegroundColor:
                                                      _muted,
                                                  padding: EdgeInsets.zero,
                                                  minimumSize: Size.zero,
                                                  tapTargetSize:
                                                      MaterialTapTargetSize
                                                          .shrinkWrap,
                                                ),
                                                child: Text(
                                                  _resendSecondsLeft > 0
                                                      ? 'Resend in ${_resendSecondsLeft}s'
                                                      : 'Resend OTP',
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.w800,
                                                    fontSize: 13,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      )
                                    : Container(
                                        key: const ValueKey('intro'),
                                        padding: const EdgeInsets.all(14),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFFF7F8FB),
                                          borderRadius:
                                              BorderRadius.circular(14),
                                          border:
                                              Border.all(color: _border),
                                        ),
                                        child: const Row(
                                          children: [
                                            Icon(
                                              Icons.chat_outlined,
                                              color: Color(0xFF25D366),
                                              size: 22,
                                            ),
                                            SizedBox(width: 12),
                                            Expanded(
                                              child: Text(
                                                'We will send a one-time password to your registered WhatsApp number.',
                                                style: TextStyle(
                                                  color: _muted,
                                                  fontSize: 13,
                                                  fontWeight: FontWeight.w500,
                                                  height: 1.35,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                          ),
                          if (formBeingSubmitted) ...[
                            const SizedBox(height: 16),
                            Row(
                              children: [
                                const SpinKitRing(
                                  color: _navy,
                                  size: 18,
                                  lineWidth: 2,
                                ),
                                const SizedBox(width: 10),
                                Text(
                                  showOtpField
                                      ? 'Verifying OTP...'
                                      : 'Sending WhatsApp OTP...',
                                  style: const TextStyle(
                                    color: _navy,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 18),
                          SizedBox(
                            width: double.infinity,
                            child: Material(
                              color: formBeingSubmitted
                                  ? _navy.withValues(alpha: 0.7)
                                  : _navy,
                              borderRadius: BorderRadius.circular(14),
                              child: InkWell(
                                onTap:
                                    formBeingSubmitted ? null : _onPrimaryTap,
                                borderRadius: BorderRadius.circular(14),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      vertical: 16),
                                  child: formBeingSubmitted
                                      ? const Center(
                                          child: SpinKitRing(
                                            color: Colors.white,
                                            size: 20,
                                            lineWidth: 2,
                                          ),
                                        )
                                      : Row(
                                          mainAxisAlignment:
                                              MainAxisAlignment.center,
                                          children: [
                                            Text(
                                              getCTAButtonText(),
                                              style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15.5,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Icon(
                                              showOtpField
                                                  ? Icons.verified_user_outlined
                                                  : Icons.arrow_forward_rounded,
                                              color: Colors.white,
                                              size: 18,
                                            ),
                                          ],
                                        ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Center(
                      child: Text(
                        'Need help? Contact your project coordinator.',
                        style: TextStyle(
                          color: _muted,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              ),
            ),
          if (showSplash)
            FadeTransition(
              opacity: _splashFade,
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Image.asset(
                      'assets/images/LOGO WHITE.png',
                      height: 56,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.high,
                      errorBuilder: (_, __, ___) => const Text(
                        'buildAhome',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 28,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 28),
                    const SpinKitRing(
                      color: Colors.white,
                      size: 26,
                      lineWidth: 2.5,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
      ),
    ),
    );
  }
}
