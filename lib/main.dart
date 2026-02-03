import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';

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
      supportedLocales: const [
        Locale('ko', 'KR'),
      ],
      locale: const Locale('ko', 'KR'),
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
  
  int? _editingId;
  bool _isPrivate = false;

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
          }
          else {
            data['target_date'] = dateStr;
            data['schedule_id'] = _selectedScheduleId;
          }
          await Supabase.instance.client.from(table).insert(data);
          } else {
            await Supabase.instance.client.from(table).update(data).eq('id', _editingId!);
          }
          setState(() {
            _inputController.clear();
            _editingId = null;
            if (!isSchedule && _selectedScheduleId == null) {
              _today = _pickedDate ?? _today;
            }
          });

        if (mounted) Navigator.pop(context);
    
    } catch (e) {
    debugPrint('저장 에러: $e');
    }
  }

  Future<void> _deleteData(bool isSchedule, int id) async {
    final table = isSchedule ? 'schedules' : 'todos';
    try {
      await Supabase.instance.client.from(table).delete().eq('id', id);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제 실패')));
    }
  }

  void _showDialog(bool isSchedule, {Map<String, dynamic>? item}) {
    if (item != null) {
      _editingId = item['id'];
      _inputController.text = item[isSchedule ? 'title' : 'content'];
      _isPrivate = item['is_private'] ?? false;
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

  @override
  Widget build(BuildContext context) {
    final String dateStr = DateFormat('yyyy-MM-dd').format(_today);
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
      body: GestureDetector(
        onHorizontalDragEnd: (details) {
          if (details.primaryVelocity == null) return;
          if (details.primaryVelocity! > 0) {
            _changeDate(-1);
          } 
          else if (details.primaryVelocity! < 0) {
            _changeDate(1);
          }
        },
        child: Container(
          color: Colors.transparent,
          child: Column(
            children: [
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
              
              Expanded(child: _buildListStream(true, dateStr)),
              
              const Divider(thickness: 2),
              
              Padding(
                padding: const EdgeInsets.all(15.0),
                child: Text(_selectedScheduleId == null ? '해야 할 일' : '선택된 일정의 할 일', 
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
              
              Expanded(child: _buildListStream(false, dateStr)),
              
              // [수정된 부분] _buildBottomButtons 메서드 호출로 변경
              _buildBottomButtons(), 
            ],
          ),
        ),
      ),
    );
  }

  // [추가된 부분] 어르신 맞춤형 큰 버튼 위젯
  Widget _buildBottomButtons() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withOpacity(0.2),
            spreadRadius: 1,
            blurRadius: 10,
            offset: const Offset(0, -3), 
          ),
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 70, 
              child: ElevatedButton(
                onPressed: () => _showDialog(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue, 
                  foregroundColor: Colors.white, 
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15), 
                  ),
                  elevation: 5, 
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.calendar_month, size: 28), 
                    SizedBox(width: 8),
                    Text(
                      '일정 등록',
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
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
                  backgroundColor: Colors.orange, 
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                  elevation: 5,
                ),
                child: const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.check_circle_outline, size: 28),
                    SizedBox(width: 8),
                    Text(
                      '할 일 추가',
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
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
    } catch (e) {
      debugPrint('상태 변경 실패: $e');
    }
  }
  
  Widget _buildListStream(bool isSchedule, String dateStr) {
    final table = isSchedule ? 'schedules' : 'todos';
    dynamic query = Supabase.instance.client.from(table).stream(primaryKey: ['id']);
    
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
            
            final bool isDone = item['is_completed'] ?? false;

            return InkWell(
              onTap: isSchedule 
                  ? () => setState(() => _selectedScheduleId = isSelected ? null : item['id']) 
                  : null,
              onLongPress: () => _showEditDeleteMenu(isSchedule, item),
              borderRadius: BorderRadius.circular(10),
              
              child: Container(
                margin: const EdgeInsets.symmetric(vertical: 6),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10), 
                decoration: BoxDecoration(
                  color: isSelected ? Colors.blue.withOpacity(0.1) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  border: isSelected ? Border.all(color: Colors.blue.withOpacity(0.3)) : null,
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: Icon(
                        isDone 
                            ? Icons.check_box 
                            : (isSchedule 
                                ? (isSelected ? Icons.check_circle : Icons.circle_outlined)
                                : Icons.check_box_outline_blank), 
                        color: isDone ? Colors.green : (isSelected ? Colors.blue : Colors.grey),
                        size: 24,
                      ),
                      onPressed: () => _toggleComplete(isSchedule, item),
                    ),
                    
                    const SizedBox(width: 5),

                    if (isPrivate) ...[
                      const Icon(Icons.lock, size: 16, color: Colors.grey),
                      const SizedBox(width: 6),
                    ],

                    Expanded(
                      child: Text(
                        item[isSchedule ? 'title' : 'content'] ?? '',
                        style: TextStyle(
                          fontSize: 20,
                          color: isDone ? Colors.grey : (isSelected ? Colors.blue : Colors.black87),
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          decoration: isDone ? TextDecoration.lineThrough : TextDecoration.none,
                          decorationColor: Colors.grey, 
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
  
  void _changeDate(int days) {
    setState(() {
      _today = _today.add(Duration(days: days));
      _selectedScheduleId = null;
    });
  }
}