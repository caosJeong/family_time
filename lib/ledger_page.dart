import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // [필수] 클립보드 사용을 위해 필요
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

class LedgerPage extends StatefulWidget {
    final Map<String, dynamic> userData;
    const LedgerPage({super.key, required this.userData});

    @override
    State<LedgerPage> createState() => _LedgerPageState();
}

class _LedgerPageState extends State<LedgerPage> {
    final _amountCtrl = TextEditingController();
    final _titleCtrl = TextEditingController();
    
    // 입력용 변수
    DateTime _selectedDate = DateTime.now();
    String _selectedCategory = '식비'; 
    bool _isExcluded = false; // 카드 대금 중복 방지용

    // 필터용 변수
    DateTime _currentMonth = DateTime.now(); 
    int? _selectedMemberId; 
    List<Map<String, dynamic>> _familyMembers = []; 

    // 카테고리 관리
    List<String> _categories = ['식비', '공과금', '대출', '쇼핑', '기타'];

    @override
    void initState() {
        super.initState();
        _loadCategories();
        _fetchFamilyMembers();
    }

    Future<void> _fetchFamilyMembers() async {
        try {
            final res = await Supabase.instance.client
                .from('users')
                .select('id, nickname')
                .eq('family_id', widget.userData['family_id']);
            
            if (mounted) {
                setState(() {
                    _familyMembers = List<Map<String, dynamic>>.from(res);
                });
            }
        } catch (e) {
            debugPrint('가족 목록 로드 실패: $e');
        }
    }

    Future<void> _loadCategories() async {
        final prefs = await SharedPreferences.getInstance();
        final saved = prefs.getStringList('my_categories');
        if (saved != null && saved.isNotEmpty) {
            setState(() {
                _categories = saved;
            });
        }
    }

    Future<void> _addNewCategory(String newCat) async {
        if (newCat.isEmpty || _categories.contains(newCat)) return;
        
        setState(() {
            _categories.add(newCat);
            _selectedCategory = newCat;
        });
        
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList('my_categories', _categories);
    }

    void _changeMonth(int offset) {
        setState(() {
            _currentMonth = DateTime(_currentMonth.year, _currentMonth.month + offset, 1);
        });
    }

