/// 练了么 · 164 号文「双清单」这一屏
///
/// 四层都要守住：
///   1. **随包资产**真的读得到（证明 `pubspec.yaml` 里注册了它，没打成"漏资产"的包）；
///   2. 164 号文要的**两份清单都在**（收集清单 + 共享清单），关键结论句不缺席；
///   3. 它是**生成物** —— 不许漏出仓库内部记号（markdown 的 `**`、HTML 注释这类），
///      因为这份文本是给用户和审核员看的；
///   4. 从「我」页**点得到**（二级菜单：不能只是写了个页面、没人能进去）。
///
/// ⚠️ 读资产用 `tester.runAsync` 在**真实异步**里读，而不是靠 pump 等 FutureBuilder：
/// 第一版靠"pump 若干帧等它出现"，结果**单跑能过、按文件顺序跑就挂** ——
/// 第二个用例里那个 future 属于上一个已被拆掉的 zone，永远不完成。
/// 真实异步不玩 fake async，就没有这种时序玄学。
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/theme.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/features/profile/collection_list_screen.dart';
import 'package:lianleme/features/profile/profile_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  /// 读**随包**的那份清单（真实异步）
  Future<String> readBundledList(WidgetTester tester) async {
    final String? text =
        await tester.runAsync(() => rootBundle.loadString(kCollectionListAsset));
    expect(text, isNotNull,
        reason: '读不到 assets/collection-list.txt —— 它必须在 pubspec.yaml 的 assets 里');
    return text!;
  }

  group('清单内容（真实资产）', () {
    testWidgets('随包资产读得到，且两份清单与关键结论句都在',
        (WidgetTester tester) async {
      final String text = await readBundledList(tester);

      // 164 号文要的两份清单
      expect(text, contains('个人信息收集清单'));
      expect(text, contains('与第三方共享个人信息清单'));
      // 结论句（审核员第一眼要找的就是这句）
      expect(text, contains('不向任何第三方出售、出租或共享'));
      // 「默认关闭」也要写在清单里 —— v1.28.0 之后的事实
      expect(text, contains('默认关闭'));
      // 收集清单要逐条列出事件（抽查两个，防止整段被换成一句空话）
      expect(text, contains('app_open'));
      expect(text, contains('set_logged'));
      // 权限与"不收集的东西"两块
      expect(text, contains('android.permission.INTERNET'));
      expect(text, contains('不收集：'));
      // 共享清单要列出随包的第三方组件
      expect(text, contains('share_plus'));
      expect(text, contains('gal'));
    });

    testWidgets('生成物里不许漏出仓库内部记号', (WidgetTester tester) async {
      final String text = await readBundledList(tester);

      for (final String bad in <String>[
        '**', // markdown 加粗：用户会看到星号
        '<!--', // HTML 注释
        'TODO',
        'README',
        'npm ',
        // 下面四个是 2026-09-30 在**真机上翻这一页**时抓到的（生成器写进去的、
        // 只对我们自己有意义的说明）—— 抓到一次就补一次，同类问题只准漏一次
        '由仓库自动生成',
        '生成物',
        '请勿手改',
        '不要手改',
      ]) {
        expect(text.contains(bad), isFalse,
            reason: '清单里出现了「$bad」—— 这是给用户/审核员看的文本');
      }
    });
  });

  group('这一屏本身', () {
    testWidgets('读到了就渲染出来', (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CollectionListScreen(
            loader: () async => '个人信息收集清单\n与第三方共享个人信息清单'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('collection-text')), findsOneWidget);
      expect(find.byKey(const Key('collection-error')), findsNothing);
    });

    testWidgets('标题有层级、正文不裸露分隔线（2026-10-01 真机走查改的）',
        (WidgetTester tester) async {
      // 这一份是纯文本资产，2026-10-01 之前整块丢给一个 Text 渲染 ——
      // 所有行一样大一样灰，标题找不到；而生成器那时还在标题上下各画一条
      // `════` 长横线，应用里看起来像连着三条细线 + 大空行。
      await tester.pumpWidget(MaterialApp(
        home: CollectionListScreen(
            loader: () async => '一、个人信息收集清单\n\n【1】本应用的核心功能不收集任何个人信息\n\n  正文一行'),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      final Text heading = tester.widget<Text>(find.text('一、个人信息收集清单'));
      expect(heading.style?.fontWeight, FontWeight.w700,
          reason: '一级标题要有分量');
      expect(heading.style?.fontSize, greaterThan(14));

      final Text sub = tester.widget<Text>(find.text('【1】本应用的核心功能不收集任何个人信息'));
      expect(sub.style?.fontWeight, FontWeight.w600, reason: '二级标题也要有层级');

      // 生成的清单文本里不该再有裸横幅线（那是排版事故的来源）
      final String asset = File('assets/collection-list.txt').readAsStringSync();
      expect(asset.contains('═'), isFalse,
          reason: '生成器不该再画横幅线 —— 层级由界面给');
      expect(asset.contains('---'), isFalse, reason: 'markdown 分隔线也一样');
    });

    testWidgets('读资产失败时如实说，而不是留一片空白',
        (WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CollectionListScreen(
            loader: () async => throw StateError('模拟打包漏资产')),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.byKey(const Key('collection-error')), findsOneWidget);
    });
  });

  group('入口（二级菜单，点得到）', () {
    late AppDatabase db;
    late DriftLocalStore store;
    late ExerciseRepository repo;
    late ProfileRepository profile;

    setUp(() async {
      db = AppDatabase(NativeDatabase.memory());
      store = DriftLocalStore(db);
      repo = ExerciseRepository(db);
      profile = ProfileRepository(db);
      await repo.importSeed(
        loadJson: () => File('assets/exercises.json').readAsString(),
      );
    });

    tearDown(() => db.close());

    testWidgets('「我 → 隐私与关于」里有「个人信息收集清单」这一项，且真的跳过去',
        (WidgetTester tester) async {
      // ⚠️ 不能用 `pumpAndSettle`：这一屏上有常驻定时器/动画，永远等不到"静止"
      Future<void> settle([int ms = 600]) async {
        final DateTime end = DateTime.now().add(Duration(milliseconds: ms));
        while (DateTime.now().isBefore(end)) {
          await tester.pump(const Duration(milliseconds: 60));
        }
      }

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: ProfileScreen(store: store, repository: repo, profile: profile),
        ),
      ));
      await settle(1200);

      // 2026-10-01 重排：清单入口进了「我 → 隐私与关于」。
      // 164 号文的要求是"以**二级菜单**形式集中展示"—— 判定依据是
      // **能从菜单点进去**（下面这几跳每一下都是一个可点的菜单项），不是"必须挂在第一层"。
      // 「我」页是懒构建的 ListView：没进视口就不存在
      for (int i = 0; i < 12; i++) {
        if (find.byKey(const Key('open-privacy-about')).evaluate().isNotEmpty) break;
        await tester.drag(find.byType(ListView), const Offset(0, -260));
        await settle(300);
      }
      final Finder entry = find.byKey(const Key('open-privacy-about'));
      expect(entry, findsOneWidget, reason: '「我」页必须有「隐私与关于」这一项');
      await tester.ensureVisible(entry);
      await settle(300);
      await tester.tap(entry);
      await settle(900);

      final Finder tile = find.byKey(const Key('collection-list'));
      expect(tile, findsOneWidget, reason: '164 号文要求以菜单形式展示');
      await tester.ensureVisible(tile);
      await settle(300);

      await tester.tap(tile);
      await settle(900);
      expect(find.byType(CollectionListScreen), findsOneWidget,
          reason: '点了要真的进去，不能只是摆一个不能点的行');
    });
  });
}
