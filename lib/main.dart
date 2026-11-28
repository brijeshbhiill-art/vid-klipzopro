import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(
    title: 'Vid Klipzo Pro',
    debugShowCheckedModeBanner: false,
    theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Color(0xFF0D0D1A), primaryColor: Color(0xFF00E5FF)),
    home: SplashScreen(),
  ));
  SubManager.i.init();
}

class SubManager {
  static final SubManager i = SubManager();
  DateTime? _t, _p;
  VoidCallback? onChange;

  Future init() async {
    try {
      var d = await getApplicationDocumentsDirectory();
      var tf = File('${d.path}/trial.txt');
      if (await tf.exists()) {
        _t = DateTime.fromMillisecondsSinceEpoch(int.parse((await tf.readAsString()).trim()));
      } else {
        _t = DateTime.now();
        await tf.writeAsString('${_t!.millisecondsSinceEpoch}');
      }
      var pf = File('${d.path}/pro.txt');
      if (await pf.exists()) _p = DateTime.fromMillisecondsSinceEpoch(int.parse((await pf.readAsString()).trim()));
      onChange?.call();
    } catch (_) { _t ??= DateTime.now(); }
  }

  bool get isPro => _p != null && DateTime.now().isBefore(_p!);
  bool get isTrial => !isPro && (_t == null || DateTime.now().isBefore(_t!.add(Duration(days: 3))));
  bool get hasAccess => isPro || isTrial;
  int get trialDays => _t == null ? 3 : (_t!.add(Duration(days: 3)).difference(DateTime.now()).inHours / 24).ceil().clamp(0, 3);
  int get proDays => _p == null ? 0 : (_p!.difference(DateTime.now()).inHours / 24).ceil().clamp(0, 365);

  Future buyPro() async {
    var d = await getApplicationDocumentsDirectory();
    _p = (isPro ? _p! : DateTime.now()).add(Duration(days: 30));
    await File('${d.path}/pro.txt').writeAsString('${_p!.millisecondsSinceEpoch}');
    onChange?.call();
  }
}

class DownloadMgr {
  static final DownloadMgr i = DownloadMgr();
  final List items = [];
  final List saved = [];
  VoidCallback? onUpdate;

  Future _dir() async {
    try {
      var pub = Directory('/storage/emulated/0/Download/VidKlipzo');
      if (!await pub.exists()) await pub.create(recursive: true);
      var test = File('${pub.path}/.t');
      await test.writeAsString('1');
      await test.delete();
      return pub;
    } catch (_) {
      return (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
    }
  }

  Future downloadYT(String url, bool audio, {String quality = 'HD'}) async {
    var id = YoutubePlayer.convertUrlToId(url);
    if (id == null) return;
    var item = {'title': 'YouTube ($id)', 'prog': 0.05, 'status': 'जुड़ रहा है...', 'path': '', 'audio': audio};
    items.insert(0, item); onUpdate?.call();
    var yt = YoutubeExplode();
    try {
      var v = await yt.videos.get(id);
      item['title'] = '${v.title} [$quality]'; onUpdate?.call();
      var m = await yt.videos.streamsClient.getManifest(id);
      var sInfo = audio ? m.audioOnly.withHighestBitrate() : m.muxed.withHighestBitrate();
      var total = sInfo.size.totalBytes;
      var d = await _dir();
      var clean = v.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      if (clean.length > 35) clean = clean.substring(0, 35);
      var f = File('${d.path}/${clean.isEmpty ? 'VidKlipzo_$id' : clean}_${DateTime.now().millisecond}.${audio ? 'm4a' : 'mp4'}');
      var sink = f.openWrite();
      var rec = 0;
      await for (var c in yt.videos.streamsClient.get(sInfo)) {
        sink.add(c);
        rec += c.length;
        if (total > 0) {
          double p = (rec / total).clamp(0.05, 0.99);
          item['prog'] = p;
          item['status'] = '${(p * 100).toInt()}%';
          onUpdate?.call();
        }
      }
      await sink.close();
      item['prog'] = 1.0;
      item['path'] = f.path;
      item['status'] = 'Completed';
    } catch (e) {
      item['status'] = 'विफल (पुनः प्रयास करें)';
    } finally {
      yt.close();
      onUpdate?.call();
    }
  }

  Future downloadDirect(String rawUrl) async {
    var url = rawUrl.replaceAll('"', '').trim();
    if (url.startsWith('http://')) url = url.replaceFirst('http://', 'https://');
    var item = {'title': 'Social_Video_${DateTime.now().millisecondsSinceEpoch}', 'prog': 0.2, 'status': 'डाउनलोड हो रहा है...', 'path': '', 'audio': false};
    items.insert(0, item); onUpdate?.call();
    try {
      var res = await http.Client().send(http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 13)');
      var d = await _dir();
      var f = File('${d.path}/${item['title']}.mp4');
      var sink = f.openWrite();
      await for (var c in res.stream) { sink.add(c); }
      await sink.close();
      item['prog'] = 1.0;
      item['path'] = f.path;
      item['status'] = 'Completed';
    } catch (_) {
      item['status'] = 'विफल';
    }
    onUpdate?.call();
  }
}
class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() { super.initState(); _go(); }
  Future _go() async {
    try {
      var d = await getApplicationDocumentsDirectory();
      bool ok = await File('${d.path}/user.txt').exists();
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ok ? Dashboard() : LoginPage()));
    } catch (_) {
      if (mounted) Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => LoginPage()));
    }
  }
  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))));
}