    // 스와이프로 통계 제외 토글 함수
    Future<void> _toggleExclusion(Map<String, dynamic> item) async {
        try {
            final bool currentStatus = item['is_excluded'] ?? false;
            final bool newStatus = !currentStatus;

            await Supabase.instance.client
                .from('ledger')
                .update({'is_excluded': newStatus})
                .eq('id', item['id']);

            if (mounted) {
                setState(() {}); // 화면 갱신
                ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                        content: Text(newStatus ? '통계에서 제외되었습니다.' : '통계에 다시 포함됩니다.'),
                        duration: const Duration(seconds: 1),
                    ),
                );
            }
        } catch (e) {
            debugPrint('상태 변경 실패: $e');
        }
    }

    // [NEW] 클립보드 파싱 함수 (핵심 기능)
    Future<void> _parseFromClipboard(StateSetter setDialogState) async {
        final ClipboardData? data = await Clipboard.getData(Clipboard.kTextPlain);
        if (data == null || data.text == null) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('클립보드에 복사된 텍스트가 없습니다.')));
            return;
        }

        String text = data.text!;
        // 예시 문자: [Web발신] 삼성카드(1234) 승인 홍*동 15,000원 02/14 12:30 스타벅스 누적100,000원

        // 1. 금액 추출 (숫자+원 또는 콤마 포함 숫자)
        // "15,000원" 패턴 찾기
        RegExp moneyRegex = RegExp(r'([0-9,]+)원');
        final moneyMatch = moneyRegex.firstMatch(text);
        
        String? amountStr;
        if (moneyMatch != null) {
            amountStr = moneyMatch.group(1); // "15,000" 추출
        } else {
            // "원"이 없는 경우도 대비해서 금액처럼 보이는 가장 큰 숫자 찾기 (단, 날짜/시간 제외)
            // 이건 오작동 가능성이 있어 일단 "원"이 있는 경우를 우선함.
        }

        // 2. 가맹점(내용) 추출 - 이건 카드사마다 형식이 달라서 완벽하진 않지만 시도
        // 보통 금액 뒤에 가맹점이 옴. 또는 키워드로 찾기.
        String? merchantStr;
        List<String> keywords = ['승인', '일시불', '결제'];
        // 단순하게 줄바꿈이나 공백으로 분리해서 추론하는 로직이 필요하지만, 
        // 여기서는 사용자가 수정할 수 있게 금액만이라도 확실히 채워주는게 목표.

        // 3. 날짜 추출 (MM/dd 형식)
        RegExp dateRegex = RegExp(r'([0-9]{2})/([0-9]{2})');
        final dateMatch = dateRegex.firstMatch(text);
        DateTime? parsedDate;
        if (dateMatch != null) {
            int month = int.parse(dateMatch.group(1)!);
            int day = int.parse(dateMatch.group(2)!);
            parsedDate = DateTime(DateTime.now().year, month, day);
        }

        if (amountStr != null) {
            setDialogState(() {
                _amountCtrl.text = amountStr!;
                if (parsedDate != null) _selectedDate = parsedDate;
                // 내용은 사용자가 직접 수정하도록 비워두거나, 전체 텍스트를 넣을 수도 있음
                // _titleCtrl.text = text; // 전체 텍스트를 넣고 싶으면 주석 해제
            });
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('문자 내용을 분석하여 입력했습니다!')));
        } else {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('금액(000원) 형식을 찾을 수 없습니다.')));
        }
    }

    @override
    Widget build(BuildContext context) {
        return Scaffold(
            backgroundColor: Colors.white,
            body: Column(
                children: [
                    // 1. 상단 필터 영역
                    Container(
                        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                        color: Colors.white,
                        child: Column(
                            children: [
                                Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                        IconButton(
                                            icon: const Icon(Icons.arrow_back_ios),
                                            onPressed: () => _changeMonth(-1),
                                        ),
                                        Text(
                                            DateFormat('yyyy년 M월').format(_currentMonth),
                                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                                        ),
                                        IconButton(
                                            icon: const Icon(Icons.arrow_forward_ios),
                                            onPressed: () => _changeMonth(1),
                                        ),
                                    ],
                                ),
                                const SizedBox(height: 10),
                                SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Row(
                                        children: [
                                            _buildFilterChip('전체', null),
                                            ..._familyMembers.map((m) => _buildFilterChip(m['nickname'] ?? '이름 없음', m['id'])),
                                        ],
                                    ),
                                ),
                            ],
                        ),
                    ),

                    // 2. 요약 카드
                    _buildSummaryCard(),
                    
                    const Divider(height: 1, thickness: 1),
                    
                    // 3. 내역 리스트
                    Expanded(child: _buildTransactionList()),
                ],
            ),
            floatingActionButton: SizedBox(
                width: 70, height: 70,
                child: FloatingActionButton(
                    onPressed: () => _showAddDialog(), 
                    backgroundColor: Colors.orange,
                    child: const Icon(Icons.add, size: 40, color: Colors.white),
                ),
            ),
        );
    }

    Widget _buildFilterChip(String label, int? memberId) {
        final bool isSelected = _selectedMemberId == memberId;
        return Padding(
            padding: const EdgeInsets.only(right: 8.0),
            child: ChoiceChip(
                label: Text(label),
                selected: isSelected,
                onSelected: (bool selected) {
                    setState(() {
                        if (selected) _selectedMemberId = memberId;
                        else if (_selectedMemberId == memberId) _selectedMemberId = null;
                    });
                },
                selectedColor: Colors.blue.shade100,
                labelStyle: TextStyle(
                    color: isSelected ? Colors.blue.shade900 : Colors.black,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
            ),
        );
    }

    Widget _buildSummaryCard() {
        final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
        final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);

        var query = Supabase.instance.client
            .from('ledger')
            .select()
            .eq('family_id', widget.userData['family_id'])
            .gte('transaction_date', startOfMonth.toIso8601String())
            .lt('transaction_date', nextMonth.toIso8601String());

        if (_selectedMemberId != null) {
            query = query.eq('created_by', _selectedMemberId!);
        }

        return FutureBuilder(
            future: query,
            builder: (context, snapshot) {
                if (!snapshot.hasData) return const SizedBox(height: 100, child: Center(child: CircularProgressIndicator()));
                
                final list = List<Map<String, dynamic>>.from(snapshot.data as List);
                int total = 0;
                int fixedCost = 0;

                for (var item in list) {
                    // 제외 항목이면 합계 계산 건너뛰기
                    if (item['is_excluded'] == true) continue;

                    int amt = item['amount'] ?? 0;
                    total += amt;
                    if (item['category'] == '공과금' || item['category'] == '대출') {
                        fixedCost += amt;
                    }
                }

                final formatter = NumberFormat('#,###');

                return Container(
                    padding: const EdgeInsets.all(20),
                    width: double.infinity,
                    color: Colors.orange.shade50,
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                            Text(
                                '${_currentMonth.month}월 ${_selectedMemberId == null ? "우리 가족" : "선택된 멤버"} 지출', 
                                style: const TextStyle(fontSize: 16, color: Colors.grey)
                            ),
                            const SizedBox(height: 5),
                            Text(
                                '${formatter.format(total)}원', 
                                style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold, color: Colors.black)
                            ),
                            const SizedBox(height: 15),
                            Row(
                                children: [
                                    const Icon(Icons.warning_amber_rounded, color: Colors.red, size: 24),
                                    const SizedBox(width: 5),
                                    const Text("고정비: ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                    Text(
                                        '${formatter.format(fixedCost)}원', 
                                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.red)
                                    ),
                                ],
                            ),
                        ],
                    ),
                );
            },
        );
    }

    Widget _buildTransactionList() {
        final startOfMonth = DateTime(_currentMonth.year, _currentMonth.month, 1);
        final nextMonth = DateTime(_currentMonth.year, _currentMonth.month + 1, 1);

        // 1. 기본 필터
        var query = Supabase.instance.client
            .from('ledger')
            .select('*, users(nickname)')
            .eq('family_id', widget.userData['family_id'])
            .gte('transaction_date', startOfMonth.toIso8601String())
            .lt('transaction_date', nextMonth.toIso8601String());

        // 2. 조건부 필터
        if (_selectedMemberId != null) {
            query = query.eq('created_by', _selectedMemberId!);
        }

        // 3. 정렬
        final finalQuery = query.order('transaction_date', ascending: false);

        return FutureBuilder(
            future: finalQuery,
            builder: (context, snapshot) {
                if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
                
                final list = List<Map<String, dynamic>>.from(snapshot.data as List);

                if (list.isEmpty) {
                    return const Center(child: Text("내역이 없습니다.", style: TextStyle(fontSize: 20, color: Colors.grey)));
                }

                return ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const Divider(),
                    itemBuilder: (context, index) {
                        final item = list[index];
                        final date = DateTime.parse(item['transaction_date']);
                        final formatter = NumberFormat('#,###');
                        
                        final isFixed = item['category'] == '공과금' || item['category'] == '대출';
                        final bool isExcluded = item['is_excluded'] ?? false;
                        final nickname = item['users']?['nickname'] ?? '알 수 없음';
                        final bool isMyItem = item['created_by'].toString() == widget.userData['id'].toString();

                        return Dismissible(
                            key: Key(item['id'].toString()),
                            // [오른쪽으로 밀기] -> 통계 제외 토글
                            background: Container(
                                color: isExcluded ? Colors.green : Colors.grey, 
                                alignment: Alignment.centerLeft,
                                padding: const EdgeInsets.only(left: 20),
                                child: Row(
                                    children: [
                                        Icon(
                                            isExcluded ? Icons.visibility : Icons.visibility_off, 
                                            color: Colors.white
                                        ),
                                        const SizedBox(width: 10),
                                        Text(
                                            isExcluded ? "통계 포함" : "통계 제외",
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)
                                        ),
                                    ],
                                ),
                            ),
                            // [왼쪽으로 밀기] -> 삭제
                            secondaryBackground: Container(
                                color: Colors.red,
                                alignment: Alignment.centerRight,
                                padding: const EdgeInsets.only(right: 20),
                                child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                        Text("삭제", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                        SizedBox(width: 10),
                                        Icon(Icons.delete, color: Colors.white),
                                    ],
                                ),
                            ),
                            confirmDismiss: (direction) async {
                                if (direction == DismissDirection.startToEnd) {
                                    // 오른쪽으로 밀기 (통계 제외)
                                    await _toggleExclusion(item);
                                    return false; 
                                } else {
                                    // 왼쪽으로 밀기 (삭제)
                                    if (!isMyItem) {
                                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('타인의 내역은 삭제할 수 없습니다.')));
                                        return false;
                                    }
                                    return await showDialog(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                            title: const Text("삭제하시겠습니까?"),
                                            content: Text("'${item['title']}' 내역을 삭제합니다."),
                                            actions: [
                                                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("취소")),
                                                ElevatedButton(
                                                    onPressed: () { 
                                                        _deleteItem(item['id'], item['created_by']);
                                                        Navigator.pop(context, true); 
                                                    },
                                                    style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                                    child: const Text("삭제"),
                                                ),
                                            ],
                                        ),
                                    );
                                }
                            },
                            child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CircleAvatar(
                                    backgroundColor: isExcluded ? Colors.grey.shade100 : (isFixed ? Colors.red.shade100 : Colors.grey.shade200),
                                    child: Icon(
                                        isExcluded ? Icons.credit_card_off : (isFixed ? Icons.home_work : Icons.shopping_cart), 
                                        color: isExcluded ? Colors.grey : (isFixed ? Colors.red : Colors.black54)
                                    ),
                                ),
                                title: Text(
                                    item['title'], 
                                    style: TextStyle(
                                        fontSize: 20, 
                                        fontWeight: FontWeight.bold,
                                        decoration: isExcluded ? TextDecoration.lineThrough : null,
                                        color: isExcluded ? Colors.grey : Colors.black
                                    )
                                ),
                                subtitle: Text(
                                    isExcluded ? "통계 제외됨" : "${item['category']} · ${DateFormat('MM.dd').format(date)} · $nickname", 
                                    style: const TextStyle(fontSize: 14, color: Colors.grey)
                                ),
                                trailing: Text(
                                    "${formatter.format(item['amount'])}원", 
                                    style: TextStyle(
                                        fontSize: 20, 
                                        fontWeight: FontWeight.bold,
                                        color: isExcluded ? Colors.grey.shade400 : Colors.black
                                    )
                                ),
                                onLongPress: () => _showEditDeleteMenu(item),
                            ),
                        );
                    },
                );
            },
        );
    }

    void _showEditDeleteMenu(Map<String, dynamic> item) {
        if (item['created_by'].toString() != widget.userData['id'].toString()) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본인이 작성한 내역만 수정/삭제할 수 있습니다.')));
            return;
        }

        showModalBottomSheet(
            context: context,
            backgroundColor: Colors.white,
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (context) {
                return SafeArea(
                    child: Wrap(
                        children: [
                            ListTile(
                                leading: const Icon(Icons.edit, color: Colors.blue),
                                title: const Text('수정하기'),
                                onTap: () {
                                    Navigator.pop(context);
                                    _showAddDialog(item: item);
                                },
                            ),
                            ListTile(
                                leading: const Icon(Icons.delete, color: Colors.red),
                                title: const Text('삭제하기', style: TextStyle(color: Colors.red)),
                                onTap: () {
                                    Navigator.pop(context);
                                    _deleteItem(item['id'], item['created_by']);
                                },
                            ),
                        ],
                    ),
                );
            },
        );
    }

    void _showNewCategoryDialog(StateSetter setDialogState) {
        final newCatCtrl = TextEditingController();
        showDialog(
            context: context,
            builder: (context) => AlertDialog(
                title: const Text("새 카테고리 추가"),
                content: TextField(
                    controller: newCatCtrl,
                    decoration: const InputDecoration(hintText: "예: 병원비, 육아"),
                    autofocus: true,
                ),
                actions: [
                    TextButton(onPressed: () => Navigator.pop(context), child: const Text("취소")),
                    ElevatedButton(
                        onPressed: () {
                            if (newCatCtrl.text.isNotEmpty) {
                                _addNewCategory(newCatCtrl.text);
                                setDialogState(() {});
                                Navigator.pop(context);
                            }
                        },
                        child: const Text("추가"),
                    )
                ],
            ),
        );
    }

    void _showAddDialog({Map<String, dynamic>? item}) {
        if (item != null) {
            _titleCtrl.text = item['title'];
            _amountCtrl.text = NumberFormat('#,###').format(item['amount']);
            _selectedCategory = item['category'];
            _selectedDate = DateTime.parse(item['transaction_date']);
            _isExcluded = item['is_excluded'] ?? false; 
        } else {
            _amountCtrl.clear();
            _titleCtrl.clear();
            _selectedCategory = '식비';
            _selectedDate = DateTime.now();
            _isExcluded = false; 
        }

        final bool isEditMode = item != null;

        showDialog(
            context: context,
            barrierDismissible: false,
            builder: (context) => StatefulBuilder(
                builder: (context, setDialogState) {
                    return Dialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        child: SingleChildScrollView(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                    Text(
                                        isEditMode ? "✏️ 내역 수정" : "💸 지출 입력", 
                                        textAlign: TextAlign.center, 
                                        style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)
                                    ),
                                    const SizedBox(height: 20),
                                    
                                    // [NEW] 문자/카톡 붙여넣기 버튼
                                    if (!isEditMode) // 새 입력일 때만 표시
                                        Container(
                                            margin: const EdgeInsets.only(bottom: 20),
                                            child: ElevatedButton.icon(
                                                onPressed: () => _parseFromClipboard(setDialogState),
                                                icon: const Icon(Icons.paste, color: Colors.white),
                                                label: const Text("문자/카톡 붙여넣기", style: TextStyle(fontSize: 16)),
                                                style: ElevatedButton.styleFrom(
                                                    backgroundColor: Colors.green,
                                                    foregroundColor: Colors.white,
                                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))
                                                ),
                                            ),
                                        ),

                                    InkWell(
                                        onTap: () async {
                                            final d = await showDatePicker(
                                                context: context, 
                                                initialDate: _selectedDate, 
                                                firstDate: DateTime(2020), 
                                                lastDate: DateTime(2030)
                                            );
                                            if (d != null) setDialogState(() => _selectedDate = d);
                                        },
                                        child: Container(
                                            padding: const EdgeInsets.all(15),
                                            decoration: BoxDecoration(border: Border.all(color: Colors.grey), borderRadius: BorderRadius.circular(10)),
                                            child: Text(DateFormat('yyyy년 MM월 dd일').format(_selectedDate), textAlign: TextAlign.center, style: const TextStyle(fontSize: 18)),
                                        ),
                                    ),
                                    const SizedBox(height: 15),
                                    
                                    Wrap(
                                        spacing: 8,
                                        children: [
                                            ..._categories.map((cat) {
                                                final isSelected = _selectedCategory == cat;
                                                return ChoiceChip(
                                                    label: Text(cat, style: TextStyle(fontSize: 16, color: isSelected ? Colors.white : Colors.black)),
                                                    selected: isSelected,
                                                    selectedColor: Colors.orange,
                                                    onSelected: (val) => setDialogState(() => _selectedCategory = cat),
                                                );
                                            }),
                                            ActionChip(
                                                label: const Text("+ 추가", style: TextStyle(color: Colors.blue)),
                                                onPressed: () => _showNewCategoryDialog(setDialogState),
                                                backgroundColor: Colors.blue.shade50,
                                            )
                                        ],
                                    ),
                                    
                                    const SizedBox(height: 15),
                                    TextField(controller: _titleCtrl, style: const TextStyle(fontSize: 20), decoration: const InputDecoration(labelText: '내역 (예: 점심)', border: OutlineInputBorder())),
                                    const SizedBox(height: 15),
                                    TextField(controller: _amountCtrl, keyboardType: TextInputType.number, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold), decoration: const InputDecoration(labelText: '금액', suffixText: '원', border: OutlineInputBorder())),
                                    
                                    const SizedBox(height: 10),
                                    Container(
                                        decoration: BoxDecoration(
                                            color: _isExcluded ? Colors.grey.shade200 : Colors.white,
                                            border: Border.all(color: _isExcluded ? Colors.grey : Colors.grey.shade300),
                                            borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: CheckboxListTile(
                                            value: _isExcluded,
                                            onChanged: (val) {
                                                setDialogState(() {
                                                    _isExcluded = val!;
                                                });
                                            },
                                            title: const Text("카드 대금 납부 (지출 합계 제외)", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                                            subtitle: const Text("체크하면 월 지출액에 포함되지 않습니다.", style: TextStyle(fontSize: 12, color: Colors.grey)),
                                            activeColor: Colors.grey,
                                            secondary: const Icon(Icons.credit_card_off),
                                        ),
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
                                                        onPressed: () => _saveLedger(context, item?['id']),
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
                    );
                },
            ),
        );
    }

    Future<void> _saveLedger(BuildContext dialogContext, int? id) async {
        if (_amountCtrl.text.isEmpty || _titleCtrl.text.isEmpty) return;
        try {
            final data = {
                'family_id': widget.userData['family_id'],
                'created_by': widget.userData['id'],
                'title': _titleCtrl.text,
                'amount': int.parse(_amountCtrl.text.replaceAll(',', '')),
                'category': _selectedCategory,
                'transaction_date': _selectedDate.toIso8601String(),
                'is_excluded': _isExcluded,
            };

            if (id == null) {
                await Supabase.instance.client.from('ledger').insert(data);
            } else {
                await Supabase.instance.client.from('ledger').update(data).eq('id', id);
            }

            if(mounted) {
                Navigator.pop(dialogContext);
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(id == null ? '저장되었습니다.' : '수정되었습니다.')));
            }
        } catch (e) {
            if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('저장 실패')));
        }
    }

    Future<void> _deleteItem(int id, int createdBy) async {
        if (createdBy.toString() != widget.userData['id'].toString()) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('본인이 작성한 내역만 삭제할 수 있습니다.')));
            return;
        }
        try {
            await Supabase.instance.client.from('ledger').delete().eq('id', id);
            if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('삭제되었습니다.')));
        } catch (e) {
            debugPrint("삭제 에러: $e");
        }
    }
}
