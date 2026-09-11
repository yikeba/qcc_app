
import 'dart:developer' as LogObj;
import 'package:qcc_flutter/home/QccExplorerService.dart';

import '../utile/JsonUtil.dart';
import 'QccClinet.dart';

class QccApiBuild{
  static String baseUrl='${QccExplorerService.baseUrl}/v1/ctx';
  static String indexUrl = QccExplorerService.baseUrl;
  static final client = QccTxClient(baseUrl: baseUrl);

  static Future<String> getqccTransactionData(String from,String to,int amount,String assetId) async {
    // ── default. 普通转账 ────────────────────────────────────────
    TxResponse recok= await client.submit(QccTxRequest(
      action: QccAction.simplePay,
      from: from,
      to: to,
      amount: amount,
      assetId: assetId,
    ));
    if(recok.data!=null) {
      Map tx=recok.data!;
      tx.putIfAbsent("fromdev", ()=> "");
      tx.putIfAbsent("memo", ()=> "");
      return JsonUtil.maptostr(recok.data!);
    }
    return "";
  }

  static creatTX_open(String from,int amount,String assetId,int matc,MatchType type
      ) async {
    TxResponse recok= await client.submit(QccTxRequest(
      action: QccAction.openTx,
      from: from,
      to: "Q5555...",
      amount: amount,
      assetId: assetId,
      matchLogic: MatchLogic(
        rule: type,   // random / fixed / dex
        maxParticipants: matc,       // 总份数
        rate: 1.0,                // 汇率（dex 时有意义）
      ),
    ));
    if(recok.data!=null) {
      return JsonUtil.maptostr(recok.data!);
    }
    return "";
  }

  static Future<String> creatTX_win(String from,String assetId,String hash) async {
    TxResponse recok=  await client.submit(QccTxRequest(
      action: QccAction.winTx,
      from: from,
      assetId: assetId,
      hash: hash
    ));
    if(recok.data!=null) {
      return JsonUtil.maptostr(recok.data!);
    }
    return "";
  }

  static creatMuaddress(String from,List<String> owners,int nums) async {
    // ── 1. 创建多签账户地址 ──────────────────────────────────────────
    final msignRes = await client.submit(QccTxRequest(
      action: QccAction.createMsign,
      from: from,
      owners: owners,
      threshold: nums,
    ));
    LogObj.log('创建多签第一步提案返回$msignRes');
  }

  static creatMuappend(String from,String hash) async {
    // ── 2. 创建多签账户--跟随签名 ──────────────────────────────────────────
    await client.submit(QccTxRequest(
      action: QccAction.appendMsign,
      from: from,
      hash: hash,
    ));
  }

  static creatMuaPay(String from,String muilt,String to,int amount,String assetId) async {
    // ── 3. 创建多签账户--转账/支付 ──────────────────────────────────────────
    final mutxRes = await client.submit(QccTxRequest(
      action: QccAction.buildMutx,
      from: from,
      fromMulti: muilt,
      to: to,
      amount: amount,
      assetId: assetId,
    ));
  }

  static creatMuaPayappend(String from,String muilt,String to,int amount,String assetId,String hash) async {
    // ── 4. 创建多签账户--转账/支付--跟随签名 ──────────────────────────────────────────
    await client.submit(QccTxRequest(
      action: QccAction.appendMutx,
      from: from,
      fromMulti: muilt,
      to: to,
      amount: amount,
      assetId: assetId,
      hash: hash,
    ));
  }


  static creatMuaAsset(
      String from, String muilt, String assetId,
      String type, int precision, bool mintable,bool freezable,
      int initialSupply
      ) async {
    // ── 5. 创建多签账户--资产发布 ──────────────────────────────────────────
    final muAssetRes = await client.submit(QccTxRequest(
      action: QccAction.issueAssetMu,
      from: from,
      fromMulti: muilt,
      assetId: assetId,
      type: type,   //'COIN',
      precision: precision,
      mintable: mintable,
      freezable: freezable,
      initialSupply: initialSupply,
    ));
  }

  static creatMuaAssetAppend(
      String from, String hash
      ) async {
    // ── 5. 创建多签账户--资产发布 追随签名 ──────────────────────────────────────────
    await client.submit(QccTxRequest(
      action: QccAction.appendAssetMu,
      from: from,
      hash: hash
    ));
  }


}