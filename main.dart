import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'register_page.dart';
import 'dart:convert'; // JSON decode করার জন্য
import 'package:http/http.dart' as http; // API কল করার জন্য

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin = FlutterLocalNotificationsPlugin();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  const AndroidInitializationSettings initializationSettingsAndroid = AndroidInitializationSettings('@mipmap/ic_launcher');
  const InitializationSettings initializationSettings = InitializationSettings(android: initializationSettingsAndroid);
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
  runApp(const DisasterApp());
}

class DisasterApp extends StatelessWidget {
  const DisasterApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.red),
      home: const Dashboard(),
    );
  }
}

class Dashboard extends StatefulWidget {
  const Dashboard({super.key});
  @override
  _DashboardState createState() => _DashboardState();
}

class _DashboardState extends State<Dashboard> {
  final MapController _mapController = MapController();
  final FlutterTts _flutterTts = FlutterTts();
  LatLng? _currentLocation;
  LatLng? _navigationTarget;
  double _currentHeading = 0.0;
  DateTime? _lastSpeechTime;
  String? _displayUserName;

  // রুট পয়েন্টগুলো রাখার জন্য নতুন লিস্ট
  List<LatLng> _routePoints = [];

  @override
  void initState() {
    super.initState();
    _fetchAndSetUserName();
    _initLocationTracking();
    _startListeningForNearbySOS();
  }

