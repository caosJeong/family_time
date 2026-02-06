import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 클립보드, 진동
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart'; // [NEW] UUID 생성
import 'package:mobile_scanner/mobile_scanner.dart'; // [NEW] QR 스캔

import 'main.dart'; // [중요] FamilySchedulePage가 있는 파일을 임포트해야 합니다!

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  
  // 가족 만들기용 컨트롤러
  final _familyController = TextEditingController();
  final _nicknameController = TextEditingController();
  
  // 가족 참여하기용 컨트롤러
  final _joinCodeController = TextEditingController();
  final _joinNicknameController = TextEditingController();

  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _checkClipboardForCode(); // 화면 진입 시 클립보드 확인
  }

  @override
  void dispose() {
    _tabController.dispose();
    _familyController.dispose();
    _nicknameController.dispose();
    _joinCodeController.dispose();
    _joinNicknameController.dispose();
    super.dispose();
  }

  // --- [1] 클립보드 자동 붙여넣기 ---
  Future<void> _checkClipboardForCode() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data != null && data.text != null) {
      final text = data.text!.trim();
      // 우리 앱 코드는 'FAM-'으로 시작한다고 가정
      if (text.startsWith('FAM-') && text.length > 5) {
        setState(() {
          _joinCodeController.text = text;
          _tabController.animateTo(1); // 참여하기 탭으로 자동 이동
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('📋 초대 코드가 자동으로 입력되었습니다!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    }
  }

  // --- [2] QR 스캔 화면으로 이동 ---
  Future<void> _scanQR() async {
    // QR 스캐너 페이지로 이동하고 결과를 받아옴
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerPage()),
    );

    if (result != null && result is String) {
      setState(() {
        _joinCodeController.text = result;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR 코드가 인식되었습니다!')),
        );
      }
    }
  }

  // --- [3] 새 가족 만들기 (UUID 사용) ---
  Future<void> _createAll() async {
    if (_familyController.text.isEmpty || _nicknameController.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // UUID로 고유 코드 생성 (예: FAM-1A2B3C4D)
      const uuid = Uuid();
      String uniqueCode = 'FAM-${uuid.v4().substring(0, 8).toUpperCase()}';

      // 1. 가족 그룹 생성
      final familyRes = await Supabase.instance.client.from('family_groups').insert({
        'name': _familyController.text,
        'invite_code': uniqueCode,
      }).select().single();

      // 2. 유저 생성
      final userRes = await Supabase.instance.client.from('users').insert({
        'nickname': _nicknameController.text,
        'family_id': familyRes['id'],
      }).select('*, family_groups(*)').single();

      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => FamilySchedulePage(userData: userRes))
        );
      }
    } catch (e) {
      debugPrint('생성 에러: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('생성 중 오류가 발생했습니다. 다시 시도해주세요.')),
        );
      }
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  // --- [4] 기존 가족 참여하기 ---
  Future<void> _joinFamily() async {
    if (_joinCodeController.text.isEmpty || _joinNicknameController.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      // 초대 코드로 가족 그룹 찾기
      final familyGroup = await Supabase.instance.client
          .from('family_groups')
          .select()
          .eq('invite_code', _joinCodeController.text.trim())
          .maybeSingle();

      if (familyGroup == null) {
        if(mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('유효하지 않은 초대 코드입니다.')),
          );
        }
        setState(() => _isLoading = false);
        return;
      }

      // 유저 생성 (찾은 가족 ID로 연결)
      final userRes = await Supabase.instance.client.from('users').insert({
        'nickname': _joinNicknameController.text,
        'family_id': familyGroup['id'],
      }).select('*, family_groups(*)').single();

      if (mounted) {
        Navigator.pushReplacement(
          context, 
          MaterialPageRoute(builder: (context) => FamilySchedulePage(userData: userRes))
        );
      }
    } catch (e) {
      debugPrint('참여 에러: $e');
      if(mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('참여 중 오류가 발생했습니다.')),
        );
      }
    } finally {
      if(mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      appBar: AppBar(
        title: const Text('시작하기'),
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: "새 가족 만들기"),
            Tab(text: "초대 코드로 참여"),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          // 탭 1: 만들기
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.house_rounded, size: 80, color: Colors.blue),
                const SizedBox(height: 30),
                TextField(
                  controller: _familyController, 
                  decoration: const InputDecoration(labelText: '가족 모임 이름'), 
                  style: const TextStyle(fontSize: 20)
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _nicknameController, 
                  decoration: const InputDecoration(labelText: '내 호칭 (예: 아빠)'), 
                  style: const TextStyle(fontSize: 20)
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity, 
                  height: 60, 
                  child: ElevatedButton(
                    onPressed: _createAll, 
                    child: const Text('가족 만들기', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold))
                  )
                ),
              ],
            ),
          ),
          
          // 탭 2: 참여하기
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.mark_email_read_rounded, size: 80, color: Colors.orange),
                const SizedBox(height: 30),
                
                // 코드 입력 + QR 스캔 버튼
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _joinCodeController, 
                        decoration: const InputDecoration(labelText: '초대 코드'), 
                        style: const TextStyle(fontSize: 20)
                      ),
                    ),
                    const SizedBox(width: 10),
                    SizedBox(
                      height: 55,
                      child: ElevatedButton.icon(
                        onPressed: _scanQR,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.black87, 
                          foregroundColor: Colors.white, 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                        ),
                        icon: const Icon(Icons.camera_alt),
                        label: const Text("QR 스캔"),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                
                TextField(
                  controller: _joinNicknameController, 
                  decoration: const InputDecoration(labelText: '내 호칭 (예: 엄마)'), 
                  style: const TextStyle(fontSize: 20)
                ),
                const SizedBox(height: 40),
                
                SizedBox(
                  width: double.infinity, 
                  height: 60, 
                  child: ElevatedButton(
                    onPressed: _joinFamily, 
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange), 
                    child: const Text('가족 참여하기', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: Colors.white))
                  )
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// --- [QR 스캐너 페이지 클래스] ---
// 이 파일 내부에 두거나 별도 파일로 분리해도 됩니다.
class QRScannerPage extends StatefulWidget {
  const QRScannerPage({super.key});

  @override
  State<QRScannerPage> createState() => _QRScannerPageState();
}

class _QRScannerPageState extends State<QRScannerPage> {
  bool _isScanned = false; 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR 코드 스캔')),
      body: MobileScanner(
        controller: MobileScannerController(
          detectionSpeed: DetectionSpeed.noDuplicates,
          facing: CameraFacing.back,
        ),
        onDetect: (capture) {
          if (_isScanned) return;
          for (final barcode in capture.barcodes) {
            if (barcode.rawValue != null) {
              final String code = barcode.rawValue!;
              // 우리 앱 코드인지 확인 (FAM으로 시작)
              if (code.startsWith('FAM-')) {
                _isScanned = true;
                HapticFeedback.mediumImpact(); // 진동 피드백
                Navigator.pop(context, code); // 코드 가지고 돌아가기
                break;
              }
            }
          }
        },
      ),
    );
  }
}