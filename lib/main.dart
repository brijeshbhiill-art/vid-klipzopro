import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SubManager.i.init();
  await MobileAds.instance.initialize();
  AdHelper.i.loadAd();
  runApp(VidKlipzoProApp());
}

class SubManager {
  static final SubManager i = SubManager();
  DateTime? _trialStart, _proEnd;
  VoidCallback? onChange;

  Future<void> init() async {
    try {
      var d = await getApplicationDocumentsDirectory();
      var tf = File('${d.path}/trial.txt');
      if (await tf.exists()) {
        _trialStart = DateTime.fromMillisecondsSinceEpoch(int.parse((await tf.readAsString()).trim()));
      } else {
        _trialStart = DateTime.now();
        await tf.writeAsString('${_trialStart!.millisecondsSinceEpoch}');
      }
      var pf = File('${d.path}/pro.txt');
      if (await pf.exists()) {
        _proEnd = DateTime.fromMillisecondsSinceEpoch(int.parse((await pf.readAsString()).trim()));
      }
    } catch (_) {
      _trialStart ??= DateTime.now();
    }
  }

  bool get isPro => _proEnd != null && DateTime.now().isBefore(_proEnd!);
  bool get isTrial => !isPro && (_trialStart == null || DateTime.now().isBefore(_trialStart!.add(Duration(days: 3))));
  bool get hasAccess => isPro || isTrial;
  int get trialDays => _trialStart == null ? 3 : (_trialStart!.add(Duration(days: 3)).difference(DateTime.now()).inHours / 24).ceil().clamp(0, 3);
  int get proDays => _proEnd == null ? 0 : (_proEnd!.difference(DateTime.now()).inHours / 24).ceil().clamp(0, 365);

  Future<void> buyPro() async {
    var d = await getApplicationDocumentsDirectory();
    _proEnd = (isPro ? _proEnd! : DateTime.now()).add(Duration(days: 30));
    await File('${d.path}/pro.txt').writeAsString('${_proEnd!.millisecondsSinceEpoch}');
    onChange?.call();
  }
}

class AdHelper {
  static final AdHelper i = AdHelper();
  static const bannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const interId = 'ca-app-pub-3940256099942544/1033173712';
  InterstitialAd? _ad;

  void loadAd() {
    if (SubManager.i.hasAccess) return;
    InterstitialAd.load(
      adUnitId: interId,
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: (a) => _ad = a, onAdFailedToLoad: (_) => _ad = null),
    );
  }

  void showAndRun(VoidCallback fn) {
    if (SubManager.i.hasAccess || _ad == null) {
      loadAd();
      fn();
      return;
    }
    _ad!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) { a.dispose(); _ad = null; loadAd(); fn(); },
      onAdFailedToShowFullScreenContent: (a, _) { a.dispose(); _ad = null; loadAd(); fn(); },
    );
    _ad!.show();
  }
}

class BannerBox extends StatefulWidget {
  @override
  _BannerBoxState createState() => _BannerBoxState();
}

class _BannerBoxState extends State<BannerBox> {
  BannerAd? _b;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    if (!SubManager.i.hasAccess) {
      _b = BannerAd(
        adUnitId: AdHelper.bannerId,
        size: AdSize.banner,
        request: AdRequest(),
        listener: BannerAdListener(onAdLoaded: (_) { if (mounted) setState(() => _ok = true); }, onAdFailedToLoad: (a, _) => a.dispose()),
      )..load();
    }
  }

  @override
  void dispose() { _b?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => (SubManager.i.hasAccess || !_ok || _b == null)
      ? SizedBox.shrink()
      : SizedBox(width: _b!.size.width.toDouble(), height: _b!.size.height.toDouble(), child: AdWidget(ad: _b!));
}

class DownloadMgr {
  static final DownloadMgr i = DownloadMgr();
  final List> items = [];
  VoidCallback? onUpdate;

