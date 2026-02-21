import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // 진동 효과 등
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:mobile_scanner/mobile_scanner.dart'; // QR 스캔 패키지
import 'main.dart'; // FamilySchedulePage 접근용

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _codeController = TextEditingController(); 
  
  bool _isCreating = true; 
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _codeController.dispose();
    super.dispose();
  }

  // 기기 ID 가져오기
  Future<String?> _getDeviceId() async {
    final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
    try {
      if (Platform.isAndroid) {
        return (await deviceInfo.androidInfo).id;
      } else if (Platform.isIOS) {
        return (await deviceInfo.iosInfo).identifierForVendor;
      }
    } catch (e) {
      debugPrint('기기 ID 에러: $e');
    }
    return null;
  }

  // QR 코드 스캔 화면 띄우기
  Future<void> _startQRScan() async {
    final String? scannedCode = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const QRScannerPage()),
    );

    if (scannedCode != null) {
      setState(() {
        _codeController.text = scannedCode;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('QR 코드가 인식되었습니다! 가족을 찾는 중...')),
        );
        _joinOrRecoverFamily();
      }
    }
  }

  // [시나리오 1] 완전히 새로운 가족 만들기
  Future<void> _createNewFamily() async {
    if (_nameController.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final deviceId = await _getDeviceId();

      final groupRes = await Supabase.instance.client
          .from('family_groups')
          .insert({
            'name': '${_nameController.text}네 가족',
            'invite_code': DateTime.now().millisecondsSinceEpoch.toString().substring(5),
          })
          .select()
          .single();

      final userRes = await Supabase.instance.client
          .from('users')
          .insert({
            'nickname': _nameController.text,
            'family_id': groupRes['id'],
            'device_id': deviceId, 
          })
          .select('*, family_groups(*)')
          .single();

      await _saveAndGoHome(userRes);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('생성 실패. 다시 시도해주세요.')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // [시나리오 2] 초대 코드 입력 후 -> (새 유저 생성 OR 기존 유저 이어하기)
  Future<void> _joinOrRecoverFamily() async {
    if (_codeController.text.isEmpty) return;
    setState(() => _isLoading = true);

    try {
      final groupData = await Supabase.instance.client
          .from('family_groups')
          .select()
          .eq('invite_code', _codeController.text.trim())
          .maybeSingle();

      if (groupData == null) {
        throw '코드가 올바르지 않습니다.';
      }

      final members = await Supabase.instance.client
          .from('users')
          .select()
          .eq('family_id', groupData['id']);

      if (!mounted) return;

      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) {
          return Container(
            padding: const EdgeInsets.all(25),
            height: MediaQuery.of(context).size.height * 0.6,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text("누가 접속하셨나요?", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                const Text("휴대폰을 바꿨다면 기존 내 이름을,\n처음 오셨다면 '새 멤버'를 선택하세요.", style: TextStyle(fontSize: 16, color: Colors.grey)),
                const SizedBox(height: 20),
                Expanded(
                  child: ListView(
                    children: [
                      ...members.map((member) => ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person)),
                        title: Text(member['nickname'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        subtitle: const Text("터치하여 이어하기 (기기 변경)"),
                        trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _claimExistingUser(member), 
                      )),
                      const Divider(),
                      ListTile(
                        leading: const CircleAvatar(backgroundColor: Colors.blue, child: Icon(Icons.add, color: Colors.white)),
                        title: const Text("새로운 가족 구성원입니다", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                        onTap: () {
                          Navigator.pop(context); 
                          _showNewMemberInput(groupData['id']); 
                        },
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      );

    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString())));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _claimExistingUser(Map<String, dynamic> member) async {
    Navigator.pop(context); 
    setState(() => _isLoading = true);

    try {
      final newDeviceId = await _getDeviceId();

      final updatedUser = await Supabase.instance.client
          .from('users')
          .update({'device_id': newDeviceId})
          .eq('id', member['id'])
          .select('*, family_groups(*)')
          .single();

      await _saveAndGoHome(updatedUser);
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('이어하기 실패. 다시 시도해주세요.')));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showNewMemberInput(int familyId) {
    showDialog(
      context: context,
      builder: (context) {
        final newNameCtrl = TextEditingController();
        return AlertDialog(
          title: const Text("새 이름 입력"),
          content: TextField(
            controller: newNameCtrl,
            decoration: const InputDecoration(hintText: "예: 아빠, 막내"),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                if (newNameCtrl.text.isEmpty) return;
                setState(() => _isLoading = true);
                
                try {
                  final deviceId = await _getDeviceId();
                  final newUser = await Supabase.instance.client
                      .from('users')
                      .insert({
                        'nickname': newNameCtrl.text,
                        'family_id': familyId,
                        'device_id': deviceId,
                      })
                      .select('*, family_groups(*)')
                      .single();
                  
                  await _saveAndGoHome(newUser);
                } catch (e) {
                  debugPrint('가입 에러: $e');
                } finally {
                  if (mounted) setState(() => _isLoading = false);
                }
              },
              child: const Text("시작하기"),
            ),
          ],
        );
      },
    );
  }

  Future<void> _saveAndGoHome(Map<String, dynamic> user) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('my_user_id', user['id'].toString());

    if (!mounted) return;
    Navigator.pushReplacement(
      context, 
      MaterialPageRoute(builder: (context) => FamilySchedulePage(userData: user))
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      // [핵심] 키보드가 올라오면 화면을 스크롤할 수 있도록 함
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  minHeight: constraints.maxHeight, // 화면의 최소 높이를 전체 화면으로 설정
                ),
                child: IntrinsicHeight(
                  child: Padding(
                    padding: const EdgeInsets.all(30.0),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Icon(Icons.family_restroom, size: 80, color: Colors.blue),
                        const SizedBox(height: 20),
                        const Text("우리 가족 일정", textAlign: TextAlign.center, style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 50),

                        // 탭바
                        Row(
                          children: [
                            Expanded(child: InkWell(onTap: () => setState(() => _isCreating = true), child: Container(padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: _isCreating ? Colors.blue : Colors.grey.shade300, width: 3))), child: Text("새 가족 만들기", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: _isCreating ? FontWeight.bold : FontWeight.normal, color: _isCreating ? Colors.blue : Colors.grey))))),
                            Expanded(child: InkWell(onTap: () => setState(() => _isCreating = false), child: Container(padding: const EdgeInsets.symmetric(vertical: 15), decoration: BoxDecoration(border: Border(bottom: BorderSide(color: !_isCreating ? Colors.blue : Colors.grey.shade300, width: 3))), child: Text("코드 입력 / 이어하기", textAlign: TextAlign.center, style: TextStyle(fontSize: 18, fontWeight: !_isCreating ? FontWeight.bold : FontWeight.normal, color: !_isCreating ? Colors.blue : Colors.grey))))),
                          ],
                        ),
                        const SizedBox(height: 40),

                        // [탭 내용] - Spacer 대신 Expanded나 여백으로 처리하여 스크롤 가능하게 함
                        if (_isCreating) ...[
                          const Text("가족 대표자 이름을 입력하세요", style: TextStyle(fontSize: 16, color: Colors.grey)),
                          const SizedBox(height: 10),
                          TextField(
                            controller: _nameController,
                            style: const TextStyle(fontSize: 22),
                            decoration: InputDecoration(hintText: "예: 엄마, 아빠", filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                          ),
                          const Spacer(), // 화면이 충분히 클 때는 아래로 밀어줌
                          SizedBox(height: 60, child: ElevatedButton(onPressed: _isLoading ? null : _createNewFamily, style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("가족 방 만들기", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
                        ] else ...[
                          SizedBox(
                            height: 60,
                            child: ElevatedButton.icon(
                              onPressed: _startQRScan,
                              icon: const Icon(Icons.camera_alt, size: 28),
                              label: const Text("📷 QR 코드로 스캔하기", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                              style: ElevatedButton.styleFrom(backgroundColor: Colors.black, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Row(children: [Expanded(child: Divider()), Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: Text("또는 직접 입력", style: TextStyle(color: Colors.grey))), Expanded(child: Divider())]),
                          const SizedBox(height: 20),

                          TextField(
                            controller: _codeController,
                            style: const TextStyle(fontSize: 24, letterSpacing: 2),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(hintText: "코드 8자리", filled: true, fillColor: Colors.grey.shade100, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none)),
                          ),
                          const SizedBox(height: 20),
                          const Text("💡 휴대폰을 바꿨다면 코드를 입력하고\n기존 내 이름을 선택하면 됩니다.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey)),
                          
                          const Spacer(), // 키보드가 없을 땐 아래로 밀고, 있으면 자연스럽게 공간 축소
                          SizedBox(height: 60, child: ElevatedButton(onPressed: _isLoading ? null : _joinOrRecoverFamily, style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: _isLoading ? const CircularProgressIndicator(color: Colors.white) : const Text("가족 찾기", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            );
          }
        ),
      ),
    );
  }
}

// --- [QR 스캐너 페이지] (예전 코드와 동일한 로직) ---
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
          detectionSpeed: DetectionSpeed.normal, 
          facing: CameraFacing.back,
          torchEnabled: false,
          formats: [BarcodeFormat.qrCode],
        ),
        onDetect: (capture) {
          if (_isScanned) return; 
          
          final List<Barcode> barcodes = capture.barcodes;
          for (final barcode in barcodes) {
            final String? code = barcode.rawValue;
            
            if (code != null && code.isNotEmpty) {
              _isScanned = true; 
              HapticFeedback.mediumImpact(); 
              
              if (mounted) {
                 Navigator.pop(context, code);
              }
              break;
            }
          }
        },
      ),
    );
  }
}
