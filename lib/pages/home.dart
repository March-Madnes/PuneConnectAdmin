import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:permission_handler/permission_handler.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  FirebaseAuth auth = FirebaseAuth.instance;
  FirebaseFirestore db = FirebaseFirestore.instance;

  ValueNotifier<dynamic> result = ValueNotifier(null);
  MobileScannerController cameraController = MobileScannerController();
  bool _screenOpened = false;
  bool _isAvailable = false;
  bool _verified = false;
  dynamic docRef;

  Future<PermissionStatus> _getCameraPermission() async {
    var status = await Permission.camera.status;
    if (!status.isGranted) {
      final result = await Permission.camera.request();
      return result;
    } else {
      return status;
    }
  }

  // Future<Set<bool>> isAvailable()  async  =>{
  //   await NfcManager.instance.isAvailable()
  // };
  void _recordCheck( String message){  
    setState(() {
          docRef = db.collection('issued_passes').doc(message);
        });
    docRef.get().then((doc) {
      if (doc.exists) {
        print("Document exists!");     
        setState(() {          
        _verified = true;
        });
        print(_verified);
      } else {
        print("Document does not exist.");
        setState(() {          
        _verified = false;
        });
      }
    }).catchError((error) {
      print("Error getting document: $error");
    });
  }

  Future<void> _processNfcData(var message) => showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Alert!'),
          content: Text('verified: $_verified'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'Cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'OK'),
              child: const Text('OK'),
            ),
          ],
        ),
      );
  Future<void> _NfcNotAvailable() => showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Alert!'),
          content: Text('NFC not available'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, 'Cancel'),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, 'OK'),
              child: const Text('OK'),
            ),
          ],
        ),
      );

  void checkNfc() async {
    _isAvailable = await NfcManager.instance.isAvailable();

    if (_isAvailable) {
      await NfcManager.instance.startSession(onDiscovered: (tag) async {
        // result.value = tag.data;
        Ndef? ndef = Ndef.from(tag);
        var message;
        if(ndef?.cachedMessage != null){
          message = ndef?.cachedMessage?.records[0].payload;
        }
        else{
          message = await ndef?.read();
        }
        // NfcManager.instance.stopSession();
        String code = String.fromCharCodes(message);        
        _recordCheck(code); 
        _processNfcData(code);
      });
    } else {
      await _NfcNotAvailable();
    }
  }

  @override
  void initState() {
    super.initState();
    checkNfc();
    super.initState();
    _controller = AnimationController(vsync: this);
    _getCameraPermission();
  }

  @override
  Widget build(BuildContext context) {
    auth.authStateChanges().listen((User? user) {
      if (user == null) {
        Navigator.pushNamed(context, '/login');
      }
    });
    return Scaffold(
      appBar: AppBar(
        title: const Text("Mobile Scanner"),
        actions: [
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder(
              valueListenable: cameraController.torchState,
              builder: (context, state, child) {
                switch (state as TorchState) {
                  case TorchState.off:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                }
              },
            ),
            iconSize: 32.0,
            onPressed: () => cameraController.toggleTorch(),
          ),
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder(
              valueListenable: cameraController.cameraFacingState,
              builder: (context, state, child) {
                switch (state as CameraFacing) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  case CameraFacing.back:
                    return const Icon(Icons.camera_rear);
                }
              },
            ),
            iconSize: 32.0,
            onPressed: () => cameraController.switchCamera(),
          ),
          IconButton(
            color: Colors.white,
            icon: const Icon(Icons.logout),
            iconSize: 32.0,
            onPressed: () => auth.signOut(),
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 400,
              width: 300,
              child: MobileScanner(
                allowDuplicates: true,
                controller: cameraController,
                onDetect: _foundBarcode,
                fit: BoxFit.cover,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _foundBarcode(Barcode barcode, MobileScannerArguments? args) {
    /// open screen
    if (!_screenOpened) {
      final String code = barcode.rawValue ?? "---";      
      try{
        _recordCheck(code);
      }
      catch(e){
        print(e);
        _recordCheck("error");
      }
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              FoundCodeScreen(
                screenClosed: _screenWasClosed, 
                value: "Pass Validation Status : ${_verified? "Valid" : "Invalid"}",
              ),
        ));          
        debugPrint('Barcode found! $code');     
      _screenOpened = true;
    }
  }

  void _screenWasClosed() {
    _screenOpened = false;
  }
}

class FoundCodeScreen extends StatefulWidget {
  final String value;
  final Function() screenClosed;
  const FoundCodeScreen({
    Key? key,
    required this.value,
    required this.screenClosed,
  }) : super(key: key);

  @override
  State<FoundCodeScreen> createState() => _FoundCodeScreenState();
}

class _FoundCodeScreenState extends State<FoundCodeScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Found Code"),
        centerTitle: true,
        leading: IconButton(
          onPressed: () {
            widget.screenClosed();
            Navigator.pop(context);
          },
          icon: Icon(
            Icons.arrow_back_outlined,
          ),
        ),
      ),
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Scanned Code:",
                style: TextStyle(
                  fontSize: 20,
                ),
              ),
              SizedBox(
                height: 20,
              ),
              Text(
                widget.value,
                style: TextStyle(
                  fontSize: 16,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