  Future<Directory> _dir() async {
    var pub = Directory('/storage/emulated/0/Download');
    if (await pub.exists()) return pub;
    return (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
  }

  Future<void> downloadYT(String url, bool audio) async {
    var id = YoutubePlayer.convertUrlToId(url);
    if (id == null) return;
    var item = {'title': 'YouTube ($id)', 'type': audio ? 'Audio M4A' : 'Video MP4', 'prog': 0.1, 'status': 'Downloading...'};
    items.insert(0, item);
    onUpdate?.call();
    var yt = YoutubeExplode();
    try {
      var v = await yt.videos.get(id);
      item['title'] = v.title;
      var m = await yt.videos.streamsClient.getManifest(id);
      var sInfo = audio ? m.audioOnly.withHighestBitrate() : m.muxed.withHighestBitrate();
      var total = sInfo.size.totalBytes;
      var d = await _dir();
      var clean = v.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      if (clean.isEmpty) clean = 'VidKlipzo_$id';
      var f = File('${d.path}/$clean.${audio ? 'm4a' : 'mp4'}');
      var sink = f.openWrite();
      var rec = 0;
      await for (var c in yt.videos.streamsClient.get(sInfo)) {
        sink.add(c);
        rec += c.length;
        if (total > 0) { item['prog'] = rec / total; onUpdate?.call(); }
      }
      await sink.close();
      item['prog'] = 1.0;
      item['status'] = 'Saved in Downloads';
    } catch (_) {
      item['status'] = 'Failed';
    } finally {
      yt.close();
      onUpdate?.call();
    }
  }

  Future<void> downloadDirect(String rawUrl) async {
    var url = rawUrl.replaceAll('"', '').trim();
    if (url.startsWith('http://')) url = url.replaceFirst('http://', 'https://');
    var item = {'title': 'Social Video_${DateTime.now().millisecondsSinceEpoch}', 'type': 'Web MP4', 'prog': 0.2, 'status': 'Downloading...'};
    items.insert(0, item);
    onUpdate?.call();
    try {
      var req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 13)';
      var res = await http.Client().send(req);
      var d = await _dir();
      var f = File('${d.path}/${item['title']}.mp4');
      var sink = f.openWrite();
      await for (var c in res.stream) { sink.add(c); }
      await sink.close();
      item['prog'] = 1.0;
      item['status'] = 'Saved in Downloads';
    } catch (_) {
      item['status'] = 'Failed';
    }
    onUpdate?.call();
  }
}

class VidKlipzoProApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vid Klipzo Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Color(0xFF0D0D1A), primaryColor: Color(0xFF00E5FF)),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    var d = await getApplicationDocumentsDirectory();
    bool ok = await File('${d.path}/user.txt').exists();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ok ? Dashboard() : LoginPage()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))));
}

class LoginPage extends StatelessWidget {
  final _c = TextEditingController();

