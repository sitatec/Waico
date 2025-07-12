import 'dart:io';

import 'package:flutter_mailer/flutter_mailer.dart';
import 'package:flutter_phone_direct_caller/flutter_phone_direct_caller.dart';

class CommunicationService {
  static Future<bool?> makePhoneCall(String phoneNumber) {
    return FlutterPhoneDirectCaller.callNumber(phoneNumber);
  }

  static Future<EmailResponseStatus> sendEmail({
    required String body,
    required String subject,
    required List<String> recipients,
    List<File> attachments = const [],
  }) async {
    final response = await FlutterMailer.send(
      MailOptions(
        body: body,
        subject: subject,
        recipients: recipients,
        attachments: attachments.map((file) => file.path).toList(),
      ),
    );

    return switch (response) {
      MailerResponse.saved => EmailResponseStatus.savedAsDraft,
      MailerResponse.sent => EmailResponseStatus.sent,
      MailerResponse.cancelled => EmailResponseStatus.cancelled,
      MailerResponse.android => EmailResponseStatus.intentSent,
      MailerResponse.unknown => EmailResponseStatus.unknown,
    };
  }
}

enum EmailResponseStatus {
  sent,
  savedAsDraft,
  cancelled,
  intentSent,
  unknown;

  String get message => switch (this) {
    EmailResponseStatus.sent => 'Email sent successfully',
    EmailResponseStatus.savedAsDraft => 'Email Saved as Draft',
    EmailResponseStatus.cancelled => 'Email canceled',
    EmailResponseStatus.intentSent => 'Email app opened with content',
    EmailResponseStatus.unknown => 'Unknown Status',
  };
}
