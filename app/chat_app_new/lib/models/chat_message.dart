// lib/models/chat_message.dart

class ChatMessage {
  final String type;
  final String? user;
  final String? text;
  final List<String>? users;
  final DateTime timestamp;

  ChatMessage({
    required this.type,
    this.user,
    this.text,
    this.users,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      type: json['type'] ?? '',
      user: json['user'],
      text: json['text'],
      users: json['users'] != null
          ? List<String>.from(json['users'])
          : null,
    );
  }

  Map<String, dynamic> toJson() {
    final map = <String, dynamic>{'type': type};
    if (user != null) map['user'] = user;
    if (text != null) map['text'] = text;
    if (users != null) map['users'] = users;
    return map;
  }
}
