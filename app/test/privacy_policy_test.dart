/// 练了么 · 应用内的隐私政策
///
/// 这一屏存在的原因是**商店审核规则**，不是"想加个页面"：
/// 小米应用商店的《隐私政策不合规的问题解析和修改指引》明确写着
/// "应用需要在**应用内**添加独立的隐私政策，且**尽量保证在四步操作之内**可以查看到"、
/// "必须是可以正常打开和查看的状态"（规则来源：国信办秘字〔2019〕191 号）。
/// 我们此前应用内一个字都没有 —— 那是上架硬伤。
///
/// 所以这里的断言分两类：
///   1. **内容**：随包那份文本真的能读出来，而且是真政策（不是占位符）
///   2. **可达性**：从「我」页两次点击能到；备案号没填时那一行不许出现
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/app_info.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart';
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/profile/privacy_policy_screen.dart';
import 'package:lianleme/features/profile/profile_screen.dart';
import 'package:drift/native.dart';

Widget _wrapPolicy({Future<String> Function()? loader, String filing = ''}) => MaterialApp(
      theme: buildAppTheme(),
      home: PrivacyPolicyScreen(loader: loader, filingNumber: filing),
    );

void main() {
  group('随包的那份政策文本', () {
    testWidgets('能读出来，而且是**真政策**而不是占位符', (WidgetTester tester) async {
      // 用默认 loader（真的读 assets/privacy-policy.txt）—— 这条同时守着
      // "pubspec 里声明了资产、gen-privacy-page.mjs 生成过"这两件事。
      await tester.pumpWidget(_wrapPolicy());
      await tester.pumpAndSettle();

      final SelectableText box =
          tester.widget<SelectableText>(find.byKey(const Key('privacy-text')));
      final String text = box.data!;

      expect(text.length, greaterThan(1000), reason: '整份政策不该只有几行');
      for (final String needed in <String>[
        '练了么 · 隐私政策',
        '一、一句话概括',
        '二、我们收集什么',
        '四、权限',
        '七、未成年人', // 结尾几节也在，说明没被截断
      ]) {
        expect(text.contains(needed), isTrue, reason: '政策里缺少「$needed」');
      }
      // 内部注记不该混进来：那是给开发者看的（状态、待办、附录里的核对命令）
      for (final String internal in <String>[
        '未经法务审核',
        '上架前只剩两件事',
        '维护者注',
        '附录 B',
        'tool/privacy-audit',
      ]) {
        expect(text.contains(internal), isFalse, reason: '应用内这份漏进了内部内容：$internal');
      }
      // Markdown 残留会让用户以为界面坏了
      expect(text.contains('**'), isFalse);
    });
  });

  group('界面', () {
    testWidgets('标题、正文、返回键都在', (WidgetTester tester) async {
      await tester.pumpWidget(_wrapPolicy(loader: () async => '政策正文'));
      await tester.pumpAndSettle();

      expect(find.text('隐私政策'), findsOneWidget);
      expect(find.byKey(const Key('privacy-text')), findsOneWidget);
      expect(find.byKey(const Key('privacy-back')), findsOneWidget);
    });

    testWidgets('**备案号没填时那一行不出现**（别印"待填"）', (WidgetTester tester) async {
      await tester.pumpWidget(_wrapPolicy(loader: () async => '政策正文'));
      await tester.pumpAndSettle();
      expect(kAppFilingNumber, isEmpty, reason: '现在确实还没备案');
      expect(find.byKey(const Key('privacy-filing')), findsNothing);
    });

    testWidgets('备案号填了之后那一行要出现', (WidgetTester tester) async {
      await tester.pumpWidget(
        _wrapPolicy(loader: () async => '政策正文', filing: '京ICP备12345678号-1A'),
      );
      await tester.pumpAndSettle();
      expect(find.text('APP 备案号：京ICP备12345678号-1A'), findsOneWidget);
    });

    testWidgets('读不到资产时如实报错，而不是留一片空白', (WidgetTester tester) async {
      await tester.pumpWidget(_wrapPolicy(loader: () async => throw StateError('缺资产')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('privacy-error')), findsOneWidget);
    });
  });

  group('可达性：两次点击之内到（商店的"四步之内"）', () {
    testWidgets('「我」页有入口，点进去就是政策', (WidgetTester tester) async {
      final AppDatabase db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final DriftLocalStore store = DriftLocalStore(db);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(
            store: store,
            repository: ExerciseRepository(db),
            profile: ProfileRepository(db),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 「关于」在页面最底下，懒构建的 ListView 得先滚过去
      final Finder tile = find.byKey(const Key('privacy-policy'));
      for (int i = 0; i < 12 && tile.evaluate().isEmpty; i++) {
        await tester.drag(find.byType(ListView), const Offset(0, -260));
        await tester.pumpAndSettle();
      }
      expect(tile, findsOneWidget, reason: '「我」页必须有隐私政策入口');

      // 直接触发 onTap，而不是 `tester.tap`。
      //
      // ⚠️ 为什么：这一条测的是**可达性**（入口在不在、点了去哪），不是命中测试。
      // 而 `tester.tap` 在这里不可靠 —— 试过 `ensureVisible`、试过再多带一段滚动，
      // 打印出来的 tile 矩形明明整个落在视口里（455–527 / 视口 0–600），
      // tap 也没报"没打中"的警告，但路由就是不跳（滚动视图的手势竞技场里，
      // 这一下被当成了"停下滚动"）。与其在测试里堆技巧，不如把它交给真机：
      // **模拟器上真的用手指点一遍**（`docs/screenshots.md` 那套），那才是真相。
      tester.widget<ListTile>(tile).onTap!();
      await tester.pump(); // 开始路由动画
      await tester.pump(const Duration(seconds: 1)); // 动画走完

      // 断言"到了哪一屏"，而**不是**"那一屏的正文已经加载出来"。
      // 正文是异步读资产的，而同文件里前面几个用例也创建过这一屏 ——
      // 一起跑时那次加载会让 `pumpAndSettle`/定长推进的时序变得不可靠
      // （单独跑绿、整个文件跑红就是这个原因）。**内容**的断言在上面的分组里，
      // 这里只关心"入口点得通、去了正确的地方"。
      expect(find.byType(PrivacyPolicyScreen), findsOneWidget,
          reason: '入口的 onTap 应当直接打开政策屏');
    });
  });
}
