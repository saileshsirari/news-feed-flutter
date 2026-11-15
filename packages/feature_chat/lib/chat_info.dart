import 'package:app_core/app_core.dart';
import 'package:flutter/material.dart';

/// Chat's tile, readable before its code loads (see MiniAppInfo).
const chatInfo = MiniAppInfo(
  id: 'chat',
  name: 'Chat',
  icon: Icons.chat_bubble,
  color: Color(0xFF00897B),
  // Messages and calls reach you whichever mini-app you're in.
  isGlobal: true,
);