class LoginPage extends StatelessWidget {
  final _c = TextEditingController();
  Future _login(BuildContext ctx) async {
    try {
      var d = await getApplicationDocumentsDirectory();
      var txt = _c.text.trim().isEmpty ? 'Vid Klipzo User\nGuest Account' : '${_c.text.split('@')[0]}\n${_c.text.trim()}';
      await File('${d.path}/user.txt').writeAsString(txt);
    } catch (_) {}
    Navigator.pushReplacement(ctx, MaterialPageRoute(builder: (_) => Dashboard()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_circle_fill, size: 72, color: Color(0xFF00E5FF)),
              SizedBox(height: 12),
              Text('Vid Klipzo Pro', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              SizedBox(height: 6),
              Text('३ दिन का फ्री ट्रायल • फिर ₹150 / महीना', style: TextStyle(color: Colors.amber)),
              SizedBox(height: 24),
              TextField(controller: _c, decoration: InputDecoration(hintText: 'ईमेल या फ़ोन नंबर डालें', filled: true, fillColor: Color(0xFF17172B), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
              SizedBox(height: 18),
              ElevatedButton(onPressed: () => _login(context), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF00E5FF), minimumSize: Size(double.infinity, 50)), child: Text('३-दिन का फ्री ट्रायल शुरू करें', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
              TextButton(onPressed: () => _login(context), child: Text('बिना लॉगिन आगे बढ़ें', style: TextStyle(color: Colors.white70))),
            ],
          ),
        ),
      ),
    );
  }
}

class Dashboard extends StatefulWidget {
  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  int _idx = 0;
  @override
  void initState() { super.initState(); SubManager.i.onChange = () { if (mounted) setState(() {}); }; }

  @override
  Widget build(BuildContext context) {
    final pages = [HomeTab(goTab: (i) => setState(() => _idx = i)), DownloadsTab(), BrowserTab(), ProTab(), ProfileTab(goTab: (i) => setState(() => _idx = i))];
    return Scaffold(
      body: pages[_idx],
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx, backgroundColor: Color(0xFF121224), selectedItemColor: Color(0xFF00E5FF), unselectedItemColor: Colors.white54, type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _idx = i),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'होम'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'डाउनलोड'),
          BottomNavigationBarItem(icon: Icon(Icons.language), label: 'ब्राउज़र'),
          BottomNavigationBarItem(icon: Icon(Icons.workspace_premium), label: 'Pro'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'प्रोफ़ाइल'),
        ],
      ),
    );
  }
}

