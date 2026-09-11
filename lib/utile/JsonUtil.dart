import 'dart:collection';
import 'dart:convert';
import 'dart:developer' as LogObj;
import 'dart:math';
import 'dart:typed_data';

class JsonUtil {
  //dart语言中，不区分 map/json  list/jsonarr;
  static MaptoJSONstr(Map<String, dynamic> map) {
    String jsonStringB = json.encode(map);
    LogObj.log(jsonStringB);
    return jsonStringB;
  }
  //随机数
  static Ramnums(int n){
    var rng = Random();
    var str= rng.nextInt(n);
    return str;
  }
  //随机字符串与字母
  static String ramstr(int n){
    String str="";
    for(int i=0;i<n;i++){
      int s=Ramnums(36);
      if(s<10){
        str=str+s.toString();
      }else{
        str=str+s.toRadixString(36);
      }
    }
    //print("随机数："+str.toString());
    return str;
  }

  //dart语言中，不区分 map/json  list/jsonarr;
  static MapStringtojsonstr(Map<String, String> map) {
    String jsonStringB = json.encode(map);
    LogObj.log("map to jsonstr:" + jsonStringB);
    return jsonStringB;
  }

  //dart语言中，不区分 map/json  list/jsonarr;
  static String maptostr(Map map) {
    String jsonStringB = json.encode(map);
    return jsonStringB;
  }

  static  strtoMap(String str) {
    Map<String, dynamic> map = HashMap();
    try {
      map = jsonDecode(str);
      return map;
    } catch (e) {
      return map;
    }
  }
  static Map<String, List<int>> strtoMapint(String str) {
    Map<String, List<int>> map = HashMap();
    try {
      Map<String, dynamic> decodedMap = jsonDecode(str);
      decodedMap.forEach((key, value) {
        if (value is List<dynamic>) {
          map[key] = List<int>.from(value);
        }
      });
      return map;
    } catch (e) {
      print("Error decoding JSON: $e");
      return map;
    }
  }

  static strtoHashmap(String str) {
    Map map = HashMap();
    try {
      map = json.decode(str);
      return map;
    } catch (e) {
      return map;
    }
  }

  static strtoMapString(String str) {
    Map<String, String> map = HashMap();
    try {
      map = json.decode(str);
      return map;
    } catch (e) {
      LogObj.log("mapstring err:" + str);
      return map;
    }
  }

  static strotList(String str) {
    List garr = [];
    try {
      garr = jsonDecode(str);
      return garr;
    } catch (e) {
      //print("strotlist err:"+str);
      return garr;
    }
  }

  static strotListstr(String str) {
    List<String> garr = [];
    try {
      garr = jsonDecode(str);
      return garr;
    } catch (e) {
      //print("strotlist err:"+str);
      return garr;
    }
  }

  static addlist(List a, List b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    List c = [];
    for (var value in b) {
      if(c.contains(value)) continue;
      c.add(value);
    }
    for (var value in a) {
      if(c.contains(value)) continue;
      c.add(value);
    }
    return c;
  }
  static List<DateTime> addlistDatetime(List<DateTime> a, List<DateTime> b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    List<DateTime> c = [];
    for (DateTime value in b) {
      if (isDatearr(value,c)) continue;
      c.add(value);
    }
    for (DateTime value in a) {
      if (isDatearr(value,c)) continue;
      c.add(value);
    }
    return c;
  }

  static List<DateTime> removeDatetime(DateTime a, List<DateTime> b) {
    List<DateTime> c = [];
    for (DateTime value in b) {
      if (a.isAtSameMomentAs(value)) continue;
      c.add(value);
    }
    return c;
  }


  //mydiaolist 数据合并使用
  static addmydialist(List a, Set b) {
    if (a.isEmpty) return b;
    if (b.isEmpty) return a;
    Set c = Set();
    for (var value in b) {
      c.add(value);
    }
    for (var value in a) {
      c.add(value);
    }
    return c;
  }

  static bool isintid(int v, List<int> list) {
    for (int id in list) {
      if (id == v) return true;
    }
    return false;
  }

  static bool isTextarr(String str, List<String> list) {
    for (String id in list) {
      if (str == id) return true;
    }
    return false;
  }

  static bool isDatearr(DateTime str, List<DateTime> list) {
    for (DateTime id in list) {
      if (str.isAtSameMomentAs(id)) return true;
    }
    return false;
  }

  static bool isDatemap(DateTime str, Map map) {
    bool ist=false;
    map.forEach((key, value) {
      if (str.isAtSameMomentAs(key)) ist=true;
    });
    return ist;
  }




  static bool iscontainsTextarr(String str, List list) {
    for (String id in list) {
      //if (id.contains(str)) return true;
      if (str.contains(id)) return true;
    }
    return false;
  }
  static bool isTextobjarr(String str, List list) {
    for (String id in list) {
      if (id==str) return true;
    }
    return false;
  }

  static bool isIntarr(int s, List<int> list) {
    for (int id in list) {
      if (id == s) return true;
    }
    return false;
  }

  static String listtostr(List list) {
    return jsonEncode(list);
  }

  //倒序list
  static List listdesc(List list){
    List desclist=[];
    for(var obj in list){
      desclist.insert(0, obj);
    }
    return desclist;
  }

