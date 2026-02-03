import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart'; // import 추가

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // 1. .env 파일을 먼저 읽어옵니다.
  await dotenv.load(fileName: ".env");

  // 2. 파일에 적힌 값을 꺼내서 사용합니다.
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      // --- 한국어 설정 시작 ---
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [
        Locale('ko', 'KR'), // 한국어 설정
      ],
      locale: const Locale('ko', 'KR'), // 앱의 기본 언어를 한국어로 고정
      // --- 한국어 설정 끝 ---
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(fontSize: 22),
        ),
      ),
      home: const AuthCheck(),
    );
  }
}

// --- [1] 가입 여부 확인 ---
class AuthCheck extends StatefulWidget {
  const AuthCheck({super.key});
  @override
  State<AuthCheck> createState() => _AuthCheckState();
}

class _AuthCheckState extends State<AuthCheck> {
  @override
  void initState() {
    super.initState();
    _checkUser();
  }

  Future<void> _checkUser() async {
    final data = await Supabase.instance.client
        .from('users')
        .select('*, family_groups(*)')
        .limit(1)
        .maybeSingle();

    if (!mounted) return;

    if (data == null) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SetupPage()));
    } else {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FamilySchedulePage(userData: data)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

// --- [2] 초기 가입 페이지 ---
class SetupPage extends StatefulWidget {
  const SetupPage({super.key});
  @override
  State<SetupPage> createState() => _SetupPageState();
}

class _SetupPageState extends State<SetupPage> {
  final _familyController = TextEditingController();
  final _nicknameController = TextEditingController();

  Future<void> _createAll() async {
    try {
      final familyRes = await Supabase.instance.client.from('family_groups').insert({
        'name': _familyController.text,
        'invite_code': 'FAM${DateTime.now().millisecond}',
      }).select().single();

      final userRes = await Supabase.instance.client.from('users').insert({
        'nickname': _nicknameController.text,
        'family_id': familyRes['id'],
      }).select('*, family_groups(*)').single();

      if (mounted) {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FamilySchedulePage(userData: userRes)));
      }
    } catch (e) {
      debugPrint('가입 에러: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('가족 등록')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          children: [
            TextField(controller: _familyController, decoration: const InputDecoration(labelText: '가족 모임 이름'), style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 20),
            TextField(controller: _nicknameController, decoration: const InputDecoration(labelText: '내 호칭 (예: 할아버지)'), style: const TextStyle(fontSize: 22)),
            const SizedBox(height: 40),
            SizedBox(width: double.infinity, height: 60, child: ElevatedButton(onPressed: _createAll, child: const Text('시작하기', style: TextStyle(fontSize: 22)))),
          ],
        ),
      ),
    );
  }
}

// --- [3] 메인 화면 (날짜 선택 필수 기능 추가) ---
class FamilySchedulePage extends StatefulWidget {
  final Map<String, dynamic> userData;
  const FamilySchedulePage({super.key, required this.userData});

  @override
  State<FamilySchedulePage> createState() => _FamilySchedulePageState();
}

class _FamilySchedulePageState extends State<FamilySchedulePage> {
  final TextEditingController _inputController = TextEditingController();
  
  DateTime _today = DateTime.now();
  DateTime? _pickedDate;
  int? _selectedScheduleId;
  
  // 수정 시 사용할 ID (null이면 새로 등록)
  int? _editingId;
  // '나만 보기' 상태 변수
  bool _isPrivate = false;

  // --- [1] 데이터 저장 및 수정 로직 ---
  Future<void> _saveData(bool isSchedule) async {
    if (_inputController.text.isEmpty) return;
    // 등록 시 사용할 날짜 (현재 선택된 날짜 기준)
    final String dateStr = DateFormat('yyyy-MM-dd').format(_pickedDate ?? _today);
    final String table = isSchedule ? 'schedules' : 'todos';
    final int? myUserId = widget.userData['id'];

    final Map<String, dynamic> data = {
      if (isSchedule) 'title': _inputController.text else 'content': _inputController.text,
      'is_private': _isPrivate,
    };

    try {
      if (_editingId == null) {
        data['family_id'] = widget.userData['family_id'];
        data['created_by'] = myUserId;
        if (isSchedule) {
          data['start_date'] = dateStr;
          }
          else {
            data['target_date'] = dateStr;
            data['schedule_id'] = _selectedScheduleId;
          }
          await Supabase.instance.client.from(table).insert(data);
          } else {
            await Supabase.instance.client.from(table).update(data).eq('id', _editingId!);
          }
          // [중요] 저장 성공 후 로컬 상태를 초기화하여 화면이 재구성되도록 유도
          setState(() {
            _inputController.clear();
            _editingId = null;
            // 할 일을 등록한 경우, 전체 보기 모드라면 날짜를 오늘로 맞춰줌
            if (!isSchedule && _selectedScheduleId == null) {
              _today = _pickedDate ?? _today;
            }
          });

        if (mounted) Navigator.pop(context);
    
    } catch (e) {
    debugPrint('저장 에러: $e');
    }
  }