class HomeTab extends StatefulWidget {
  final Function(int) goTab;
  HomeTab({required this.goTab});
  @override
  _HomeTabState createState() => _HomeTabState();
}

class _HomeTabState extends State<HomeTab> {
  final _url = TextEditingController();
  final _scroll = ScrollController();
  final _yt = YoutubeExplode();
  final Set _liked = {};
  dynamic _searchList;
  bool _loading = true;
  bool _loadingMore = false;
  String _selectedCat = 'Trending';
  int _extraIdx = 0;

  final List _moreQueries = [
    'Latest Bollywood Songs 2026',
    'Hindi Comedy Skits Funny Videos',
    'New South Hindi Dubbed Movies 2026',
    'Viral Indian Shorts Compilation',
    '4K Ultra HD Nature Travel India',
    'Hindi Tech Gadgets Unboxing',
  ];

  final List _cats = [
    {'label': 'Trending', 'q': 'Trending India Hindi videos 2026'},
    {'label': 'Music', 'q': 'New Hindi Songs Bollywood 2026'},
    {'label': 'Comedy', 'q': 'Hindi Comedy Videos Funny Skits'},
    {'label': 'Movies', 'q': 'New Hindi Movie Trailer 4K'},
    {'label': 'Tech', 'q': 'Tech Unboxing Hindi India'},
  ];

  List feed = [
    {'title': 'Big Buck Bunny 4K 60fps Ultra HD', 'url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ', 'img': 'https://img.youtube.com/vi/aqz-KE-bpKQ/hqdefault.jpg', 'channel': 'Blender Studio'},
    {'title': 'Costa Rica 4K HDR Nature & Music', 'url': 'https://www.youtube.com/watch?v=LXb3EKWsInQ', 'img': 'https://img.youtube.com/vi/LXb3EKWsInQ/hqdefault.jpg', 'channel': '4K Nature'},
  ];

