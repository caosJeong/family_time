import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:device_info_plus/device_info_plus.dart';

import 'setup_page.dart'; 
import 'ledger_page.dart'; // [필수] 가계부 페이지

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
            title: 'Family Calendar',
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
                fontFamily: 'Pretendard',
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

    Future<String?> _getDeviceId() async {
        final DeviceInfoPlugin deviceInfo = DeviceInfoPlugin();
        try {
            if (Platform.isAndroid) {
                return (await deviceInfo.androidInfo).id;
            } else if (Platform.isIOS) {
                return (await deviceInfo.iosInfo).identifierForVendor;
            }
        } catch (e) {
            debugPrint('기기 정보 가져오기 실패: $e');
        }
        return null;
    }

    Future<void> _checkUser() async {
        final prefs = await SharedPreferences.getInstance();
        String? storedUserId = prefs.getString('my_user_id');

        if (!mounted) return;

        if (storedUserId == null) {
            final String? deviceId = await _getDeviceId();
            if (deviceId != null) {
                final existingUser = await Supabase.instance.client
                        .from('users')
                        .select('id')
                        .eq('device_id', deviceId)
                        .maybeSingle();

                if (existingUser != null) {
                    storedUserId = existingUser['id'].toString();
                    await prefs.setString('my_user_id', storedUserId);
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('기존 계정을 찾았습니다! 로그인합니다.')),
                    );
                }
            }
        }

        if (storedUserId == null) {
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SetupPage()));
            return;
        }

        final data = await Supabase.instance.client
                .from('users')
                .select('*, family_groups(*)')
                .eq('id', storedUserId)
                .maybeSingle();

        if (!mounted) return;

        if (data == null) {
            await prefs.remove('my_user_id');
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const SetupPage()));
        } else {
            final String? currentDeviceId = await _getDeviceId();
            if (currentDeviceId != null && data['device_id'] != currentDeviceId) {
                await Supabase.instance.client.from('users').update({'device_id': currentDeviceId}).eq('id', storedUserId);
            }
            Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => FamilySchedulePage(userData: data)));
        }
    }

    @override
    Widget build(BuildContext context) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
}

class FamilySchedulePage extends StatefulWidget {
    final Map<String, dynamic> userData;
    const FamilySchedulePage({super.key, required this.userData});

    @override
    State<FamilySchedulePage> createState() => _FamilySchedulePageState();
}

class _FamilySchedulePageState extends State<FamilySchedulePage> {
    final TextEditingController _inputController = TextEditingController();
    
    // 탭 상태 (0: 일정, 1: 가계부)
    int _currentIndex = 0; 

    DateTime _today = DateTime.now();
    DateTime? _pickedDate;      
    DateTime? _pickedEndDate;   
    DateTime? _pickedDueDate;
    String _repeatOption = 'none';   
    
    ViewMode _viewMode = ViewMode.daily;
    
    int? _selectedScheduleId;
    int? _editingId;
    bool _isPrivate = false;
    
    List<Map<String, dynamic>> _schedules = [];
    List<Map<String, dynamic>> _todos = [];
    List<Map<String, dynamic>> _completions = [];
    List<Map<String, dynamic>> _familyMembers = [];
    List<Map<String, dynamic>> _myFamilyHistoryList = [];
    
    bool _isLoading = false;

    @override
    void initState() {
        super.initState();
        _fetchData();
    }

