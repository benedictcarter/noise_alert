import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/profile.dart';
import '../../providers.dart';
import 'my_details_form.dart';
import 'settings_widgets.dart';

class MyDetailsScreen extends ConsumerWidget {
  const MyDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ComplainantProfile profile = ref.watch(profileProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('My details')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 40),
        children: <Widget>[
          const Explainer(
            'These go at the bottom of your complaint, so the airport knows '
            'who is writing and where from. They are kept on this phone. '
            'Nothing is uploaded and nobody else can see them.',
          ),
          const MyDetailsForm(),
          if (!profile.isComplete)
            const Padding(
              padding: EdgeInsets.only(top: 20),
              child: Explainer(
                'Please fill in your name and postcode. A complaint needs '
                'them.',
                warning: true,
              ),
            ),
        ],
      ),
    );
  }
}