  @override
  void initState() {
    super.initState();
    _fetchYT('Trending India Hindi videos 2026');
    _scroll.addListener(() {
      if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 400 && !_loadingMore) {
        _loadMore();
      }
    });
  }

  @override
  void dispose() {
    _yt.close();
    _scroll.dispose();
    _url.dispose();
    super.dispose();
  }

  Future _fetchYT(String query) async {
    if (mounted) setState(() => _loading = true);
    try {
      _searchList = await _yt.search.search(query);
      List list = _searchList.map((v) => {
        'title': v.title,
        'url': v.url,
        'img': v.thumbnails.highResUrl,
        'channel': v.author,
      }).toList();
      if (mounted && list.isNotEmpty) setState(() => feed = list);
    } catch (_) {} finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future _loadMore() async {
    if (_loadingMore) return;
    setState(() => _loadingMore = true);
    try {
      dynamic next;
      if (_searchList != null) {
        next = await _searchList.nextPage();
      }
      if (next == null || next.isEmpty) {
        var q = _moreQueries[_extraIdx % _moreQueries.length];
        _extraIdx++;
        next = await _yt.search.search(q);
      }
      if (next != null && next.isNotEmpty) {
        _searchList = next;
        var existing = feed.map((e) => e['url']).toSet();
        List more = next.where((v) => !existing.contains(v.url)).map((v) => {
          'title': v.title,
          'url': v.url,
          'img': v.thumbnails.highResUrl,
          'channel': v.author,
        }).toList();
        if (mounted && more.isNotEmpty) setState(() => feed.addAll(more));
      }
    } catch (_) {} finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future _handleInput(String raw) async {
    var q = raw.trim();
    if (q.isEmpty) return;
    if (q.contains('http') || q.contains('youtu.be') || q.contains('youtube.com') || q.contains('.com')) {
      var u = q.startsWith('http') ? q : 'https://$q';
      var id = YoutubePlayer.convertUrlToId(u);
      Navigator.push(context, MaterialPageRoute(builder: (_) => id != null ? YTPlayerPage(url: u, id: id) : WebPage(url: u, title: 'Video Player')));
      return;
    }
    _fetchYT(q);
  }

  void _dlSheet(Map v) {
    showModalBottomSheet(
      context: context, backgroundColor: Color(0xFF16162B),
      builder: (_) => Padding(
        padding: EdgeInsets.all(18),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('डाउनलोड क्वालिटी चुनें', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF00E5FF))),
          SizedBox(height: 12),
          ListTile(leading: Icon(Icons.hd, color: Colors.amber), title: Text('4K / 1080p Full HD वीडियो (MP4)'), onTap: () { Navigator.pop(context); DownloadMgr.i.downloadYT(v['url'], false, quality: '4K HD'); widget.goTab(1); }),
          ListTile(leading: Icon(Icons.sd, color: Color(0xFF00E5FF)), title: Text('720p सामान्य वीडियो (MP4)'), onTap: () { Navigator.pop(context); DownloadMgr.i.downloadYT(v['url'], false, quality: '720p'); widget.goTab(1); }),
          ListTile(leading: Icon(Icons.headphones, color: Color(0xFFE040FB)), title: Text('केवल ऑडियो (M4A / MP3 संगीत)'), onTap: () { Navigator.pop(context); DownloadMgr.i.downloadYT(v['url'], true, quality: 'Audio'); widget.goTab(1); }),
        ]),
      ),
    );
  }

  Widget _btn(IconData ic, String lbl, Color col, VoidCallback fn) => InkWell(
    onTap: fn,
    child: Column(children: [Icon(ic, color: col, size: 22), SizedBox(height: 3), Text(lbl, style: TextStyle(fontSize: 11, color: Colors.white70))]),
  );

  @override
  Widget build(BuildContext context) {
    var s = SubManager.i;
    var badge = s.isPro ? 'PRO' : (s.isTrial ? 'FREE ${s.trialDays}D' : 'PRO ₹150');
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Row(children: [Icon(Icons.play_circle_filled, color: Color(0xFF00E5FF), size: 26), SizedBox(width: 6), Text('Vid Klipzo Pro', style: TextStyle(fontSize: 21, fontWeight: FontWeight.bold))]),
              Row(children: [
                GestureDetector(onTap: () => widget.goTab(3), child: Container(padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: BoxDecoration(border: Border.all(color: Colors.amber), borderRadius: BorderRadius.circular(12)), child: Text(badge, style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)))),
                SizedBox(width: 8),
                GestureDetector(onTap: () => widget.goTab(4), child: CircleAvatar(radius: 17, backgroundColor: Color(0xFF1A1A32), child: Icon(Icons.person, color: Color(0xFF00E5FF), size: 20))),
              ]),
            ]),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 14), padding: EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: Color(0xFF141428), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFF00E5FF), width: 1.5)),
            child: Row(children: [
              Expanded(child: TextField(controller: _url, onSubmitted: _handleInput, decoration: InputDecoration(hintText: 'YouTube वीडियो खोजें या लिंक पेस्ट करें...', border: InputBorder.none))),
              TextButton(onPressed: () async { var d = await Clipboard.getData('text/plain'); if (d?.text != null) { setState(() => _url.text = d!.text!); _handleInput(d!.text!); } }, child: Text('पेस्ट', style: TextStyle(color: Color(0xFF00E5FF)))),
              ElevatedButton(onPressed: () => _handleInput(_url.text), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFE040FB)), child: Text('खोजें', style: TextStyle(color: Colors.white))),
            ]),
          ),
          Container(
            height: 44, margin: EdgeInsets.only(top: 8),
            child: ListView.builder(
              scrollDirection: Axis.horizontal, padding: EdgeInsets.symmetric(horizontal: 12), itemCount: _cats.length,
              itemBuilder: (_, i) {
                var c = _cats[i];
                bool sel = _selectedCat == c['label'];
                return Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(c['label'], style: TextStyle(color: sel ? Colors.black : Colors.white, fontWeight: FontWeight.bold, fontSize: 12)),
                    selected: sel, selectedColor: Color(0xFF00E5FF), backgroundColor: Color(0xFF16162B),
                    onSelected: (_) { setState(() => _selectedCat = c['label']); _fetchYT(c['q']); },
                  ),
                );
              },
            ),
          ),
          if (_loading) Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 4), child: LinearProgressIndicator(color: Color(0xFF00E5FF))),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => _fetchYT('Trending India Hindi videos 2026'),
              child: ListView.builder(
                controller: _scroll,
                padding: EdgeInsets.fromLTRB(14, 8, 14, 14),
                itemCount: feed.length + (_loadingMore ? 1 : 0),
                itemBuilder: (ctx, idx) {
                  if (idx == feed.length) {
                    return Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))));
                  }
                  var v = feed[idx];
                  bool isLiked = _liked.contains(v['url']);
                  bool isSaved = DownloadMgr.i.saved.any((e) => e['url'] == v['url']);
                  return Card(
                    color: Color(0xFF16162B), margin: EdgeInsets.only(bottom: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      GestureDetector(
                        onTap: () => _handleInput(v['url']),
                        child: Stack(alignment: Alignment.center, children: [
                          ClipRRect(borderRadius: BorderRadius.vertical(top: Radius.circular(16)), child: Image.network(v['img'], height: 185, width: double.infinity, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(height: 185, color: Color(0xFF232342), child: Icon(Icons.movie, size: 50, color: Colors.white38)))),
                          CircleAvatar(radius: 26, backgroundColor: Colors.black54, child: Icon(Icons.play_arrow, color: Color(0xFF00E5FF), size: 36)),
                        ]),
                      ),
                      Padding(padding: EdgeInsets.fromLTRB(12, 10, 12, 2), child: Text(v['title'], maxLines: 2, overflow: TextOverflow.ellipsis, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15))),
                      Padding(padding: EdgeInsets.symmetric(horizontal: 12), child: Text(v['channel'] ?? 'YouTube', style: TextStyle(color: Colors.white54, fontSize: 12))),
                      Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        child: Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
                          _btn(isLiked ? Icons.thumb_up : Icons.thumb_up_outlined, 'पसंद', isLiked ? Color(0xFF00E5FF) : Colors.white70, () => setState(() => isLiked ? _liked.remove(v['url']) : _liked.add(v['url']))),
                          _btn(Icons.comment_outlined, 'कमेंट', Colors.white70, () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('कमेंट बॉक्स जल्द आ रहा है!')))),
                          _btn(Icons.headphones, 'ऑडियो', Color(0xFFE040FB), () { DownloadMgr.i.downloadYT(v['url'], true, quality: 'Audio'); widget.goTab(1); }),
                          _btn(Icons.four_k, '4K', Colors.amber, () => _dlSheet(v)),
                          _btn(Icons.download, 'डाउनलोड', Color(0xFF00E5FF), () => _dlSheet(v)),
                          _btn(isSaved ? Icons.bookmark : Icons.bookmark_border, 'सेव', isSaved ? Colors.amber : Colors.white70, () { setState(() { if (!isSaved) DownloadMgr.i.saved.add(v); }); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('सेव लिस्ट में जुड़ गया!'))); }),
                        ]),
                      ),
                    ]),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class YTPlayerPage extends StatefulWidget {
  final String url, id;
  YTPlayerPage({required this.url, required this.id});
  @override
  _YTPlayerPageState createState() => _YTPlayerPageState();
}