    // --- [UI] 상단 탭 버튼 ---
    Widget _buildTopSegment() {
        return Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            height: 55, 
            decoration: BoxDecoration(
                color: Colors.grey.shade200,
                borderRadius: BorderRadius.circular(15),
            ),
            child: Row(
                children: [
                    _buildSegmentButton("📅 일정·할일", 0),
                    _buildSegmentButton("💰 가계부", 1),
                ],
            ),
        );
    }

    Widget _buildSegmentButton(String text, int index) {
        final bool isSelected = _currentIndex == index;
        return Expanded(
            child: GestureDetector(
                onTap: () {
                    setState(() {
                        _currentIndex = index;
                        if (index == 0) _fetchData();
                    });
                },
                child: Container(
                    margin: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                        color: isSelected ? Colors.white : Colors.transparent,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: isSelected
                                ? [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 4, offset: const Offset(0, 2))]
                                : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                        text,
                        style: TextStyle(
                            fontSize: 20, 
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                            color: isSelected ? Colors.black : Colors.grey.shade600,
                        ),
                    ),
                ),
            ),
        );
    }

    @override
    Widget build(BuildContext context) {
        final String familyName = widget.userData['family_groups']?['name'] ?? 'Family';

        return Scaffold(
            backgroundColor: Colors.white,
            appBar: AppBar(
                title: GestureDetector(
                    onTap: _showFamilyManageSheet,
                    child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            Text(familyName, style: Theme.of(context).textTheme.titleLarge),
                            const SizedBox(width: 5),
                            const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                        ],
                    ),
                ),
                centerTitle: true,
                actions: [
                    IconButton(icon: const Icon(Icons.person_add_alt_1_rounded, size: 30), onPressed: _showInviteCode),
                    const SizedBox(width: 10),
                ],
            ),
            
            body: Column(
                children: [
                    _buildTopSegment(),
                    Expanded(
                        child: _currentIndex == 0 
                                ? _buildCalendarPage() 
                                : LedgerPage(userData: widget.userData),
                    ),
                ],
            ),
        );
    }

    // --- 달력 페이지 ---
    Widget _buildCalendarPage() {
        return _isLoading 
                ? const Center(child: CircularProgressIndicator()) 
                : Column(
                        children: [
                            _buildViewTabs(), 
                            _buildDateHeader(), 
                            Expanded(
                                child: _viewMode == ViewMode.daily 
                                        ? _buildDailyView() 
                                        : (_viewMode == ViewMode.weekly ? _buildWeeklyView() : _buildMonthlyView())
                            ), 
                            _buildBottomButtons()
                        ]
                    );
    }

    void _goToDailyView(DateTime date) {
        setState(() {
            _today = date;
            _viewMode = ViewMode.daily;
            _currentIndex = 0;
        });
        _fetchData();
    }

    Future<void> _switchFamily(String targetUserId) async {
        Navigator.pop(context);
        if (targetUserId == widget.userData['id'].toString()) return;

        setState(() => _isLoading = true);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('my_user_id', targetUserId);

        if (!mounted) return;
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => const AuthCheck()));
    }

    Future<void> _showFamilyManageSheet() async {
        final prefs = await SharedPreferences.getInstance();
        final List<String> historyIds = prefs.getStringList('family_history') ?? [];
        
        final currentId = widget.userData['id'].toString();
        if (!historyIds.contains(currentId)) {
            historyIds.add(currentId);
            await prefs.setStringList('family_history', historyIds);
        }

        if (historyIds.isNotEmpty) {
            final res = await Supabase.instance.client
                    .from('users')
                    .select('*, family_groups(name)')
                    .filter('id', 'in', historyIds);
            
            _myFamilyHistoryList = List<Map<String, dynamic>>.from(res);
        }

        if (!mounted) return;

        showModalBottomSheet(
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (context) {
                return SafeArea(
                    child: Container(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                                Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(10)))),
                                const SizedBox(height: 20),
                                const Text("가족 전환", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 15),
                                if (_myFamilyHistoryList.isEmpty)
                                    const Padding(padding: EdgeInsets.all(10), child: Text("가족 목록을 불러오는 중..."))
                                else
                                    Flexible(
                                        child: ListView(
                                            shrinkWrap: true,
                                            children: _myFamilyHistoryList.map((user) {
                                                final bool isCurrent = user['id'].toString() == widget.userData['id'].toString();
                                                final String familyName = user['family_groups']?['name'] ?? '알 수 없는 가족';
                                                final String myNickname = user['nickname'] ?? '나';
                                                return ListTile(
                                                    leading: CircleAvatar(backgroundColor: isCurrent ? Colors.blue : Colors.grey.shade200, child: Icon(Icons.home, color: isCurrent ? Colors.white : Colors.grey)),
                                                    title: Text(familyName, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 18)),
                                                    subtitle: Text("$myNickname (으)로 접속 중"),
                                                    trailing: isCurrent ? const Icon(Icons.check_circle, color: Colors.blue) : null,
                                                    onTap: () => _switchFamily(user['id'].toString()),
                                                );
                                            }).toList(),
                                        ),
                                    ),
                                const Divider(height: 30),
                                ListTile(
                                    leading: const CircleAvatar(backgroundColor: Colors.orange, child: Icon(Icons.add, color: Colors.white)),
                                    title: const Text("새 가족 만들기 / 초대 코드 입력", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                    onTap: () {
                                        Navigator.pop(context);
                                        Navigator.push(context, MaterialPageRoute(builder: (context) => const SetupPage()));
                                    },
                                ),
                            ],
                        ),
                    ),
                );
            },
        );
    }

    void _showInviteCode() {
        final String code = widget.userData['family_groups']['invite_code'] ?? 'CODE_ERROR';
        final String name = widget.userData['family_groups']['name'] ?? '우리 가족';

        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                title: const Text('가족 초대하기', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold)),
                content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Text("'$name'에 가족을 초대하세요!", style: const TextStyle(fontSize: 16)),
                        const SizedBox(height: 20),
                        Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.grey.shade300)), child: QrImageView(data: code, version: QrVersions.auto, size: 200.0)),
                        const SizedBox(height: 20),
                        SelectableText(code, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 1)),
                        const SizedBox(height: 10),
                        const Text("상대방 앱에서 'QR 스캔'을 켜주세요.", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14)),
                    ],
                ),
                actions: [
                    TextButton.icon(onPressed: () { Clipboard.setData(ClipboardData(text: code)); ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('코드가 복사되었습니다.'))); Navigator.pop(context); }, icon: const Icon(Icons.copy), label: const Text('코드 복사')),
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text('닫기')),
                ],
            ),
        );
    }

    Future<void> _launchURL(String? urlString) async {
        if (urlString == null || urlString.trim().isEmpty) return;
        if (!urlString.startsWith('http://') && !urlString.startsWith('https://')) {
            urlString = 'https://$urlString';
        }
        final Uri url = Uri.parse(urlString);
        try {
            if (await canLaunchUrl(url)) {
                await launchUrl(url, mode: LaunchMode.externalApplication);
            } else {
                if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('링크를 열 수 없습니다.')));
            }
        } catch (e) {
            debugPrint('링크 에러: $e');
        }
    }

    Future<void> _fetchData() async {
        if (!mounted) return;
        setState(() => _isLoading = true);

        try {
            final familyId = widget.userData['family_id'];
            final myUserId = widget.userData['id'];

            final todoRes = await Supabase.instance.client.from('todos').select().eq('family_id', familyId).order('due_date');

            // [수정됨] 일정은 반복 일정도 가져와야 하므로, 날짜 필터를 제거하고 전체를 가져온 뒤 Dart에서 필터링합니다.
            final scheduleRes = await Supabase.instance.client
                    .from('schedules').select().eq('family_id', familyId)
                    .order('start_date');

            // 날짜 범위 계산 (완료된 할 일 등을 위해서 필요)
            DateTime startDt, endDt;
            if (_viewMode == ViewMode.daily) {
                startDt = DateTime(_today.year, _today.month, _today.day);
                endDt = DateTime(_today.year, _today.month, _today.day);
            } else if (_viewMode == ViewMode.weekly) {
                startDt = _today.subtract(Duration(days: _today.weekday % 7));
                startDt = DateTime(startDt.year, startDt.month, startDt.day);
                endDt = startDt.add(const Duration(days: 6));
            } else {
                final firstDay = DateTime(_today.year, _today.month, 1);
                final lastDay = DateTime(_today.year, _today.month + 1, 0);
                startDt = firstDay.subtract(Duration(days: firstDay.weekday % 7));
                endDt = lastDay.add(Duration(days: 6 - (lastDay.weekday % 7)));
            }
            final String viewStartStr = DateFormat('yyyy-MM-dd').format(startDt);
            final DateTime nextDayOfEnd = endDt.add(const Duration(days: 1));
            final String viewEndNextDayStr = DateFormat('yyyy-MM-dd').format(nextDayOfEnd);
            
            final completionRes = await Supabase.instance.client
                    .from('todo_completions').select().gte('completed_date', viewStartStr).lt('completed_date', viewEndNextDayStr);

            final familyRes = await Supabase.instance.client.from('users').select().eq('family_id', familyId);

            if (mounted) {
                setState(() {
                    _schedules = List<Map<String, dynamic>>.from(scheduleRes).where((item) {
                        final bool isPrivate = item['is_private'] ?? false;
                        return !isPrivate || (item['created_by'] == myUserId);
                    }).toList();

                    _todos = List<Map<String, dynamic>>.from(todoRes).where((item) {
                        final bool isPrivate = item['is_private'] ?? false;
                        final int creator = item['created_by'];
                        final int? assignee = item['assignee_id'];
                        if (isPrivate) {
                            return creator == myUserId || assignee == myUserId;
                        }
                        return true;
                    }).toList();
                    
                    _completions = List<Map<String, dynamic>>.from(completionRes);
                    _familyMembers = List<Map<String, dynamic>>.from(familyRes);

                    _isLoading = false;
                });
            }
        } catch (e) {
            debugPrint('데이터 로드 실패: $e');
            if (mounted) setState(() => _isLoading = false);
        }
    }

    void _changeViewMode(ViewMode mode) {
        setState(() {
            _viewMode = mode;
            _today = DateTime.now();
            _selectedScheduleId = null;
        });
        _fetchData();
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
        _fetchData();
    }

    Future<DateTime?> _pickDateTime(DateTime initialDate) async {
        final DateTime? date = await showDatePicker(
            context: context, initialDate: initialDate, firstDate: DateTime(2000), lastDate: DateTime(2100),
            locale: const Locale('ko', 'KR'),
        );
        if (date == null) return null;
        if (!mounted) return date;
        final TimeOfDay? time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(initialDate));
        if (time == null) return date;
        return DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }

    Future<void> _saveData(bool isSchedule) async {
        if (_inputController.text.isEmpty) return;
        
        final start = _pickedDate ?? DateTime.now();
        final startStr = start.toIso8601String(); 
        final myUserId = widget.userData['id'];

        final Map<String, dynamic> data = {
            if (isSchedule) 'title': _inputController.text else 'content': _inputController.text,
            'is_private': _isPrivate,
            'repeat_option': _repeatOption, // [NEW] 일정, 할 일 공통 저장
        };

        try {
            if (_editingId == null) {
                data['family_id'] = widget.userData['family_id'];
                data['created_by'] = myUserId;
                
                if (isSchedule) {
                    data['start_date'] = startStr;
                    DateTime end = _pickedEndDate ?? start;
                    if (end.isBefore(start)) end = start.add(const Duration(hours: 1));
                    data['end_date'] = end.toIso8601String();
                } else {
                    data['target_date'] = startStr;
                    DateTime due = _pickedDueDate ?? start;
                    if (due.isBefore(start)) due = start; 
                    data['due_date'] = due.toIso8601String();
                    data['schedule_id'] = _selectedScheduleId;
                    data['assignee_id'] = myUserId; 
                }
                
                final table = isSchedule ? 'schedules' : 'todos';
                await Supabase.instance.client.from(table).insert(data);

            } else {
                if (isSchedule) {
                    data['start_date'] = _pickedDate!.toIso8601String();
                    data['end_date'] = _pickedEndDate!.toIso8601String();
                } else {
                    data['target_date'] = _pickedDate!.toIso8601String();
                    data['due_date'] = _pickedDueDate!.toIso8601String();
                }
                final table = isSchedule ? 'schedules' : 'todos';
                await Supabase.instance.client.from(table).update(data).eq('id', _editingId!);
            }
            
            _closeDialog();
            setState(() {
                _inputController.clear();
                _editingId = null;
                if (!isSchedule && _selectedScheduleId == null) _today = start; 
            });
            await _fetchData(); 
        } catch (e) {
            debugPrint('저장 에러: $e');
        }
    }

    Future<void> _deleteData(bool isSchedule, int id) async {
        try {
            await Supabase.instance.client.from(isSchedule ? 'schedules' : 'todos').delete().eq('id', id);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
            await _fetchData();
        } catch (e) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제 실패')));
        }
    }

    Future<void> _assignTodo(int todoId, int assigneeId) async {
        try {
            await Supabase.instance.client.from('todos').update({'assignee_id': assigneeId}).eq('id', todoId);
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('담당자를 지정했습니다.')));
            await _fetchData(); 
        } catch (e) {
            debugPrint('할당 에러: $e');
        }
    }

    Future<void> _saveDetail(bool isSchedule, int id, String memo, String link, String repeatOption) async {
        try {
            final Map<String, dynamic> updateData = {
                'description': memo,
                'link_url': link,
                'repeat_option': repeatOption, // [NEW] 수정 시 반복 옵션 업데이트
            };

            await Supabase.instance.client
                    .from(isSchedule ? 'schedules' : 'todos')
                    .update(updateData)
                    .eq('id', id);
                    
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장되었습니다.')));
            await _fetchData();
        } catch (e) {
            debugPrint('상세 저장 에러: $e');
        }
    }

    Future<void> _toggleComplete(bool isSchedule, Map<String, dynamic> item, DateTime date) async {
        if (isSchedule) return;
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final todoId = item['id'];

        final bool isCompleted = _completions.any((c) => c['todo_id'] == item['id'] && c['completed_date'] == dateStr);
        
        try {
            if (isCompleted) {
                await Supabase.instance.client.from('todo_completions').delete().eq('todo_id', todoId).eq('completed_date', dateStr);
            } else {
                await Supabase.instance.client.from('todo_completions').insert({'todo_id': todoId, 'completed_date': dateStr});
            }
            await _fetchData();
        } catch (e) {
            debugPrint('상태 변경 실패: $e');
        }
    }

    void _showAddToLedgerDialog(Map<String, dynamic> item, bool isSchedule, DateTime viewDate) {
        final TextEditingController amountCtrl = TextEditingController();
        final String title = item[isSchedule ? 'title' : 'content'] ?? '';
        
        DateTime date = viewDate;
        
        String selectedCategory = '공과금'; 
        final List<String> categories = ['식비', '공과금', '대출', '쇼핑', '기타'];

        showDialog(
            context: context,
            builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) => Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: Padding(
                        padding: const EdgeInsets.all(25.0),
                        child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                const Text("💰 가계부에 기록하기", style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                const SizedBox(height: 20),
                                Text("내역: $title", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                Text("날짜: ${DateFormat('M월 d일').format(date)}", style: const TextStyle(fontSize: 16, color: Colors.grey)),
                                const SizedBox(height: 20),
                                Wrap(
                                    spacing: 8,
                                    children: categories.map((cat) {
                                        final isSelected = selectedCategory == cat;
                                        return ChoiceChip(
                                            label: Text(cat),
                                            selected: isSelected,
                                            onSelected: (val) => setDialogState(() => selectedCategory = cat),
                                            selectedColor: Colors.orange,
                                            labelStyle: TextStyle(color: isSelected ? Colors.white : Colors.black),
                                        );
                                    }).toList(),
                                ),
                                const SizedBox(height: 20),
                                TextField(
                                    controller: amountCtrl,
                                    keyboardType: TextInputType.number,
                                    autofocus: true,
                                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                                    decoration: const InputDecoration(labelText: '얼마를 냈나요?', suffixText: '원', border: OutlineInputBorder(), filled: true, fillColor: Colors.white),
                                ),
                                const SizedBox(height: 30),

                                Row(
                                    children: [
                                        Expanded(
                                            child: SizedBox(
                                                height: 55,
                                                child: OutlinedButton(
                                                    onPressed: () => Navigator.pop(context),
                                                    style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade400), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                                                    child: const Text("취소", style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold)),
                                                ),
                                            ),
                                        ),
                                        const SizedBox(width: 15),
                                        Expanded(
                                            child: SizedBox(
                                                height: 55,
                                                child: ElevatedButton(
                                                    onPressed: () async {
                                                        if (amountCtrl.text.isEmpty) return;
                                                        try {
                                                            await Supabase.instance.client.from('ledger').insert({
                                                                'family_id': widget.userData['family_id'],
                                                                'created_by': widget.userData['id'],
                                                                'title': title,
                                                                'amount': int.parse(amountCtrl.text.replaceAll(',', '')),
                                                                'category': selectedCategory,
                                                                'transaction_date': date.toIso8601String(),
                                                            });
                                                            if (mounted) {
                                                                Navigator.pop(context); 
                                                                Navigator.pop(context); 
                                                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('가계부에 저장되었습니다!')));
                                                            }
                                                        } catch (e) {
                                                            debugPrint('가계부 저장 실패: $e');
                                                        }
                                                    },
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                                                    child: const Text("저장", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
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
        );
    }

    void _showDetailDialog(bool isSchedule, Map<String, dynamic> item, DateTime viewDate) {
        final TextEditingController memoCtrl = TextEditingController(text: item['description'] ?? '');
        final TextEditingController linkCtrl = TextEditingController(text: item['link_url'] ?? '');
        String currentRepeat = item['repeat_option'] ?? 'none';

        showDialog(
            context: context,
            builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) => Dialog(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(25.0),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    const Text("📝 상세 내용 / 설정", style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                    const SizedBox(height: 25),
                                    
                                    // [수정됨] 반복 설정 (일정도 표시)
                                    const Text("반복 설정", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue)),
                                    const SizedBox(height: 8),
                                    Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 15),
                                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
                                        child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                                value: currentRepeat,
                                                isExpanded: true,
                                                items: const [DropdownMenuItem(value: 'none', child: Text('반복 없음')), DropdownMenuItem(value: 'daily', child: Text('매일 반복')), DropdownMenuItem(value: 'weekly', child: Text('매주 반복 (요일)')), DropdownMenuItem(value: 'monthly', child: Text('매월 반복 (날짜)'))],
                                                onChanged: (val) { if (val != null) setDialogState(() => currentRepeat = val); },
                                            ),
                                        ),
                                    ),
                                    const SizedBox(height: 20),

                                    TextField(controller: memoCtrl, maxLines: 5, style: const TextStyle(fontSize: 20), decoration: InputDecoration(labelText: '메모 / 설명', border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), filled: true, fillColor: Colors.white)),
                                    const SizedBox(height: 20),
                                    TextField(controller: linkCtrl, style: const TextStyle(fontSize: 20, color: Colors.blue), decoration: InputDecoration(labelText: '웹 링크 (URL)', prefixIcon: const Icon(Icons.link), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)), filled: true, fillColor: Colors.white)),
                                    
                                    if (item['link_url'] != null && item['link_url'] != '') ...[
                                        const SizedBox(height: 10),
                                        ElevatedButton.icon(onPressed: () => _launchURL(item['link_url']), icon: const Icon(Icons.open_in_new), label: const Text("링크 열기", style: TextStyle(fontSize: 18)), style: ElevatedButton.styleFrom(backgroundColor: Colors.green.shade50, foregroundColor: Colors.green)),
                                    ],
                                    const SizedBox(height: 15),

                                    Container(
                                        width: double.infinity,
                                        height: 55,
                                        margin: const EdgeInsets.only(bottom: 10),
                                        child: OutlinedButton.icon(
                                            onPressed: () => _showAddToLedgerDialog(item, isSchedule, viewDate), 
                                            icon: const Icon(Icons.account_balance_wallet, color: Colors.orange, size: 28),
                                            label: const Text("가계부로 보내기", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.orange)),
                                            style: OutlinedButton.styleFrom(side: const BorderSide(color: Colors.orange, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))),
                                        ),
                                    ),

                                    ElevatedButton(
                                        onPressed: () { 
                                            Navigator.pop(context); 
                                            _saveDetail(isSchedule, item['id'], memoCtrl.text, linkCtrl.text, currentRepeat); 
                                        },
                                        style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), backgroundColor: Colors.blue, foregroundColor: Colors.white),
                                        child: const Text("저장 완료", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                                    ),
                                ],
                            ),
                        ),
                    ),
                ),
            ),
        );
    }

    void _showAssignDialog(Map<String, dynamic> todo) {
        showModalBottomSheet(
            context: context,
            builder: (context) {
                return Container(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                            const Text("누구에게 부탁할까요?", style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 20),
                            ..._familyMembers.map((member) {
                                final bool isAssigned = member['id'] == todo['assignee_id'];
                                return ListTile(
                                    leading: CircleAvatar(backgroundColor: isAssigned ? Colors.blue : Colors.grey.shade200, child: Icon(Icons.person, color: isAssigned ? Colors.white : Colors.grey)),
                                    title: Text(member['nickname'] ?? '이름 없음', style: const TextStyle(fontSize: 20)),
                                    trailing: isAssigned ? const Icon(Icons.check, color: Colors.blue) : null,
                                    onTap: () { Navigator.pop(context); if (member['id'] != todo['assignee_id']) _assignTodo(todo['id'], member['id']); },
                                );
                            }),
                        ],
                    ),
                );
            },
        );
    }

    void _showDialog(bool isSchedule, {Map<String, dynamic>? item, DateTime? specificDate}) {
        if (item != null) {
            _editingId = item['id'];
            _inputController.text = item[isSchedule ? 'title' : 'content'];
            _isPrivate = item['is_private'] ?? false;
            _repeatOption = item['repeat_option'] ?? 'none'; 

            if (isSchedule) {
                _pickedDate = DateTime.parse(item['start_date']);
                _pickedEndDate = DateTime.parse(item['end_date']);
            } else {
                _pickedDate = DateTime.parse(item['target_date']);
                _pickedDueDate = DateTime.parse(item['due_date']);
            }
        } else {
            _editingId = null;
            _inputController.clear();
            final baseDate = specificDate ?? _today;
            _pickedDate = DateTime(baseDate.year, baseDate.month, baseDate.day, 9, 0);
            final endOfDay = DateTime(baseDate.year, baseDate.month, baseDate.day, 23, 59);
            _pickedEndDate = _pickedDate!.add(const Duration(hours: 9)); 
            _pickedDueDate = endOfDay;
            _isPrivate = false;
            _repeatOption = 'none';
        }

        showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) => Dialog(
                    insetPadding: const EdgeInsets.all(15),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    child: SingleChildScrollView(
                        child: Padding(
                            padding: const EdgeInsets.all(25.0),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    Text(_editingId == null ? (isSchedule ? '📅 일정 등록' : '✅ 할 일 추가') : '✏️ 내용 수정', style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
                                    const SizedBox(height: 25),
                                    TextField(controller: _inputController, autofocus: true, style: const TextStyle(fontSize: 22, color: Colors.black), decoration: InputDecoration(hintText: '내용을 입력하세요', filled: true, fillColor: Colors.grey.shade100, contentPadding: const EdgeInsets.symmetric(vertical: 18, horizontal: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(15), borderSide: BorderSide.none))),
                                    const SizedBox(height: 20),
                                    _buildDateSelector(context, label: isSchedule ? "시작" : "시작일", date: _pickedDate!, onChanged: (d) => setDialogState(() => _pickedDate = d)),
                                    const SizedBox(height: 12),
                                    if (isSchedule) 
                                        _buildDateSelector(context, label: "종료", date: _pickedEndDate!, onChanged: (d) => setDialogState(() => _pickedEndDate = d))
                                    else 
                                        _buildDateSelector(context, label: "마감일", date: _pickedDueDate!, onChanged: (d) => setDialogState(() => _pickedDueDate = d), icon: Icons.alarm),
                                    
                                    const SizedBox(height: 15),
                                    
                                    Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 15),
                                        decoration: BoxDecoration(color: Colors.grey.shade100, borderRadius: BorderRadius.circular(15)),
                                        child: DropdownButtonHideUnderline(
                                            child: DropdownButton<String>(
                                                value: _repeatOption,
                                                isExpanded: true,
                                                items: const [
                                                    DropdownMenuItem(value: 'none', child: Text('반복 없음')),
                                                    DropdownMenuItem(value: 'daily', child: Text('매일 반복')),
                                                    DropdownMenuItem(value: 'weekly', child: Text('매주 반복 (요일)')),
                                                    DropdownMenuItem(value: 'monthly', child: Text('매월 반복 (날짜)')),
                                                ],
                                                onChanged: (val) {
                                                    if (val != null) setDialogState(() => _repeatOption = val);
                                                },
                                            ),
                                        ),
                                    ),

                                    const SizedBox(height: 25),
                                    GestureDetector(
                                        onTap: () => setDialogState(() => _isPrivate = !_isPrivate),
                                        child: Container(
                                            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 20),
                                            decoration: BoxDecoration(color: _isPrivate ? Colors.orange.shade50 : Colors.transparent, borderRadius: BorderRadius.circular(30), border: _isPrivate ? Border.all(color: Colors.orange) : null),
                                            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.min, children: [Icon(_isPrivate ? Icons.lock : Icons.lock_open, color: _isPrivate ? Colors.orange : Colors.grey, size: 28), const SizedBox(width: 10), Text("나만 보기 (비공개)", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: _isPrivate ? Colors.orange : Colors.grey)), const SizedBox(width: 10), Switch(value: _isPrivate, activeColor: Colors.white, activeTrackColor: Colors.orange, onChanged: (val) => setDialogState(() => _isPrivate = val))]),
                                        ),
                                    ),
                                    const SizedBox(height: 30),
                                    Row(children: [Expanded(child: SizedBox(height: 60, child: OutlinedButton(onPressed: _closeDialog, style: OutlinedButton.styleFrom(side: BorderSide(color: Colors.grey.shade400, width: 2), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15))), child: const Text('취소', style: TextStyle(fontSize: 20, color: Colors.grey, fontWeight: FontWeight.bold))))), const SizedBox(width: 15), Expanded(child: SizedBox(height: 60, child: ElevatedButton(onPressed: () => _saveData(isSchedule), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5), child: const Text('저장', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)))))],),
                                ],
                            ),
                        ),
                    ),
                ),
            ),
        );
    }
    
    Widget _buildDateSelector(BuildContext context, {required String label, required DateTime date, required Function(DateTime) onChanged, IconData icon = Icons.calendar_month}) {
        return InkWell(
            onTap: () async {
                final picked = await _pickDateTime(date);
                if (picked != null) onChanged(picked);
            },
            child: Container(
                padding: const EdgeInsets.symmetric(vertical: 15, horizontal: 20),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15), border: Border.all(color: Colors.blue.shade100, width: 2), boxShadow: [BoxShadow(color: Colors.blue.shade50, blurRadius: 5, offset: const Offset(0, 3))]),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [Icon(icon, size: 24, color: Colors.blue.shade700), const SizedBox(width: 8), Text(label, style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue.shade900))]), Column(crossAxisAlignment: CrossAxisAlignment.end, children: [Text(DateFormat('M월 d일 (E)', 'ko_KR').format(date), style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.black87)), Text(DateFormat('a h:mm', 'ko_KR').format(date), style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.blue))])]),
            ),
        );
    }

    void _closeDialog() {
        _inputController.clear(); _editingId = null; _pickedDate = null; _pickedEndDate = null; _pickedDueDate = null;
        if (mounted) Navigator.pop(context);
    }

    // [수정됨] 롱탭 메뉴에 '상세 설정' 추가
    void _showEditDeleteMenu(bool isSchedule, Map<String, dynamic> item, DateTime viewDate) {
        if (item['created_by'] != widget.userData['id']) return;
        showModalBottomSheet(
            context: context,
            builder: (context) => Wrap(
                children: [
                    ListTile(leading: const Icon(Icons.edit, color: Colors.blue), title: const Text('수정하기'), onTap: () { Navigator.pop(context); _showDialog(isSchedule, item: item); }),
                    ListTile(leading: const Icon(Icons.delete, color: Colors.red), title: const Text('삭제하기', style: TextStyle(color: Colors.red)), onTap: () { Navigator.pop(context); _deleteData(isSchedule, item['id']); }),
                    ListTile(leading: const Icon(Icons.settings, color: Colors.grey), title: const Text('상세 설정'), onTap: () { Navigator.pop(context); _showDetailDialog(isSchedule, item, viewDate); }),
                ],
            ),
        );
    }

    // [수정됨] 아이콘 클릭 동작 및 아이콘 변경
    Widget _buildListView(bool isSchedule, DateTime date) {
        final items = _filterItemsForDate(isSchedule ? _schedules : _todos, date, isSchedule: isSchedule);
        final dateStr = DateFormat('yyyy-MM-dd').format(date);
        final myId = widget.userData['id'];

        if (items.isEmpty) return Center(child: Text(isSchedule ? '일정이 없습니다' : '할 일이 없습니다', style: const TextStyle(color: Colors.grey, fontSize: 18)));

        return ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 10), 
            itemCount: items.length, 
            itemBuilder: (context, index) {
                final item = items[index];
                final bool isSelected = isSchedule && (_selectedScheduleId == item['id']);
                final bool isPrivate = item['is_private'] ?? false;
                final int? assigneeId = item['assignee_id'];
                final int creatorId = item['created_by'];
                final bool hasLink = item['link_url'] != null && item['link_url'].toString().trim().isNotEmpty;
                final bool isReceivedRequest = (creatorId != myId && assigneeId == myId);
                final bool isSentRequest = (creatorId == myId && assigneeId != null && assigneeId != myId);
                bool isDone = false;
                if (!isSchedule) isDone = _completions.any((c) => c['todo_id'] == item['id'] && c['completed_date'] == dateStr);

                Widget cardContent = Container(
                    margin: const EdgeInsets.symmetric(vertical: 5), 
                    padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 5),
                    decoration: BoxDecoration(color: isReceivedRequest ? Colors.green.withOpacity(0.1) : (isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent), borderRadius: BorderRadius.circular(10), border: isSelected ? Border.all(color: Colors.blue.withOpacity(0.3)) : null),
                    child: Row(children: [
                        if (!isSchedule) IconButton(icon: Icon(isDone ? Icons.check_box : Icons.check_box_outline_blank, color: isDone ? Colors.green : Colors.grey, size: 30), onPressed: () => _toggleComplete(isSchedule, item, date)),
                        const SizedBox(width: 5),
                        if (isReceivedRequest) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.card_giftcard, color: Colors.green, size: 20)) else if (isSentRequest) const Padding(padding: EdgeInsets.only(right: 8), child: Icon(Icons.send, color: Colors.orange, size: 20)),
                        if (isPrivate) const Padding(padding: EdgeInsets.only(right: 5), child: Icon(Icons.lock, size: 16, color: Colors.grey)),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(item[isSchedule ? 'title' : 'content'] ?? '', style: TextStyle(fontSize: 22, color: isDone ? Colors.grey : (isSelected ? Colors.blue : Colors.black87), fontWeight: isSelected ? FontWeight.bold : FontWeight.normal, decoration: isDone ? TextDecoration.lineThrough : null)), if (assigneeId != null && assigneeId != myId && !isSchedule) FutureBuilder(future: Future.value(_familyMembers.firstWhere((m) => m['id'] == assigneeId, orElse: () => {})['nickname']), builder: (context, snapshot) => snapshot.hasData && snapshot.data != null ? Text("To. ${snapshot.data}", style: const TextStyle(fontSize: 14, color: Colors.grey)) : const SizedBox.shrink()), if (isReceivedRequest && !isSchedule) FutureBuilder(future: Future.value(_familyMembers.firstWhere((m) => m['id'] == creatorId, orElse: () => {})['nickname']), builder: (context, snapshot) => snapshot.hasData && snapshot.data != null ? Text("From. ${snapshot.data}", style: const TextStyle(fontSize: 14, color: Colors.green)) : const SizedBox.shrink())])),
                        
                        // [수정 포인트] 아이콘 변경 (edit_note -> edit) 및 동작 변경 (상세 -> 수정 다이얼로그)
                        if (hasLink) 
                            IconButton(icon: const Icon(Icons.open_in_new, color: Colors.blue, size: 30), onPressed: () => _launchURL(item['link_url']), tooltip: '링크 열기') 
                        else 
                            IconButton(
                                icon: const Icon(Icons.edit, color: Colors.grey, size: 26), // 아이콘 변경
                                onPressed: () => _showDialog(isSchedule, item: item), // 동작 변경 (수정)
                                tooltip: '수정하기'
                            ) 
                    ]),
                );

                return Dismissible(
                    key: Key('item-${isSchedule ? 'S' : 'T'}-${item['id']}'),
                    direction: !isSchedule ? DismissDirection.horizontal : DismissDirection.startToEnd,
                    background: Container(color: Colors.orange, alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Row(children: [Icon(Icons.edit_note, color: Colors.white, size: 30), SizedBox(width: 10), Text("상세 작성", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold))])),
                    secondaryBackground: Container(color: Colors.green, alignment: Alignment.centerRight, padding: const EdgeInsets.symmetric(horizontal: 20), child: const Row(mainAxisAlignment: MainAxisAlignment.end, children: [Text("부탁하기", style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)), SizedBox(width: 10), Icon(Icons.person_add, color: Colors.white, size: 30)])),
                    confirmDismiss: (direction) async { if (direction == DismissDirection.startToEnd) _showDetailDialog(isSchedule, item, date); else _showAssignDialog(item); return false; }, 
                    child: InkWell(onTap: isSchedule ? () => setState(() => _selectedScheduleId = isSelected ? null : item['id']) : null, onLongPress: () => _showEditDeleteMenu(isSchedule, item, date), borderRadius: BorderRadius.circular(10), child: cardContent),
                );
            },
        );
    }

    List<Map<String, dynamic>> _filterItemsForDate(List<Map<String, dynamic>> source, DateTime date, {required bool isSchedule}) {
        final viewDate = DateTime(date.year, date.month, date.day);

        if (isSchedule) {
            return source.where((item) {
                DateTime start = DateTime.parse(item['start_date']);
                DateTime end = DateTime.parse(item['end_date'] ?? item['start_date']);
                
                final cleanStart = DateTime(start.year, start.month, start.day);
                final cleanEnd = DateTime(end.year, end.month, end.day);
                final String repeat = item['repeat_option'] ?? 'none';

                if (repeat == 'none') {
                    return (cleanStart.isBefore(viewDate) || cleanStart.isAtSameMomentAs(viewDate)) && 
                           (cleanEnd.isAfter(viewDate) || cleanEnd.isAtSameMomentAs(viewDate));
                } else {
                    if (viewDate.isBefore(cleanStart)) return false; 
                    if (repeat == 'daily') return true; 
                    if (repeat == 'weekly') return viewDate.weekday == cleanStart.weekday; 
                    if (repeat == 'monthly') return viewDate.day == cleanStart.day; 
                    return false;
                }
            }).toList();
        }
        
        return source.where((item) {
            if (_selectedScheduleId != null && item['schedule_id'] != _selectedScheduleId) return false;
            
            DateTime targetDate = DateTime.parse(item['target_date']); 
            final cleanTargetDate = DateTime(targetDate.year, targetDate.month, targetDate.day);
            
            if (viewDate.isBefore(cleanTargetDate)) return false;

            final String type = item['repeat_option'] ?? 'none';
            
            if (type == 'none') {
                DateTime due = DateTime.parse(item['due_date'] ?? item['target_date']);
                final cleanDue = DateTime(due.year, due.month, due.day);
                return (cleanTargetDate.isBefore(viewDate) || cleanTargetDate.isAtSameMomentAs(viewDate)) && 
                       (cleanDue.isAfter(viewDate) || cleanDue.isAtSameMomentAs(viewDate));
            } 
            else if (type == 'daily') return true; 
            else if (type == 'weekly') return viewDate.weekday == targetDate.weekday;
            else if (type == 'monthly') return viewDate.day == targetDate.day;
            
            return false;
        }).toList();
    }

    Widget _buildViewTabs() {
        return Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [_buildTabButton('오늘', ViewMode.daily), _buildTabButton('주간', ViewMode.weekly), _buildTabButton('월간', ViewMode.monthly)]));
    }

    Widget _buildTabButton(String text, ViewMode mode) {
        final bool isActive = _viewMode == mode;
        return InkWell(onTap: () => _changeViewMode(mode), borderRadius: BorderRadius.circular(20), child: Container(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10), decoration: BoxDecoration(color: isActive ? Colors.blue : Colors.grey.shade200, borderRadius: BorderRadius.circular(20)), child: Text(text, style: TextStyle(color: isActive ? Colors.white : Colors.black, fontWeight: FontWeight.bold, fontSize: 18))));
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
        return Container(padding: const EdgeInsets.all(10), color: Colors.grey.shade50, child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [IconButton(icon: const Icon(Icons.arrow_back_ios, size: 30), onPressed: () => _changeDate(-1)), Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)), IconButton(icon: const Icon(Icons.arrow_forward_ios, size: 30), onPressed: () => _changeDate(1))]));
    }

    // [수정됨] 일일 뷰에서 리스트 비율 동적 조절
    Widget _buildDailyView() {
        final dailySchedules = _filterItemsForDate(_schedules, _today, isSchedule: true);
        final dailyTodos = _filterItemsForDate(_todos, _today, isSchedule: false);

        int scheduleFlex = 5;
        int todoFlex = 5;

        // 동적 비율 설정
        if (dailySchedules.isEmpty && dailyTodos.isNotEmpty) {
            scheduleFlex = 3; // 일정이 없으면 작게
            todoFlex = 7;     // 할 일이 있으면 길게
        } else if (dailySchedules.isNotEmpty && dailyTodos.isEmpty) {
            scheduleFlex = 7; // 일정이 있으면 길게
            todoFlex = 3;     // 할 일이 없으면 작게
        }
        // 둘 다 있거나, 둘 다 없으면 5:5

        return GestureDetector(
            onHorizontalDragEnd: (details) { if (details.primaryVelocity! > 0) _changeDate(-1); else if (details.primaryVelocity! < 0) _changeDate(1); },
            child: Container(
                color: Colors.transparent, 
                child: Column(
                    children: [
                        Expanded(flex: scheduleFlex, child: _buildListView(true, _today)),
                        const Divider(thickness: 2),
                        Padding(padding: const EdgeInsets.all(10), child: Text(_selectedScheduleId == null ? '오늘 할 일' : '선택된 일정의 할 일', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))),
                        Expanded(flex: todoFlex, child: _buildListView(false, _today))
                    ]
                )
            ),
        );
    }

    Widget _buildWeeklyView() {
        final startOfWeek = _today.subtract(Duration(days: _today.weekday % 7));
        return ListView.builder(padding: const EdgeInsets.all(12), itemCount: 7, itemBuilder: (context, index) { final day = startOfWeek.add(Duration(days: index)); return _buildCardForDay(day); });
    }

    Widget _buildMonthlyView() {
        final firstDay = DateTime(_today.year, _today.month, 1);
        final lastDay = DateTime(_today.year, _today.month + 1, 0);
        final startCalendar = firstDay.subtract(Duration(days: firstDay.weekday % 7));
        final endCalendar = lastDay.add(Duration(days: 6 - (lastDay.weekday % 7)));
        final diff = endCalendar.difference(startCalendar).inDays + 1;
        return Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: ['일','월','화','수','목','금','토'].map((e) => Padding(padding: const EdgeInsets.symmetric(vertical: 10), child: Text(e, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)))).toList()),
            Expanded(child: GridView.builder(padding: const EdgeInsets.all(5), gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 7, childAspectRatio: 0.65), itemCount: diff, itemBuilder: (context, index) {
                final day = startCalendar.add(Duration(days: index));
                final isToday = DateFormat('yyyy-MM-dd').format(day) == DateFormat('yyyy-MM-dd').format(DateTime.now());
                final isCurrentMonth = day.month == _today.month;
                final daySchedules = _filterItemsForDate(_schedules, day, isSchedule: true);
                return InkWell(onTap: () => _goToDailyView(day), child: Container(margin: const EdgeInsets.all(2), decoration: BoxDecoration(color: isToday ? Colors.blue.shade50 : (isCurrentMonth ? Colors.white : Colors.grey.shade200), border: Border.all(color: Colors.grey.shade300), borderRadius: BorderRadius.circular(5)), child: Column(children: [Text(day.day.toString(), style: TextStyle(fontSize: 16, fontWeight: isToday ? FontWeight.bold : FontWeight.normal, color: isCurrentMonth ? Colors.black : Colors.grey)), ...daySchedules.take(2).map((e) => Container(margin: const EdgeInsets.only(top: 2), width: double.infinity, color: Colors.blue.shade100, child: Text(e['title'], style: const TextStyle(fontSize: 10), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center))), if(daySchedules.length > 2) const Text('...', style: TextStyle(fontSize: 10))])));
            })),
        ]);
    }

    Widget _buildCardForDay(DateTime day) {
        final dateStr = DateFormat('yyyy-MM-dd').format(day);
        final isToday = dateStr == DateFormat('yyyy-MM-dd').format(DateTime.now());
        final dayEvents = _filterItemsForDate(_schedules, day, isSchedule: true);
        return Card(shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: isToday ? const BorderSide(color: Colors.blue, width: 2) : BorderSide.none), elevation: 3, color: isToday ? Colors.blue.shade50 : Colors.white, margin: const EdgeInsets.only(bottom: 16), child: InkWell(onTap: () => _goToDailyView(day), borderRadius: BorderRadius.circular(16), child: Padding(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Text(DateFormat('M월 d일 (E)', 'ko_KR').format(day), style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: isToday ? Colors.blue : Colors.black87)), if (dayEvents.isNotEmpty) Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), decoration: BoxDecoration(color: Colors.blue.shade100, borderRadius: BorderRadius.circular(12)), child: Text('${dayEvents.length}개', style: const TextStyle(fontSize: 14, color: Colors.blue, fontWeight: FontWeight.bold)))]), const SizedBox(height: 12), if (dayEvents.isEmpty) const Padding(padding: EdgeInsets.symmetric(vertical: 8), child: Text('일정 없음', style: TextStyle(fontSize: 18, color: Colors.grey))) else ...dayEvents.map((e) { return Padding(padding: const EdgeInsets.only(bottom: 8), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [const Padding(padding: EdgeInsets.only(top: 6, right: 8), child: Icon(Icons.circle, size: 8, color: Colors.blue)), Expanded(child: Text(e['title'], style: const TextStyle(fontSize: 20, height: 1.3, fontWeight: FontWeight.w500)))])); })]))));
    }

    Widget _buildBottomButtons() {
        return Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(color: Colors.white, boxShadow: [BoxShadow(color: Colors.grey.withOpacity(0.2), spreadRadius: 1, blurRadius: 10, offset: const Offset(0, -3))]), child: Row(children: [Expanded(child: SizedBox(height: 70, child: ElevatedButton(onPressed: () => _showDialog(true), style: ElevatedButton.styleFrom(backgroundColor: Colors.blue, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.calendar_month, size: 28), SizedBox(width: 8), Text('일정 등록', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))])))), const SizedBox(width: 15), Expanded(child: SizedBox(height: 70, child: ElevatedButton(onPressed: () => _showDialog(false), style: ElevatedButton.styleFrom(backgroundColor: Colors.orange, foregroundColor: Colors.white, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)), elevation: 5), child: const Row(mainAxisAlignment: MainAxisAlignment.center, children: [Icon(Icons.check_circle_outline, size: 28), SizedBox(width: 8), Text('할 일 추가', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold))]))))]));
    }
}