  // --- [2] 삭제 로직 ---
  Future<void> _deleteData(bool isSchedule, int id) async {
    final table = isSchedule ? 'schedules' : 'todos';
    try {
      await Supabase.instance.client.from(table).delete().eq('id', id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제 실패')));
    }
  }

  // --- [3] 다이얼로그 (등록/수정 공용) ---
  void _showDialog(bool isSchedule, {Map<String, dynamic>? item}) {
    // 수정 모드일 경우 데이터 채워넣기
    if (item != null) {
      _editingId = item['id'];
      _inputController.text = item[isSchedule ? 'title' : 'content'];
      _isPrivate = item['is_private'] ?? false;
      // 날짜는 기존 날짜 유지 또는 변경 가능하도록 로직 추가 가능
    } else {
      _editingId = null;
      _inputController.clear();
      _pickedDate = null;
      _isPrivate = false;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(_editingId == null ? (isSchedule ? '새 일정' : '새 할 일') : '수정하기'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _inputController,
                autofocus: true,
                decoration: const InputDecoration(hintText: '내용을 입력하세요'),
              ),
              const SizedBox(height: 15),
              
              // 1. 날짜 선택 (스케줄 등록 시에만 노출)
              if (isSchedule && _editingId == null) ...[
                ElevatedButton.icon(
                  onPressed: () async {
                    final date = await showDatePicker(
                      context: context,
                      initialDate: _today,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                      locale: const Locale('ko', 'KR'),
                    );
                    if (date != null) setDialogState(() => _pickedDate = date);
                  },
                  icon: const Icon(Icons.calendar_month),
                  label: Text(_pickedDate == null ? '날짜 선택' : DateFormat('M월 d일').format(_pickedDate!)),
                ),
                const SizedBox(height: 10),
              ],

              // 2. 공개 여부 설정 (일반 할 일 또는 스케줄일 때만)
              // 스케줄에 종속된 할 일은 스케줄 설정을 따라간다고 가정하여 숨김
              if (isSchedule || _selectedScheduleId == null)
                SwitchListTile(
                  title: const Text("나만 보기", style: TextStyle(fontSize: 16)),
                  value: _isPrivate,
                  onChanged: (val) => setDialogState(() => _isPrivate = val),
                  secondary: Icon(_isPrivate ? Icons.lock : Icons.public),
                ),
            ],
          ),
          actions: [
            TextButton(onPressed: _closeDialog, child: const Text('취소')),
            ElevatedButton(onPressed: () => _saveData(isSchedule), child: const Text('저장')),
          ],
        ),
      ),
    );
    
  }

  void _closeDialog() {
    _inputController.clear();
    _editingId = null;
    _pickedDate = null;
    if (mounted) Navigator.pop(context);
  }

  // --- [4] 메인 UI ---
  @override
  Widget build(BuildContext context) {
    final String dateStr = DateFormat('yyyy-MM-dd').format(_today);
    // 한국어 설정 덕분에 'E' 패턴이 '월', '화' 등으로 자동 출력됨
    final String formattedDay = DateFormat('M월 d일 (E)', 'ko_KR').format(_today);
    final String familyName = widget.userData['family_groups']?['name'] ?? 'Family';

    return Scaffold(
      appBar: AppBar(
        title: Text(familyName, style: Theme.of(context).textTheme.titleLarge),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.today),
            onPressed: () => setState(() { _today = DateTime.now(); _selectedScheduleId = null; }),
          )
        ],
      ),
      // [GestureDetector 위치] Scaffold의 body 전체를 감싸야 화면 어디를 밀어도 작동함
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          // 오른쪽(->)으로 밀면 속도가 양수: 어제
          if (details.primaryVelocity! > 0) {
            _changeDate(-1);
          } 
          // 왼쪽(<-)으로 밀면 속도가 음수: 내일
          else if (details.primaryVelocity! < 0) {
            _changeDate(1);
          }
        },
        child: Container(
          color: Colors.transparent, // 터치 영역 확보용
          child: Column(
            children: [
              // 날짜 헤더 (화살표 포함)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(icon: const Icon(Icons.arrow_back_ios), onPressed: () => _changeDate(-1)),
                    Text(formattedDay, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                    IconButton(icon: const Icon(Icons.arrow_forward_ios), onPressed: () => _changeDate(1)),
                  ],
                ),
              ),
              const Divider(height: 1),
              
              // 스케줄 영역
              Expanded(child: _buildListStream(true, dateStr)),
              
              const Divider(thickness: 2),
              
              // 할 일 영역 타이틀
              Padding(
                padding: const EdgeInsets.all(15.0),
                child: Text(_selectedScheduleId == null ? '해야 할 일' : '선택된 일정의 할 일', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              
              // 할 일 영역
              Expanded(child: _buildListStream(false, dateStr)),
              
              // 하단 버튼
              Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(child: ElevatedButton(onPressed: () => _showDialog(true), child: const Text('일정 등록'))),
                    const SizedBox(width: 15),
                    Expanded(child: ElevatedButton(onPressed: () => _showDialog(false), child: const Text('할 일 추가'))),
                  ],
                ),
              )
            ],
          ),
        ),
      ),
    );
  }
  Future<void> _toggleComplete(bool isSchedule, Map<String, dynamic> item) async {
    final table = isSchedule ? 'schedules' : 'todos';
    final bool currentStatus = item['is_completed'] ?? false;
    
    try {
      await Supabase.instance.client
          .from(table)
          .update({'is_completed': !currentStatus})
          .eq('id', item['id']);
      // StreamBuilder가 자동으로 화면을 갱신합니다.
    } catch (e) {
      debugPrint('상태 변경 실패: $e');
    }
  }
  
  Widget _buildListStream(bool isSchedule, String dateStr) {
    // 1. 테이블 및 쿼리 기본 설정
    final table = isSchedule ? 'schedules' : 'todos';
    dynamic query = Supabase.instance.client.from(table).stream(primaryKey: ['id']);
    
    // 2. 쿼리 필터링 조건 설정
    if (isSchedule) {
      query = query.eq('start_date', dateStr);
    } else {
      if (_selectedScheduleId != null) {
        query = query.eq('schedule_id', _selectedScheduleId);
      } else {
        query = query.eq('target_date', dateStr);
      }
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: query.order('created_at'),
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        final int myUserId = widget.userData['id'];

        final items = snapshot.data!.where((item) {
          final bool isPrivate = item['is_private'] ?? false;
          final int? creatorId = item['created_by']; 
          return !isPrivate || (creatorId == myUserId);
        }).toList();

        if (items.isEmpty) {
          return Center(
            child: Text(
              isSchedule ? '일정이 없습니다.' : '할 일이 없습니다.',
              style: const TextStyle(color: Colors.grey, fontSize: 18),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final bool isPrivate = item['is_private'] ?? false;
            final bool isSelected = isSchedule && (_selectedScheduleId == item['id']);
            
            // [추가] 완료 여부 가져오기 (DB에 is_completed 컬럼이 있어야 함)
            final bool isDone = item['is_completed'] ?? false;

            return InkWell(
              // 본문 탭: 스케줄 선택 (완료된 건 선택 시에도 시각적 구분이 유지됨)
              onTap: isSchedule 
                  ? () => setState(() => _selectedScheduleId = isSelected ? null : item['id']) 
                  : null,
              onLongPress: () => _showEditDeleteMenu(isSchedule, item),
              borderRadius: BorderRadius.circular(10),
              
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10), // 패딩 약간 조정
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: Colors.blue.withOpacity(0.3)) : null,
                ),
                child: Row(
                  children: [
                    // [수정] 아이콘을 버튼으로 변경 (완료 토글 기능)
                    IconButton(
                      icon: Icon(
                        // 완료됨 ? 체크박스 : (스케줄 선택됨 ? 체크원 : 빈원/점)
                        isDone 
                            ? Icons.check_box 
                            : (isSchedule 
                                ? (isSelected ? Icons.check_circle : Icons.circle_outlined)
                                : Icons.check_box_outline_blank), // 할 일은 네모 박스로
                        color: isDone ? Colors.green : (isSelected ? Colors.blue : Colors.grey),
                        size: 24,
                      ),
                      // 아이콘 클릭 시 DB 업데이트 함수 호출
                      onPressed: () => _toggleComplete(isSchedule, item),
                    ),
                    
                    const SizedBox(width: 5),

                    // 비밀글 아이콘
                    if (isPrivate) ...[
                      const Icon(Icons.lock, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                    ],

                    // [수정] 텍스트 스타일 (취소선 적용)
                    Expanded(
                      child: Text(
                        item[isSchedule ? 'title' : 'content'] ?? '',
                        style: TextStyle(
                          fontSize: 20,
                          // 완료되면 회색 & 취소선, 아니면 기존 로직
                          color: isDone ? Colors.grey : (isSelected ? Colors.blue : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          decoration: isDone ? TextDecoration.lineThrough : TextDecoration.none,
                          decorationColor: Colors.grey, // 취소선 색상
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // 수정/삭제 팝업 메뉴
  void _showEditDeleteMenu(bool isSchedule, Map<String, dynamic> item) {
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.edit),
            title: const Text('수정하기'),
            onTap: () {
              Navigator.pop(context);
              _showDialog(isSchedule, item: item);
            },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red),
            title: const Text('삭제하기', style: TextStyle(color: Colors.red)),
            onTap: () {
              Navigator.pop(context);
              _deleteData(isSchedule, item['id']);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(25, 15, 25, 5),
      child: Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildActionButton(String label, MaterialColor color, VoidCallback onPressed) {
    return SizedBox(
      height: 60,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(backgroundColor: color.shade50),
        child: Text(label, style: TextStyle(fontSize: 18, color: color, fontWeight: FontWeight.bold)),
      ),
    );
  }
  // 날짜 변경 로직
  void _changeDate(int days) {
    setState(() {
      _today = _today.add(Duration(days: days));
      // 날짜가 바뀌면 선택된 스케줄 필터도 초기화하는 것이 자연스럽습니다.
      _selectedScheduleId = null;
    });
  }
}