class _YTPlayerPageState extends State<YTPlayerPage> {
  late YoutubePlayerController _c;
  @override
  void initState() { super.initState(); _c = YoutubePlayerController(initialVideoId: widget.id, flags: YoutubePlayerFlags(autoPlay: true)); }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text('Vid Klipzo प्लेयर'), backgroundColor: Color(0xFF0D0D1A)),
    body: Column(children: [
      YoutubePlayer(controller: _c, showVideoProgressIndicator: true),
      SizedBox(height: 20),
      Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
        ElevatedButton.icon(onPressed: () { DownloadMgr.i.downloadYT(widget.url, true, quality: 'Audio'); Navigator.pop(context); }, icon: Icon(Icons.headphones), label: Text('ऑडियो MP3')),
        ElevatedButton.icon(onPressed: () { DownloadMgr.i.downloadYT(widget.url, false, quality: '4K HD'); Navigator.pop(context); }, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFE040FB)), icon: Icon(Icons.download), label: Text('डाउनलोड 4K MP4')),
      ]),
    ]),
  );
}

class LocalPlayerPage extends StatefulWidget {
  final String path, title;
  LocalPlayerPage({required this.path, required this.title});
  @override
  _LocalPlayerPageState createState() => _LocalPlayerPageState();
}

class _LocalPlayerPageState extends State<LocalPlayerPage> {
  late VideoPlayerController _vc;
  @override
  void initState() {
    super.initState();
    _vc = VideoPlayerController.file(File(widget.path))..initialize().then((_) { setState(() {}); _vc.play(); });
  }
  @override
  void dispose() { _vc.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), backgroundColor: Color(0xFF0D0D1A)),
    body: Center(child: _vc.value.isInitialized ? AspectRatio(aspectRatio: _vc.value.aspectRatio, child: VideoPlayer(_vc)) : CircularProgressIndicator(color: Color(0xFF00E5FF))),
    floatingActionButton: FloatingActionButton(backgroundColor: Color(0xFF00E5FF), onPressed: () => setState(() => _vc.value.isPlaying ? _vc.pause() : _vc.play()), child: Icon(_vc.value.isPlaying ? Icons.pause : Icons.play_arrow, color: Colors.black)),
  );
}

