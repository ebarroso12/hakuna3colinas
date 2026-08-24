import 'package:flutter/material.dart';

import '../models/app_notification.dart';
import '../models/top.dart';
import '../services/supabase_service.dart';
import '../widgets/app_logo.dart';

/// Central de notificações in-app (Realtime — funciona com o app aberto).
/// Push de verdade (app fechado) fica pra quando o Firebase Cloud
/// Messaging for configurado — ver nota em SupabaseService.
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key, required this.top});

  final Top top;

  IconData _iconFor(String type) {
    switch (type) {
      case 'urgencia':
        return Icons.priority_high;
      case 'apoio':
        return Icons.group_add;
      case 'atendimento':
        return Icons.medical_services;
      default:
        return Icons.notifications;
    }
  }

  @override
  Widget build(BuildContext context) {
    final myId = SupabaseService.instance.currentUser?.id;
    return Scaffold(
      appBar: AppBar(
        leading: const AppLogoAppBarLeading(),
        title: const Text('Notificações'),
      ),
      body: StreamBuilder<List<AppNotification>>(
        stream: SupabaseService.instance.watchMyNotifications(top.id),
        builder: (context, snapshot) {
          final notifications = snapshot.data ?? const [];
          if (notifications.isEmpty) {
            return const Center(child: Text('Nenhuma notificação ainda.'));
          }
          return ListView.builder(
            itemCount: notifications.length,
            itemBuilder: (context, index) {
              final n = notifications[index];
              final isDirectUnread = n.recipientId == myId && n.isUnread;
              return ListTile(
                leading: Icon(_iconFor(n.type)),
                title: Text(
                  n.title,
                  style: TextStyle(
                    fontWeight: isDirectUnread ? FontWeight.bold : null,
                  ),
                ),
                subtitle: Text(
                  '${n.body ?? ''}\n${n.createdAt.toLocal()}'.trim(),
                ),
                isThreeLine: n.body != null,
                onTap: isDirectUnread
                    ? () => SupabaseService.instance.markNotificationRead(n.id)
                    : null,
              );
            },
          );
        },
      ),
    );
  }
}
