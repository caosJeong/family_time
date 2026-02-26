// lib/models.dart
class ScheduleItem {
    final int? id;
    final int familyId;
    final int createdBy;
    final String title;
    final DateTime startDate;
    final DateTime endDate;
    final bool isPrivate;
    final String repeatOption;
    final String? description;
    final String? linkUrl;

    ScheduleItem({
        this.id,
        required this.familyId,
        required this.createdBy,
        required this.title,
        required this.startDate,
        required this.endDate,
        required this.isPrivate,
        required this.repeatOption,
        this.description,
        this.linkUrl,
    });

    factory ScheduleItem.fromMap(Map<String, dynamic> map) {
        return ScheduleItem(
            id: map['id'],
            familyId: map['family_id'] ?? 0,
            createdBy: map['created_by'] ?? 0,
            title: map['title'] ?? '',
            startDate: DateTime.parse(map['start_date']),
            endDate: map['end_date'] != null ? DateTime.parse(map['end_date']) : DateTime.parse(map['start_date']),
            isPrivate: map['is_private'] ?? false,
            repeatOption: map['repeat_option'] ?? 'none',
            description: map['description'],
            linkUrl: map['link_url'],
        );
    }

    Map<String, dynamic> toMap() {
        return {
            'family_id': familyId,
            'created_by': createdBy,
            'title': title,
            'start_date': startDate.toIso8601String(),
            'end_date': endDate.toIso8601String(),
            'is_private': isPrivate,
            'repeat_option': repeatOption,
            'description': description,
            'link_url': linkUrl,
        };
    }
}

class TodoItem {
    final int? id;
    final int familyId;
    final int createdBy;
    final String content;
    final DateTime targetDate;
    final DateTime dueDate;
    final int? scheduleId;
    final int? assigneeId;
    final bool isPrivate;
    final String repeatOption;
    final String? description;
    final String? linkUrl;
    final bool isUndecided; // [추가됨] 기간 미정 여부

    TodoItem({
        this.id,
        required this.familyId,
        required this.createdBy,
        required this.content,
        required this.targetDate,
        required this.dueDate,
        this.scheduleId,
        this.assigneeId,
        required this.isPrivate,
        required this.repeatOption,
        this.description,
        this.linkUrl,
        this.isUndecided = false,
    });

    factory TodoItem.fromMap(Map<String, dynamic> map) {
        return TodoItem(
            id: map['id'],
            familyId: map['family_id'] ?? 0,
            createdBy: map['created_by'] ?? 0,
            content: map['content'] ?? '',
            targetDate: map['target_date'] != null ? DateTime.parse(map['target_date']) : DateTime.now(),
            dueDate: map['due_date'] != null ? DateTime.parse(map['due_date']) : DateTime.now(),
            scheduleId: map['schedule_id'],
            assigneeId: map['assignee_id'],
            isPrivate: map['is_private'] ?? false,
            repeatOption: map['repeat_option'] ?? 'none',
            description: map['description'],
            linkUrl: map['link_url'],
            isUndecided: map['is_undecided'] ?? false, // DB에 is_undecided 컬럼 필수
        );
    }

    Map<String, dynamic> toMap() {
        return {
            'family_id': familyId,
            'created_by': createdBy,
            'content': content,
            'target_date': targetDate.toIso8601String(),
            'due_date': dueDate.toIso8601String(),
            'schedule_id': scheduleId,
            'assignee_id': assigneeId,
            'is_private': isPrivate,
            'repeat_option': repeatOption,
            'description': description,
            'link_url': linkUrl,
            'is_undecided': isUndecided,
        };
    }
}
