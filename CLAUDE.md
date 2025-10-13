# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

DataPass is a native Sailfish OS application for monitoring Telekom data usage. It's built using Qt/QML and follows the standard Sailfish app architecture with:

- **Main application**: `qml/harbour-datapass.qml` - ApplicationWindow with global coverData object
- **Main page**: `qml/pages/MainPage.qml` - Primary UI with data fetching and display logic
- **Cover page**: `qml/cover/CoverPage.qml` - Active cover for quick refresh
- **Build configuration**: `harbour-datapass.pro` - Qt project file with Sailfish-specific settings

## Development Commands

### Building
```bash
# Standard Qt/Sailfish build process
qmake5
make
```

### Packaging
```bash
# RPM packaging for Sailfish OS
rpmbuild -bb rpm/harbour-datapass.spec
```

### Translation Updates
The project includes internationalization support for German, French, and Finnish:
```bash
# Update translation files (handled by Qt build system)
lupdate harbour-datapass.pro
lrelease harbour-datapass.pro
```

## Architecture Notes

- **Global State**: The app uses a `coverData` QtObject in the main ApplicationWindow to share data between the main page and cover
- **API Integration**: Connects to Telekom's public API for data usage monitoring
- **Local Storage**: Implements trend analysis with local data persistence
- **Cover Integration**: Active cover supports pull-to-refresh functionality through the global coverData.refresh() method

## Key Files

- `harbour-datapass.pro` - Project configuration with Sailfish-specific settings
- `qml/harbour-datapass.qml` - Main application window with global data object
- `qml/pages/MainPage.qml` - Primary UI logic
- `rpm/harbour-datapass.spec` - RPM packaging specification
- `translations/` - Multi-language support files

## Platform Specifics

This is a **Sailfish OS application** that:
- Uses Sailfish Silica UI components
- Follows Sailfish app packaging standards (harbour- prefix)
- Requires sailfishsilica-qt5 >= 0.10.9
- Built as noarch RPM package
- Uses standard Sailfish icon sizes (86x86, 108x108, 128x128, 172x172)