import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ILauncherApp());
}

// ---------------------------------------------------------------------------
// Models + native channel
// ---------------------------------------------------------------------------

class AppInfo {
  final String name;
  final String package;
  final Uint8List icon;
  AppInfo(this.name, this.package, this.icon);
}

class LauncherChannel {
  static const _channel = MethodChannel('ilauncher/apps');

  static Future<List<AppInfo>> getApps() async {
    final List<dynamic> raw = await _channel.invokeMethod('getApps');
    return raw
        .map((e) => AppInfo(
      e['name'] as String,
      e['package'] as String,
      e['icon'] as Uint8List,
    ))
        .toList();
  }

  static Future<void> launchApp(String package) =>
      _channel.invokeMethod('launchApp', {'package': package});
}

// ---------------------------------------------------------------------------
// App
// ---------------------------------------------------------------------------

class ILauncherApp extends StatelessWidget {
  const ILauncherApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true),
      home: const HomeScreen(),
    );
  }
}

// Built-in wallpapers (gradients)
const List<List<Color>> kGradients = [
  [Color(0xFF1B2A49), Color(0xFF3B1E54), Color(0xFF0B0B14)], // Midnight
  [Color(0xFF0F2027), Color(0xFF203A43), Color(0xFF2C5364)], // Ocean
  [Color(0xFFFF9966), Color(0xFFFF5E62), Color(0xFF6A1B4D)], // Sunset
  [Color(0xFF134E5E), Color(0xFF71B280), Color(0xFF0B3B2E)], // Forest
  [Color(0xFF232526), Color(0xFF414345), Color(0xFF0D0D0D)], // Graphite
];

