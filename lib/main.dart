import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

void main() => runApp(const VidKlipzoProApp());

class VidKlipzoProApp extends StatelessWidget {
  const VidKlipzoProApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vid Klipzo Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: const Color(0xFF0C0D14),
      ),
      home: const LoginScreen(),
    );
  }
}

// १. लॉगिन स्क्रीन
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF2B124C), Color(0xFF0C0D14)],
            stops: [0.0, 0.45],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'Vid Klipzo Pro',
                  style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 18),
                ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: [Color(0xFFD946EF), Color(0xFF38BDF8)],
                  ).createShader(bounds),
                  child: const Text(
                    'Welcome Back!',
                    style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
                const SizedBox(height: 6),
                const Text('Sign In to Your Account', style: TextStyle(color: Colors.white70)),
                const SizedBox(height: 28),
                TextField(
                  decoration: InputDecoration(
                    hintText: 'Email or Phone',
                    filled: true,
                    fillColor: const Color(0xFF171926),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFF38BDF8)),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  obscureText: true,
                  decoration: InputDecoration(
                    hintText: 'Password',
                    filled: true,
                    fillColor: const Color(0xFF171926),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFD946EF)),
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  width: double.infinity,
                  height: 50,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFFD946EF), Color(0xFF38BDF8)]),
                    borderRadius: BorderRadius.circular(25),
                  ),
                  child: ElevatedButton(
                    onPressed: () {
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (_) => const MainDashboard()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.transparent,
                      shadowColor: Colors.transparent,
                    ),
                    child: const Text('Login', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                  ),
                ),
                TextButton(
                  onPressed: () {
                    Navigator.pushReplacement(
                      context,
                      MaterialPageRoute(builder: (_) => const MainDashboard()),
                    );
                  },
                  child: const Text('Skip Login (Guest Mode)', style: TextStyle(color: Colors.white54)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// २. मुख्य डैशबोर्ड (नीला नियॉन लिंक बार + रंग-बिरंगे नियॉन बटन)
class MainDashboard extends StatefulWidget {
  const MainDashboard({super.key});

  @override
  State<MainDashboard> createState() => _MainDashboardState();
}

class _MainDashboardState extends State<MainDashboard> {
  final TextEditingController _searchController = TextEditingController();
  int _tabIndex = 0;
  String _selectedCategory = 'All';

  // हर कैटेगरी बटन का अलग नियॉन रंग
  final List> _categories = [
    {'name': 'All', 'color': const Color(0xFF38BDF8)},
    {'name': 'Gaming', 'color': const Color(0xFFEC4899)},
    {'name': 'Music', 'color': const Color(0xFFA855F7)},
    {'name': 'Tech', 'color': const Color(0xFF22C55E)},
    {'name': 'Movie Trailers', 'color': const Color(0xFFF59E0B)},
  ];

  final List> _feedVideos = [
    {
      'title': 'Amazing Sci-Fi Cinematic Trailer 4K',
      'channel': '@ExploreWithLira',
      'meta': '1.2M views • 3 days ago',
      'duration': '10:15',
      'url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ',
    },
    {
      'title': 'Mysteries of Space & Universe Science (Full HD)',
      'channel': '@ScienceWorld',
      'meta': '850K views • 1 week ago',
      'duration': '05:24',
      'url': 'https://www.youtube.com/watch?v=libKVRa01L8',
    },
    {
      'title': 'How Black Holes Work in Deep Space',
      'channel': '@CosmicJourney',
      'meta': '640K views • 2 weeks ago',
      'duration': '08:42',
      'url': 'https://www.youtube.com/watch?v=e-P5IFTqB98',
    },
  ];

  void _openPlayer(String url, String title, String channel) {
    final videoId = YoutubePlayer.convertUrlToId(url);
    if (videoId == null || videoId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('कृपया सही YouTube वीडियो लिंक डालें')),
      );
      return;
    }
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VideoPlayerScreen(
          videoId: videoId,
          title: title,
          channel: channel,
          suggestedVideos: _feedVideos,
        ),
      ),
    );
  }

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null && data!.text!.isNotEmpty) {
      setState(() => _searchController.text = data.text!);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('लिंक पेस्ट हो गया!')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF32145A),
              Color(0xFF151326),
              Color(0xFF0C0D14),
            ],
            stops: [0.0, 0.28, 0.65],
          ),
        ),
        child: SafeArea(
          child: _tabIndex == 1 ? _buildDownloadsTab() : _buildHomeTab(),
        ),
      ),
      bottomNavigationBar: _customBottomNavBar(_tabIndex, (i) => setState(() => _tabIndex = i)),
    );
  }

  Widget _buildHomeTab() {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // 1. टॉप हेडर: Vid Klipzo Pro + PRO ₹150 बैज
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'Vid Klipzo\nPro',
              style: TextStyle(fontSize: 25, fontWeight: FontWeight.bold, height: 1.15),
            ),
            _proBadge(context),
          ],
        ),
        const SizedBox(height: 16),

        // 2. नीले नियॉन बॉर्डर वाला लिंक पेस्ट और प्ले बार
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFF111526).withOpacity(0.92),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFF38BDF8), width: 1.8),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFF38BDF8).withOpacity(0.45),
                blurRadius: 14,
                spreadRadius: 1,
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  onSubmitted: (val) => _openPlayer(val.trim(), 'Custom Video Stream', '@VidKlipzoPro'),
                  decoration: const InputDecoration(
                    hintText: 'Paste link here...',
                    hintStyle: TextStyle(color: Colors.white54, fontSize: 13),
                    border: InputBorder.none,
                    contentPadding: EdgeInsets.symmetric(horizontal: 6),
                  ),
                ),
              ),
              // नीला चमकता Paste बटन
              Container(
                height: 34,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0EA5E9).withOpacity(0.22),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF38BDF8), width: 1.3),
                ),
                child: TextButton(
                  onPressed: _pasteFromClipboard,
                  style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 12)),
                  child: const Text(
                    'Paste',
                    style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              // गुलाबी-नीला ग्रेडिएंट Play बटन
              Container(
                height: 34,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFFEC4899), Color(0xFF38BDF8)],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFFEC4899).withOpacity(0.4),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: ElevatedButton(
                  onPressed: () => _openPlayer(_searchController.text.trim(), 'Custom Video Stream', '@VidKlipzoPro'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text(
                    'Play',
                    style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // 3. रंग-बिरंगे चमकते नियॉन कैटेगरी बटन
        SizedBox(
          height: 38,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            itemCount: _categories.length,
            itemBuilder: (context, index) {
              final catName = _categories[index]['name'] as String;
              final Color neonColor = _categories[index]['color'] as Color;
              final isSelected = _selectedCategory == catName;

              return GestureDetector(
                onTap: () => setState(() => _selectedCategory = catName),
                child: Container(
                  margin: const EdgeInsets.only(right: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? neonColor : neonColor.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: neonColor, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: neonColor.withOpacity(isSelected ? 0.55 : 0.25),
                        blurRadius: 10,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                  child: Text(
                    catName,
                    style: TextStyle(
                      color: isSelected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 18),

        // 4. बड़े वीडियो कार्ड्स और चमकते हुए Download बटन
        ..._feedVideos.map((video) {
          final vidId = YoutubePlayer.convertUrlToId(video['url']!) ?? 'aqz-KE-bpKQ';
          return Container(
            margin: const EdgeInsets.only(bottom: 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                GestureDetector(
                  onTap: () => _openPlayer(video['url']!, video['title']!, video['channel']!),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Image.network(
                          'https://img.youtube.com/vi/$vidId/hqdefault.jpg',
                          height: 190,
                          width: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        bottom: 10,
                        right: 10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            video['duration']!,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const CircleAvatar(
                      radius: 17,
                      backgroundColor: Color(0xFF282442),
                      child: Icon(Icons.play_arrow_rounded, color: Color(0xFF38BDF8), size: 20),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            video['title']!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            video['meta']!,
                            style: const TextStyle(fontSize: 12, color: Colors.white54),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      height: 36,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFD946EF), Color(0xFF38BDF8)],
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFD946EF).withOpacity(0.5),
                            blurRadius: 12,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      child: ElevatedButton(
                        onPressed: () {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('डाउनलोड शुरू हो गया: ${video['title']}')),
                          );
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                        ),
                        child: const Text(
                          'Download',
                          style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // डाउनलोड टैब (Private Lock और Ringtone बटन के साथ)
  Widget _buildDownloadsTab() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('My Downloads', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              ElevatedButton.icon(
                onPressed: () {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Private Folder: पिन या फ़िंगरप्रिंट लॉक सेट करें')),
                  );
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF1A1C29)),
                icon: const Icon(Icons.lock, color: Colors.amber, size: 18),
                label: const Text('Private Lock', style: TextStyle(color: Colors.amber)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF141622),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Row(
              children: [
                const Icon(Icons.music_note, color: Color(0xFFD946EF), size: 32),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sample Audio Track.mp3', style: TextStyle(fontWeight: FontWeight.bold)),
                      Text('3.4 MB • Ready to cut ringtone', style: TextStyle(fontSize: 12, color: Colors.white54)),
                    ],
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Ringtone Cutter खुला: गाना काटकर रिंगटोन बनाएँ')),
                    );
                  },
                  style: OutlinedButton.styleFrom(side: const BorderSide(color: Color(0xFF38BDF8))),
                  icon: const Icon(Icons.content_cut, size: 16, color: Color(0xFF38BDF8)),
                  label: const Text('Ringtone', style: TextStyle(color: Color(0xFF38BDF8), fontSize: 12)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ३. वीडियो प्लेयर स्क्रीन (सभी ९ नियॉन बटन के साथ)
class VideoPlayerScreen extends StatefulWidget {
  final String videoId;
  final String title;
  final String channel;
  final List> suggestedVideos;

  const VideoPlayerScreen({
    super.key,
    required this.videoId,
    required this.title,
    required this.channel,
    required this.suggestedVideos,
  });

  @override
  State<VideoPlayerScreen> createState() => _VideoPlayerScreenState();
}

class _VideoPlayerScreenState extends State<VideoPlayerScreen> {
  late YoutubePlayerController _controller;
  bool isLiked = false;
  bool isSaved = false;
  bool isAudioOnly = false;
  bool isBgPlay = false;
  String quality = '720p';
  double speed = 1.0;
  int _tabIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = YoutubePlayerController(
      initialVideoId: widget.videoId,
      flags: const YoutubePlayerFlags(autoPlay: true),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _showMsg(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(text), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Stack(
              children: [
                YoutubePlayer(
                  controller: _controller,
                  showVideoProgressIndicator: true,
                  progressIndicatorColor: const Color(0xFFD946EF),
                ),
                Positioned(
                  top: 8,
                  left: 8,
                  child: CircleAvatar(
                    backgroundColor: Colors.black54,
                    radius: 18,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: const Icon(Icons.arrow_back, color: Colors.white, size: 18),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ),
                ),
                Positioned(top: 8, right: 8, child: _proBadge(context)),
              ],
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(14),
                children: [
                  Text(widget.title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(widget.channel, style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        _glowCircleButton(
                          icon: isLiked ? Icons.favorite : Icons.favorite_border,
                          label: 'Like',
                          glowColor: const Color(0xFFD946EF),
                          isActive: isLiked,
                          onTap: () {
                            setState(() => isLiked = !isLiked);
                            _showMsg(isLiked ? 'वीडियो लाइक किया गया' : 'लाइक हटाया गया');
                          },
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: Icons.chat_bubble_outline,
                          label: 'Comment',
                          glowColor: const Color(0xFF38BDF8),
                          onTap: () => _showMsg('कमेंट सेक्शन खुला'),
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: Icons.headphones,
                          label: 'Audio',
                          glowColor: const Color(0xFFA855F7),
                          isActive: isAudioOnly,
                          onTap: () {
                            setState(() => isAudioOnly = !isAudioOnly);
                            _showMsg(isAudioOnly ? 'Only Audio मोड चालू (MP3)' : 'वीडियो मोड चालू');
                          },
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: Icons.download_rounded,
                          label: 'Download',
                          glowColor: const Color(0xFFEC4899),
                          isFilledGradient: true,
                          onTap: () => _showMsg('डाउनलोड शुरू हो गया...'),
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: isSaved ? Icons.bookmark : Icons.bookmark_border,
                          label: 'Save',
                          glowColor: Colors.amber,
                          isActive: isSaved,
                          onTap: () {
                            setState(() => isSaved = !isSaved);
                            _showMsg(isSaved ? 'वीडियो सेव हो गया' : 'सेव से हटाया गया');
                          },
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: Icons.hd_outlined,
                          label: quality,
                          glowColor: Colors.greenAccent,
                          onTap: () {
                            setState(() {
                              quality = quality == '360p' ? '720p' : (quality == '720p' ? '4K PRO' : '360p');
                            });
                            _showMsg(quality == '4K PRO'
                                ? '4K क्वालिटी के लिए PRO ₹150 प्लान चुनें!'
                                : 'वीडियो क्वालिटी: $quality');
                          },
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: Icons.picture_in_picture_alt,
                          label: 'BG Play',
                          glowColor: Colors.orangeAccent,
                          isActive: isBgPlay,
                          onTap: () {
                            setState(() => isBgPlay = !isBgPlay);
                            _showMsg(isBgPlay ? 'बैकग्राउंड प्ले चालू हो गया' : 'बैकग्राउंड प्ले बंद');
                          },
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: Icons.speed,
                          label: '${speed}x',
                          glowColor: Colors.cyanAccent,
                          onTap: () {
                            setState(() {
                              speed = speed == 1.0 ? 1.5 : (speed == 1.5 ? 2.0 : 1.0);
                              _controller.setPlaybackRate(speed);
                            });
                            _showMsg('प्लेबैक स्पीड: ${speed}x');
                          },
                        ),
                        const SizedBox(width: 14),
                        _glowCircleButton(
                          icon: Icons.share,
                          label: 'Share',
                          glowColor: Colors.lightBlueAccent,
                          onTap: () => _showMsg('शेयर करने के लिए लिंक कॉपी हुआ'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _customBottomNavBar(_tabIndex, (i) => setState(() => _tabIndex = i)),
    );
  }

  Widget _glowCircleButton({
    required IconData icon,
    required String label,
    required Color glowColor,
    required VoidCallback onTap,
    bool isActive = false,
    bool isFilledGradient = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: isFilledGradient
                  ? const LinearGradient(colors: [Color(0xFFD946EF), Color(0xFF38BDF8)])
                  : null,
              color: isFilledGradient
                  ? null
                  : (isActive ? glowColor.withOpacity(0.25) : const Color(0xFF1A1C29)),
              border: Border.all(color: glowColor, width: 1.6),
              boxShadow: [
                BoxShadow(
                  color: glowColor.withOpacity(0.45),
                  blurRadius: 10,
                  spreadRadius: 1,
                ),
              ],
            ),
            child: Icon(icon, color: isFilledGradient ? Colors.white : glowColor, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, style: const TextStyle(fontSize: 11, color: Colors.white70)),
        ],
      ),
    );
  }
}

Widget _proBadge(BuildContext context) {
  return GestureDetector(
    onTap: () {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PRO ₹150 प्लान: बिना विज्ञापन और 4K सपोर्ट!')),
      );
    },
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1729).withOpacity(0.9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.amber, width: 1.2),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.workspace_premium, color: Colors.amber, size: 22),
          SizedBox(width: 6),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('PRO', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
              Text('₹150', style: TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
        ],
      ),
    ),
  );
}

Widget _customBottomNavBar(int currentIndex, Function(int) onTap) {
  final items = [
    {'icon': Icons.home_rounded, 'label': 'Home'},
    {'icon': Icons.download_rounded, 'label': 'Downloads'},
    {'icon': Icons.language_rounded, 'label': 'Browser'},
    {'icon': Icons.workspace_premium_rounded, 'label': 'Pro'},
  ];

  return Container(
    height: 64,
    decoration: const BoxDecoration(
      color: Color(0xFF12131E),
      border: Border(top: BorderSide(color: Colors.white10)),
    ),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: List.generate(items.length, (i) {
        final isSelected = currentIndex == i;
        final isPro = i == 3;
        return GestureDetector(
          onTap: () => onTap(i),
          behavior: HitTestBehavior.opaque,
          child: SizedBox(
            width: 75,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isSelected)
                  Container(
                    height: 3,
                    width: 48,
                    margin: const EdgeInsets.only(bottom: 6),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFD946EF), Color(0xFF38BDF8)],
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  )
                else
                  const SizedBox(height: 9),
                Icon(
                  items[i]['icon'] as IconData,
                  color: isPro ? Colors.amber : (isSelected ? Colors.white : Colors.white54),
                  size: 24,
                ),
                const SizedBox(height: 3),
                Text(
                  items[i]['label'] as String,
                  style: TextStyle(
                    fontSize: 11,
                    color: isPro ? Colors.amber : (isSelected ? Colors.white : Colors.white54),
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ],
            ),
          ),
        );
      }),
    ),
  );
}
           
