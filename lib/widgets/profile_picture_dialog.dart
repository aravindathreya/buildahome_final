import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../app_theme.dart';
import '../services/profile_picture_service.dart';

/// Shows a startup prompt if the user has no profile picture yet.
///
/// Staff / non-client users may skip with "Maybe later" only
/// [ProfilePictureService.maxStartupSkips] times; after that the dialog is
/// required until a photo is uploaded.
Future<void> maybePromptForProfilePicture(BuildContext context) async {
  if (ProfilePictureService.promptShownThisSession) {
    debugPrint('[ProfilePic] skip — already shown this session');
    return;
  }
  final existing = await ProfilePictureService.getStoredPath();
  if (existing != null) {
    debugPrint('[ProfilePic] skip — picture already set ($existing)');
    return;
  }
  if (!context.mounted) {
    debugPrint('[ProfilePic] skip — context not mounted');
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  final role = (prefs.getString('role') ?? '').trim().toLowerCase();
  final userId =
      (prefs.getString('userId') ?? prefs.getString('user_id') ?? '').trim();
  final isClient = role == 'client';

  // Clients keep a soft optional prompt; other roles get the skip limit.
  final enforceSkipLimit = !isClient;
  final remaining = enforceSkipLimit
      ? await ProfilePictureService.remainingSkips()
      : ProfilePictureService.maxStartupSkips;
  final requirePhoto = enforceSkipLimit && remaining <= 0;

  if (!context.mounted) return;

  debugPrint(
    '[ProfilePic] showing prompt userId=$userId role=$role '
    'remaining=$remaining require=$requirePhoto',
  );
  try {
    ProfilePictureService.promptShownThisSession = true;
    await showProfilePictureDialog(
      context,
      isStartupPrompt: true,
      remainingSkips: remaining,
      requirePhoto: requirePhoto,
    );
  } catch (e) {
    ProfilePictureService.promptShownThisSession = false;
    debugPrint('[ProfilePic] dialog failed: $e');
  }
}

/// Profile picture picker + upload dialog.
///
/// Returns the new picture path when uploaded, otherwise `null`.
Future<String?> showProfilePictureDialog(
  BuildContext context, {
  bool isStartupPrompt = false,
  String? currentPicturePath,
  int? remainingSkips,
  bool requirePhoto = false,
}) {
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: !requirePhoto,
    builder: (dialogContext) => PopScope(
      canPop: !requirePhoto,
      child: _ProfilePictureDialog(
        isStartupPrompt: isStartupPrompt,
        currentPicturePath: currentPicturePath,
        remainingSkips: remainingSkips,
        requirePhoto: requirePhoto,
      ),
    ),
  );
}

class _ProfilePictureDialog extends StatefulWidget {
  final bool isStartupPrompt;
  final String? currentPicturePath;
  final int? remainingSkips;
  final bool requirePhoto;

  const _ProfilePictureDialog({
    required this.isStartupPrompt,
    this.currentPicturePath,
    this.remainingSkips,
    this.requirePhoto = false,
  });

  @override
  State<_ProfilePictureDialog> createState() => _ProfilePictureDialogState();
}

class _ProfilePictureDialogState extends State<_ProfilePictureDialog> {
  bool _uploading = false;
  String? _error;
  String? _localPreviewPath;

  Future<void> _pickAndUpload(ImageSource source) async {
    if (_uploading) return;
    setState(() {
      _error = null;
    });

    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1280,
        maxHeight: 1280,
        imageQuality: 85,
      );
      if (picked == null) return;

      if (!mounted) return;
      setState(() {
        _localPreviewPath = picked.path;
        _uploading = true;
        _error = null;
      });