  Future<void> _login(BuildContext ctx) async {
    var d = await getApplicationDocumentsDirectory();
    var txt = _c.text.trim().isEmpty ? 'Vid Klipzo User\nGuest Account' : '${_c.text.split('@')[0]}\n${_c.text.trim()}';
    await File('${d.path}/user.txt').writeAsString(txt);
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
              Text('Vid Klipzo Pro', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Free 3 Days Trial • फिर ₹150 / 1 Month', style: TextStyle(color: Colors.amber)),
              SizedBox(height: 28),
              TextField(controller: _c, decoration: InputDecoration(hintText: 'Email या Phone डालें', filled: true, fillColor: Color(0xFF17172B), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _login(context),
                style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF00E5FF), minimumSize: Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('Start 3-Day Free Trial', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              TextButton(onPressed: () => _login(context), child: Text('Skip Login (Guest Mode)', style: TextStyle(color: Colors.white70))),
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
  void initState() {
    super.initState();
    SubManager.i.onChange = () { if (mounted) setState(() {}); };
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(goTab: (i) => setState(() => _idx = i)),
      DownloadsTab(),
      BrowserTab(),
      ProTab(),
      ProfileTab(goTab: (i) => setState(() => _idx = i)),
    ];
    return Scaffold(
      body: Column(children: [Expanded(child: pages[_idx]), BannerBox()]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        backgroundColor: Color(0xFF121224),
        selectedItemColor: Color(0xFF00E5FF),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _idx = i),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
          BottomNavigationBarItem(icon: Icon(Icons.language), label: 'Browser'),
          BottomNavigationBarItem(icon: Icon(Icons.workspace_premium), label: 'Pro'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  final Function(int) goTab;
  final _url = TextEditingController();
  HomeTab({required this.goTab});

  void _play(BuildContext ctx, String raw) {
    var u = raw.trim();
    if (u.isEmpty) return;
    if (u.startsWith('http://')) u = u.replaceFirst('http://', 'https://');
    if (!u.startsWith('https://')) u = 'https://$u';
    AdHelper.i.showAndRun(() {
      var id = YoutubePlayer.convertUrlToId(u);
      Navigator.push(ctx, MaterialPageRoute(builder: (_) => id != null ? YTPlayerPage(url: u, id: id) : WebPage(url: u, title: 'Video Player')));
    });
  }

  @override
  Widget build(BuildContext context) {
    var s = SubManager.i;
    var badge = s.isPro ? 'PRO' : (s.isTrial ? 'FREE ${s.trialDays}D' : 'PRO ₹150');
    final samples = [
      {'title': 'Sci-Fi Cinematic 4K Trailer', 'url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ', 'img': 'https://img.youtube.com/vi/aqz-KE-bpKQ/hqdefault.jpg'},
      {'title': 'Desi Comedy & Music Mix', 'url': 'https://www.youtube.com/watch?v=LXb3EKWsInQ', 'img': 'https://img.youtube.com/vi/LXb3EKWsInQ/hqdefault.jpg'},
    ];
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vid Klipzo Pro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => goTab(3),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(border: Border.all(color: Colors.amber), borderRadius: BorderRadius.circular(12)),
                        child: Text(badge, style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(onTap: () => goTab(4), child: CircleAvatar(radius: 17, backgroundColor: Color(0xFF1A1A32), child: Icon(Icons.person, color: Color(0xFF00E5FF), size: 20))),
                  ],
                ),
              ],
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 14),
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Color(0xFF141428), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFF00E5FF), width: 1.5)),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _url, decoration: InputDecoration(hintText: 'किसी भी ऐप का लिंक पेस्ट करें...', border: InputBorder.none))),
                TextButton(onPressed: () async { var d = await Clipboard.getData('text/plain'); if (d?.text != null) _url.text = d!.text!; }, child: Text('Paste', style: TextStyle(color: Color(0xFF00E5FF)))),
                ElevatedButton(onPressed: () => _play(context, _url.text), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFE040FB)), child: Text('Play', style: TextStyle(color: Colors.white))),
              ],
            ),
          ),
          SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 14),
              itemCount: samples.length,
              itemBuilder: (ctx, idx) {
                var v = samples[idx];
                return Card(
                  color: Color(0xFF16162B),
                  margin: EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      GestureDetector(onTap: () => _play(context, v['url']!), child: Image.network(v['img']!, height: 170, width: double.infinity, fit: BoxFit.cover)),
                      ListTile(
                        title: Text(v['title']!, style: TextStyle(fontWeight: FontWeight.bold)),
                        trailing: ElevatedButton(
                          onPressed: () => AdHelper.i.showAndRun(() { DownloadMgr.i.downloadYT(v['url']!, false); goTab(1); }),
                          style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFD500F9)),
                          child: Text('Download', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                );
              },
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Vid Klipzo Player'), backgroundColor: Color(0xFF0D0D1A)),
      body: Column(
        children: [
          YoutubePlayer(controller: _c, showVideoProgressIndicator: true),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(onPressed: () => AdHelper.i.showAndRun(() => DownloadMgr.i.downloadYT(widget.url, true)), icon: Icon(Icons.headphones), label: Text('Audio')),
              ElevatedButton.icon(onPressed: () => AdHelper.i.showAndRun(() => DownloadMgr.i.downloadYT(widget.url, false)), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFE040FB)), icon: Icon(Icons.download), label: Text('Download MP4')),
            ],
          ),
          Spacer(),
          BannerBox(),
        ],
      ),
    );
  }
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
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36')
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _grab() async {
    var js = "(function(){var v=document.querySelector('video');if(v){var s=v.currentSrc||v.src;if(s&&s.indexOf('http')===0&&s.indexOf('blob:')!==0)return s;}var m=document.querySelector('meta[property=\"og:video\"]');return m?m.content:'';})()";
    var res = (await _wc.runJavaScriptReturningResult(js)).toString().replaceAll('"', '').trim();
    if (res.startsWith('http')) {
      AdHelper.i.showAndRun(() {
        DownloadMgr.i.downloadDirect(res);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('डाउनलोड शुरू! Downloads टैब देखें')));
import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'package:youtube_player_flutter/youtube_player_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SubManager.i.init();
  await MobileAds.instance.initialize();
  AdHelper.i.loadAd();
  runApp(VidKlipzoProApp());
}

class SubManager {
  static final SubManager i = SubManager();
  DateTime? _trialStart, _proEnd;
  VoidCallback? onChange;

  Future<void> init() async {
    try {
      var d = await getApplicationDocumentsDirectory();
      var tf = File('${d.path}/trial.txt');
      if (await tf.exists()) {
        _trialStart = DateTime.fromMillisecondsSinceEpoch(int.parse((await tf.readAsString()).trim()));
      } else {
        _trialStart = DateTime.now();
        await tf.writeAsString('${_trialStart!.millisecondsSinceEpoch}');
      }
      var pf = File('${d.path}/pro.txt');
      if (await pf.exists()) {
        _proEnd = DateTime.fromMillisecondsSinceEpoch(int.parse((await pf.readAsString()).trim()));
      }
    } catch (_) {
      _trialStart ??= DateTime.now();
    }
  }

  bool get isPro => _proEnd != null && DateTime.now().isBefore(_proEnd!);
  bool get isTrial => !isPro && (_trialStart == null || DateTime.now().isBefore(_trialStart!.add(Duration(days: 3))));
  bool get hasAccess => isPro || isTrial;
  int get trialDays => _trialStart == null ? 3 : (_trialStart!.add(Duration(days: 3)).difference(DateTime.now()).inHours / 24).ceil().clamp(0, 3);
  int get proDays => _proEnd == null ? 0 : (_proEnd!.difference(DateTime.now()).inHours / 24).ceil().clamp(0, 365);

  Future<void> buyPro() async {
    var d = await getApplicationDocumentsDirectory();
    _proEnd = (isPro ? _proEnd! : DateTime.now()).add(Duration(days: 30));
    await File('${d.path}/pro.txt').writeAsString('${_proEnd!.millisecondsSinceEpoch}');
    onChange?.call();
  }
}

class AdHelper {
  static final AdHelper i = AdHelper();
  static const bannerId = 'ca-app-pub-3940256099942544/6300978111';
  static const interId = 'ca-app-pub-3940256099942544/1033173712';
  InterstitialAd? _ad;

  void loadAd() {
    if (SubManager.i.hasAccess) return;
    InterstitialAd.load(
      adUnitId: interId,
      request: AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(onAdLoaded: (a) => _ad = a, onAdFailedToLoad: (_) => _ad = null),
    );
  }

  void showAndRun(VoidCallback fn) {
    if (SubManager.i.hasAccess || _ad == null) {
      loadAd();
      fn();
      return;
    }
    _ad!.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (a) { a.dispose(); _ad = null; loadAd(); fn(); },
      onAdFailedToShowFullScreenContent: (a, _) { a.dispose(); _ad = null; loadAd(); fn(); },
    );
    _ad!.show();
  }
}