  static mapfordynamictostring(Map map) {
    // 动态对象转字符串
    Map<String, String> smap = HashMap();
    map.forEach((key, value) {
      smap.putIfAbsent(key.toString(), () => value.toString());
    });
    return smap;
  }
  static int strtoint(String str) {
    try{
      return int.parse(str);
    }catch (e){
      return -1;
    }
  }
  static num strtodou(String str) {
    try{
      return double.parse(str);
    }catch (e){
      LogObj.log("str to double err $str");
      return -1;
    }
  }

  static Map<String, dynamic> mapfordynamic(Map map) {
    // 动态对象转字符串
    Map<String, dynamic> smap = HashMap();
    map.forEach((key, value) {
      smap.putIfAbsent(key.toString(), () => value.toString());
    });
    return smap;
  }

  static maptoFormstr(Map map) {
    String formstr = "";
    map.forEach((key, value) {
      if (formstr.isNotEmpty) formstr = formstr + "&";
      formstr =
          formstr + Uri.encodeComponent(key) + "=" + Uri.encodeComponent(value);
    });
    LogObj.log("map to form :" + formstr);
    return formstr;
  }


  static String formatNum(dynamic nums, {int postion = 2}) {
    var num;
    if (nums is double) {
      num = nums;
    } else {
      num = double.parse(nums.toString());
    }
    if ((num.toString().length - num.toString().lastIndexOf(".") - 1) < postion) {
      return (num.toStringAsFixed(postion)
          .substring(0, num.toString().lastIndexOf(".") + postion + 1)
          .toString());
    } else {
      return (num.toString()
          .substring(0, num.toString().lastIndexOf(".") + postion + 1)
          .toString());
    }
  }

  static int getmoneyint(String str) {
    //元单位字符串 转化为分单位整型
    num mdu = strtodou(str);
    mdu = mdu * 100;
    return mdu.toInt();
  }
  //倒序，
  static Map sortdescMap(Map map){
    List keys = map.keys.toList();
    // key排序
    keys.sort((a, b) {
      List<int> al = a.codeUnits;
      List<int> bl = b.codeUnits;
      for (int i = 0; i < al.length; i++) {
        if (bl.length <= i) return 1;
        if (al[i] < bl[i]) {
          return 1;
        } else if (al[i] < bl[i]) return -1;
      }
      return 0;
    });
    Map treeMap = {};
    for (var element in keys) {
      treeMap[element] = map[element];
    }
    return treeMap;
  }
  //正序
  static Map sortMap(Map map){
    List keys = map.keys.toList();
    // key排序
    keys.sort((a, b) {
      List<int> al = a.codeUnits;
      List<int> bl = b.codeUnits;
      for (int i = 0; i < al.length; i++) {
        if (bl.length <= i) return 1;
        if (al[i] > bl[i]) {
          return 1;
        } else if (al[i] < bl[i]) return -1;
      }
      return 0;
    });
    Map treeMap = {};
    for (var element in keys) {
      treeMap[element] = map[element];
    }
    return treeMap;
  }
  //正序
  static sortlist(List list,String key){
    list.sort((obj1, obj2) {
      return obj1[key].compareTo(obj2[key]);
      //return obj1.compareTo(obj2);
    });
    return list;
  }

  //倒序
  static sortmaxtominlist(List list,String key){
    list.sort((obj1, obj2) {
      return obj2[key].compareTo(obj1[key]);
    });
    return list;
  }

  //正序
  static sortlistdate(List list){
    list.sort((obj1, obj2) {
      return obj1.compareTo(obj2);
      //return obj1.compareTo(obj2);
    });
    return list;
  }

  static String getbase64trz(String jsonstr) {
    try {
      // 先清理无关字符
      String clean = jsonstr.trim();
      clean = clean.replaceAll("\n", "").replaceAll("\r", "").replaceAll(" ", "");

      // 修正长度（补足 =）
      int mod4 = clean.length % 4;
      if (mod4 > 0) {
        clean += '=' * (4 - mod4);
      }

      // 解码
      final bytes = base64Decode(clean);
      return utf8.decode(bytes);
    } catch (e) {
      //LogObj.log("还原base64错误: $e");
      return jsonstr;
    }
  }

  static getbase64(String jsonstr){
    try {
      List<int> bytes = base64Decode(jsonstr).toList();
      String gstr = utf8.decode(bytes);
      return gstr;
    }catch(e){
     // LogObj.log("还原base64错误$e");
      return jsonstr;
    }
  }
  static Uint8List? getbase64Uint8list(String? jsonstr){
    try {
      if(jsonstr==null) return null;
      List<int> bytes = base64Decode(jsonstr).toList();
      return Uint8List.fromList(bytes);
    }catch(e){
      return null;
    }
  }


  static String? setbase64Uint8list(Uint8List? bytes){
    try {
      List<int> stringBytes =bytes!.toList();
      String datastr = base64.encode(stringBytes);
      return datastr;
    }catch(e){
      return null;
    }
  }

  static setbase64(String jsonstr){
    try {
      List<int> stringBytes = utf8.encode(jsonstr);
      String datastr = base64.encode(stringBytes);
      return datastr;
    }catch(e){
      return jsonstr;
    }
  }

}