class WebPage extends StatefulWidget {
  final String url, title;
  WebPage({required this.url, required this.title});
  @override
  _WebPageState createState() => _WebPageState();
}

class _WebPageState extends State<WebPage> {
  late WebViewController _wc;
  @override
  void initState() {
    super.initState();
    _wc = WebViewController()..setJavaScriptMode(JavaScriptMode.unrestricted)..setUserAgent('Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36')..loadRequest(Uri.parse(widget.url));
  }
  Future _grab() async {
    var js = "(function(){var v=document.querySelector('video');if(v){var s=v.currentSrc||v.src;if(s&&s.indexOf('http')===0&&s.indexOf('blob:')!==0)return s;}var m=document.querySelector('meta[property=\"og:video\"]');return m?m.content:'';})()";
    var res = (await _wc.runJavaScriptReturningResult(js)).toString().replaceAll('"', '').trim();
    if (res.startsWith('http')) { DownloadMgr.i.downloadDirect(res); ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('डाउनलोड शुरू! डाउनलोड टैब देखें'))); }
    else { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('पहले वीडियो चलाएँ, फिर डाउनलोड दबाएँ'))); }
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: Text(widget.title), backgroundColor: Color(0xFF0D0D1A), actions: [IconButton(icon: Icon(Icons.refresh), onPressed: () => _wc.reload())]),
    body: WebViewWidget(controller: _wc),
    bottomNavigationBar: SafeArea(child: Padding(padding: EdgeInsets.all(10), child: ElevatedButton.icon(onPressed: _grab, style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFD500F9), minimumSize: Size(double.infinity, 48)), icon: Icon(Icons.download, color: Colors.white), label: Text('इस पेज का वीडियो डाउनलोड करें', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))))),
  );
}

class DownloadsTab extends StatefulWidget {
  @override
  _DownloadsTabState createState() => _DownloadsTabState();
}

