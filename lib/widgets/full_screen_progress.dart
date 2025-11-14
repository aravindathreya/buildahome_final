import 'package:flutter/material.dart';
import '../app_theme.dart';

class FullScreenProgress extends StatelessWidget {
  final String title;
  final String message;
  final double progress;
  final String? error;
  final String? errorMessage;

  const FullScreenProgress({
    Key? key,
    required this.title,
    required this.message,
    this.progress = 0.0,
    this.error,
    this.errorMessage,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.backgroundPrimary,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: AppTheme.backgroundSecondary,
        automaticallyImplyLeading: error != null,
        leading: error != null
            ? IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              )
            : null,
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (error == null) ...[
                Container(
                  padding: EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: AppTheme.primaryColorConst.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: CircularProgressIndicator(
                    value: progress > 0 ? progress : null,
                    strokeWidth: 4,
                    valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                  ),
                ),
                SizedBox(height: 32),
                Text(
                  message,
                  style: TextStyle(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                  textAlign: TextAlign.center,
                ),
                SizedBox(height: 24),
                if (progress > 0) ...[
                  Container(
                    width: double.infinity,
                    padding: EdgeInsets.symmetric(horizontal: 16),
                    child: LinearProgressIndicator(
                      value: progress,
                      backgroundColor: AppTheme.backgroundPrimaryLight,
                      valueColor: AlwaysStoppedAnimation<Color>(AppTheme.primaryColorConst),
                      minHeight: 8,
                    ),
                  ),
                  SizedBox(height: 12),
                  Text(
                    "${(progress * 100).toStringAsFixed(0)}%",
                    style: TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ] else ...[
                Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                SizedBox(height: 24),
                Text(
                  "Upload Failed",
                  style: TextStyle(
                    color: Colors.red,
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 16),
                Text(
                  errorMessage ?? "An error occurred during upload",
                  style: TextStyle(
                    color: AppTheme.textSecondary,
                    fontSize: 16,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

