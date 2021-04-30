/// A notification
class Notification {
  // ignore: public_member_api_docs
  Notification({
    required this.id,
    required this.app,
    required this.user,
    required this.datetime,
    required this.objectType,
    required this.objectId,
    required this.subject,
    required this.subjectRich,
    required this.subjectRichParameters,
    required this.message,
    required this.messageRich,
    required this.messageRichParameters,
    required this.link,
    required this.icon,
    required this.actions,
  });

  // ignore: public_member_api_docs
  factory Notification.fromJson(Map<String, dynamic> json) => Notification(
        id: json['notification_id'] as int,
        app: json['app'] as String,
        user: json['user'] as String,
        datetime: DateTime.parse(json['datetime'] as String).toLocal(),
        objectType: json['object_type'] as String,
        objectId: json['object_id'] as String,
        subject: json['subject'] as String,
        subjectRich: json['subjectRich'] as String,
        subjectRichParameters:
            json['subjectRichParameters'] as Map<String, Map<String, dynamic>>,
        message: json['message'] as String,
        messageRich: json['messageRich'] as String,
        messageRichParameters: json['messageRichParameters'] as List<dynamic>,
        link: json['link'] as String,
        icon: json['icon'] as String,
        actions: (json['actions'] as List)
            .map<NotificationAction>(
              (a) => NotificationAction.fromJson(a as Map<String, dynamic>),
            )
            .toList(),
      );

  /// ID if the notification
  final int id;

  /// Name of the app
  final String app;

  /// ID of the user this notifications is for
  final String user;

  /// Date time of when the notification was published
  final DateTime datetime;

  /// Type of the object the notification is about
  final String objectType;

  /// ID of the object the notification is about
  final String objectId;

  /// Short subject that should be presented to the user
  final String subject;

  /// Subject with placeholders
  final String subjectRich;

  /// Subject parameters for [subjectRich]
  final Map<String, Map<String, dynamic>> subjectRichParameters;

  /// Long message that should be presented to the user
  final String message;

  /// Message with placeholders
  final String messageRich;

  /// Message parameters for [subjectRich]
  final List<dynamic> messageRichParameters;

  /// Link that should be followed when clicking on the notification
  final String link;

  /// Icon to display next to the notification
  final String icon;

  /// List of possible actions
  final List<NotificationAction> actions;
}

/// Actions to display as response to the notification
class NotificationAction {
  // ignore: public_member_api_docs
  NotificationAction({
    required this.label,
    required this.link,
    required this.type,
    required this.primary,
  });

  // ignore: public_member_api_docs
  factory NotificationAction.fromJson(Map<String, dynamic> json) =>
      NotificationAction(
        label: json['label'] as String,
        link: json['link'] as String,
        type: json['type'] as String,
        primary: json['primary'] as bool,
      );

  /// Label of the button that should be presented
  final String label;

  /// Link that should be followed when clicking on the button
  final String link;

  /// HTTP method to request against the link
  final String type;

  /// Whether the action is the primary action for the notification
  final bool primary;
}