class BannerBox extends StatefulWidget {
  @override
  _BannerBoxState createState() => _BannerBoxState();
}

class _BannerBoxState extends State<BannerBox> {
  BannerAd? _b;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    if (!SubManager.i.hasAccess) {
      _b = BannerAd(
        adUnitId: AdHelper.bannerId,
        size: AdSize.banner,
        request: AdRequest(),
        listener: BannerAdListener(onAdLoaded: (_) { if (mounted) setState(() => _ok = true); }, onAdFailedToLoad: (a, _) => a.dispose()),
      )..load();
    }
  }

  @override
  void dispose() { _b?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => (SubManager.i.hasAccess || !_ok || _b == null)
      ? SizedBox.shrink()
      : SizedBox(width: _b!.size.width.toDouble(), height: _b!.size.height.toDouble(), child: AdWidget(ad: _b!));
}

class DownloadMgr {
  static final DownloadMgr i = DownloadMgr();
  final List> items = [];
  VoidCallback? onUpdate;

  Future<Directory> _dir() async {
    var pub = Directory('/storage/emulated/0/Download');
    if (await pub.exists()) return pub;
    return (await getExternalStorageDirectory()) ?? await getApplicationDocumentsDirectory();
  }

  Future<void> downloadYT(String url, bool audio) async {
    var id = YoutubePlayer.convertUrlToId(url);
    if (id == null) return;
    var item = {'title': 'YouTube ($id)', 'type': audio ? 'Audio M4A' : 'Video MP4', 'prog': 0.1, 'status': 'Downloading...'};
    items.insert(0, item);
    onUpdate?.call();
    var yt = YoutubeExplode();
    try {
      var v = await yt.videos.get(id);
      item['title'] = v.title;
      var m = await yt.videos.streamsClient.getManifest(id);
      var sInfo = audio ? m.audioOnly.withHighestBitrate() : m.muxed.withHighestBitrate();
      var total = sInfo.size.totalBytes;
      var d = await _dir();
      var clean = v.title.replaceAll(RegExp(r'[^\w\s-]'), '').trim();
      if (clean.isEmpty) clean = 'VidKlipzo_$id';
      var f = File('${d.path}/$clean.${audio ? 'm4a' : 'mp4'}');
      var sink = f.openWrite();
      var rec = 0;
      await for (var c in yt.videos.streamsClient.get(sInfo)) {
        sink.add(c);
        rec += c.length;
        if (total > 0) { item['prog'] = rec / total; onUpdate?.call(); }
      }
      await sink.close();
      item['prog'] = 1.0;
      item['status'] = 'Saved in Downloads';
    } catch (_) {
      item['status'] = 'Failed';
    } finally {
      yt.close();
      onUpdate?.call();
    }
  }

  Future<void> downloadDirect(String rawUrl) async {
    var url = rawUrl.replaceAll('"', '').trim();
    if (url.startsWith('http://')) url = url.replaceFirst('http://', 'https://');
    var item = {'title': 'Social Video_${DateTime.now().millisecondsSinceEpoch}', 'type': 'Web MP4', 'prog': 0.2, 'status': 'Downloading...'};
    items.insert(0, item);
    onUpdate?.call();
    try {
      var req = http.Request('GET', Uri.parse(url))..headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 13)';
      var res = await http.Client().send(req);
      var d = await _dir();
      var f = File('${d.path}/${item['title']}.mp4');
      var sink = f.openWrite();
      await for (var c in res.stream) { sink.add(c); }
      await sink.close();
      item['prog'] = 1.0;
      item['status'] = 'Saved in Downloads';
    } catch (_) {
      item['status'] = 'Failed';
    }
    onUpdate?.call();
  }
}

class VidKlipzoProApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vid Klipzo Pro',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(scaffoldBackgroundColor: Color(0xFF0D0D1A), primaryColor: Color(0xFF00E5FF)),
      home: SplashScreen(),
    );
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _go();
  }

  Future<void> _go() async {
    var d = await getApplicationDocumentsDirectory();
    bool ok = await File('${d.path}/user.txt').exists();
    if (!mounted) return;
    Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ok ? Dashboard() : LoginPage()));
  }

  @override
  Widget build(BuildContext context) => Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFF00E5FF))));
}

class LoginPage extends StatelessWidget {
  final _c = TextEditingController();

  Future<void> _login(BuildContext ctx) async {
    var d = await getApplicationDocumentsDirectory();
    var txt = _c.text.trim().isEmpty ? 'Vid Klipzo User\nGuest Account' : '${_c.text.split('@')[0]}\n${_c.text.trim()}';
    await File('${d.path}/user.txt').writeAsString(txt);
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
              Text('Vid Klipzo Pro', style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold)),
              SizedBox(height: 8),
              Text('Free 3 Days Trial • फिर ₹150 / 1 Month', style: TextStyle(color: Colors.amber)),
              SizedBox(height: 28),
              TextField(controller: _c, decoration: InputDecoration(hintText: 'Email या Phone डालें', filled: true, fillColor: Color(0xFF17172B), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
              SizedBox(height: 20),
              ElevatedButton(
                onPressed: () => _login(context),
                style: ElevatedButton.styleFrom(backgroundColor: Color(0xFF00E5FF), minimumSize: Size(double.infinity, 52), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
                child: Text('Start 3-Day Free Trial', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 16)),
              ),
              TextButton(onPressed: () => _login(context), child: Text('Skip Login (Guest Mode)', style: TextStyle(color: Colors.white70))),
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
  void initState() {
    super.initState();
    SubManager.i.onChange = () { if (mounted) setState(() {}); };
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomeTab(goTab: (i) => setState(() => _idx = i)),
      DownloadsTab(),
      BrowserTab(),
      ProTab(),
      ProfileTab(goTab: (i) => setState(() => _idx = i)),
    ];
    return Scaffold(
      body: Column(children: [Expanded(child: pages[_idx]), BannerBox()]),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _idx,
        backgroundColor: Color(0xFF121224),
        selectedItemColor: Color(0xFF00E5FF),
        unselectedItemColor: Colors.white54,
        type: BottomNavigationBarType.fixed,
        onTap: (i) => setState(() => _idx = i),
        items: [
          BottomNavigationBarItem(icon: Icon(Icons.home), label: 'Home'),
          BottomNavigationBarItem(icon: Icon(Icons.download), label: 'Downloads'),
          BottomNavigationBarItem(icon: Icon(Icons.language), label: 'Browser'),
          BottomNavigationBarItem(icon: Icon(Icons.workspace_premium), label: 'Pro'),
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
        ],
      ),
    );
  }
}

class HomeTab extends StatelessWidget {
  final Function(int) goTab;
  final _url = TextEditingController();
  HomeTab({required this.goTab});

  void _play(BuildContext ctx, String raw) {
    var u = raw.trim();
    if (u.isEmpty) return;
    if (u.startsWith('http://')) u = u.replaceFirst('http://', 'https://');
    if (!u.startsWith('https://')) u = 'https://$u';
    AdHelper.i.showAndRun(() {
      var id = YoutubePlayer.convertUrlToId(u);
      Navigator.push(ctx, MaterialPageRoute(builder: (_) => id != null ? YTPlayerPage(url: u, id: id) : WebPage(url: u, title: 'Video Player')));
    });
  }

