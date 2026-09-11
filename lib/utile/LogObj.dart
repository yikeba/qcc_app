import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';

class LogObj{

  static log(String debug){
    if (kDebugMode || kProfileMode) {
      developer.log("QCC DEBUG_:$debug");
    }
  }

}