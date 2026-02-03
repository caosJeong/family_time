import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SetupPage extends StatefulWidget {
  const SetupPage({super.key});

  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _familyController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _isGroupCreated = false;
  int? _createdFamilyId;

  // 1. 가족 그룹 생성 (MySQL의 AUTO_INCREMENT와 동일하게 ID 생성됨)
  Future<void> _createFamilyGroup() async {
    if (_familyController.text.isEmpty) return;
    try {
      final response = await Supabase.instance.client.from('family_groups').insert({
        'name': _familyController.text,
        'invite_code': 'ABC${DateTime.now().millisecond}', // 임시 초대코드
      }).select().single();

      setState(() {
        _createdFamilyId = response['id']; // 생성된 자동 증가 ID 저장
        _isGroupCreated = true;
      });
      
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('가족 그룹이 만들어졌습니다!')),
      );
    } catch (e) {
      debugPrint('그룹 생성 에러: $e');
    }
  }

  // 2. 유저 정보 생성 (가족 그룹 ID 연결)
  Future<void> _createUser() async {
    if (_nicknameController.text.isEmpty || _createdFamilyId == null) return;
    try {
      await Supabase.instance.client.from('users').insert({
        'nickname': _nicknameController.text,
        'family_id': _createdFamilyId,
        'auth_provider': 'guest', // 우선은 테스트용으로 guest 설정
      });

      // 가입 성공 시 메인 화면으로 이동
      if (mounted) {
        Navigator.pop(context); // 현재 페이지 닫고 메인으로
      }
    } catch (e) {
      debugPrint('유저 생성 에러: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('시작하기 (초기 설정)')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (!_isGroupCreated) ...[
                const Text('1. 우리 가족 이름을 정해주세요', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: _familyController,
                  style: const TextStyle(fontSize: 22),
                  decoration: const InputDecoration(hintText: '예: 행복한 우리집, 평화로운가'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _createFamilyGroup,
                    child: const Text('가족 그룹 만들기', style: TextStyle(fontSize: 20)),
                  ),
                ),
              ] else ...[
                const Text('2. 당신의 호칭을 적어주세요', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                const SizedBox(height: 10),
                TextField(
                  controller: _nicknameController,
                  style: const TextStyle(fontSize: 22),
                  decoration: const InputDecoration(hintText: '예: 할아버지, 아빠, 딸'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 60,
                  child: ElevatedButton(
                    onPressed: _createUser,
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
                    child: const Text('가입 완료하고 시작하기', style: TextStyle(fontSize: 20, color: Colors.white)),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}