  @override
  Widget build(BuildContext context) {
    var s = SubManager.i;
    var badge = s.isPro ? 'PRO' : (s.isTrial ? 'FREE ${s.trialDays}D' : 'PRO ₹150');
    final samples = [
      {'title': 'Sci-Fi Cinematic 4K Trailer', 'url': 'https://www.youtube.com/watch?v=aqz-KE-bpKQ', 'img': 'https://img.youtube.com/vi/aqz-KE-bpKQ/hqdefault.jpg'},
      {'title': 'Desi Comedy & Music Mix', 'url': 'https://www.youtube.com/watch?v=LXb3EKWsInQ', 'img': 'https://img.youtube.com/vi/LXb3EKWsInQ/hqdefault.jpg'},
    ];
    return SafeArea(
      child: Column(
        children: [
          Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('Vid Klipzo Pro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                Row(
                  children: [
                    GestureDetector(
                      onTap: () => goTab(3),
                      child: Container(
                        padding: EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(border: Border.all(color: Colors.amber), borderRadius: BorderRadius.circular(12)),
                        child: Text(badge, style: TextStyle(color: Colors.amber, fontWeight: FontWeight.bold, fontSize: 12)),
                      ),
                    ),
                    SizedBox(width: 8),
                    GestureDetector(onTap: () => goTab(4), child: CircleAvatar(radius: 17, backgroundColor: Color(0xFF1A1A32), child: Icon(Icons.person, color: Color(0xFF00E5FF), size: 20))),
                  ],
                ),
              ],
            ),
          ),
          Container(
            margin: EdgeInsets.symmetric(horizontal: 14),
            padding: EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(color: Color(0xFF141428), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFF00E5FF), width: 1.5)),
            child: Row(
              children: [
                Expanded(child: TextField(controller: _url, decoration: InputDecoration(hintText: 'किसी भी ऐप का लिंक पेस्ट करें...', border: InputBorder.none))),
                TextButton(onPressed: () async { var d = await Clipboard.getData('text/plain'); if (d?.text != null) _url.text = d!.text!; }, child: Text('Paste', style: TextStyle(color: Color(0xFF00E5FF)))),
                ElevatedButton(onPressed: () => _play(context, _url.text), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFE040FB)), child: Text('Play', style: TextStyle(color: Colors.white))),
              ],
            ),
          ),
          SizedBox(height: 12),
          Expanded(
            child: ListView.builder(
              padding: EdgeInsets.symmetric(horizontal: 14),
              itemCount: samples.length,
              itemBuilder: (ctx, idx) {
                var v = samples[idx];
                return Card(
                  color: Color(0xFF16162B),
                  margin: EdgeInsets.only(bottom: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      GestureDetector(onTap: () => _play(context, v['url']!), child: Image.network(v['img']!, height: 170, width: double.infinity, fit: BoxFit.cover)),
                      ListTile(
                        title: Text(v['title']!, style: TextStyle(fontWeight: FontWeight.bold)),
                        trailing: ElevatedButton(
                          onPressed: () => AdHelper.i.showAndRun(() { DownloadMgr.i.downloadYT(v['url']!, false); goTab(1); }),
                          style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFD500F9)),
                          child: Text('Download', style: TextStyle(color: Colors.white)),
                        ),
                      ),
                    ],
                  ),
                );
              },
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
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Vid Klipzo Player'), backgroundColor: Color(0xFF0D0D1A)),
      body: Column(
        children: [
          YoutubePlayer(controller: _c, showVideoProgressIndicator: true),
          SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              ElevatedButton.icon(onPressed: () => AdHelper.i.showAndRun(() => DownloadMgr.i.downloadYT(widget.url, true)), icon: Icon(Icons.headphones), label: Text('Audio')),
              ElevatedButton.icon(onPressed: () => AdHelper.i.showAndRun(() => DownloadMgr.i.downloadYT(widget.url, false)), style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFE040FB)), icon: Icon(Icons.download), label: Text('Download MP4')),
            ],
          ),
          Spacer(),
          BannerBox(),
        ],
      ),
    );
  }
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
    _wc = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 Chrome/120.0.0.0 Mobile Safari/537.36')
      ..loadRequest(Uri.parse(widget.url));
  }

  Future<void> _grab() async {
    var js = "(function(){var v=document.querySelector('video');if(v){var s=v.currentSrc||v.src;if(s&&s.indexOf('http')===0&&s.indexOf('blob:')!==0)return s;}var m=document.querySelector('meta[property=\"og:video\"]');return m?m.content:'';})()";
    var res = (await _wc.runJavaScriptReturningResult(js)).toString().replaceAll('"', '').trim();
    if (res.startsWith('http')) {
      AdHelper.i.showAndRun(() {
        DownloadMgr.i.downloadDirect(res);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('डाउनलोड शुरू! Downloads टैब देखें')));
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('पहले वीडियो प्ले करें, फिर डाउनलोड दबाएँ')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: Color(0xFF0D0D1A), actions: [IconButton(icon: Icon(Icons.refresh), onPressed: () => _wc.reload())]),
      body: WebViewWidget(controller: _wc),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(10),
          child: ElevatedButton.icon(
            onPressed: _grab,
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFD500F9), minimumSize: Size(double.infinity, 48)),
            icon: Icon(Icons.download, color: Colors.white),
            label: Text('इस पेज का वीडियो डाउनलोड करें', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
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
      child: list.isEmpty
          ? Center(child: Text('अभी कोई डाउनलोड नहीं है', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: EdgeInsets.all(14),
              itemCount: list.length,
              itemBuilder: (_, i) => Card(
                color: Color(0xFF16162B),
                child: ListTile(
                  title: Text(list[i]['title']),
                  subtitle: LinearProgressIndicator(value: (list[i]['prog'] as num).toDouble(), color: Color(0xFFE040FB)),
                  trailing: Text(list[i]['status'], style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12)),
                ),
              ),
            ),
    );
  }
}