      final path = await ProfilePictureService.upload(File(picked.path));
      if (!mounted) return;
      Navigator.of(context).pop(path);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _uploading = false;
        _error = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      });
    }
  }

  Future<void> _onMaybeLater() async {
    if (_uploading || widget.requirePhoto) return;
    if (widget.isStartupPrompt && widget.remainingSkips != null) {
      await ProfilePictureService.recordStartupSkip();
    }
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  String get _skipLabel {
    final left = widget.remainingSkips;
    if (left == null) {
      return widget.isStartupPrompt ? 'Maybe later' : 'Cancel';
    }
    if (left <= 1) return 'Skip (1)';
    return 'Maybe later ($left left)';
  }

  @override
  Widget build(BuildContext context) {
    final currentUrl =
        ProfilePictureService.resolveUrl(widget.currentPicturePath);
    final showSkip = widget.isStartupPrompt
        ? !widget.requirePhoto
        : true;

    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titlePadding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      title: Text(
        widget.isStartupPrompt
            ? 'Add a profile picture'
            : 'Update profile picture',
        style: const TextStyle(
          color: AppTheme.navy,
          fontWeight: FontWeight.w800,
          fontSize: 18,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.requirePhoto
                ? 'You’ve used all skips. Please add a photo so your team can recognise you.'
                : widget.isStartupPrompt
                    ? 'Set a photo so your team can recognise you easily.'
                    : 'Choose a photo from your gallery or take a new one.',
            style: const TextStyle(
              color: AppTheme.mutedGrey,
              fontSize: 14,
              height: 1.35,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (widget.isStartupPrompt &&
              !widget.requirePhoto &&
              widget.remainingSkips != null) ...[
            const SizedBox(height: 8),
            Text(
              widget.remainingSkips! <= 1
                  ? 'Last skip available — after this you’ll need to add a photo.'
                  : 'You can skip ${widget.remainingSkips} more time${widget.remainingSkips == 1 ? '' : 's'}.',
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          const SizedBox(height: 20),
          _buildPreview(currentUrl),
          if (_uploading) ...[
            const SizedBox(height: 16),
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2.4),
            ),
            const SizedBox(height: 8),
            const Text(
              'Uploading…',
              style: TextStyle(
                color: AppTheme.mutedGrey,
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(
              _error!,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFFDC2626),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 8),
          _sourceTile(
            icon: Icons.camera_alt_rounded,
            label: 'Take photo',
            onTap: _uploading ? null : () => _pickAndUpload(ImageSource.camera),
          ),
          _sourceTile(
            icon: Icons.photo_library_rounded,
            label: 'Choose from gallery',
            onTap:
                _uploading ? null : () => _pickAndUpload(ImageSource.gallery),
          ),
        ],
      ),
      actions: [
        if (showSkip)
          TextButton(
            onPressed: _uploading ? null : _onMaybeLater,
            child: Text(
              widget.isStartupPrompt ? _skipLabel : 'Cancel',
              style: const TextStyle(
                color: AppTheme.mutedGrey,
                fontWeight: FontWeight.w700,
              ),
            ),
          )
        else
          const SizedBox.shrink(),
      ],
    );
  }

  Widget _buildPreview(String? currentUrl) {
    final hasLocal = _localPreviewPath != null;
    return Container(
      width: 88,
      height: 88,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.navy.withValues(alpha: 0.08),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: hasLocal
          ? Image.file(File(_localPreviewPath!), fit: BoxFit.cover)
          : currentUrl != null
              ? CachedNetworkImage(
                  imageUrl: currentUrl,
                  fit: BoxFit.cover,
                  placeholder: (_, __) => const Center(
                    child: Icon(Icons.person_rounded,
                        color: AppTheme.mutedGrey, size: 36),
                  ),
                  errorWidget: (_, __, ___) => const Center(
                    child: Icon(Icons.person_rounded,
                        color: AppTheme.mutedGrey, size: 36),
                  ),
                )
              : const Center(
                  child: Icon(Icons.person_rounded,
                      color: AppTheme.mutedGrey, size: 36),
                ),
    );
  }

  Widget _sourceTile({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: AppTheme.navy.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Icon(icon, color: AppTheme.navy, size: 20),
      ),
      title: Text(
        label,
        style: TextStyle(
          color: onTap == null ? AppTheme.mutedGrey : AppTheme.navy,
          fontWeight: FontWeight.w700,
          fontSize: 15,
        ),
      ),
      trailing: Icon(
        Icons.chevron_right_rounded,
        color: onTap == null ? AppTheme.mutedGrey : AppTheme.navy,
      ),
      onTap: onTap,
    );
  }
}

/// Circular avatar that shows the network profile picture or initials fallback.
class ProfileAvatar extends StatelessWidget {
  final String? picturePath;
  final String displayName;
  final double size;
  final Color backgroundColor;
  final Color foregroundColor;
  final Color? borderColor;
  final VoidCallback? onTap;
  final bool showEditBadge;

  const ProfileAvatar({
    super.key,
    required this.displayName,
    this.picturePath,
    this.size = 52,
    this.backgroundColor = const Color(0x1FFFFFFF),
    this.foregroundColor = Colors.white,
    this.borderColor,
    this.onTap,
    this.showEditBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final url = ProfilePictureService.resolveUrl(picturePath);
    final initial = displayName.trim().isNotEmpty
        ? displayName.trim()[0].toUpperCase()
        : 'U';

    final avatar = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: backgroundColor,
        shape: BoxShape.circle,
        border: Border.all(
          color: borderColor ?? Colors.white.withValues(alpha: 0.2),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      alignment: Alignment.center,
      child: url == null
          ? Text(
              initial,
              style: TextStyle(
                color: foregroundColor,
                fontSize: size * 0.42,
                fontWeight: FontWeight.w800,
              ),
            )
          : CachedNetworkImage(
              imageUrl: url,
              width: size,
              height: size,
              fit: BoxFit.cover,
              placeholder: (_, __) => Text(
                initial,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w800,
                ),
              ),
              errorWidget: (_, __, ___) => Text(
                initial,
                style: TextStyle(
                  color: foregroundColor,
                  fontSize: size * 0.42,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
    );

    final withBadge = showEditBadge
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              avatar,
              Positioned(
                right: -2,
                bottom: -2,
                child: Container(
                  width: size * 0.34,
                  height: size * 0.34,
                  decoration: BoxDecoration(
                    color: AppTheme.accentBlue,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(
                    Icons.camera_alt_rounded,
                    size: size * 0.18,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          )
        : avatar;

    if (onTap == null) return withBadge;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: withBadge,
    );
  }
}
