import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:photo_view/photo_view.dart';

import 'app_theme.dart';
import 'widgets/skeleton_loader.dart';

class FullScreenImage extends StatefulWidget {
  final String id;
  final List<String>? imageUrls;
  final int initialIndex;

  const FullScreenImage(
    this.id, {
    super.key,
    this.imageUrls,
    this.initialIndex = 0,
  });

  List<String> get urls {
    if (imageUrls != null && imageUrls!.isNotEmpty) return imageUrls!;
    return [id];
  }

  @override
  State<FullScreenImage> createState() => _FullScreenImageState();
}

class _FullScreenImageState extends State<FullScreenImage> {
  late final PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    final urls = widget.urls;
    _currentIndex = widget.initialIndex.clamp(0, urls.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  ImageProvider _imageProvider(String url) {
    final uri = Uri.tryParse(url);
    if (uri != null && (uri.scheme == 'http' || uri.scheme == 'https')) {
      return CachedNetworkImageProvider(url);
    }

    final file = File(url);
    if (file.existsSync()) {
      return FileImage(file);
    }

    return CachedNetworkImageProvider(url);
  }

  void _goTo(int index) {
    final target = index.clamp(0, widget.urls.length - 1);
    _pageController.animateToPage(
      target,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Widget _navArrow(IconData icon, VoidCallback onTap) {
    return Material(
      color: Colors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(icon, color: Colors.white, size: 30),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final urls = widget.urls;
    final hasMultiple = urls.length > 1;

    return Theme(
      data: AppTheme.darkTheme,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          automaticallyImplyLeading: true,
          backgroundColor: Colors.black,
          iconTheme: const IconThemeData(color: Colors.white),
          title: Text(
            hasMultiple
                ? '${_currentIndex + 1} / ${urls.length}'
                : 'Image preview',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: PageView.builder(
                  controller: _pageController,
                  itemCount: urls.length,
                  onPageChanged: (index) {
                    setState(() => _currentIndex = index);
                  },
                  itemBuilder: (context, index) {
                    return PhotoView(
                      backgroundDecoration:
                          const BoxDecoration(color: Colors.black),
                      minScale: PhotoViewComputedScale.contained,
                      imageProvider: _imageProvider(urls[index]),
                      loadingBuilder: (context, event) => const Center(
                        child: SizedBox(
                          width: 120,
                          height: 120,
                          child: SkeletonImage(radius: 16),
                        ),
                      ),
                      errorBuilder: (context, error, stackTrace) => Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.broken_image_outlined,
                              color: Colors.white54,
                              size: 48,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'Could not load image',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.7),
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
                    ),
                    if (hasMultiple && _currentIndex > 0)
                      Positioned(
                        left: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _navArrow(
                            Icons.chevron_left_rounded,
                            () => _goTo(_currentIndex - 1),
                          ),
                        ),
                      ),
                    if (hasMultiple && _currentIndex < urls.length - 1)
                      Positioned(
                        right: 8,
                        top: 0,
                        bottom: 0,
                        child: Center(
                          child: _navArrow(
                            Icons.chevron_right_rounded,
                            () => _goTo(_currentIndex + 1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              if (hasMultiple) ...[
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(urls.length, (index) {
                    final active = index == _currentIndex;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: active ? 18 : 7,
                      height: 7,
                      decoration: BoxDecoration(
                        color: active
                            ? Colors.white
                            : Colors.white.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(99),
                      ),
                    );
                  }),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