class BrowserTab extends StatelessWidget {
  final _q = TextEditingController();
  void _open(BuildContext ctx, String t, String u) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => WebPage(url: u, title: t)));

  @override
  Widget build(BuildContext context) {
    final sites = [
      ['Instagram', 'https://www.instagram.com', Colors.pinkAccent],
      ['Facebook', 'https://m.facebook.com', Colors.blueAccent],
      ['YouTube', 'https://m.youtube.com', Colors.redAccent],
      ['X (Twitter)', 'https://mobile.x.com', Colors.lightBlueAccent],
      ['Pinterest', 'https://in.pinterest.com', Colors.red],
      ['Google Search', 'https://www.google.com', Color(0xFF00E5FF)],
    ];
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(14),
        children: [
          Text('All Apps & Browser', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          TextField(
            controller: _q,
            onSubmitted: (v) => _open(context, 'Search', v.contains('.') ? 'https://$v' : 'https://www.google.com/search?q=${Uri.encodeComponent(v)}'),
            decoration: InputDecoration(hintText: 'वेबसाइट या Google पर खोजें...', filled: true, fillColor: Color(0xFF141428), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
          ),
          SizedBox(height: 14),
          ...sites.map((s) => Card(
                color: Color(0xFF16162B),
                child: ListTile(
                  leading: Icon(Icons.public, color: s[2] as Color),
                  title: Text(s[0] as String, style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _open(context, s[0] as String, s[1] as String),
                ),
              )),
        ],
      ),
    );
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: Color(0xFF141428), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFF00E5FF))),
              child: Text(
                s.isPro ? 'Pro Active (${s.proDays} दिन बाकी)' : (s.isTrial ? 'Free 3 Days Trial चालू है (${s.trialDays} दिन बाकी)' : '3 Days Free Trial पूरा हो गया है'),
                style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(color: Color(0xFF16162B), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber, width: 2)),
              child: Column(
                children: [
                  Icon(Icons.workspace_premium, color: Colors.amber, size: 54),
                  SizedBox(height: 10),
                  Text('Vid Klipzo Pro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Ad-Free • Unlimited 4K & Social Downloads', style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 16),
                  Text('₹150 / 1 Month', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.amber)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async { await SubManager.i.buyPro(); setState(() {}); },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: Size(double.infinity, 48)),
                    child: Text('Activate Pro — ₹150 / 1 Month', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
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

  Future<void> _load() async {
    var d = await getApplicationDocumentsDirectory();
    var f = File('${d.path}/user.txt');
    if (await f.exists()) {
      var l = (await f.readAsString()).split('\n');
      if (mounted) setState(() { name = l[0]; if (l.length > 1) contact = l[1]; });
    }
  }

  Future<void> _logout() async {
    var d = await getApplicationDocumentsDirectory();
    var f = File('${d.path}/user.txt');
    if (await f.exists()) await f.delete();
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(context, MaterialPageRoute(builder: (_) => LoginPage()), (_) => false);
  }

  @override
  Widget build(BuildContext context) {
    var s = SubManager.i;
    return SafeArea(
      child: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Text('My Profile', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          SizedBox(height: 16),
          Container(
            padding: EdgeInsets.all(20),
            decoration: BoxDecoration(color: Color(0xFF16162B), borderRadius: BorderRadius.circular(18), border: Border.all(color: Color(0xFF00E5FF))),
            child: Column(
              children: [
                CircleAvatar(radius: 36, backgroundColor: Color(0xFF232342), child: Icon(Icons.person, size: 40, color: Color(0xFF00E5FF))),
                SizedBox(height: 10),
                Text(name, style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold)),
                Text(contact, style: TextStyle(color: Colors.white60, fontSize: 13)),
                SizedBox(height: 10),
                Chip(label: Text(s.isPro ? 'PRO (${s.proDays}D)' : (s.isTrial ? 'Free Trial (${s.trialDays}D)' : 'Free Plan')), backgroundColor: Colors.amber.withOpacity(0.2)),
              ],
            ),
          ),
          SizedBox(height: 14),
          ListTile(tileColor: Color(0xFF16162B), leading: Icon(Icons.download, color: Color(0xFF00E5FF)), title: Text('Total Downloads: ${DownloadMgr.i.items.length}'), onTap: () => widget.goTab(1)),
          SizedBox(height: 8),
          ListTile(tileColor: Color(0xFF16162B), leading: Icon(Icons.workspace_premium, color: Colors.amber), title: Text('Free 3 Days / Pro (₹150 / 1 Month)'), onTap: () => widget.goTab(3)),
          SizedBox(height: 20),
          ElevatedButton.icon(onPressed: _logout, style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent, minimumSize: Size(double.infinity, 48)), icon: Icon(Icons.logout, color: Colors.white), label: Text('Logout', style: TextStyle(color: Colors.white))),
        ],
      ),
    );
  }
}
￼Enter      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('पहले वीडियो प्ले करें, फिर डाउनलोड दबाएँ')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), backgroundColor: Color(0xFF0D0D1A), actions: [IconButton(icon: Icon(Icons.refresh), onPressed: () => _wc.reload())]),
      body: WebViewWidget(controller: _wc),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: EdgeInsets.all(10),
          child: ElevatedButton.icon(
            onPressed: _grab,
            style: ElevatedButton.styleFrom(backgroundColor: Color(0xFFD500F9), minimumSize: Size(double.infinity, 48)),
            icon: Icon(Icons.download, color: Colors.white),
            label: Text('इस पेज का वीडियो डाउनलोड करें', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ),
      ),
    );
  }
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
      child: list.isEmpty
          ? Center(child: Text('अभी कोई डाउनलोड नहीं है', style: TextStyle(color: Colors.white54)))
          : ListView.builder(
              padding: EdgeInsets.all(14),
              itemCount: list.length,
              itemBuilder: (_, i) => Card(
                color: Color(0xFF16162B),
                child: ListTile(
                  title: Text(list[i]['title']),
                  subtitle: LinearProgressIndicator(value: (list[i]['prog'] as num).toDouble(), color: Color(0xFFE040FB)),
                  trailing: Text(list[i]['status'], style: TextStyle(color: Color(0xFF00E5FF), fontSize: 12)),
                ),
              ),
            ),
    );
  }
}