class _DownloadsTabState extends State<DownloadsTab> {
  @override
  void initState() { super.initState(); DownloadMgr.i.onUpdate = () { if (mounted) setState(() {}); }; }
  @override
  Widget build(BuildContext context) {
    var list = DownloadMgr.i.items;
    return SafeArea(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(padding: EdgeInsets.all(16), child: Text('मेरे डाउनलोड (${list.length})', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))),
        Expanded(
          child: list.isEmpty
              ? Center(child: Text('अभी कोई डाउनलोड नहीं है\nहोम पेज पर जाकर किसी भी वीडियो का डाउनलोड दबाएँ', textAlign: TextAlign.center, style: TextStyle(color: Colors.white54)))
              : ListView.builder(
                  padding: EdgeInsets.symmetric(horizontal: 14), itemCount: list.length,
                  itemBuilder: (_, i) {
                    var it = list[i];
                    bool done = it['status'] == 'Completed' && (it['path'] as String).isNotEmpty;
                    return Card(
                      color: Color(0xFF16162B),
                      child: ListTile(
                        leading: Icon(it['audio'] == true ? Icons.audiotrack : Icons.movie, color: Color(0xFF00E5FF)),
                        title: Text(it['title'], maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SizedBox(height: 6),
                          LinearProgressIndicator(value: (it['prog'] as num).toDouble(), color: Color(0xFFE040FB)),
                          SizedBox(height: 4),
                          Text(done ? 'पूर्ण हुआ' : it['status'], style: TextStyle(color: done ? Colors.greenAccent : Colors.amber, fontSize: 12)),
                        ]),
                        trailing: done
                            ? ElevatedButton(onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => LocalPlayerPage(path: it['path'], title: it['title']))), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF00E5FF)), child: Text('चलाएँ', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)))
                            : null,
                      ),
                    );
                  },
                ),
        ),
      ]),
    );
  }
}

class BrowserTab extends StatelessWidget {
  final _q = TextEditingController();
  void _open(BuildContext ctx, String t, String u) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => WebPage(url: u, title: t)));
  @override
  Widget build(BuildContext context) {
    final sites = [['Instagram', 'https://www.instagram.com', Colors.pinkAccent], ['Facebook', 'https://m.facebook.com', Colors.blueAccent], ['YouTube', 'https://m.youtube.com', Colors.redAccent], ['X (Twitter)', 'https://mobile.x.com', Colors.lightBlueAccent], ['Pinterest', 'https://in.pinterest.com', Colors.red], ['Google Search', 'https://www.google.com', Color(0xFF00E5FF)]];
    return SafeArea(child: ListView(padding: EdgeInsets.all(14), children: [
      Text('सभी ऐप्स और ब्राउज़र', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)), SizedBox(height: 10),
      TextField(controller: _q, onSubmitted: (v) => _open(context, 'Search', v.contains('.') ? 'https://$v' : 'https://www.google.com/search?q=${Uri.encodeComponent(v)}'), decoration: InputDecoration(hintText: 'वेबसाइट या Google पर खोजें...', filled: true, fillColor: Color(0xFF141428), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
      SizedBox(height: 14),
      ...sites.map((s) => Card(color: Color(0xFF16162B), child: ListTile(leading: Icon(Icons.public, color: s[2] as Color), title: Text(s[0] as String, style: TextStyle(fontWeight: FontWeight.bold)), trailing: Icon(Icons.arrow_forward_ios, size: 16), onTap: () => _open(context, s[0] as String, s[1] as String)))),
    ]));
  }
}

class ProTab extends StatefulWidget {
  @override
  _ProTabState createState() => _ProTabState();
}

