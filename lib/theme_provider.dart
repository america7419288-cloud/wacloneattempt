import 'package:flutter/cupertino.dart';

/// Global dark mode state — AMOLED black everywhere.
final ValueNotifier<bool> darkModeNotifier = ValueNotifier<bool>(false);

const _kAmoledBlack = Color(0xFF000000);
const _kAmoledSurface = Color(0xFF0D0D0D);
const _kAmoledCard = Color(0xFF1C1C1E);
const _kFontFamily = 'SFProRounded';

CupertinoThemeData get lightTheme => const CupertinoThemeData(
      brightness: Brightness.light,
      primaryColor: CupertinoColors.systemBlue,
      scaffoldBackgroundColor: CupertinoColors.systemGroupedBackground,
      barBackgroundColor: CupertinoColors.systemBackground,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          inherit: false,
          fontFamily: _kFontFamily,
          color: CupertinoColors.black,
        ),
        navTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: _kFontFamily,
          color: CupertinoColors.black,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        navLargeTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: _kFontFamily,
          color: CupertinoColors.black,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
    );

CupertinoThemeData get darkTheme => const CupertinoThemeData(
      brightness: Brightness.dark,
      primaryColor: CupertinoColors.systemBlue,
      scaffoldBackgroundColor: _kAmoledBlack,
      barBackgroundColor: _kAmoledSurface,
      textTheme: CupertinoTextThemeData(
        textStyle: TextStyle(
          inherit: false,
          fontFamily: _kFontFamily, 
          color: CupertinoColors.white,
        ),
        navTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: _kFontFamily,
          color: CupertinoColors.white,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.4,
        ),
        navLargeTitleTextStyle: TextStyle(
          inherit: false,
          fontFamily: _kFontFamily,
          color: CupertinoColors.white,
          fontSize: 34,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.4,
        ),
      ),
    );