class BrowserTab extends StatelessWidget {
  final _q = TextEditingController();
  void _open(BuildContext ctx, String t, String u) => Navigator.push(ctx, MaterialPageRoute(builder: (_) => WebPage(url: u, title: t)));

  @override
  Widget build(BuildContext context) {
    final sites = [
      ['Instagram', 'https://www.instagram.com', Colors.pinkAccent],
      ['Facebook', 'https://m.facebook.com', Colors.blueAccent],
      ['YouTube', 'https://m.youtube.com', Colors.redAccent],
      ['X (Twitter)', 'https://mobile.x.com', Colors.lightBlueAccent],
      ['Pinterest', 'https://in.pinterest.com', Colors.red],
      ['Google Search', 'https://www.google.com', Color(0xFF00E5FF)],
    ];
    return SafeArea(
child: ListView(
        padding: EdgeInsets.all(14),
        children: [
          Text('All Apps & Browser', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
          SizedBox(height: 10),
          TextField(
            controller: _q,
            onSubmitted: (v) => _open(context, 'Search', v.contains('.') ? 'https://$v' : 'https://www.google.com/search?q=${Uri.encodeComponent(v)}'),
            decoration: InputDecoration(hintText: 'वेबसाइट या Google पर खोजें...', filled: true, fillColor: Color(0xFF141428), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14))),
          ),
          SizedBox(height: 14),
          ...sites.map((s) => Card(
                color: Color(0xFF16162B),
                child: ListTile(
                  leading: Icon(Icons.public, color: s[2] as Color),
                  title: Text(s[0] as String, style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Icon(Icons.arrow_forward_ios, size: 16),
                  onTap: () => _open(context, s[0] as String, s[1] as String),
                ),
              )),
        ],
      ),
    );
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
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(color: Color(0xFF141428), borderRadius: BorderRadius.circular(16), border: Border.all(color: Color(0xFF00E5FF))),
              child: Text(
                s.isPro ? 'Pro Active (${s.proDays} दिन बाकी)' : (s.isTrial ? 'Free 3 Days Trial चालू है (${s.trialDays} दिन बाकी)' : '3 Days Free Trial पूरा हो गया है'),
                style: TextStyle(color: Color(0xFF00E5FF), fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 20),
            Container(
              padding: EdgeInsets.all(22),
              decoration: BoxDecoration(color: Color(0xFF16162B), borderRadius: BorderRadius.circular(20), border: Border.all(color: Colors.amber, width: 2)),
              child: Column(
                children: [
                  Icon(Icons.workspace_premium, color: Colors.amber, size: 54),
                  SizedBox(height: 10),
                  Text('Vid Klipzo Pro', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                  SizedBox(height: 8),
                  Text('Ad-Free • Unlimited 4K & Social Downloads', style: TextStyle(color: Colors.white70)),
                  SizedBox(height: 16),
                  Text('₹150 / 1 Month', style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold, color: Colors.amber)),
                  SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () async { await SubManager.i.buyPro(); setState(() {}); },
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.amber, minimumSize: Size(double.infinity, 48)),
                    child: Text('Activate Pro — ₹150 / 1 Month', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ),
                ],
              ),
            ),
