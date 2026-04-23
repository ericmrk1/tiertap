#!/bin/sh
PLIST="${BUILT_PRODUCTS_DIR}/${WRAPPER_NAME}/Info.plist"
if [ -f "$PLIST" ]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleIconName AppIcon" "$PLIST" 2>/dev/null || /usr/libexec/PlistBuddy -c "Add :CFBundleIconName string AppIcon" "$PLIST"
fi

