// lib/models/chat_message.dart

class ChatMessage {
  final int? id;
  final String type;
  final String? user;
  final String? text;
  final String? roomID;
  final List<String>? users;
  final DateTime timestamp;

  ChatMessage({
    this.id,
    required this.type,
    this.user,
    this.text,
    this.roomID,
    this.users,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'],
      type: json['type'] ?? '',
      user: json['user'],
      text: json['text'],
      roomID: json['room_id'],
      users: json['users'] != null ? List<String>.from(json['users']) : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type};
    if (id != null) map['id'] = id;
    if (user != null) map['user'] = user;
    if (text != null) map['text'] = text;
    if (roomID != null) map['room_id'] = roomID;
    if (users != null) map['users'] = users;
    return map;
  }
}