class _ProTabState extends State<ProTab> {
  @override
  Widget build(BuildContext context) {
    var s = SubManager.i;
    return SafeArea(child: Padding(padding: EdgeInsets.all(20), child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(padding: EdgeInsets.all(14), decoration: BoxDecoration(color: Color(0xFF141428), borderRadius: BorderRadius.circular(14), border: Border.all(color: Color(0xFF00E5FF))), child: Text(s.isPro ? 'Pro प्लान सक्रिय है (${s.proDays} दिन बाकी)' : (s.isTrial ? '३ दिन का फ्री ट्रायल चालू है (${s.trialDays} दिन बाकी)' : '३ दिन का फ्री ट्रायल पूरा हो गया है'), style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold))),
      SizedBox(height: 18),
      Container(padding: EdgeInsets.all(20), decoration: BoxDecoration(color: Color(0xFF16162B), borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.amber, width: 2)), child: Column(children: [
        Icon(Icons.workspace_premium, color: Colors.amber, size: 50), SizedBox(height: 8),
        Text('Vid Klipzo Pro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), SizedBox(height: 6),
        Text('विज्ञापन मुक्त • असीमित 4K और सोशल डाउनलोड', style: TextStyle(color: Colors.white70)), SizedBox(height: 14),
        Text('₹150 / 1 महीना', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.amber)), SizedBox(height: 14),
        ElevatedButton(onPressed: () async { await SubManager.i.buyPro(); setState(() {}); }, style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: Size(double.infinity, 48)), child: Text('Pro सक्रिय करें — ₹150 / 1 महीना', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold))),
      ])),
    ])));
  }
}

class ProfileTab extends StatefulWidget {
  final Function(int) goTab;
  ProfileTab({required this.goTab});
  @override
  _ProfileTabState createState() => _ProfileTabState();
}

class _ProfileTabState extends State<ProfileTab> {
  String name = 'Vid Klipzo User', contact = 'Guest Account';
  @override
  void initState() { super.initState(); _load(); }
  Future _load() async {
    try {
      var d = await getApplicationDocumentsDirectory(); var f = File('${d.path}/user.txt');
      if (await f.exists()) { var l = (await f.readAsString()).split('\n'); if (mounted) setState(() { name = l[0]; if (l.length > 1) contact = l[1]; }); }
    } catch (_) {}
  }
  Future _logout() async {
    try {
      var d = await getApplicationDocumentsDirectory(); var f = File('${d.path}/user.txt');
      if (await f.exists()) await f.delete();
    } catch (_) {}
    if (mounted) Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => LoginPage()), (_) => false);
  }
  @override
  Widget build(BuildContext context) {
    var s = SubManager.i;
    return SafeArea(child: ListView(padding: EdgeInsets.all(16), children: [
      Text('मेरी प्रोफ़ाइल', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)), SizedBox(height: 14),
      Container(padding: EdgeInsets.all(18), decoration: BoxDecoration(color: Color(0xFF16162B), borderRadius: BorderRadius.circular(18), border: Border.all(color: Color(0xFF00E5FF))), child: Column(children: [
        CircleAvatar(radius: 34, backgroundColor: Color(0xFF232342), child: Icon(Icons.person, size: 38, color: Color(0xFF00E5FF))), SizedBox(height: 8),
        Text(name, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(contact, style: TextStyle(color: Colors.white60, fontSize: 13)), SizedBox(height: 8),
        Chip(label: Text(s.isPro ? 'PRO (${s.proDays} दिन)' : (s.isTrial ? 'फ्री ट्रायल (${s.trialDays} दिन)' : 'फ्री प्लान')), backgroundColor: Colors.amber.withOpacity(0.2)),
      ])),
      SizedBox(height: 12),
      ListTile(tileColor: Color(0xFF16162B), leading: Icon(Icons.download, color: Color(0xFF00E5FF)), title: Text('कुल डाउनलोड: ${DownloadMgr.i.items.length}'), onTap: () => widget.goTab(1)),
      SizedBox(height: 8),
      ListTile(tileColor: Color(0xFF16162B), leading: Icon(Icons.bookmark, color: Colors.amber), title: Text('सेव किए गए वीडियो: ${DownloadMgr.i.saved.length}')),
      SizedBox(height: 8),
      ListTile(tileColor: Color(0xFF16162B), leading: Icon(Icons.workspace_premium, color: Colors.amber), title: Text('३ दिन फ्री / Pro प्लान (₹150 / महीना)'), onTap: () => widget.goTab(3)),
      SizedBox(height: 18),
      ElevatedButton.icon(onPressed: _logout, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: Size(double.infinity, 48)), icon: Icon(Icons.logout, color: Colors.white), label: Text('लॉग आउट करें', style: TextStyle(color: Colors.white))),
    ]));
  }
}
