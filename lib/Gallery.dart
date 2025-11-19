import 'dart:async';
import 'dart:convert';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'FullScreenImage.dart';
import 'app_theme.dart';
import 'services/data_provider.dart';

class Gallery extends StatefulWidget {
  const Gallery({super.key});

  @override
  State<Gallery> createState() => _GalleryState();
}

class _GalleryState extends State<Gallery> {
  List<dynamic> _entries = [];
  List<String> _uniqueDates = [];
  bool _isLoading = false;
  bool _isRefreshing = false;
  String? _errorMessage;
  int _loadRequestId = 0;
  static const Duration _requestTimeout = Duration(seconds: 20);

  @override
  void initState() {
    super.initState();
    _loadGallery();
  }

  Future<void> _loadGallery({bool showLoader = true}) async {
    final int requestId = ++_loadRequestId;

    if (showLoader) {
      if (!mounted) return;
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      if (!mounted) return;
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    }

    try {
      // Try to load from cache first
      final dataProvider = DataProvider();
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      final projectId = prefs.getString('project_id');
      
      if (projectId == null) {
        throw Exception('Project not selected. Please reopen the project and try again.');
      }

      // For non-Client users, check cache first
      List<dynamic>? cachedData;
      if (role != null && role != 'Client' && dataProvider.cachedGallery != null) {
        cachedData = dataProvider.cachedGallery;
      }

      // Use cache if available and not refreshing
      if (cachedData != null && !showLoader) {
        _processData(cachedData, requestId);
        
        // Still refresh in background
        _fetchGalleryFromApi(projectId, requestId, dataProvider);
        return;
      }

      // Fetch from API
      await _fetchGalleryFromApi(projectId, requestId, dataProvider);
    } catch (e) {
      if (_shouldIgnoreLoad(requestId)) return;
      if (!mounted) return;
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (_shouldIgnoreLoad(requestId)) return;
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  Future<void> _fetchGalleryFromApi(String projectId, int requestId, DataProvider dataProvider) async {
    try {
      final response = await http.get(Uri.parse('https://office.buildahome.in/API/get_gallery_data?id=$projectId'))
          .timeout(_requestTimeout);
      
      if (response.statusCode != 200) {
        throw Exception('Unable to load gallery right now. Please try again.');
      }

      final data = jsonDecode(response.body) as List<dynamic>;
      
      // Update cache for non-Client users
      final prefs = await SharedPreferences.getInstance();
      final role = prefs.getString('role');
      if (role != null && role != 'Client') {
        dataProvider.cachedGallery = data;
        dataProvider.lastGalleryLoad = DateTime.now();
      }

      _processData(data, requestId);
    } catch (e) {
      if (_shouldIgnoreLoad(requestId)) return;
      rethrow;
    }
  }

  void _processData(List<dynamic> data, int requestId) {
    if (_shouldIgnoreLoad(requestId)) return;
    if (!mounted) return;

    final dates = <String>[];
    for (final entry in data) {
      final date = entry['date']?.toString();
      if (date != null && !dates.contains(date)) {
        dates.add(date);
      }
    }

    setState(() {
      _entries = data;
      _uniqueDates = dates;
    });
  }

  bool _shouldIgnoreLoad(int requestId) => !mounted || requestId != _loadRequestId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canPop = Navigator.of(context).canPop();
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: AppTheme.backgroundSecondary,
        automaticallyImplyLeading: canPop,
        leading: canPop
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios_new_rounded),
                onPressed: () => Navigator.of(context).maybePop(),
              )
            : null,
        title: Text(
          'Gallery',
          style: theme.textTheme.headlineSmall?.copyWith(fontSize: 20),
        ),
      ),
      body: SafeArea(
        child: RefreshIndicator(
          color: AppTheme.primaryColorConst,
          onRefresh: () => _loadGallery(showLoader: false),
          child: _buildBody(context, theme),
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, ThemeData theme) {
    if (_errorMessage != null && _entries.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 40),
          _buildErrorState(),
        ],
      );
    }

    if (_isLoading && _uniqueDates.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: List.generate(6, (index) => _buildLoadingCard()),
      );
    }

    if (!_isLoading && _uniqueDates.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
        children: [
          _buildHeader(theme),
          const SizedBox(height: 40),
          _buildEmptyState(),
        ],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
      children: [
        _buildHeader(theme),
        const SizedBox(height: 24),
        if (_isRefreshing && _entries.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                ),
              ),
            ),
          ),
        for (final date in _uniqueDates) _buildDateSection(context, date, theme),
      ],
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.error_outline, color: Colors.redAccent, size: 48),
          const SizedBox(height: 12),
          Text(
            'Something went wrong',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 8),
          Text(
            _errorMessage ?? 'Please try again later.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _loadGallery(),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.primaryColorConst,
              foregroundColor: Colors.white,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Project gallery',
          style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Text(
          'Browse chronological site progress photographs shared by the buildAhome team.',
          style: theme.textTheme.bodyMedium?.copyWith(color: AppTheme.textSecondary),
        ),
      ],
    );
  }

  Widget _buildLoadingCard() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 140,
            height: 18,
            decoration: BoxDecoration(
              color: AppTheme.backgroundPrimaryLight,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            children: List.generate(
              3,
              (_) => Container(
                width: 90,
                height: 90,
                decoration: BoxDecoration(
                  color: AppTheme.backgroundPrimaryLight,
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Icon(Icons.photo_library_outlined, color: AppTheme.primaryColorConst, size: 32),
          const SizedBox(height: 12),
          Text(
            'No uploads yet',
            style: TextStyle(fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'You will receive a notification as soon as the team shares the first set of photos.',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }

  Widget _buildDateSection(BuildContext context, String date, ThemeData theme) {
    final items = _entries.where((element) => element['date'] == date).toList();
    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.primaryColorConst.withOpacity(0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: AppTheme.primaryColorConst.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.date_range, size: 18, color: AppTheme.primaryColorConst),
              ),
              const SizedBox(width: 12),
              Text(
                date,
                style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: items.map((entry) => _buildImageTile(context, entry)).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildImageTile(BuildContext context, dynamic entry) {
    final double tileSize = (MediaQuery.of(context).size.width - 16 * 2 - 10 * 2) / 3;
    final imageUrl = "https://office.buildahome.in/files/migrated/${entry['image']}";
    final child = CachedNetworkImage(
      imageUrl: imageUrl,
      fit: BoxFit.cover,
      progressIndicatorBuilder: (context, url, progress) => _buildImageSkeleton(),
      errorWidget: (context, url, error) => _buildBrokenImage(),
    );
    final onTap = () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => FullScreenImage(imageUrl)));

    return AnimatedWidgetSlide(
      direction: SlideDirection.bottomToTop,
      duration: const Duration(milliseconds: 300),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          width: tileSize,
          height: tileSize,
          decoration: BoxDecoration(
            color: AppTheme.backgroundPrimaryLight,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: child,
          ),
        ),
      ),
    );
  }

  Widget _buildBrokenImage() {
    return Container(
      color: AppTheme.backgroundPrimaryLight,
      child: const Center(
        child: Icon(Icons.broken_image_outlined, color: AppTheme.onBackgroundColorConst),
      ),
    );
  }

  Widget _buildImageSkeleton() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                AppTheme.backgroundPrimaryLight,
                AppTheme.backgroundSecondary,
                AppTheme.backgroundPrimaryLight,
              ],
            ),
          ),
        );
      },
    );
  }

}
enum SlideDirection { leftToRight, rightToLeft, topToBottom, bottomToTop }

class AnimatedWidgetSlide extends StatefulWidget {
  final Widget child;
  final SlideDirection direction;
  final Duration duration;

  const AnimatedWidgetSlide({
    super.key,
    required this.child,
    required this.direction,
    required this.duration,
  });

  @override
  State<AnimatedWidgetSlide> createState() => _AnimatedWidgetSlideState();
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
          curve: Curves.easeIn,
        ));
        break;
      case SlideDirection.rightToLeft:
        _slideAnimation = Tween<Offset>(
          begin: const Offset(1.0, 0.0),
          end: const Offset(0.0, 0.0),
        ).animate(CurvedAnimation(
          parent: _animationController,
          curve: Curves.easeIn,
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