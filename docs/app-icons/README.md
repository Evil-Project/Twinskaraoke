# Experimental app icons

Settings → Experiments → Enable Experiments → App Icon shows light and dark previews for Original and Experimental. Original is the default. The OS owns the selection; failed changes keep the actual selection and show an alert. App Icon remains accessible to restore Original if Experiments is disabled while Experimental is selected.

The app always uses `AppIcon.icon`, `ExperimentalAppIcon.icon`, and four fixed images in `IconPreviews.xcassets`. It has no build-profile detection or profile-specific icon names. Watch uses `AppIcon.icon` for its installed icon; watchOS does not support changing that icon at runtime.

Icon previews are exported from their Icon Composer packages using Xcode’s `ictool`, with Default and Dark renditions at 256×256. Regenerate them when changing the artwork.

Tests cover bundled resources, switching and restoring, errors and retry, relaunch, unsupported devices, concurrent requests, and the chooser UI. Verify Home Screen changes on a physical iPhone or iPad.
