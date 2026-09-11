import 'package:qcc_flutter/views/setting/AppTranslator.dart';

import '../qccwallet/QccWallet.dart';

class QccObj{
  static AppTranslationManager translationManager= AppTranslationManager.instance;

  // 在 WalletInitPage 状态类中
  static List<QccWallet> _wallets = []; // 存储所有已生成的钱包
  static QccWallet? activeWallet;    // 当前正在选中的钱包

  static List<QccWallet> readWallets(){
    final visibleWallets = _wallets.where((w) => w.isVisible).toList();
    return visibleWallets;
  }

  static void insertWallet(QccWallet qcc){
    _wallets.add(qcc);
  }
  static void removeWallet(QccWallet qcc){
    _wallets.remove(qcc);
  }
  static QccWallet getWalletIndex(int index){
    return _wallets[index];
  }
  static void setWallets(List<QccWallet> arr){
    _wallets.clear();
    _wallets.addAll(arr);
  }
}