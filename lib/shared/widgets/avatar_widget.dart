import 'package:flutter/material.dart';

class AvatarWidget extends StatelessWidget {
  const AvatarWidget({
    super.key,
    this.name,
    this.radius = 20,
  });

  final String? name;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final initial = name != null && name!.isNotEmpty
        ? name!.substring(0, 1).toUpperCase()
        : '?';

    return CircleAvatar(
      radius: radius,
      child: Text(initial),
    );
  }
}