  // ১. রিয়েল টাইম রোড রাউটিং ফাংশন
  Future<void> _fetchRoute(LatLng target) async {
    if (_currentLocation == null) return;

    // তোর দেওয়া API Key
    const String apiKey = "eyJvcmciOiI1YjNjZTM1OTc4NTExMTAwMDFjZjYyNDgiLCJpZCI6IjI0ZThmZWNhODc5MDRjOTc5ZDQ3OGJlODc4NTEwZGM2IiwiaCI6Im11cm11cjY0In0=";

    final url = Uri.parse(
        'https://api.openrouteservice.org/v2/directions/driving-car?api_key=$apiKey&start=${_currentLocation!.longitude},${_currentLocation!.latitude}&end=${target.longitude},${target.latitude}'
    );

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final List coordinates = data['features'][0]['geometry']['coordinates'];

        setState(() {
          _routePoints = coordinates.map((point) => LatLng(point[1], point[0])).toList();
        });
      }
    } catch (e) {
      debugPrint("Routing Error: $e");
    }
  }

  void _fetchAndSetUserName() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (userDoc.exists && mounted) {
          setState(() {
            _displayUserName = userDoc.data()?['name']?.toString();
          });
        }
      } catch (e) { debugPrint("Error fetching name: $e"); }
    }
  }

  void _initLocationTracking() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) await Geolocator.requestPermission();

    Geolocator.getPositionStream(
      locationSettings: const LocationSettings(accuracy: LocationAccuracy.high, distanceFilter: 2),
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
          _currentHeading = position.heading;
        });
        if (_navigationTarget != null) {
          _checkNavigationPath(position);
          _fetchRoute(_navigationTarget!); // লোকেশন বদলালে রুট আপডেট হবে
        }
      }
    });
  }

  void _checkNavigationPath(Position position) {
    double bearing = Geolocator.bearingBetween(position.latitude, position.longitude, _navigationTarget!.latitude, _navigationTarget!.longitude);
    double diff = (bearing - _currentHeading + 360) % 360;

    if (_lastSpeechTime == null || DateTime.now().difference(_lastSpeechTime!).inSeconds > 15) {
      if (diff > 45 && diff < 150) { _flutterTts.speak("Turn right"); _lastSpeechTime = DateTime.now(); }
      else if (diff > 210 && diff < 315) { _flutterTts.speak("Turn left"); _lastSpeechTime = DateTime.now(); }
    }
  }

  void _sendSOSAlert() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) { _showRegistrationWarning(); return; }
    if (_currentLocation == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("লোকেশন পাওয়া যাচ্ছে না!")));
      return;
    }

    try {
      var userDoc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      String name = userDoc.exists ? (userDoc.data()?['name'] ?? "Victim") : (user.displayName ?? "Victim");
      String phone = userDoc.exists ? (userDoc.data()?['phone'] ?? "No Phone") : (user.phoneNumber ?? "No Phone");

      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'name': name,
        'phone': phone,
        'location': {'latitude': _currentLocation!.latitude, 'longitude': _currentLocation!.longitude},
        'time': FieldValue.serverTimestamp(),
        'uid': user.uid,
      });

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("SOS পাঠানো হয়েছে! সাহায্য আসছে, $name।"), backgroundColor: Colors.red));
    } catch (e) { debugPrint("SOS Error: $e"); }
  }

  void _showRegistrationWarning() {
    showDialog(context: context, builder: (context) => AlertDialog(
      title: const Text("Registration Required"),
      content: const Text("You must be a registered user to send SOS."),
      actions: [ElevatedButton(onPressed: () async { Navigator.pop(context); await Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterPage())); _fetchAndSetUserName(); }, child: const Text("Go to Register"))],
    ));
  }

  void _startListeningForNearbySOS() {
    FirebaseFirestore.instance.collection('sos_alerts').orderBy('time', descending: true).limit(1).snapshots().listen((snapshot) async {
      if (snapshot.docs.isNotEmpty && _currentLocation != null) {
        var alert = snapshot.docs.first;
        var alertTime = alert['time'] as Timestamp?;
        if (alertTime != null && DateTime.now().difference(alertTime.toDate()).inSeconds < 60) {
          var alertLoc = alert['location'];
          double dist = Geolocator.distanceBetween(_currentLocation!.latitude, _currentLocation!.longitude, alertLoc['latitude'], alertLoc['longitude']) / 1000;
          if (dist <= 7.0) {
            _showHighPriorityNotification("URGENT SOS", "Victim nearby within ${dist.toStringAsFixed(1)}km!");
            await _flutterTts.speak("Emergency alert! Someone needs help nearby.");
          }
        }
      }
    });
  }

  Future<void> _showHighPriorityNotification(String title, String body) async {
    const AndroidNotificationDetails details = AndroidNotificationDetails('emergency_channel', 'Alerts', importance: Importance.max, priority: Priority.high);
    await flutterLocalNotificationsPlugin.show(1, title, body, const NotificationDetails(android: details));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Rescue Monitor"),
        backgroundColor: Colors.redAccent,
        actions: [Center(child: Padding(padding: const EdgeInsets.only(right: 15), child: Text(_displayUserName ?? "Guest", style: const TextStyle(fontWeight: FontWeight.bold))))],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(10),
            child: Row(
              children: [
                Expanded(child: ElevatedButton(onPressed: () async { await Navigator.push(context, MaterialPageRoute(builder: (context) => const RegisterPage())); _fetchAndSetUserName(); }, child: const Text("Register"))),
                const SizedBox(width: 10),
                Expanded(child: ElevatedButton(onPressed: _sendSOSAlert, style: ElevatedButton.styleFrom(backgroundColor: Colors.red), child: const Text("SEND SOS", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)))),
              ],
            ),
          ),
          Expanded(
            flex: 3,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('sos_alerts').snapshots(),
              builder: (context, snapshot) {
                List<Marker> markers = [];
                if (_currentLocation != null) {
                  markers.add(Marker(point: _currentLocation!, child: const Icon(Icons.navigation, color: Colors.blue, size: 40)));
                }
                if (snapshot.hasData) {
                  for (var doc in snapshot.data!.docs) {
                    var data = doc.data() as Map<String, dynamic>;
                    if (data['location'] != null) {
                      markers.add(Marker(point: LatLng(data['location']['latitude'], data['location']['longitude']), child: const Icon(Icons.location_on, color: Colors.red, size: 35)));
                    }
                  }
                }
                return FlutterMap(
                  mapController: _mapController,
                  options: const MapOptions(initialCenter: LatLng(23.6850, 90.3563), initialZoom: 12),
                  children: [
                    TileLayer(urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png', userAgentPackageName: 'com.example.disastermanagementsystem'),
                    // ২. নীল রঙের রোড লাইন ড্র করার লেয়ার
                    PolylineLayer(
                      polylines: [
                        Polyline(points: _routePoints, color: Colors.blue, strokeWidth: 5.0),
                      ],
                    ),
                    MarkerLayer(markers: markers),
                  ],
                );
              },
            ),
          ),
          Expanded(
            flex: 2,
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance.collection('sos_alerts').orderBy('time', descending: true).snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                return ListView.builder(
                  itemCount: snapshot.data!.docs.length,
                  itemBuilder: (context, index) {
                    var data = snapshot.data!.docs[index].data() as Map<String, dynamic>;
                    return ListTile(
                      leading: const Icon(Icons.warning, color: Colors.red),
                      title: Text("${data['name']} (${data['phone']})"),
                      subtitle: const Text("Tap to view route"),
                      onTap: () {
                        if (data['location'] != null) {
                          LatLng target = LatLng(data['location']['latitude'], data['location']['longitude']);
                          setState(() => _navigationTarget = target);
                          _mapController.move(target, 15);
                          _fetchRoute(target); // ক্লিক করলেই রুট খুঁজে বের করবে
                        }
                      },
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}