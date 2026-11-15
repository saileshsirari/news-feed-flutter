import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'package:feature_communities/events/event_screen.dart';
import 'package:feature_communities/payments/payment_order.dart';
import 'package:feature_communities/payments/payments_api.dart';

/// Everything you've paid for (or tried to): paid, refunded, on its way back.
class MyTicketsScreen extends ConsumerWidget {
  const MyTicketsScreen({super.key});

  static Future<void> open(BuildContext context) =>
      Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MyTicketsScreen()));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final orders = ref.watch(myOrdersProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your tickets')),
      body: switch (orders) {
        AsyncData(:final value) when value.where((o) => o.status != OrderStatus.expired).isEmpty => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text('No tickets yet. Paid events show a Buy ticket button.', textAlign: TextAlign.center),
            ),
          ),
        AsyncData(:final value) => RefreshIndicator(
            onRefresh: () => ref.refresh(myOrdersProvider.future),
            child: ListView(
              children: [
                // Orders never paid (closed, or not paid in time) aren't tickets: left out.
                for (final o in value.where((o) => o.status != OrderStatus.expired)) _OrderTile(o),
              ],
            ),
          ),
        AsyncError() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Couldn\'t load your tickets.'),
                TextButton(onPressed: () => ref.invalidate(myOrdersProvider), child: const Text('Try again')),
              ],
            ),
          ),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _OrderTile extends StatelessWidget {
  const _OrderTile(this.order);
  final PaymentOrder order;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final o = order;
    final colour = switch (o.status) {
      OrderStatus.paid => colors.primary,
      OrderStatus.refunding || OrderStatus.refunded => colors.tertiary,
      OrderStatus.failed => colors.error,
      _ => colors.outline,
    };
    final when = DateFormat('d MMM yyyy').format((o.paidAt ?? o.createdAt).toLocal());
    return ListTile(
      leading: Icon(o.status == OrderStatus.paid ? Icons.confirmation_number : Icons.receipt_long_outlined, color: colour),
      title: Text(o.description.replaceFirst('Ticket: ', ''), maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(
        [
          '${o.price} · $when',
          if (o.status != OrderStatus.paid && o.note != null) o.note!,
        ].join('\n'),
      ),
      isThreeLine: o.status != OrderStatus.paid && o.note != null,
      trailing: Text(o.statusLabel, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colour)),
      onTap: o.isTicket ? () => EventScreen.open(context, o.itemId) : null,
    );
  }
}