// Dock mein pehle ye apps dhoondi jayengi (Phone, Messages, Browser, Camera)
const List<List<String>> kDockPreferred = [
  [
    'com.google.android.dialer',
    'com.android.dialer',
    'com.samsung.android.dialer',
  ],
  [
    'com.google.android.apps.messaging',
    'com.android.messaging',
    'com.samsung.android.messaging',
    'com.android.mms',
  ],
  ['com.android.chrome', 'org.mozilla.firefox', 'com.brave.browser'],
  [
    'com.android.camera',
    'com.android.camera2',
    'com.google.android.GoogleCamera',
    'com.sec.android.app.camera',
  ],
];

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<AppInfo> _apps = [];
  bool _loading = true;
  String? _error;

  DateTime _now = DateTime.now();
  Timer? _timer;

  int _page = 0;

  int _gradientIndex = 0;
  String? _wallpaperPath;

  static const int _cols = 4;
  static const int _rows = 6;
  static const int _perPage = _cols * _rows;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _loadApps();
    _timer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  // ----------------------------- Prefs / wallpaper -------------------------

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _gradientIndex = prefs.getInt('gradient_index') ?? 0;
      _wallpaperPath = prefs.getString('wallpaper_path');
    });
  }

  Future<void> _selectGradient(int index) async {
    final prefs = await SharedPreferences.getInstance();
    await _deleteOldWallpaperFile();
    await prefs.setInt('gradient_index', index);
    await prefs.remove('wallpaper_path');
    if (!mounted) return;
    setState(() {
      _gradientIndex = index;
      _wallpaperPath = null;
    });
  }

  Future<void> _deleteOldWallpaperFile() async {
    if (_wallpaperPath == null) return;
    try {
      await File(_wallpaperPath!).delete();
    } catch (_) {}
  }

  Future<void> _pickFromGallery() async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1600,
        imageQuality: 90,
      );
      if (picked == null) return;

      final dir = await getApplicationDocumentsDirectory();
      final newPath =
          '${dir.path}/wallpaper_${DateTime.now().millisecondsSinceEpoch}.jpg';
      await File(picked.path).copy(newPath);

      await _deleteOldWallpaperFile();

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('wallpaper_path', newPath);
      if (!mounted) return;
      setState(() => _wallpaperPath = newPath);
    } catch (e) {
      debugPrint('Wallpaper pick ERROR: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Wallpaper set nahi hua: $e')),
      );
    }
  }

  void _openWallpaperSheet() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1C1C1E),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Wallpaper',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 84,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: kGradients.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 12),
                    itemBuilder: (_, i) {
                      final selected =
                          _wallpaperPath == null && _gradientIndex == i;
                      return GestureDetector(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _selectGradient(i);
                        },
                        child: Container(
                          width: 56,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: kGradients[i],
                            ),
                            border: Border.all(
                              color: selected ? Colors.white : Colors.white24,
                              width: selected ? 2.5 : 1,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pop(sheetContext);
                      _pickFromGallery();
                    },
                    icon: const Icon(Icons.photo_library_outlined),
                    label: const Text('Gallery se photo chuno'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ----------------------------- Apps -------------------------------------

  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await LauncherChannel.getApps();
      apps.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      if (!mounted) return;
      setState(() {
        _apps = apps;
        _loading = false;
      });
    } catch (e, st) {
      debugPrint('getApps ERROR: $e');
      debugPrint('$st');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Dock ki 4 apps chuno. Pehle Phone/Messages/Browser/Camera, baqi jagah
  /// pehli available apps se bharo.
  List<AppInfo> _pickDockApps() {
    final dock = <AppInfo>[];
    for (final group in kDockPreferred) {
      for (final pkg in group) {
        final match = _apps.where((a) => a.package == pkg);
        if (match.isNotEmpty) {
          dock.add(match.first);
          break;
        }
      }
    }
    for (final app in _apps) {
      if (dock.length >= 4) break;
      if (!dock.any((d) => d.package == app.package)) dock.add(app);
    }
    return dock.take(4).toList();
  }

  // ----------------------------- UI pieces --------------------------------

  Widget _wallpaper() {
    final path = _wallpaperPath;
    if (path != null && File(path).existsSync()) {
      return Stack(
        fit: StackFit.expand,
        children: [
          Image.file(File(path), fit: BoxFit.cover, gaplessPlayback: true),
          Container(color: Colors.black.withOpacity(0.18)),
        ],
      );
    }
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: kGradients[_gradientIndex],
        ),
      ),
    );
  }

  Widget _dateLabel() {
    return Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 6),
      child: Text(
        DateFormat('EEEE, d MMMM').format(_now),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w500,
          color: Colors.white.withOpacity(0.85),
        ),
      ),
    );
  }

  Widget _pageDots(int count) {
    if (count <= 1) return const SizedBox(height: 14);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: List.generate(count, (i) {
          final active = i == _page;
          return AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            margin: const EdgeInsets.symmetric(horizontal: 4),
            width: active ? 8 : 7,
            height: active ? 8 : 7,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white.withOpacity(active ? 0.95 : 0.4),
            ),
          );
        }),
      ),
    );
  }

  Widget _dock(List<AppInfo> dockApps) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(34),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
            constraints: const BoxConstraints(minHeight: 60),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.22),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(color: Colors.white.withOpacity(0.12)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: dockApps
                  .map((a) => AppIcon(app: a, showLabel: false))
                  .toList(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGrid(List<AppInfo> gridApps, int pageCount) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline,
                  size: 48, color: Colors.redAccent),
              const SizedBox(height: 12),
              const Text(
                'Apps load nahi hui',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              SelectableText(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: Colors.white70),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadApps,
                child: const Text('Dobara try karo'),
              ),
            ],
          ),
        ),
      );
    }

    if (_apps.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Koi app nahi mili (list khali hai)',
                style: TextStyle(fontSize: 16)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: _loadApps,
              child: const Text('Dobara try karo'),
            ),
          ],
        ),
      );
    }

    return PageView.builder(
      physics: const BouncingScrollPhysics(),
      itemCount: pageCount,
      onPageChanged: (p) => setState(() => _page = p),
      itemBuilder: (context, page) {
        final start = page * _perPage;
        final end = (start + _perPage).clamp(0, gridApps.length);
        final items = gridApps.sublist(start, end);
        return GridView.builder(
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _cols,
            mainAxisSpacing: 14,
            crossAxisSpacing: 8,
            childAspectRatio: 0.78,
          ),
          itemCount: items.length,
          itemBuilder: (_, i) => AppIcon(app: items[i]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final dockApps = _pickDockApps();
    final gridApps = _apps
        .where((a) => !dockApps.any((d) => d.package == a.package))
        .toList();
    final pageCount = (gridApps.length / _perPage).ceil().clamp(1, 99);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        // Khali jagah par long-press = wallpaper badlo
        onLongPress: _openWallpaperSheet,
        child: Stack(
          children: [
            Positioned.fill(child: _wallpaper()),
            SafeArea(
              child: Column(
                children: [
                  _dateLabel(),
                  Expanded(child: _buildGrid(gridApps, pageCount)),
                  _pageDots(pageCount),
                  _dock(dockApps),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Widgets
// ---------------------------------------------------------------------------

/// iOS jaisa "squircle" icon (continuous corner curve + halka shadow)
class SquircleIcon extends StatelessWidget {
  final Uint8List bytes;
  final double size;
  const SquircleIcon({super.key, required this.bytes, this.size = 58});

  @override
  Widget build(BuildContext context) {
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(size * 0.45),
    );
    return Container(
      width: size,
      height: size,
      decoration: ShapeDecoration(
        shape: shape,
        // transparent icons ke peeche halka background
        color: Colors.white.withOpacity(0.14),
        shadows: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ClipPath(
        clipper: ShapeBorderClipper(shape: shape),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          gaplessPlayback: true,
        ),
      ),
    );
  }
}

class AppIcon extends StatelessWidget {
  final AppInfo app;
  final bool showLabel;
  const AppIcon({super.key, required this.app, this.showLabel = true});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => LauncherChannel.launchApp(app.package),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SquircleIcon(bytes: app.icon),
          if (showLabel) ...[
            const SizedBox(height: 6),
            Text(
              app.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white,
                shadows: [Shadow(color: Colors.black54, blurRadius: 4)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}