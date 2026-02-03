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

  // --- [5] 리스트 빌더 (필터링 & 수정/삭제 기능 포함) ---
  // 리스트 빌더 위젯 (스케줄/할 일 공용)
  Widget _buildListStream(bool isSchedule, String dateStr) {
    // 1. 테이블 및 쿼리 기본 설정
    final table = isSchedule ? 'schedules' : 'todos';
    dynamic query = Supabase.instance.client.from(table).stream(primaryKey: ['id']);
    
    // 2. 쿼리 필터링 조건 설정
    if (isSchedule) {
      // 스케줄: 해당 날짜의 데이터만
      query = query.eq('start_date', dateStr);
    } else {
      // 할 일: 선택된 스케줄이 있으면 FK로, 없으면 날짜로 조회
      if (_selectedScheduleId != null) {
        query = query.eq('schedule_id', _selectedScheduleId);
      } else {
        query = query.eq('target_date', dateStr);
      }
    }

    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: query.order('created_at'), // 생성순 정렬
      builder: (context, snapshot) {
        // 로딩 상태 처리
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        
        // 3. 비즈니스 로직: '나만 보기' 필터링 (Client-side Filtering)
        // widget.userData['id']는 public.users 테이블의 PK(int)입니다.
        final int myUserId = widget.userData['id'];

        final items = snapshot.data!.where((item) {
          final bool isPrivate = item['is_private'] ?? false;
          final int? creatorId = item['created_by']; // DB에서 int로 저장됨
          
          // 조건: 공개글(false)이거나, 비공개글이면 작성자가 나(myUserId)여야 함
          return !isPrivate || (creatorId == myUserId);
        }).toList();

        // 데이터 없음 처리
        if (items.isEmpty) {
          return Center(
            child: Text(
              isSchedule ? '일정이 없습니다.' : '할 일이 없습니다.',
              style: const TextStyle(color: Colors.grey, fontSize: 18),
            ),
          );
        }

        // 4. UI 렌더링
        return ListView.builder(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
          itemCount: items.length,
          itemBuilder: (context, index) {
            final item = items[index];
            final bool isPrivate = item['is_private'] ?? false;
            
            // 스케줄 선택 상태 확인
            final bool isSelected = isSchedule && (_selectedScheduleId == item['id']);

            return InkWell(
              // 탭 이벤트: 스케줄이면 선택 토글, 할 일이면 없음(추후 완료 처리)
              onTap: isSchedule 
                  ? () => setState(() => _selectedScheduleId = isSelected ? null : item['id']) 
                  : null,
                  
              // 롱 프레스 이벤트: 수정/삭제 메뉴 호출
              onLongPress: () => _showEditDeleteMenu(isSchedule, item),
              
              borderRadius: BorderRadius.circular(10), // 터치 효과 둥글게
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                decoration: BoxDecoration(
                  // 선택된 스케줄은 파란색 배경 강조
                  color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: Colors.blue.withOpacity(0.3)) : null,
                ),
                child: Row(
                  children: [
                    // 아이콘 (스케줄은 선택 표시, 할 일은 점)
                    Icon(
                      isSchedule 
                        ? (isSelected ? Icons.check_circle : Icons.circle_outlined)
                        : Icons.fiber_manual_record, // 작은 점
                      size: isSchedule ? 22 : 14,
                      color: isSelected ? Colors.blue : Colors.grey,
                    ),
                    const SizedBox(width: 10),

                    // 비밀글 자물쇠 아이콘 표시
                    if (isPrivate) ...[
                      const Icon(Icons.lock, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                    ],

                    // 텍스트 내용
                    Expanded(
                      child: Text(
                        item[isSchedule ? 'title' : 'content'] ?? '',
                        style: TextStyle(
                          fontSize: 20,
                          // 선택된 항목은 굵게 및 파란색
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? Colors.blue : Colors.black87,
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