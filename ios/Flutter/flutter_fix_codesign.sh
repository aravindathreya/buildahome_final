#!/bin/bash
# Fix for Flutter code signing issue on simulator
# Remove extended attributes before code signing
if [ -d "$BUILT_PRODUCTS_DIR/Flutter.framework" ]; then
    xattr -rc "$BUILT_PRODUCTS_DIR/Flutter.framework" 2>/dev/null || true
fi
