/// 练了么 · 动作选择页 widget 测试
library;

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lianleme/core/labels.dart';
import 'package:lianleme/data/db.dart' hide Exercise, SetRecord, Workout, WorkoutItem;
import 'package:lianleme/data/drift_local_store.dart';
import 'package:lianleme/data/exercise_repository.dart';
import 'package:lianleme/data/local_store.dart';
import 'package:lianleme/data/profile_repository.dart';
import 'package:lianleme/domain/models.dart';
import 'package:lianleme/features/exercise/exercise_picker_screen.dart';

void main() {
  late AppDatabase db;
  late ExerciseRepository repo;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ExerciseRepository(db);
    await repo.importSeed(
      loadJson: () => File('assets/exercises.json').readAsString(),
    );
  });

  tearDown(() => db.close());

  Future<void> pumpPicker(WidgetTester tester, {LocalStore? store}) async {
    await tester.pumpWidget(
      MaterialApp(home: ExercisePickerScreen(repository: repo, store: store)),
    );
    await tester.pumpAndSettle();
  }

  /// 造一条历史记录：最近练过某个动作。
  Future<LocalStore> storeWithRecent(String exerciseId) async {
    final DriftLocalStore store = DriftLocalStore(db);
    await store.saveSet(SetRecord(
      id: 's1',
      workoutId: 'w1',
      exerciseId: exerciseId,
      setIndex: 1,
      reps: 5,
      completedAtMs: 1000,
      weightKg: 60,
    ));
    return store;
  }

  group('动作说明', () {
    testWidgets('写在种子里的说明会出现在列表里（选动作时才知道这是什么）',
        (WidgetTester tester) async {
      await pumpPicker(tester);

      // 杠铃卧推是推荐位上的动作，种子里有说明
      expect(find.textContaining('肩胛后收贴凳'), findsOneWidget);
    });

    testWidgets('没写说明的动作不会显示空的一行', (WidgetTester tester) async {
      await pumpPicker(tester);

      // 「垫脚高脚杯深蹲」是长尾动作，还没写说明 —— 副标题里不该出现多余的 " · "
      final Finder tile = find.byKey(const Key('exercise-ex_heel_elevated_goblet_squat'));
      if (tile.evaluate().isNotEmpty) {
        final String subtitle = tester
            .widgetList<Text>(find.descendant(of: tile, matching: find.byType(Text)))
            .map((Text t) => t.data ?? '')
            .join('|');
        expect(subtitle.contains(' ·  · '), isFalse,
            reason: '没有说明就不该多一个分隔号');
      }
    });
  });

  group('按类别筛选（热身 / 拉伸）', () {
    // 2026-09-29：热身与拉伸进了库（12 + 9 条）。它们不加进来，"练完拉一下"就记不了；
    // 但它们混在 339 条里排在最末（常用度 20），所以要有一行自己的入口。
    testWidgets('筛「拉伸」→ 只剩拉伸，力量动作不见了', (WidgetTester tester) async {
      await pumpPicker(tester);
      expect(find.text('杠铃卧推'), findsOneWidget);

      await tester.tap(find.byKey(const Key('cat-stretch')));
      await tester.pumpAndSettle();

      expect(find.text('杠铃卧推'), findsNothing);
      expect(find.text('腘绳肌拉伸'), findsOneWidget);
      expect(find.text('拉伸'), findsWidgets, reason: '标题里要标出类别，否则用户不知道自己筛了什么');
    });

    testWidgets('筛「热身」→ 开合跳在，拉伸不在', (WidgetTester tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byKey(const Key('cat-warmup')));
      await tester.pumpAndSettle();

      expect(find.text('开合跳'), findsOneWidget);
      expect(find.text('腘绳肌拉伸'), findsNothing);
    });

    testWidgets('筛「有氧」→ 只剩有氧（力量与拉伸都不见了）',
        (WidgetTester tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byKey(const Key('cat-cardio')));
      await tester.pumpAndSettle();

      // ⚠️ **不按具体动作名断言**：有氧有 13 个，一屏放不下，
      // ListView 只 build 可见的那几个 —— "找不到跳绳"可能只是它在屏幕外。
      // （第一次写这条就是这么错的。）按类别的**表现**断言才稳：
      // 每个可见行的副标题都带类别，且力量/拉伸的动作一个都不在。
      expect(find.textContaining('有氧 · '), findsWidgets);
      expect(find.text('腘绳肌拉伸'), findsNothing);
      expect(find.text('杠铃卧推'), findsNothing);
      expect(find.textContaining('拉伸 · '), findsNothing);

      // 具体是谁属于有氧，在仓库层断言（exercise_repository_test）
    });

    testWidgets('「全部类型」能退回去（默认就看得到全部）',
        (WidgetTester tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byKey(const Key('cat-warmup')));
      await tester.pumpAndSettle();
      expect(find.text('杠铃卧推'), findsNothing);

      await tester.tap(find.byKey(const Key('cat-all')));
      await tester.pumpAndSettle();
      expect(find.text('杠铃卧推'), findsOneWidget, reason: '退回全部类型');
    });

    testWidgets('类别与部位可以叠加（"腿部的拉伸"）', (WidgetTester tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byKey(const Key('cat-stretch')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('腿'));
      await tester.pumpAndSettle();

      expect(find.text('腘绳肌拉伸'), findsOneWidget);
      expect(find.text('门框胸部拉伸'), findsNothing, reason: '胸部的拉伸不该出现在腿的筛选里');
    });
  });

  group('按器械筛选（居家 / 女性人群进来的第一道门）', () {
    testWidgets('筛哑铃 → 杠铃动作不再出现', (WidgetTester tester) async {
      await pumpPicker(tester);
      expect(find.text('杠铃卧推'), findsOneWidget, reason: '不筛的时候它在最前面');

      await tester.tap(find.byKey(const Key('equip-dumbbell')));
      await tester.pumpAndSettle();

      expect(find.text('杠铃卧推'), findsNothing);
      expect(find.textContaining('哑铃'), findsWidgets);
    });

    testWidgets('筛自重 → 拿不到杠铃/器械动作（家里没器械的人走这条路）',
        (WidgetTester tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byKey(const Key('equip-bodyweight')));
      await tester.pumpAndSettle();

      expect(find.text('杠铃卧推'), findsNothing);
      expect(find.text('器械推胸'), findsNothing);
      expect(find.text('平板支撑'), findsOneWidget, reason: '自重动作要都在');
    });

    testWidgets('器械与搜索可以叠加', (WidgetTester tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byKey(const Key('equip-dumbbell')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('exercise-search')), '卧推');
      await tester.pumpAndSettle();

      expect(find.textContaining('哑铃'), findsWidgets);
      expect(find.text('杠铃卧推'), findsNothing, reason: '器械条件不能被搜索顶掉');
    });

    testWidgets('器械与部位可以叠加，且「全部器械」能退回去',
        (WidgetTester tester) async {
      await pumpPicker(tester);

      await tester.tap(find.byKey(const Key('equip-bodyweight')));
      await tester.pumpAndSettle();
      expect(find.text('杠铃卧推'), findsNothing);

      await tester.tap(find.byKey(const Key('equip-all')));
      await tester.pumpAndSettle();
      expect(find.text('杠铃卧推'), findsOneWidget, reason: '退回全部');
    });
  });

  testWidgets('默认按常用度列出动作', (WidgetTester tester) async {
    await pumpPicker(tester);

    expect(find.byKey(const Key('exercise-search')), findsOneWidget);
    // popularity 100 的杠铃卧推应该在最前面那批里
    expect(find.text('杠铃卧推'), findsOneWidget);
  });

  testWidgets('搜索同时匹配名称与别名', (WidgetTester tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byKey(const Key('exercise-search')), 'bp');
    await tester.pumpAndSettle();

    expect(find.text('杠铃卧推'), findsOneWidget, reason: 'bp 是它的别名');
    expect(find.text('杠铃深蹲'), findsNothing, reason: '深蹲不该被 bp 搜出来');
  });

  testWidgets('别名也能搜到名字里没有这个词的动作', (WidgetTester tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byKey(const Key('exercise-search')), '法式卧推');
    await tester.pumpAndSettle();

    expect(find.text('仰卧臂屈伸'), findsOneWidget,
        reason: '「法式卧推」是仰卧臂屈伸的别名');
  });

  testWidgets('点击动作会把它作为路由结果返回', (WidgetTester tester) async {
    ExerciseData? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push<ExerciseData>(
                    MaterialPageRoute<ExerciseData>(
                      builder: (_) => ExercisePickerScreen(repository: repo),
                    ),
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('exercise-search')), 'rdl');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('exercise-ex_rdl')));
    await tester.pumpAndSettle();

    expect(picked?.id, 'ex_rdl');
  });

  testWidgets('搜不到时给明确空状态，而不是一片空白', (WidgetTester tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byKey(const Key('exercise-search')), 'zzzzzz');
    await tester.pumpAndSettle();

    expect(find.textContaining('没找到'), findsOneWidget);
  });

  // ---------- S3 浏览态分区（规格：最近做过 / 常用 / 按部位筛选）----------

  testWidgets('浏览态分三区：最近做过 / 常用 / 全部动作', (WidgetTester tester) async {
    final LocalStore store = await storeWithRecent('ex_bb_squat');
    await pumpPicker(tester, store: store);

    // 首屏：最近做过 + 常用（这正是规格那条"≤5 秒、不滚动"要的效果）
    expect(find.text('最近做过'), findsOneWidget);
    expect(find.text('常用'), findsOneWidget);
    expect(find.byKey(const Key('exercise-ex_bb_squat')), findsOneWidget,
        reason: '刚练过的动作必须在首屏');

    // 「全部动作」在首屏之下（ListView 懒构建），要滚下去才断言得到
    await tester.dragUntilVisible(
      find.text('全部动作'),
      find.byKey(const Key('picker-list')),
      const Offset(0, -200),
    );
    expect(find.text('全部动作'), findsOneWidget);
  });

  testWidgets('最近做过的动作不会在「常用」里重复出现（重复只会让人多滚一次）',
      (WidgetTester tester) async {
    // ex_bb_squat 的 popularity 也是 100，不去重的话会同时进两个区
    final LocalStore store = await storeWithRecent('ex_bb_squat');
    await pumpPicker(tester, store: store);

    expect(find.byKey(const Key('exercise-ex_bb_squat')), findsOneWidget,
        reason: '只应出现一次：在「最近做过」里');
  });

  // ---------- 置顶（2026-10-04，用户自己钉住"我就是要练这几个"）----------

  testWidgets('★ 置顶区排在最前，且那个动作不会在别的区里再出现一次',
      (WidgetTester tester) async {
    // ex_bb_squat 的 popularity 也是 100 —— 不去重的话它会同时出现在置顶与常用里
    final LocalStore store = DriftLocalStore(db);
    await store.setPinnedExerciseIds(<String>['ex_bb_squat']);
    await pumpPicker(tester, store: store);

    expect(find.text('置顶'), findsOneWidget);
    expect(find.byKey(const Key('exercise-ex_bb_squat')), findsOneWidget,
        reason: '只应出现一次：在「置顶」里');
  });

  testWidgets('★ 置顶的动作**又刚练过**时，整屏只出现一次（真机抓到的漏网）',
      (WidgetTester tester) async {
    // 2026-10-04 真机上发现的：只过滤了「常用 / 全部」，漏了「最近做过」——
    // 而真机上"刚练过的"与"被置顶的"恰好是同一个动作，于是同一屏出现两次。
    // 这条测试的夹具必须是**同一个动作既最近做过、又被置顶**，否则盖不住这个 bug。
    final LocalStore store = await storeWithRecent('ex_bb_squat');
    await store.setPinnedExerciseIds(<String>['ex_bb_squat']);
    await pumpPicker(tester, store: store);

    expect(find.text('置顶'), findsOneWidget);
    expect(find.byKey(const Key('exercise-ex_bb_squat')), findsOneWidget,
        reason: '置顶 + 最近做过 = 同一个动作，整屏只该出现一次');
  });

  testWidgets('★ 点星标真的置顶（写进库里，不是只改界面）', (WidgetTester tester) async {
    final LocalStore store = DriftLocalStore(db);
    await pumpPicker(tester, store: store);
    expect(await store.pinnedExerciseIds(), isEmpty);

    await tester.tap(find.byKey(const Key('pin-ex_bb_squat')));
    await tester.pumpAndSettle();

    expect(await store.pinnedExerciseIds(), <String>['ex_bb_squat'],
        reason: '落库才算数 —— 冷启动之后它还得在');
    expect(find.text('置顶'), findsOneWidget);
  });

  testWidgets('★ 再点一次取消置顶（置顶不是单向的）', (WidgetTester tester) async {
    final LocalStore store = DriftLocalStore(db);
    await store.setPinnedExerciseIds(<String>['ex_bb_squat']);
    await pumpPicker(tester, store: store);

    await tester.tap(find.byKey(const Key('pin-ex_bb_squat')));
    await tester.pumpAndSettle();

    expect(await store.pinnedExerciseIds(), isEmpty);
    expect(find.text('置顶'), findsNothing);
  });

  testWidgets('置顶的动作被删掉后，静默跳过（不显示点不动的行）',
      (WidgetTester tester) async {
    final LocalStore store = DriftLocalStore(db);
    // 一个**不在库里**的 id：自定义动作被删之后就会留下这种脏数据
    await store.setPinnedExerciseIds(<String>['ex_已经不存在了']);
    await pumpPicker(tester, store: store);

    expect(find.text('置顶'), findsNothing,
        reason: '一个都不剩就别显示空的分区标题');
    expect(find.byKey(const Key('picker-list')), findsOneWidget,
        reason: '页面本身要照常能用');
  });

  testWidgets('不传 store 时没有星标（点了没地方存，就别给这个按钮）',
      (WidgetTester tester) async {
    await pumpPicker(tester);

    expect(find.byKey(const Key('pin-ex_bb_squat')), findsNothing);
  });

  testWidgets('没有历史时不显示「最近做过」区，但「常用」照常', (WidgetTester tester) async {
    final LocalStore store = DriftLocalStore(db); // 空库，没有任何训练记录
    await pumpPicker(tester, store: store);

    expect(find.text('最近做过'), findsNothing);
    expect(find.text('常用'), findsOneWidget);
  });

  testWidgets('不传 store 也不崩（只是没有最近做过分区）', (WidgetTester tester) async {
    await pumpPicker(tester);

    expect(find.text('最近做过'), findsNothing);
    expect(find.text('常用'), findsOneWidget);
  });

  testWidgets('一旦开始搜索就退回平铺列表，不显示分区标题', (WidgetTester tester) async {
    final LocalStore store = await storeWithRecent('ex_bb_squat');
    await pumpPicker(tester, store: store);
    expect(find.text('常用'), findsOneWidget, reason: '前置：浏览态是有分区的');

    await tester.enterText(find.byKey(const Key('exercise-search')), 'bp');
    await tester.pumpAndSettle();

    // 搜索时用户已经知道自己在找什么，分区只会碍事
    expect(find.text('最近做过'), findsNothing);
    expect(find.text('常用'), findsNothing);
    expect(find.text('全部动作'), findsNothing);
    expect(find.text('杠铃卧推'), findsOneWidget);
  });

  // ---------- S3 右上角「新建自定义动作」----------

  testWidgets('新建 → 填表 → 保存：新动作直接作为选择结果返回',
      (WidgetTester tester) async {
    ExerciseData? picked;

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push<ExerciseData>(
                    MaterialPageRoute<ExerciseData>(
                      builder: (_) => ExercisePickerScreen(repository: repo),
                    ),
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('picker-new-custom')));
    await tester.pumpAndSettle();
    expect(find.text('新建自定义动作'), findsOneWidget);

    await tester.enterText(find.byKey(const Key('custom-name')), '我的新动作');
    await tester.pumpAndSettle();

    // 器械 chips 在 800×600 的测试画布下会被挤到首屏之下 —— 直接 tap 会落空，
    // 而且会误触到底部的保存按钮（第一次就踩到了这个）。先滚动到位。
    final Finder dumbbell = find.byKey(const Key('custom-equipment-dumbbell'));
    await tester.ensureVisible(dumbbell);
    await tester.pumpAndSettle();
    await tester.tap(dumbbell);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('custom-save')));
    await tester.pumpAndSettle();

    // 建完直接返回选中 —— 刚起完名字还要回列表里再找一遍是最烦的
    expect(picked?.name, '我的新动作');
    expect(picked?.equipment, 'dumbbell');
    expect(picked?.weightIncrement, 2, reason: '哑铃步长是 2kg');
    expect(picked?.isBuiltin, isFalse);
    expect(picked?.defaultWeightKg, isNotNull,
        reason: '步长 > 0 必须有起始重量，否则会被当成自重动作');
  });

  testWidgets('用户在设置里定过步进时：新建动作按**用户那个值**开场（10.9 清单第 8a 条）',
      (WidgetTester tester) async {
    // 场景：这家的片子只有 5 kg 一档，用户在设置里把步进定成了 5。
    // 那么新建的哑铃动作该是 5，而不是器械表里那个 2 —— 用户刚说过的偏好更可信。
    await ProfileRepository(db).setDefaultWeightIncrement(5);

    ExerciseData? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push<ExerciseData>(
                    MaterialPageRoute<ExerciseData>(
                      builder: (_) => ExercisePickerScreen(repository: repo),
                    ),
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('picker-new-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-name')), '片子五公斤');
    await tester.pumpAndSettle();

    final Finder dumbbell = find.byKey(const Key('custom-equipment-dumbbell'));
    await tester.ensureVisible(dumbbell);
    await tester.pumpAndSettle();
    await tester.tap(dumbbell);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('custom-save')));
    await tester.pumpAndSettle();

    expect(picked?.weightIncrement, 5, reason: '设置里定过的步进优先于器械默认值');
  });

  testWidgets('自重动作不许被那个"默认步进"污染（0 是"没有重量"的标记）',
      (WidgetTester tester) async {
    await ProfileRepository(db).setDefaultWeightIncrement(5);

    ExerciseData? picked;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (BuildContext ctx) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  picked = await Navigator.of(ctx).push<ExerciseData>(
                    MaterialPageRoute<ExerciseData>(
                      builder: (_) => ExercisePickerScreen(repository: repo),
                    ),
                  );
                },
                child: const Text('开始'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('开始'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('picker-new-custom')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('custom-name')), '徒手深蹲');
    await tester.pumpAndSettle();

    final Finder bw = find.byKey(const Key('custom-equipment-bodyweight'));
    await tester.ensureVisible(bw);
    await tester.pumpAndSettle();
    await tester.tap(bw);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('custom-save')));
    await tester.pumpAndSettle();

    expect(picked?.weightIncrement, 0,
        reason: '自重动作的 0 不能被默认步进盖掉（否则引体向上会变成"能加 5 kg"）');
    expect(picked?.defaultWeightKg, isNull);
  });

  testWidgets('名称为空时保存按钮不可用（不让用户建出无名动作）',
      (WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(home: ExercisePickerScreen(repository: repo)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('picker-new-custom')));
    await tester.pumpAndSettle();

    final Finder save = find.byKey(const Key('custom-save'));
    expect(tester.widget<FilledButton>(save).onPressed, isNull, reason: '还没填名字');

    await tester.enterText(find.byKey(const Key('custom-name')), '  ');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNull,
        reason: '只有空白也不算填了名字');

    await tester.enterText(find.byKey(const Key('custom-name')), '有效名字');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);
  });

  testWidgets('部位筛选只有 6 个主部位（辅助肌群不是可选部位）',
      (WidgetTester tester) async {
    await pumpPicker(tester);
    // 这条守着 2026-09-30 的回归：给详情页补中文标签时改了 kMuscleLabels，
    // 而筛选行当时遍历的是它 —— 于是部位 chips 从 6 个变成 24 个。
    for (final String k in kPrimaryMuscleGroups) {
      expect(find.byKey(Key('muscle-$k')), findsOneWidget, reason: '缺 $k');
    }
    // 辅助肌群绝不能变成筛选项
    for (final String fine in <String>['lats', 'triceps', 'front_delts', 'glutes']) {
      expect(find.byKey(Key('muscle-$fine')), findsNothing,
          reason: '$fine 是辅助肌群，只用于显示，不该出现在筛选里');
    }
  });
}
