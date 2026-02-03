import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

// --- [0] 뷰 모드 상태 정의 ---
enum ViewMode { daily, weekly, monthly }

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

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
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('ko', 'KR')],
      locale: const Locale('ko', 'KR'),
      theme: ThemeData(
        useMaterial3: true,
        primarySwatch: Colors.blue,
        textTheme: const TextTheme(
          titleLarge: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
          bodyLarge: TextStyle(fontSize: 22),
          bodyMedium: TextStyle(fontSize: 18),
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

// --- [3] 메인 화면 (전체 Select 방식 통일) ---
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
  
  ViewMode _viewMode = ViewMode.daily;
  
  int? _selectedScheduleId;
  int? _editingId;
  bool _isPrivate = false;

  // [데이터 저장소] 모든 뷰가 이 리스트를 공유합니다.
  List<Map<String, dynamic>> _schedules = [];
  List<Map<String, dynamic>> _todos = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _fetchData(); // 앱 켜지면 데이터 로드
  }

  // --- [핵심] 데이터 가져오기 (Daily, Weekly, Monthly 통합) ---
  Future<void> _fetchData() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final familyId = widget.userData['family_id'];
      final myUserId = widget.userData['id'];

      // 1. 현재 화면의 시작일과 종료일 계산
      String viewStart, viewEnd;
      if (_viewMode == ViewMode.daily) {
        viewStart = DateFormat('yyyy-MM-dd').format(_today);
        viewEnd = viewStart;
      } else if (_viewMode == ViewMode.weekly) {
        final startOfWeek = _today.subtract(Duration(days: _today.weekday % 7));
        viewStart = DateFormat('yyyy-MM-dd').format(startOfWeek);
        viewEnd = DateFormat('yyyy-MM-dd').format(startOfWeek.add(const Duration(days: 6)));
      } else {
        final firstDay = DateTime(_today.year, _today.month, 1);
        final lastDay = DateTime(_today.year, _today.month + 1, 0);
        viewStart = DateFormat('yyyy-MM-dd').format(firstDay.subtract(Duration(days: firstDay.weekday % 7)));
        viewEnd = DateFormat('yyyy-MM-dd').format(lastDay.add(Duration(days: 6 - (lastDay.weekday % 7))));
      }

      // 2. [수정] 스케줄 쿼리 (기간 중첩 로직)
      // 시작일이 화면 종료일보다 작거나 같고, 종료일(또는 시작일)이 화면 시작일보다 크거나 같은 데이터
      final scheduleRes = await Supabase.instance.client
          .from('schedules')
          .select()
          .eq('family_id', familyId)
          .lte('start_date', viewEnd) // 시작일 <= 화면종료일
          .gte('start_date', viewStart) // 일단 단순화를 위해 기존 로직 유지 (기간 컬럼 추가 시 수정 가능)
          .order('start_date');

      // 3. [핵심 수정] 할 일 쿼리 (target_date ~ due_date 기간 조회)
      // 할 일의 기간이 현재 보고 있는 화면의 기간과 겹치는 것들을 모두 가져옵니다.
      final todoRes = await Supabase.instance.client
          .from('todos')
          .select()
          .eq('family_id', familyId)
          .or('target_date.lte.$viewEnd,due_date.gte.$viewStart') // 기간 중첩 쿼리
          .order('due_date');

      if (mounted) {
        setState(() {
          _schedules = List<Map<String, dynamic>>.from(scheduleRes).where((item) {
            return !(item['is_private'] ?? false) || (item['created_by'] == myUserId);
          }).toList();

          _todos = List<Map<String, dynamic>>.from(todoRes).where((item) {
            return !(item['is_private'] ?? false) || (item['created_by'] == myUserId);
          }).toList();
          
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('데이터 로드 실패: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // --- 뷰/날짜 변경 ---
  void _changeViewMode(ViewMode mode) {
    setState(() {
      _viewMode = mode;
      _today = DateTime.now();
      _selectedScheduleId = null;
    });
    _fetchData(); // 뷰 바뀌면 무조건 새로고침
  }

  void _changeDate(int offset) {
    setState(() {
      if (_viewMode == ViewMode.daily) {
        _today = _today.add(Duration(days: offset));
      } else if (_viewMode == ViewMode.weekly) {
        _today = _today.add(Duration(days: offset * 7));
      } else {
        _today = DateTime(_today.year, _today.month + offset, 1);
      }
      _selectedScheduleId = null;
    });
    _fetchData(); // 날짜 바뀌면 무조건 새로고침
  }

  // --- DB 저장/수정/삭제/완료 ---
  Future<void> _saveData(bool isSchedule) async {
    if (_inputController.text.isEmpty) return;
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
        } else {
          data['target_date'] = dateStr;
          data['schedule_id'] = _selectedScheduleId;
        }
        await Supabase.instance.client.from(table).insert(data);
      } else {
        await Supabase.instance.client.from(table).update(data).eq('id', _editingId!);
      }
      
      _closeDialog();
      setState(() {
        _inputController.clear();
        _editingId = null;
        if (!isSchedule && _selectedScheduleId == null) _today = _pickedDate ?? _today;
      });
      
      await _fetchData(); // [통일] 저장 후엔 무조건 새로고침

    } catch (e) {
      debugPrint('저장 에러: $e');
    }
  }

  Future<void> _deleteData(bool isSchedule, int id) async {
    final table = isSchedule ? 'schedules' : 'todos';
    try {
      await Supabase.instance.client.from(table).delete().eq('id', id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
      await _fetchData(); // 삭제 후 새로고침
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제 실패')));
    }
  }

  Future<void> _toggleComplete(bool isSchedule, Map<String, dynamic> item) async {
    final table = isSchedule ? 'schedules' : 'todos';
    final bool currentStatus = item['is_completed'] ?? false;
    
    // UI 즉시 반영 (낙관적 업데이트)
    setState(() {
      item['is_completed'] = !currentStatus;
    });

    try {
      await Supabase.instance.client.from(table).update({'is_completed': !currentStatus}).eq('id', item['id']);
      await _fetchData(); // DB 반영 후 확실하게 데이터 동기화
    } catch (e) {
      debugPrint('상태 변경 실패: $e');
    }
  }

  // --- [수정됨] 큼지막한 등록 화면 (어르신 맞춤형) ---
  void _showDialog(bool isSchedule, {Map<String, dynamic>? item, DateTime? specificDate}) {
    if (specificDate != null) _pickedDate = specificDate;

    if (item != null) {
      _editingId = item['id'];
      _inputController.text = item[isSchedule ? 'title' : 'content'];
      _isPrivate = item['is_private'] ?? false;
    } else {
      _editingId = null;
      _inputController.clear();
      _pickedDate = specificDate;
      _isPrivate = false;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Dialog(
          insetPadding: const EdgeInsets.all(10),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(25.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    _editingId == null 
                        ? (isSchedule ? '📅 새 일정 등록' : '✅ 할 일 추가') 
                        : '✏️ 내용 수정',
                    style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 30),

                  TextField(
                    controller: _inputController,
                    autofocus: true,
                    style: const TextStyle(fontSize: 26, color: Colors.black),
                    decoration: InputDecoration(
                      hintText: '내용을 입력하세요',
                      hintStyle: TextStyle(fontSize: 22, color: Colors.grey.shade400),
                      filled: true,
                      fillColor: Colors.grey.shade100,
                      contentPadding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                  const SizedBox(height: 25),

                  if (isSchedule && _editingId == null) ...[
                    InkWell(
                      onTap: () async {
                        final date = await showDatePicker(
                          context: context,
                          initialDate: _pickedDate ?? _today,
                          firstDate: DateTime(2000),
                          lastDate: DateTime(2100),
                          locale: const Locale('ko', 'KR'),
                        );
                        if (date != null) setDialogState(() => _pickedDate = date);
                      },
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(15),
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.calendar_month, size: 32, color: Colors.blue),
                            const SizedBox(width: 15),
                            Text(
                              _pickedDate == null 
                                  ? '날짜를 선택하세요' 
                                  : DateFormat('M월 d일 (E)', 'ko_KR').format(_pickedDate!),
                              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: Colors.blue),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 25),
                  ],

                  Transform.scale(
                    scale: 1,
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text("나만 보기", style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                      value: _isPrivate,
                      activeColor: Colors.orange,
                      onChanged: (val) => setDialogState(() => _isPrivate = val),
                    ),
                  ),
                  const SizedBox(height: 30),

                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 65,
                          child: OutlinedButton(
                            onPressed: _closeDialog,
                            style: OutlinedButton.styleFrom(
                              side: BorderSide(color: Colors.grey.shade400, width: 2),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                            ),
                            child: const Text('취소', style: TextStyle(fontSize: 22, color: Colors.grey, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 15),
                      Expanded(
                        child: SizedBox(
                          height: 65,
                          child: ElevatedButton(
                            onPressed: () => _saveData(isSchedule),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                              elevation: 5,
                            ),
                            child: const Text('저장하기', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
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

  void _showEditDeleteMenu(bool isSchedule, Map<String, dynamic> item) {
    if (item['created_by'] != widget.userData['id']) return;
    showModalBottomSheet(
      context: context,
      builder: (context) => Wrap(
        children: [
          ListTile(
            leading: const Icon(Icons.edit), title: const Text('수정하기'),
            onTap: () { Navigator.pop(context); _showDialog(isSchedule, item: item); },
          ),
          ListTile(
            leading: const Icon(Icons.delete, color: Colors.red), title: const Text('삭제하기', style: TextStyle(color: Colors.red)),
            onTap: () { Navigator.pop(context); _deleteData(isSchedule, item['id']); },
          ),
        ],
      ),
    );
  }

  // --- [메인 UI 빌드] ---
  @override
  Widget build(BuildContext context) {
    final String familyName = widget.userData['family_groups']?['name'] ?? 'Family';

    return Scaffold(
      appBar: AppBar(
        title: Text(familyName, style: Theme.of(context).textTheme.titleLarge),
        centerTitle: true,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: _buildViewTabs(),
        ),
      ),
      body: _isLoading 
          ? const Center(child: CircularProgressIndicator()) 
          : Column(
              children: [
                _buildDateHeader(),
                Expanded(
                  // 뷰 모드에 따라 UI만 다르게 그림 (데이터는 _schedules 공유)
                  child: _viewMode == ViewMode.daily 
                    ? _buildDailyView() 
                    : (_viewMode == ViewMode.weekly ? _buildWeeklyView() : _buildMonthlyView()),
                ),
                _buildBottomButtons(),
              ],
            ),
    );
  }

  Widget _buildViewTabs() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _buildTabButton('오늘', ViewMode.daily),
          _buildTabButton('주간', ViewMode.weekly),
          _buildTabButton('월간', ViewMode.monthly),
        ],
      ),
    );
  }

  Widget _buildTabButton(String text, ViewMode mode) {
    final bool isActive = _viewMode == mode;
    return InkWell(
      onTap: () => _changeViewMode(mode),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: isActive ? Colors.blue : Colors.grey.shade200,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isActive ? Colors.white : Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
      ),
    );
  }

  Widget _buildDateHeader() {
    String title;
    if (_viewMode == ViewMode.daily) {
      title = DateFormat('M월 d일 (E)', 'ko_KR').format(_today);
    } else if (_viewMode == ViewMode.weekly) {
      final startOfWeek = _today.subtract(Duration(days: _today.weekday % 7));
      final endOfWeek = startOfWeek.add(const Duration(days: 6));
      title = "${DateFormat('M.d').format(startOfWeek)} ~ ${DateFormat('M.d').format(endOfWeek)}";
    } else {
      title = DateFormat('yyyy년 M월').format(_today);
    }

    return Container(
      padding: const EdgeInsets.all(10),
      color: Colors.grey.shade50,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          IconButton(icon: const Icon(Icons.arrow_back_ios, size: 30), onPressed: () => _changeDate(-1)),
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 30), onPressed: () => _changeDate(1)),
        ],
      ),
    );
  }

  // --- [뷰 1] 일간 뷰 (이제 List를 사용합니다) ---
  Widget _buildDailyView() {
    return GestureDetector(
      onHorizontalDragEnd: (details) {
        if (details.primaryVelocity! > 0) _changeDate(-1);
        else if (details.primaryVelocity! < 0) _changeDate(1);
      },
      child: Container(
        color: Colors.transparent,
        child: Column(
          children: [
            // 상단: 스케줄 리스트
            Expanded(child: _buildListView(true)), 
            const Divider(thickness: 2),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Text(_selectedScheduleId == null ? '오늘 할 일' : '선택된 일정의 할 일', 
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            ),
            // 하단: 할 일 리스트
            Expanded(child: _buildListView(false)), 
          ],
        ),
      ),
    );
  }

  // --- [뷰 2] 주간 뷰 ---
  Widget _buildWeeklyView() {
    final startOfWeek = _today.subtract(Duration(days: _today.weekday % 7));
    
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 7,
      itemBuilder: (context, index) {
        final day = startOfWeek.add(Duration(days: index));
        final dateStr = DateFormat('yyyy-MM-dd').format(day);
        
        // 가져온 _schedules(이번주 전체)에서 필터링
        final dayEvents = _schedules.where((e) => e['start_date'] == dateStr).toList();
        final isToday = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: isToday ? const BorderSide(color: Colors.blue, width: 2) : BorderSide.none,
          ),
          elevation: 3,
          color: isToday ? Colors.blue.shade50 : Colors.white,
          margin: const EdgeInsets.only(bottom: 16),
          child: InkWell(
            onTap: () => _showDialog(true, specificDate: day),
            borderRadius: BorderRadius.circular(16),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        DateFormat('M월 d일 (E)', 'ko_KR').format(day),
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          color: isToday ? Colors.blue : Colors.black87,
                        ),
                      ),
                      if (dayEvents.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12)),
                          child: Text('${dayEvents.length}개', style: const TextStyle(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.bold)),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (dayEvents.isEmpty)
                    const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('일정 없음', style: TextStyle(fontSize: 18, color: Colors.grey)))
                  else
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: dayEvents.map((e) {
                        final bool isDone = e['is_completed'] ?? false;
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(padding: const EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 8, color: isDone ? Colors.grey : Colors.blue)),
                              Expanded(
                                child: Text(e['title'], style: TextStyle(
                                  fontSize: 20, height: 1.3,
                                  decoration: isDone ? TextDecoration.lineThrough : null,
                                  color: isDone ? Colors.grey : Colors.black87,
                                  fontWeight: FontWeight.w500,
                                )),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- [뷰 3] 월간 뷰 ---
  Widget _buildMonthlyView() {
    final firstDay = DateTime(_today.year, _today.month, 1);
    final lastDay = DateTime(_today.year, _today.month + 1, 0);
    final startCalendar = firstDay.subtract(Duration(days: firstDay.weekday % 7));
    final endCalendar = lastDay.add(Duration(days: 6 - (lastDay.weekday % 7)));
    final diff = endCalendar.difference(startCalendar).inDays + 1;

    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: ['일','월','화','수','목','금','토'].map((e) => 
            Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(e, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))
          ).toList(),
        ),
        Expanded(
          child: GridView.builder(
            padding: const EdgeInsets.all(5),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7, childAspectRatio: 0.65,
            ),
            itemCount: diff,
            itemBuilder: (context, index) {
              final day = startCalendar.add(Duration(days: index));
              final dateStr = DateFormat('yyyy-MM-dd').format(day);
              
              final dayEvents = _schedules.where((e) => e['start_date'] == dateStr).toList();
              final isCurrentMonth = day.month == _today.month;
              final isToday = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());

              return InkWell(
                onTap: () => _showDialog(true, specificDate: day),
                child: Container(
                  margin: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: isToday ? Colors.blue.shade50 : (isCurrentMonth ? Colors.white : Colors.grey.shade200),
                    border: Border.all(color: Colors.grey.shade300),
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Column(
                    children: [
                      Text(day.day.toString(), style: TextStyle(
                          fontSize: 16, 
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                          color: isCurrentMonth ? Colors.black : Colors.grey)),
                      ...dayEvents.take(2).map((e) => Container(
                        margin: const EdgeInsets.only(top: 2),
                        width: double.infinity,
                        color: (e['is_completed'] ?? false) ? Colors.grey.shade300 : Colors.blue.shade100,
                        child: Text(e['title'], style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center),
                      )),
                      if(dayEvents.length > 2) const Text('...', style: TextStyle(fontSize: 10))
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // --- [UI Helper] 리스트 렌더링 (StreamBuilder 사용 안함) ---
  Widget _buildListView(bool isSchedule) {
    List<Map<String, dynamic>> items;
    final dateStr = DateFormat('yyyy-MM-dd').format(_today);

    if (isSchedule) {
      items = _schedules.where((e) => e['start_date'] == dateStr).toList();
    } else {
      if (_selectedScheduleId != null) {
        items = _todos.where((e) => e['schedule_id'] == _selectedScheduleId).toList();
      } else {
        items = _todos.where((e) => e['target_date'] == dateStr).toList();
      }
    }

    if (items.isEmpty) return Center(child: Text(isSchedule ? '일정이 없습니다' : '할 일이 없습니다', style: const TextStyle(color: Colors.grey, fontSize: 18)));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final item = items[index];
        final bool isSelected = isSchedule && (_selectedScheduleId == item['id']);
        final bool isDone = item['is_completed'] ?? false;
        final bool isPrivate = item['is_private'] ?? false;

        return InkWell(
          onTap: isSchedule ? () => setState(() => _selectedScheduleId = isSelected ? null : item['id']) : null,
          onLongPress: () => _showEditDeleteMenu(isSchedule, item),
          borderRadius: BorderRadius.circular(10),
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 5),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
            decoration: BoxDecoration(
              color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
              border: isSelected ? Border.all(color: Colors.blue.withOpacity(0.3)) : null,
            ),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(
                    isDone ? Icons.check_box : (isSchedule && isSelected ? Icons.check_circle : Icons.check_box_outline_blank),
                    color: isDone ? Colors.green : (isSelected ? Colors.blue : Colors.grey),
                    size: 30,
                  ),
                  onPressed: () => _toggleComplete(isSchedule, item),
                ),
                const SizedBox(width: 5),
                if (isPrivate) const Icon(Icons.lock, size: 16, color: Colors.grey),
                Expanded(
                  child: Text(item[isSchedule ? 'title' : 'content'] ?? '',
                    style: TextStyle(fontSize: 22, 
                      color: isDone ? Colors.grey : (isSelected ? Colors.blue : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      decoration: isDone ? TextDecoration.lineThrough : null)),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // --- [UI Helper] 하단 버튼 ---
  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 10, offset: const Offset(0, -3))],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 70, 
              child: ElevatedButton(
                onPressed: () => _showDialog(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, foregroundColor: Colors.white, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5, 
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.calendar_month, size: 28), SizedBox(width: 8),
                    Text('일정 등록', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 15), 
          Expanded(
            child: SizedBox(
              height: 70,
              child: ElevatedButton(
                onPressed: () => _showDialog(false),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.orange, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5,
                ),
                child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.check_circle_outline, size: 28), SizedBox(width: 8),
                    Text('할 일 추가', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
                ]),
              ),
            ),
          ),
        ],
      ),
    );
  }
}