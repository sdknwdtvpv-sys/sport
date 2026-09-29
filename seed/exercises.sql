-- 练了么 · 内置动作库种子数据（自动生成，请勿手改）
-- 修改请编辑 seed/parts/*.json 后重新运行：node seed/build.mjs
-- 动作总数：351
-- 生成时间戳：1767225600000（固定值，保证可复现）

BEGIN TRANSACTION;

-- 幂等：只清理内置动作，用户自定义动作（is_builtin = 0）与其历史记录不受影响
DELETE FROM exercise WHERE is_builtin = 1;

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_bb_bench_press', '杠铃卧推', 'Barbell Bench Press', '["平板卧推","卧推","bp","bench"]', 'chest', '["triceps","front_delts"]', 'barbell', 'strength', 'weight_reps', 120, 40, 2.5, NULL, '肩胛后收贴凳，杠铃落在乳头附近；最常见的错是肘部外展成 90° 顶着肩推。', 1, 100, 1767225600000, 1767225600000, NULL),
  ('ex_bb_incline_bench_press', '上斜杠铃卧推', 'Incline Barbell Bench Press', '["上斜卧推","上斜杠铃推胸"]', 'chest', '["front_delts","triceps"]', 'barbell', 'strength', 'weight_reps', 120, 35, 2.5, NULL, '上斜 30°、杠铃落在锁骨下方；屁股别抬离凳面。', 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_bb_decline_bench_press', '下斜杠铃卧推', 'Decline Barbell Bench Press', '["下斜卧推"]', 'chest', '["triceps","front_delts"]', 'barbell', 'strength', 'weight_reps', 120, 35, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_smith_bench_press', '史密斯卧推', 'Smith Machine Bench Press', '["史密斯平板卧推"]', 'chest', '["triceps","front_delts"]', 'machine', 'strength', 'weight_reps', 120, 30, 5, NULL, NULL, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_smith_incline_press', '史密斯上斜卧推', 'Smith Machine Incline Press', '[]', 'chest', '["front_delts","triceps"]', 'machine', 'strength', 'weight_reps', 120, 25, 5, NULL, NULL, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_bb_floor_press', '地板卧推', 'Barbell Floor Press', '["地板推胸"]', 'chest', '["triceps"]', 'barbell', 'strength', 'weight_reps', 120, 40, 2.5, NULL, NULL, 1, 46, 1767225600000, 1767225600000, NULL),
  ('ex_db_bench_press', '哑铃卧推', 'Dumbbell Bench Press', '["平板哑铃卧推","哑铃平板卧推"]', 'chest', '["triceps","front_delts"]', 'dumbbell', 'strength', 'weight_reps', 120, 12, 2, NULL, '两手哑铃在中线靠拢但不撞；下放到胸口两侧即可，别贪深让肩关节过伸。', 1, 95, 1767225600000, 1767225600000, NULL),
  ('ex_db_incline_press', '上斜哑铃卧推', 'Incline Dumbbell Press', '["上斜哑铃推举"]', 'chest', '["front_delts","triceps"]', 'dumbbell', 'strength', 'weight_reps', 120, 10, 2, NULL, '凳角 30° 左右；角度越大越像推举，胸的参与反而变少。', 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_db_decline_press', '下斜哑铃卧推', 'Decline Dumbbell Press', '[]', 'chest', '["triceps","front_delts"]', 'dumbbell', 'strength', 'weight_reps', 120, 10, 2, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_db_close_grip_press', '窄距哑铃卧推', 'Close-Grip Dumbbell Press', '["窄距哑铃推胸"]', 'chest', '["triceps"]', 'dumbbell', 'strength', 'weight_reps', 120, 10, 2, NULL, NULL, 1, 44, 1767225600000, 1767225600000, NULL),
  ('ex_db_swissball_press', '瑞士球哑铃卧推', 'Swiss Ball Dumbbell Press', '["健身球卧推"]', 'chest', '["triceps","core"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_db_fly', '哑铃飞鸟', 'Dumbbell Fly', '["平板飞鸟","飞鸟"]', 'chest', '["shoulders"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, '肘微屈并固定角度，像抱一棵树；下放到胸口有拉伸感就停，别做成卧推。', 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_db_incline_fly', '上斜哑铃飞鸟', 'Incline Dumbbell Fly', '["上斜飞鸟"]', 'chest', '["shoulders"]', 'dumbbell', 'strength', 'weight_reps', 90, 6, 2, NULL, NULL, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_cable_crossover', '绳索夹胸', 'Cable Crossover', '["龙门架夹胸","绳索飞鸟","龙门架飞鸟"]', 'chest', '["shoulders"]', 'cable', 'strength', 'weight_reps', 90, 10, 2.5, NULL, '身体略前倾，两手在胸前交叉；重量宁小勿大，靠行程不靠磅数。', 1, 82, 1767225600000, 1767225600000, NULL),
  ('ex_cable_low_fly', '低位绳索夹胸', 'Low Cable Crossover', '["低位夹胸","下斜绳索夹胸"]', 'chest', '[]', 'cable', 'strength', 'weight_reps', 90, 10, 2.5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_cable_high_fly', '高位绳索夹胸', 'High Cable Crossover', '["高位夹胸","上斜绳索夹胸"]', 'chest', '[]', 'cable', 'strength', 'weight_reps', 90, 10, 2.5, NULL, NULL, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_machine_pec_deck', '蝴蝶机夹胸', 'Pec Deck Fly', '["蝴蝶机","夹胸机"]', 'chest', '["shoulders"]', 'machine', 'strength', 'weight_reps', 90, 25, 5, NULL, '肘与肩同高，夹到胸前停半秒；别用惯性把配重片甩起来。', 1, 80, 1767225600000, 1767225600000, NULL),
  ('ex_machine_chest_press', '器械推胸', 'Chest Press Machine', '["坐姿推胸"]', 'chest', '["triceps","front_delts"]', 'machine', 'strength', 'weight_reps', 120, 30, 5, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_machine_incline_press', '上斜器械推胸', 'Incline Chest Press Machine', '[]', 'chest', '["front_delts","triceps"]', 'machine', 'strength', 'weight_reps', 120, 25, 5, NULL, NULL, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_machine_single_chest_press', '单臂器械推胸', 'Single-Arm Chest Press', '[]', 'chest', '["core"]', 'machine', 'strength', 'weight_reps', 90, 15, 5, NULL, NULL, 1, 30, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_dip', '双杠臂屈伸', 'Chest Dip', '["双杠","臂屈伸","双杠撑"]', 'chest', '["triceps","front_delts"]', 'bodyweight', 'strength', 'reps_only', 120, NULL, 0, NULL, NULL, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_dip', '负重双杠臂屈伸', 'Weighted Dip', '["负重双杠"]', 'chest', '["triceps","front_delts"]', 'bodyweight', 'strength', 'weight_reps', 120, 10, 2.5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_push_up', '俯卧撑', 'Push-up', '["伏地挺身","掌上压"]', 'chest', '["triceps","front_delts","abs","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '身体一条直线、胸口离地一拳；撅臀或塌腰都是核心没在干活。', 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_incline_push_up', '上斜俯卧撑', 'Incline Push-up', '["高台俯卧撑"]', 'chest', '["triceps","front_delts","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_decline_push_up', '下斜俯卧撑', 'Decline Push-up', '["脚抬高俯卧撑"]', 'chest', '["front_delts","triceps","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_db_pullover', '哑铃仰卧屈臂上拉', 'Dumbbell Pullover', '["仰卧上拉","上拉"]', 'chest', '["lats","triceps"]', 'dumbbell', 'strength', 'weight_reps', 90, 15, 2, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_pull_up', '引体向上', 'Pull-up', '["正握引体","引体"]', 'back', '["lats","biceps","core"]', 'bodyweight', 'strength', 'reps_only', 120, NULL, 0, NULL, '先沉肩再拉，胸口找杠；晃身体借力就成了甩上去，背没练到。', 1, 95, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_pull_up', '负重引体向上', 'Weighted Pull-up', '["负重引体"]', 'back', '["lats","biceps"]', 'bodyweight', 'strength', 'weight_reps', 120, 10, 2.5, NULL, NULL, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_chin_up', '反握引体向上', 'Chin-up', '["反手引体","窄握引体"]', 'back', '["lats","biceps"]', 'bodyweight', 'strength', 'reps_only', 120, NULL, 0, NULL, NULL, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_assisted_pull_up', '辅助引体向上', 'Assisted Pull-up', '["引体辅助","器械引体"]', 'back', '["lats","biceps"]', 'machine', 'strength', 'assisted_reps', 90, 30, 5, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_lat_pulldown', '高位下拉', 'Lat Pulldown', '["下拉","宽握下拉"]', 'back', '["lats","biceps"]', 'cable', 'strength', 'weight_reps', 90, 40, 2.5, NULL, '挺胸、先沉肩再拉；拉到锁骨就够，不要往脑后拉。', 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_close_grip_pulldown', '窄握高位下拉', 'Close-Grip Lat Pulldown', '["窄距下拉","V把下拉"]', 'back', '["lats","biceps"]', 'cable', 'strength', 'weight_reps', 90, 40, 2.5, NULL, NULL, 1, 64, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_grip_pulldown', '反握高位下拉', 'Reverse-Grip Lat Pulldown', '["反手下拉"]', 'back', '["lats","biceps"]', 'cable', 'strength', 'weight_reps', 90, 35, 2.5, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_pulldown', '单臂高位下拉', 'Single-Arm Lat Pulldown', '[]', 'back', '["lats","biceps"]', 'cable', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_seated_cable_row', '坐姿绳索划船', 'Seated Cable Row', '["坐姿划船","绳索划船"]', 'back', '["lats","traps","biceps","rear_delts"]', 'cable', 'strength', 'weight_reps', 90, 35, 2.5, NULL, '先坐稳再挺胸拉向腹部；靠后仰借力等于把活交给了惯性。', 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_cable_row', '单臂绳索划船', 'Single-Arm Cable Row', '["单臂坐姿划船"]', 'back', '["lats","biceps","rear_delts"]', 'cable', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_wide_cable_row', '宽握坐姿划船', 'Wide-Grip Cable Row', '["宽握划船"]', 'back', '["traps","rear_delts","lats"]', 'cable', 'strength', 'weight_reps', 90, 35, 2.5, NULL, NULL, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_bb_row', '杠铃划船', 'Barbell Row', '["俯身划船","划船"]', 'back', '["lats","traps","biceps","lower_back","rear_delts"]', 'barbell', 'strength', 'weight_reps', 120, 40, 2.5, NULL, '躯干前倾约 45°、背保持中立；拉向肚脐，别用腰把重量拽起来。', 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_grip_bb_row', '反握杠铃划船', 'Reverse-Grip Barbell Row', '["反手划船"]', 'back', '["lats","biceps","lower_back"]', 'barbell', 'strength', 'weight_reps', 120, 35, 2.5, NULL, NULL, 1, 46, 1767225600000, 1767225600000, NULL),
  ('ex_pendlay_row', '潘德雷划船', 'Pendlay Row', '["触地划船"]', 'back', '["lats","traps","lower_back","biceps","rear_delts"]', 'barbell', 'strength', 'weight_reps', 120, 40, 2.5, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_t_bar_row', 'T杠划船', 'T-Bar Row', '["T杆划船"]', 'back', '["lats","traps","biceps","rear_delts"]', 'barbell', 'strength', 'weight_reps', 120, 30, 2.5, NULL, NULL, 1, 68, 1767225600000, 1767225600000, NULL),
  ('ex_wide_t_bar_row', '宽握T杠划船', 'Wide-Grip T-Bar Row', '[]', 'back', '["shoulders"]', 'barbell', 'strength', 'weight_reps', 120, 30, 2.5, NULL, NULL, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_one_arm_db_row', '单臂哑铃划船', 'One-Arm Dumbbell Row', '["哑铃划船"]', 'back', '["lats","biceps","obliques"]', 'dumbbell', 'strength', 'weight_reps', 90, 12, 2, NULL, '一手撑凳保持背平，哑铃拉向髋部；肩膀别转，转了就是斜方肌在拉。', 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_two_arm_db_row', '双臂哑铃划船', 'Two-Arm Dumbbell Row', '["俯身双臂划船"]', 'back', '["arms"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_chest_supported_row', '胸托划船', 'Chest-Supported Row', '["海豹划船","上斜凳划船"]', 'back', '["lats","traps","biceps","rear_delts"]', 'machine', 'strength', 'weight_reps', 90, 30, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_machine_row', '器械划船', 'Seated Row Machine', '["坐姿器械划船"]', 'back', '["lats","biceps"]', 'machine', 'strength', 'weight_reps', 90, 35, 5, NULL, NULL, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_machine_row', '单臂器械划船', 'Single-Arm Machine Row', '[]', 'back', '["arms"]', 'machine', 'strength', 'weight_reps', 90, 20, 5, NULL, NULL, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_inverted_row', '澳式划船', 'Inverted Row', '["反向划船","自重划船"]', 'back', '["lats","biceps","abs","core"]', 'bodyweight', 'strength', 'reps_only', 90, NULL, 0, NULL, NULL, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_deadlift', '硬拉', 'Deadlift', '["屈腿硬拉","传统硬拉","dl"]', 'legs', '["hamstrings","glutes","lower_back","traps","lats","grip"]', 'barbell', 'strength', 'weight_reps', 180, 50, 2.5, NULL, '杠铃贴小腿，先蹬地再挺髋，背全程中立；宁可少加重也别弓腰拉。', 1, 98, 1767225600000, 1767225600000, NULL),
  ('ex_sumo_deadlift', '相扑硬拉', 'Sumo Deadlift', '["宽站距硬拉"]', 'legs', '["glutes","quads","lower_back"]', 'barbell', 'strength', 'weight_reps', 180, 50, 2.5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_rack_pull', '架上硬拉', 'Rack Pull', '["半程硬拉"]', 'back', '["traps","lower_back","glutes","hamstrings"]', 'barbell', 'strength', 'weight_reps', 180, 60, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_straight_arm_pulldown', '直臂下压', 'Straight-Arm Pulldown', '["直臂下拉"]', 'back', '["lats","triceps","core"]', 'cable', 'strength', 'weight_reps', 60, 20, 2.5, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_face_pull', '面拉', 'Face Pull', '["绳索面拉"]', 'back', '["rear_delts","traps","front_delts"]', 'cable', 'strength', 'weight_reps', 60, 15, 2.5, NULL, NULL, 1, 66, 1767225600000, 1767225600000, NULL),
  ('ex_bb_shrug', '杠铃耸肩', 'Barbell Shrug', '["耸肩"]', 'back', '["traps","forearms"]', 'barbell', 'strength', 'weight_reps', 90, 40, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_db_shrug', '哑铃耸肩', 'Dumbbell Shrug', '[]', 'back', '["traps","forearms"]', 'dumbbell', 'strength', 'weight_reps', 90, 20, 2, NULL, NULL, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_farmer_walk', '农夫行走', 'Farmer''s Walk', '["农夫走","负重行走"]', 'back', '["forearms","traps","abs"]', 'dumbbell', 'strength', 'distance_time', 120, 20, 2, 20, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_bb_squat', '杠铃深蹲', 'Barbell Back Squat', '["深蹲","后蹲","squat"]', 'legs', '["glutes","core","lower_back"]', 'barbell', 'strength', 'weight_reps', 180, 40, 2.5, NULL, '下蹲到髋低于膝、膝与脚尖同向；最常见的错是只顾蹲低却弓了腰。', 1, 100, 1767225600000, 1767225600000, NULL),
  ('ex_front_squat', '前蹲', 'Front Squat', '["颈前深蹲"]', 'legs', '["glutes","abs","core"]', 'barbell', 'strength', 'weight_reps', 180, 30, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_goblet_squat', '高脚杯深蹲', 'Goblet Squat', '["杯式深蹲","哑铃深蹲"]', 'legs', '["glutes","abs","core"]', 'dumbbell', 'strength', 'weight_reps', 90, 16, 2, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_smith_squat', '史密斯深蹲', 'Smith Machine Squat', '[]', 'legs', '["glutes","core"]', 'machine', 'strength', 'weight_reps', 120, 40, 5, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_hack_squat', '哈克深蹲', 'Hack Squat', '["倒蹬深蹲"]', 'legs', '["glutes"]', 'machine', 'strength', 'weight_reps', 120, 40, 5, NULL, NULL, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_box_squat', '箱式深蹲', 'Box Squat', '["坐箱深蹲"]', 'legs', '["glutes","lower_back"]', 'barbell', 'strength', 'weight_reps', 150, 40, 2.5, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_pause_squat', '暂停深蹲', 'Pause Squat', '["停顿深蹲"]', 'legs', '["glutes","abs"]', 'barbell', 'strength', 'weight_reps', 180, 35, 2.5, NULL, NULL, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_bodyweight_squat', '徒手深蹲', 'Bodyweight Squat', '["自重深蹲","空蹲"]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_leg_press', '腿举', 'Leg Press', '["倒蹬","腿推"]', 'legs', '["quads","glutes","hamstrings"]', 'machine', 'strength', 'weight_reps', 120, 60, 5, NULL, '脚踩满踏板、膝不锁死；下放到大腿贴近腹部，别让尾骨离开靠垫。', 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_press', '单腿腿举', 'Single-Leg Press', '[]', 'legs', '["quads","glutes"]', 'machine', 'strength', 'weight_reps', 120, 30, 5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_bulgarian_split_squat', '保加利亚分腿蹲', 'Bulgarian Split Squat', '["分腿蹲","保加利亚蹲"]', 'legs', '["glutes","quads","core"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_static_lunge', '静态分腿蹲', 'Static Lunge', '["原地弓步蹲"]', 'legs', '["core"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 44, 1767225600000, 1767225600000, NULL),
  ('ex_walking_lunge', '箭步蹲', 'Walking Lunge', '["行走箭步蹲","弓步蹲"]', 'legs', '["glutes","quads","abs","hamstrings"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_lunge', '反向箭步蹲', 'Reverse Lunge', '["后撤步箭步蹲"]', 'legs', '["core","glutes","hamstrings"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_bb_lunge', '杠铃箭步蹲', 'Barbell Lunge', '[]', 'legs', '["core"]', 'barbell', 'strength', 'weight_reps', 120, 30, 2.5, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_lateral_lunge', '侧向弓步', 'Lateral Lunge', '["侧弓步"]', 'legs', '["glutes","hamstrings","core"]', 'dumbbell', 'strength', 'reps_only', 90, 8, 2, NULL, NULL, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_leg_extension', '腿屈伸', 'Leg Extension', '["坐姿腿屈伸","腿伸展"]', 'legs', '["quads"]', 'machine', 'strength', 'weight_reps', 90, 25, 5, NULL, '膝与器械转轴对齐，伸到腿几乎直就停；别甩起来，末端停半秒更有效。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_extension', '单腿腿屈伸', 'Single-Leg Extension', '[]', 'legs', '["quads"]', 'machine', 'strength', 'weight_reps', 60, 15, 5, NULL, NULL, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_lying_leg_curl', '俯卧腿弯举', 'Lying Leg Curl', '["腿弯举"]', 'legs', '["hamstrings","calves"]', 'machine', 'strength', 'weight_reps', 90, 25, 5, NULL, NULL, 1, 76, 1767225600000, 1767225600000, NULL),
  ('ex_seated_leg_curl', '坐姿腿弯举', 'Seated Leg Curl', '[]', 'legs', '["hamstrings","calves"]', 'machine', 'strength', 'weight_reps', 90, 25, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_rdl', '罗马尼亚硬拉', 'Romanian Deadlift', '["rdl","直腿罗马尼亚"]', 'legs', '["hamstrings","glutes","lower_back"]', 'barbell', 'strength', 'weight_reps', 120, 40, 2.5, NULL, '髋向后推、背平、杠铃贴腿下滑；感觉大腿后侧被拉长，而不是腰在弯。', 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_stiff_leg_deadlift', '直腿硬拉', 'Stiff-Leg Deadlift', '["直腿拉"]', 'legs', '["hamstrings","glutes","lower_back"]', 'barbell', 'strength', 'weight_reps', 120, 40, 2.5, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_rdl', '单腿罗马尼亚硬拉', 'Single-Leg RDL', '["单腿硬拉"]', 'legs', '["hamstrings","glutes","obliques"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_hip_thrust', '臀推', 'Barbell Hip Thrust', '["杠铃臀推","臀冲"]', 'legs', '["glutes","hamstrings"]', 'barbell', 'strength', 'weight_reps', 120, 40, 2.5, NULL, '上背靠凳、下巴收，顶到髋完全伸开停半秒；别用腰拱起来代替髋伸。', 1, 80, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_machine_hip_thrust', '器械臀推', 'Machine Hip Thrust', '[]', 'legs', '["glutes","hamstrings"]', 'machine', 'strength', 'weight_reps', 120, 40, 5, NULL, NULL, 1, 46, 1767225600000, 1767225600000, NULL),
  ('ex_glute_bridge', '臀桥', 'Glute Bridge', '[]', 'legs', '["glutes","hamstrings"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_glute_bridge', '负重臀桥', 'Weighted Glute Bridge', '[]', 'legs', '["glutes","hamstrings"]', 'barbell', 'strength', 'weight_reps', 90, 30, 2.5, NULL, NULL, 1, 36, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_glute_bridge', '单腿臀桥', 'Single-Leg Glute Bridge', '[]', 'legs', '["glutes","hamstrings"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 35, 1767225600000, 1767225600000, NULL),
  ('ex_hip_abduction', '髋外展', 'Hip Abduction', '["器械外展","坐姿外展"]', 'legs', '["abductors","core"]', 'machine', 'strength', 'weight_reps', 60, 30, 5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_hip_adduction', '髋内收', 'Hip Adduction', '["器械内收","坐姿内收"]', 'legs', '["adductors","core"]', 'machine', 'strength', 'weight_reps', 60, 30, 5, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_standing_calf_raise', '站姿提踵', 'Standing Calf Raise', '["提踵"]', 'legs', '["calves"]', 'machine', 'strength', 'weight_reps', 60, 40, 5, NULL, NULL, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_seated_calf_raise', '坐姿提踵', 'Seated Calf Raise', '[]', 'legs', '["calves"]', 'machine', 'strength', 'weight_reps', 60, 30, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_leg_press_calf_raise', '腿举提踵', 'Leg Press Calf Raise', '[]', 'legs', '["calves"]', 'machine', 'strength', 'weight_reps', 60, 60, 5, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_calf_raise', '单腿站姿提踵', 'Single-Leg Calf Raise', '["单腿提踵"]', 'legs', '["calves","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_smith_calf_raise', '史密斯提踵', 'Smith Machine Calf Raise', '[]', 'legs', '["calves"]', 'machine', 'strength', 'weight_reps', 60, 40, 5, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_bb_ohp', '杠铃站姿推举', 'Overhead Press', '["站姿推举","推举","ohp","实力举","军事推举"]', 'shoulders', '["front_delts","triceps","abs"]', 'barbell', 'strength', 'weight_reps', 150, 25, 2.5, NULL, '核心收紧、头略后让杠铃走直线；靠腿弹一下那是借力推举。', 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_seated_bb_press', '坐姿杠铃推举', 'Seated Barbell Press', '["颈前推举"]', 'shoulders', '["front_delts","triceps"]', 'barbell', 'strength', 'weight_reps', 150, 25, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_db_shoulder_press', '哑铃推举', 'Dumbbell Shoulder Press', '["坐姿哑铃推举","肩推","哑铃肩推"]', 'shoulders', '["front_delts","triceps"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, '肘略前于身体，推到头顶上方；别为了推起来而塌腰。', 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_db_press', '单臂哑铃推举', 'One-Arm Dumbbell Press', '[]', 'shoulders', '["front_delts","obliques"]', 'dumbbell', 'strength', 'weight_reps', 120, 10, 2, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_arnold_press', '阿诺德推举', 'Arnold Press', '["阿诺德"]', 'shoulders', '["front_delts","side_delts","triceps"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_smith_shoulder_press', '史密斯推举', 'Smith Machine Shoulder Press', '[]', 'shoulders', '["front_delts","triceps"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_machine_shoulder_press', '器械推肩', 'Machine Shoulder Press', '["推肩机"]', 'shoulders', '["front_delts","triceps"]', 'machine', 'strength', 'weight_reps', 120, 25, 5, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_handstand_push_up', '倒立撑', 'Handstand Push-up', '["靠墙倒立撑"]', 'shoulders', '["front_delts","triceps","abs","core","chest"]', 'bodyweight', 'strength', 'reps_only', 120, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_db_lateral_raise', '哑铃侧平举', 'Dumbbell Lateral Raise', '["侧平举","侧举"]', 'shoulders', '["side_delts","upper_back"]', 'dumbbell', 'strength', 'weight_reps', 60, 5, 2, NULL, '肘微屈、小指略高，抬到与肩平；耸着肩甩起来就是斜方肌在干活。', 1, 95, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_cable_lateral_raise', '绳索侧平举', 'Cable Lateral Raise', '[]', 'shoulders', '["side_delts","upper_back"]', 'cable', 'strength', 'weight_reps', 60, 5, 2.5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_machine_lateral_raise', '器械侧平举', 'Machine Lateral Raise', '[]', 'shoulders', '["side_delts","upper_back"]', 'machine', 'strength', 'weight_reps', 60, 15, 5, NULL, NULL, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_cable_lateral', '单臂绳索侧平举', 'Single-Arm Cable Lateral Raise', '[]', 'shoulders', '["side_delts"]', 'cable', 'strength', 'weight_reps', 60, 5, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_lean_away_lateral', '斜托侧平举', 'Lean-Away Lateral Raise', '["单手斜托侧平举"]', 'shoulders', '["side_delts"]', 'dumbbell', 'strength', 'weight_reps', 60, 6, 2, NULL, NULL, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_smith_lateral_raise', '史密斯侧平举', 'Smith Machine Lateral Raise', '[]', 'shoulders', '["side_delts"]', 'machine', 'strength', 'weight_reps', 60, 10, 5, NULL, NULL, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_db_front_raise', '哑铃前平举', 'Dumbbell Front Raise', '["前平举"]', 'shoulders', '["front_delts","chest"]', 'dumbbell', 'strength', 'weight_reps', 60, 6, 2, NULL, '举到与肩平即可；过顶会变成斜方肌主导，也容易夹到肩。', 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_bb_front_raise', '杠铃前平举', 'Barbell Front Raise', '[]', 'shoulders', '["front_delts"]', 'barbell', 'strength', 'weight_reps', 60, 15, 2.5, NULL, NULL, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_cable_front_raise', '绳索前平举', 'Cable Front Raise', '[]', 'shoulders', '["front_delts","chest"]', 'cable', 'strength', 'weight_reps', 60, 7.5, 2.5, NULL, NULL, 1, 44, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_cable_front', '单臂绳索前平举', 'Single-Arm Cable Front Raise', '[]', 'shoulders', '["front_delts"]', 'cable', 'strength', 'weight_reps', 60, 5, 2.5, NULL, NULL, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_bent_over_db_fly', '俯身哑铃飞鸟', 'Bent-Over Reverse Fly', '["反向飞鸟","后束飞鸟"]', 'shoulders', '["rear_delts","traps"]', 'dumbbell', 'strength', 'weight_reps', 60, 5, 2, NULL, '俯身近乎平行地面，肘微屈向后展开；重量要小，肩后侧本就弱。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_bent_over_cable_fly', '俯身绳索飞鸟', 'Bent-Over Cable Fly', '["绳索反向飞鸟"]', 'shoulders', '["rear_delts","traps"]', 'cable', 'strength', 'weight_reps', 60, 5, 2.5, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_pec_deck', '反向蝴蝶机', 'Reverse Pec Deck', '["反向蝴蝶机飞鸟","后束器械"]', 'shoulders', '["rear_delts","traps","upper_back"]', 'machine', 'strength', 'weight_reps', 60, 15, 5, NULL, '握把在肩上方、向后展开；坐直别后仰，肩后侧不需要大重量。', 1, 66, 1767225600000, 1767225600000, NULL),
  ('ex_upright_row', '直立划船', 'Upright Row', '[]', 'shoulders', '["traps","side_delts","biceps","upper_back"]', 'barbell', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_bb_curl', '杠铃弯举', 'Barbell Curl', '["弯举"]', 'arms', '["biceps","forearms"]', 'barbell', 'strength', 'weight_reps', 90, 20, 2.5, NULL, '肘固定、身体别晃；用腰把杠铃甩上去是最常见的作弊。', 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_ez_bar_curl', 'EZ杠弯举', 'EZ-Bar Curl', '["曲杠弯举"]', 'arms', '["biceps","forearms"]', 'barbell', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 68, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_bb_curl', '反握杠铃弯举', 'Reverse Barbell Curl', '["反握弯举"]', 'arms', '["forearms","biceps"]', 'barbell', 'strength', 'weight_reps', 90, 15, 2.5, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_db_curl', '哑铃弯举', 'Dumbbell Curl', '["坐姿哑铃弯举"]', 'arms', '["biceps"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, '手腕别外翻，抬到肱二头明显收紧就够；下放慢一点刺激更好。', 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_db_alternating_curl', '哑铃交替弯举', 'Alternating Dumbbell Curl', '["交替弯举"]', 'arms', '["biceps"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_hammer_curl', '锤式弯举', 'Hammer Curl', '["锤式"]', 'arms', '["biceps","forearms"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, '拇指朝上对握，练肱肌与前臂；肘别往前跑。', 1, 82, 1767225600000, 1767225600000, NULL),
  ('ex_incline_hammer_curl', '斜托锤式弯举', 'Incline Hammer Curl', '[]', 'arms', '["biceps","forearms"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 36, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_cable_hammer_curl', '绳索锤式弯举', 'Cable Hammer Curl', '["绳索锤式"]', 'arms', '["biceps","forearms"]', 'cable', 'strength', 'weight_reps', 60, 15, 2.5, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_concentration_curl', '集中弯举', 'Concentration Curl', '[]', 'arms', '["biceps","forearms"]', 'dumbbell', 'strength', 'weight_reps', 60, 8, 2, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_preacher_curl', '牧师凳弯举', 'Preacher Curl', '["斜托弯举","牧师椅弯举"]', 'arms', '["biceps","forearms"]', 'barbell', 'strength', 'weight_reps', 90, 15, 2.5, NULL, NULL, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_incline_db_curl', '斜托哑铃弯举', 'Incline Dumbbell Curl', '["上斜弯举"]', 'arms', '["biceps","forearms"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_zottman_curl', '佐特曼弯举', 'Zottman Curl', '[]', 'arms', '["biceps","forearms"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_cable_curl', '绳索弯举', 'Cable Curl', '[]', 'arms', '["biceps","forearms"]', 'cable', 'strength', 'weight_reps', 60, 15, 2.5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_cable_reverse_curl', '绳索反握弯举', 'Cable Reverse Curl', '[]', 'arms', '["forearms","biceps"]', 'cable', 'strength', 'weight_reps', 60, 12.5, 2.5, NULL, NULL, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_machine_curl', '器械弯举', 'Machine Curl', '[]', 'arms', '["biceps"]', 'machine', 'strength', 'weight_reps', 90, 20, 5, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_cable_pushdown', '绳索下压', 'Cable Triceps Pushdown', '["下压","三头下压"]', 'arms', '["triceps"]', 'cable', 'strength', 'weight_reps', 60, 20, 2.5, NULL, '肘夹紧身侧，只让小臂下压；上身别跟着往下压。', 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_straight_bar_pushdown', '直杆下压', 'Straight-Bar Pushdown', '["横杆下压"]', 'arms', '["triceps","front_delts"]', 'cable', 'strength', 'weight_reps', 60, 20, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_grip_pushdown', '反握下压', 'Reverse-Grip Pushdown', '[]', 'arms', '["triceps","forearms"]', 'cable', 'strength', 'weight_reps', 60, 15, 2.5, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_pushdown', '单臂绳索下压', 'Single-Arm Pushdown', '[]', 'arms', '["triceps"]', 'cable', 'strength', 'weight_reps', 60, 10, 2.5, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_close_grip_bench', '窄握卧推', 'Close-Grip Bench Press', '["窄距卧推","窄握推胸"]', 'arms', '["triceps","front_delts","chest"]', 'barbell', 'strength', 'weight_reps', 120, 30, 2.5, NULL, '握距与肩同宽或略窄，肘贴近身体；手腕别过度后折。', 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_close_grip_smith', '窄握史密斯卧推', 'Close-Grip Smith Press', '[]', 'arms', '["triceps","front_delts"]', 'machine', 'strength', 'weight_reps', 120, 25, 5, NULL, NULL, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_skull_crusher', '仰卧臂屈伸', 'Skull Crusher', '["碎颅式","法式卧推"]', 'arms', '["triceps","front_delts"]', 'barbell', 'strength', 'weight_reps', 90, 15, 2.5, NULL, NULL, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_overhead_db_extension', '哑铃颈后臂屈伸', 'Overhead Dumbbell Extension', '["颈后臂屈伸"]', 'arms', '["triceps","front_delts"]', 'dumbbell', 'strength', 'weight_reps', 90, 10, 2, NULL, NULL, 1, 68, 1767225600000, 1767225600000, NULL),
  ('ex_overhead_cable_extension', '绳索过顶臂屈伸', 'Overhead Cable Extension', '["绳索颈后臂屈伸"]', 'arms', '["triceps","front_delts"]', 'cable', 'strength', 'weight_reps', 60, 15, 2.5, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_overhead_cable', '单臂绳索过顶臂屈伸', 'Single-Arm Overhead Cable Extension', '[]', 'arms', '["triceps"]', 'cable', 'strength', 'weight_reps', 60, 10, 2.5, NULL, NULL, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_machine_triceps_extension', '器械臂屈伸', 'Machine Triceps Extension', '[]', 'arms', '["triceps"]', 'machine', 'strength', 'weight_reps', 60, 20, 5, NULL, NULL, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_triceps_kickback', '哑铃俯身臂屈伸', 'Triceps Kickback', '["后踢腿","臂屈伸后踢"]', 'arms', '["triceps"]', 'dumbbell', 'strength', 'weight_reps', 60, 5, 2, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_diamond_push_up', '窄握俯卧撑', 'Diamond Push-up', '["钻石俯卧撑"]', 'arms', '["triceps","front_delts","core","chest"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_wrist_curl', '腕弯举', 'Wrist Curl', '["正握腕弯举"]', 'arms', '["forearms"]', 'dumbbell', 'strength', 'weight_reps', 60, 8, 2, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_wrist_curl', '反向腕弯举', 'Reverse Wrist Curl', '[]', 'arms', '["forearms"]', 'dumbbell', 'strength', 'weight_reps', 60, 6, 2, NULL, NULL, 1, 35, 1767225600000, 1767225600000, NULL),
  ('ex_crunch', '卷腹', 'Crunch', '["仰卧卷腹"]', 'core', '["abs"]', 'bodyweight', 'strength', 'reps_only', 45, NULL, 0, NULL, '靠腹肌把肩胛卷离地面，不是靠脖子；手别拽头。', 1, 82, 1767225600000, 1767225600000, NULL),
  ('ex_sit_up', '仰卧起坐', 'Sit-up', '[]', 'core', '["abs","hip_flexors"]', 'bodyweight', 'strength', 'weight_reps', 45, NULL, 0, NULL, NULL, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_crunch', '反向卷腹', 'Reverse Crunch', '[]', 'core', '["abs"]', 'bodyweight', 'strength', 'reps_only', 45, NULL, 0, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_side_crunch', '侧卷腹', 'Side Crunch', '["侧腹卷腹"]', 'core', '["obliques"]', 'bodyweight', 'strength', 'weight_reps', 45, NULL, 0, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_heel_touch', '仰卧交替触踝', 'Heel Touch', '["触踝"]', 'core', '["obliques"]', 'bodyweight', 'strength', 'weight_reps', 45, NULL, 0, NULL, NULL, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_hanging_leg_raise', '悬垂举腿', 'Hanging Leg Raise', '["单杠举腿"]', 'core', '["abs","hip_flexors","grip"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_hanging_knee_raise', '悬垂举膝', 'Hanging Knee Raise', '["单杠举膝"]', 'core', '["abs","hip_flexors","grip"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_hanging_side_leg_raise', '悬垂侧举腿', 'Hanging Side Leg Raise', '[]', 'core', '["obliques","hip_flexors"]', 'bodyweight', 'strength', 'weight_reps', 60, NULL, 0, NULL, NULL, 1, 30, 1767225600000, 1767225600000, NULL),
  ('ex_lying_leg_raise', '仰卧举腿', 'Lying Leg Raise', '[]', 'core', '["abs","hip_flexors","quads"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_plank', '平板支撑', 'Plank', '["平板"]', 'core', '["abs","obliques","front_delts"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, '肘在肩正下方、臀腿收紧成一条线；塌腰或撅臀都说明核心没在撑。', 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_plank', '负重平板支撑', 'Weighted Plank', '[]', 'core', '["abs","obliques"]', 'bodyweight', 'strength', 'weight_time', 60, 5, 2.5, NULL, NULL, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_side_plank', '侧平板', 'Side Plank', '["侧桥"]', 'core', '["obliques","front_delts"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_russian_twist', '俄罗斯转体', 'Russian Twist', '["俄式转体"]', 'core', '["obliques","front_delts"]', 'bodyweight', 'strength', 'reps_only', 45, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_cable_side_bend', '绳索侧屈', 'Cable Side Bend', '["绳索体侧屈"]', 'core', '["obliques"]', 'cable', 'strength', 'weight_reps', 45, 15, 2.5, NULL, NULL, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_ab_wheel', '健腹轮', 'Ab Wheel Rollout', '["腹肌轮","健腹轮跪姿"]', 'core', '["abs","hip_flexors","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_cable_crunch', '绳索卷腹', 'Cable Crunch', '["跪姿绳索卷腹"]', 'core', '["abs"]', 'cable', 'strength', 'weight_reps', 60, 25, 2.5, NULL, NULL, 1, 66, 1767225600000, 1767225600000, NULL),
  ('ex_machine_crunch', '器械卷腹', 'Machine Crunch', '[]', 'core', '["abs"]', 'machine', 'strength', 'weight_reps', 60, 25, 5, NULL, NULL, 1, 45, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_dead_bug', '死虫', 'Dead Bug', '["死虫式"]', 'core', '["abs","quads"]', 'bodyweight', 'strength', 'reps_only', 45, NULL, 0, NULL, NULL, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_bird_dog', '鸟狗式', 'Bird Dog', '[]', 'core', '["lower_back","glutes","front_delts"]', 'bodyweight', 'strength', 'reps_only', 45, NULL, 0, NULL, NULL, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_mountain_climber', '登山跑', 'Mountain Climber', '["登山者"]', 'core', '["abs","hip_flexors","front_delts","quads"]', 'bodyweight', 'strength', 'time', 45, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_pallof_press', '帕洛夫抗旋转', 'Pallof Press', '["抗旋转推"]', 'core', '["obliques","abs","front_delts"]', 'cable', 'strength', 'weight_reps', 45, 10, 2.5, NULL, NULL, 1, 35, 1767225600000, 1767225600000, NULL),
  ('ex_back_extension', '山羊挺身', 'Back Extension', '["罗马椅挺身","背屈伸"]', 'back', '["lower_back","glutes","hamstrings"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_active_hang', '主动悬垂', 'Active Hang', '[]', 'back', '["upper_back","forearms","core"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_archer_push_up', '弓手俯卧撑', 'Archer Push-up', '["单臂俯卧撑辅助版"]', 'chest', '["triceps","front_delts","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_arm_circles', '绕臂', 'Arm Circles', '[]', 'shoulders', '["chest","upper_back"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_assault_bike', '风阻单车', 'Assault Bike', '["空气单车","风扇单车"]', 'legs', '["front_delts"]', 'machine', 'cardio', 'distance_time', 60, NULL, 0, 5000, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_assisted_chin_up', '辅助反握引体向上', 'Assisted Chin-up', '[]', 'arms', '["lats"]', 'machine', 'strength', 'assisted_reps', 60, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_assisted_dip', '辅助双杠臂屈伸', 'Assisted Dip', '[]', 'arms', '["chest"]', 'machine', 'strength', 'assisted_reps', 60, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_assisted_pistol_squat', '辅助单腿深蹲', 'Assisted Pistol Squat', '[]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_band_pull_apart', '弹力带扩胸', 'Band Pull-Apart', '[]', 'back', '["rear_delts","front_delts"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, '手肘微屈、肩胛向后夹；练肩后侧与上背最省事的居家动作。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_clamshell', '弹力带蚌式开合', 'Banded Clamshell', '[]', 'legs', '["core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, '侧躺屈膝、带子套膝上，上侧膝打开；骨盆别跟着翻。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_dead_bug', '弹力带死虫', 'Banded Dead Bug', '[]', 'core', '["glutes","front_delts"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, '腰贴地，对侧手脚下放；腰一离地就说明放得太远了。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_donkey_kick', '弹力带跪姿后踢腿', 'Banded Donkey Kick', '[]', 'legs', '["hamstrings","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_face_pull', '弹力带面拉', 'Banded Face Pull', '[]', 'back', '["rear_delts","front_delts"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, '带子固定在与脸同高处，向脸方向拉并外旋；练肩后侧与上背，重量不必大。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_fire_hydrant', '弹力带消防栓式', 'Banded Fire Hydrant', '[]', 'legs', '["core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_frog_pump', '弹力带蛙式臀冲', 'Banded Frog Pump', '[]', 'legs', '["hamstrings"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_glute_bridge', '弹力带臀桥', 'Banded Glute Bridge', '[]', 'legs', '["hamstrings","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, '脚跟踩实、带子套膝上，顶髋并外推膝盖；靠臀发力，不是靠腰。', 1, 78, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_banded_hip_thrust', '弹力带臀推', 'Banded Hip Thrust', '[]', 'legs', '["hamstrings","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_kickback', '弹力带后踢腿', 'Banded Kickback', '[]', 'legs', '["hamstrings","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_lat_pulldown', '弹力带高位下拉', 'Banded Lat Pulldown', '[]', 'back', '["biceps","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_lateral_walk', '弹力带侧向走', 'Banded Lateral Walk', '["螃蟹走"]', 'legs', '["quads","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_monster_walk', '弹力带怪兽走', 'Banded Monster Walk', '[]', 'legs', '["quads","hamstrings","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_pallof_press', '弹力带帕洛夫推', 'Banded Pallof Press', '[]', 'core', '["glutes","front_delts"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, '侧对固定点，把带子从胸前推出并抗旋；最直接的抗旋转练法。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_row', '弹力带划船', 'Banded Row', '[]', 'back', '["biceps","upper_back"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, '带子固定在与胸同高处，向后拉到肘过身侧；全程别让带子松回去。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_seated_hip_abduction', '弹力带坐姿髋外展', 'Banded Seated Hip Abduction', '[]', 'legs', '["core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_squat', '弹力带深蹲', 'Banded Squat', '[]', 'legs', '["glutes","hamstrings","core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_banded_standing_hip_abduction', '弹力带站姿髋外展', 'Banded Standing Hip Abduction', '[]', 'legs', '["core"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_banded_woodchop', '弹力带伐木', 'Banded Woodchop', '[]', 'core', '["front_delts","glutes"]', 'band', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_barbell_glute_bridge', '杠铃臀桥', 'Barbell Glute Bridge', '[]', 'legs', '["hamstrings","core"]', 'barbell', 'strength', 'weight_reps', 120, 20, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_battle_ropes', '战绳', 'Battle Ropes', '["甩绳"]', 'shoulders', '["core"]', 'band', 'cardio', 'time', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_bear_crawl', '熊爬', 'Bear Crawl', '[]', 'core', '["front_delts","quads"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_bear_plank', '熊式平板支撑', 'Bear Plank', '[]', 'core', '["quads","front_delts"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_belt_squat', '腰带深蹲', 'Belt Squat', '[]', 'legs', '["glutes"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_bench_dip', '凳上臂屈伸', 'Bench Dip', '["长凳臂屈伸"]', 'arms', '["chest","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '手撑身后凳沿，屈肘下沉到大臂与地面平行；肩疼就把身体贴近凳。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_bicycle_crunch', '自行车卷腹', 'Bicycle Crunch', '["空中蹬车"]', 'core', '["quads"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '对侧肘找膝，转的是躯干不是手肘；慢一点比快一倍有效。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_burpee', '波比跳', 'Burpee', '["立卧撑跳"]', 'legs', '["chest","front_delts","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_butterfly_stretch', '蝴蝶式拉伸', 'Butterfly Stretch', '[]', 'legs', '["adductors"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_cable_kickback', '绳索后踢腿', 'Cable Kickback', '[]', 'legs', '["hamstrings"]', 'cable', 'strength', 'weight_reps', 120, 10, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_cable_pallof_hold', '绳索帕洛夫静力保持', 'Cable Pallof Hold', '[]', 'core', '["glutes","front_delts"]', 'cable', 'strength', 'time', 60, 10, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_cable_pull_through', '绳索胯下拉', 'Cable Pull-Through', '["绳索拉胯"]', 'legs', '["hamstrings","lower_back"]', 'cable', 'strength', 'weight_reps', 120, 10, 2.5, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_cable_rear_delt_fly', '绳索反向飞鸟', 'Cable Rear Delt Fly', '[]', 'shoulders', '["upper_back"]', 'cable', 'strength', 'weight_reps', 90, 10, 2.5, NULL, '绳索交叉握、向后展开到与肩平；别用手臂拽，肩胛不要夹。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_cable_standing_hip_abduction', '绳索站姿髋外展', 'Cable Standing Hip Abduction', '[]', 'legs', '["core"]', 'cable', 'strength', 'weight_reps', 120, 10, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_cable_standing_hip_adduction', '绳索站姿髋内收', 'Cable Standing Hip Adduction', '[]', 'legs', '["core","glutes"]', 'cable', 'strength', 'weight_reps', 120, 10, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_cable_woodchop', '绳索伐木', 'Cable Woodchop', '["绳索斜劈"]', 'core', '["front_delts"]', 'cable', 'strength', 'weight_reps', 60, 10, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_calf_raise', '徒手提踵', 'Calf Raise', '[]', 'legs', '[]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_captains_chair_knee_raise', '船长椅举膝', 'Captain''s Chair Knee Raise', '["罗马椅举膝"]', 'core', '["front_delts"]', 'machine', 'strength', 'reps_only', 60, 20, 5, NULL, '背贴靠垫，靠腹肌把膝抬到与髋同高；别靠身体前后晃借力。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_cat_cow_stretch', '猫牛式', 'Cat-Cow Stretch', '["猫牛式拉伸"]', 'core', '["lats"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_chair_dip', '椅上臂屈伸', 'Chair Dip', '[]', 'arms', '["chest","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '同凳上臂屈伸，椅子抵住墙；下沉别过深，肩前侧最容易在这里受伤。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_childs_pose', '婴儿式', 'Child''s Pose', '[]', 'back', '["front_delts","glutes"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_clamshell', '蚌式开合', 'Clamshell', '[]', 'legs', '["core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_commando_pull_up', '突击队引体向上', 'Commando Pull-up', '["平行引体"]', 'back', '["biceps","upper_back","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_copenhagen_plank', '哥本哈根平板支撑', 'Copenhagen Plank', '[]', 'core', '["quads","glutes"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_cossack_squat', '哥萨克深蹲', 'Cossack Squat', '["侧向深蹲"]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_crab_walk', '螃蟹爬', 'Crab Walk', '[]', 'arms', '["glutes","core","front_delts"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_cross_body_shoulder_stretch', '交叉肩部拉伸', 'Cross-Body Shoulder Stretch', '[]', 'shoulders', '["upper_back"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_curtsy_lunge', '交叉箭步蹲', 'Curtsy Lunge', '[]', 'legs', '["quads","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '后腿斜向侧后方落脚，前脚站稳再起身；膝盖别内扣。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_cycling', '骑行', 'Cycling', '["单车","自行车"]', 'legs', '[]', 'machine', 'cardio', 'distance_time', 60, NULL, 0, 10000, NULL, 1, 20, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_dead_hang', '静态悬垂', 'Dead Hang', '[]', 'arms', '["lats","front_delts","core"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_decline_sit_up', '下斜仰卧起坐', 'Decline Sit-Up', '[]', 'core', '["quads"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_deficit_reverse_lunge', '垫高反向箭步蹲', 'Deficit Reverse Lunge', '[]', 'legs', '["quads","hamstrings","core"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_donkey_calf_raise', '驴式提踵', 'Donkey Calf Raise', '[]', 'legs', '[]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_donkey_kick', '跪姿后踢腿', 'Donkey Kick', '["驴踢"]', 'legs', '["hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_doorway_chest_stretch', '门框胸部拉伸', 'Doorway Chest Stretch', '[]', 'chest', '["front_delts"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_doorway_row', '门框划船', 'Doorway Row', '[]', 'back', '["biceps","upper_back","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_drag_curl', '拖拽弯举', 'Drag Curl', '[]', 'arms', '["forearms"]', 'barbell', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_dragon_flag', '龙旗', 'Dragon Flag', '[]', 'core', '["lats","quads"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_curtsy_lunge', '哑铃交叉箭步蹲', 'Dumbbell Curtsy Lunge', '[]', 'legs', '["quads","hamstrings","core"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_glute_bridge', '哑铃臀桥', 'Dumbbell Glute Bridge', '[]', 'legs', '["hamstrings","core"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_hip_thrust', '哑铃臀推', 'Dumbbell Hip Thrust', '[]', 'legs', '["hamstrings"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_lateral_lunge', '哑铃侧向弓步', 'Dumbbell Lateral Lunge', '[]', 'legs', '["glutes","adductors","hamstrings"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_romanian_deadlift', '哑铃罗马尼亚硬拉', 'Dumbbell Romanian Deadlift', '["哑铃直腿硬拉"]', 'legs', '["glutes","lower_back"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_side_bend', '哑铃体侧屈', 'Dumbbell Side Bend', '[]', 'core', '["grip"]', 'dumbbell', 'strength', 'weight_reps', 60, 8, 2, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_skull_crusher', '双哑铃仰卧臂屈伸', 'Two Dumbbell Skullcrusher', '[]', 'arms', '["front_delts"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, '仰卧，肘固定在头顶上方只让前臂转；肘一散开就成了推举。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_sumo_deadlift', '哑铃相扑硬拉', 'Dumbbell Sumo Deadlift', '[]', 'legs', '["glutes","quads","adductors"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_dumbbell_sumo_squat', '哑铃相扑深蹲', 'Dumbbell Sumo Squat', '["相扑深蹲"]', 'legs', '["quads","adductors","hamstrings"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_elliptical', '椭圆机', 'Elliptical', '["椭圆仪"]', 'legs', '[]', 'machine', 'cardio', 'time', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_explosive_push_up', '爆发俯卧撑', 'Explosive Push-up', '["击掌俯卧撑"]', 'chest', '["triceps","front_delts","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_fast_feet', '快速碎步', 'Fast Feet', '[]', 'legs', '["quads"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_feet_elevated_pike_push_up', '垫脚派克俯卧撑', 'Feet-Elevated Pike Push-up', '[]', 'shoulders', '["triceps","chest","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_fire_hydrant', '消防栓式', 'Fire Hydrant', '[]', 'legs', '["core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_flutter_kick', '仰卧交替打腿', 'Flutter Kick', '["剪式打腿"]', 'core', '["quads"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_forward_lunge', '前箭步蹲', 'Forward Lunge', '[]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '前脚迈出一步、后膝下沉到接近地面；上身保持直立，前膝别内扣。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_frog_pump', '蛙式臀冲', 'Frog Pump', '[]', 'legs', '["hamstrings"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_front_foot_elevated_split_squat', '前脚垫高分腿蹲', 'Front-Foot Elevated Split Squat', '[]', 'legs', '["glutes","core"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_glute_bridge_march', '臀桥踏步', 'Glute Bridge March', '[]', 'legs', '["hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_glute_focused_back_extension', '臀部集中山羊挺身', 'Glute-Focused Back Extension', '[]', 'legs', '["hamstrings","lower_back"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_good_morning', '早安式体前屈', 'Good Morning', '["早安式"]', 'legs', '["glutes","lower_back"]', 'barbell', 'strength', 'weight_reps', 120, 20, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_half_burpee', '半程波比跳', 'Half Burpee', '[]', 'core', '["quads","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_half_kneeling_pallof_press', '半跪姿帕洛夫推', 'Half-Kneeling Pallof Press', '[]', 'core', '["glutes","front_delts"]', 'cable', 'strength', 'weight_reps', 60, 10, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_hamstring_stretch', '腘绳肌拉伸', 'Hamstring Stretch', '[]', 'legs', '["calves"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_heel_elevated_goblet_squat', '垫脚高脚杯深蹲', 'Heel-Elevated Goblet Squat', '[]', 'legs', '["glutes","core"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_heel_tap', '仰卧触踝', 'Heel Tap', '[]', 'core', '[]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_high_knees', '高抬腿', 'High Knees', '[]', 'legs', '["core"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_hiking', '徒步', 'Hiking', '["徒步走","登山"]', 'legs', '["glutes"]', 'bodyweight', 'cardio', 'distance_time', 60, NULL, 0, 5000, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_hindu_push_up', '印度俯卧撑', 'Hindu Push-up', '["潜水式俯卧撑"]', 'chest', '["front_delts","triceps","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_hip_airplane', '髋部飞机式', 'Hip Airplane', '[]', 'legs', '["hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_hollow_body_hold', '空心支撑', 'Hollow Body Hold', '[]', 'core', '["quads"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, '肩与腿离地、腰贴地；腰拱起来就屈膝降难度。', 1, 78, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_hollow_rock', '空心摇摆', 'Hollow Rock', '[]', 'core', '["quads"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_inchworm', '毛毛虫爬行', 'Inchworm', '[]', 'core', '["front_delts","hamstrings","chest"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_incline_cable_fly', '上斜绳索飞鸟', 'Incline Cable Fly', '[]', 'chest', '["front_delts"]', 'cable', 'strength', 'weight_reps', 120, 10, 2.5, NULL, '上斜角度做夹胸，肘微屈固定；拉向锁骨方向，别做成推。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_jump_rope', '跳绳', 'Jump Rope', '[]', 'legs', '["front_delts"]', 'bodyweight', 'cardio', 'time', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_jump_squat', '深蹲跳', 'Jump Squat', '[]', 'legs', '["glutes","calves"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_jumping_jack', '开合跳', 'Jumping Jack', '[]', 'legs', '["front_delts","calves"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_kettlebell_romanian_deadlift', '壶铃罗马尼亚硬拉', 'Kettlebell Romanian Deadlift', '[]', 'legs', '["glutes","lower_back"]', 'kettlebell', 'strength', 'weight_reps', 120, 12, 4, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_kettlebell_swing', '壶铃摆荡', 'Kettlebell Swing', '["壶铃摇摆"]', 'legs', '["hamstrings","core"]', 'kettlebell', 'strength', 'weight_reps', 120, 12, 4, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_knee_push_up', '跪姿俯卧撑', 'Knee Push-up', '[]', 'chest', '["triceps","front_delts","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_kneeling_hip_flexor_stretch', '跪姿髂腰肌拉伸', 'Kneeling Hip Flexor Stretch', '[]', 'legs', '["quads"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_l_sit_hold', 'L 式支撑', 'L-Sit Hold', '[]', 'core', '["triceps","quads","front_delts"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_l_sit_pull_up', 'L 式引体向上', 'L-Sit Pull-up', '[]', 'back', '["biceps","core","forearms"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_landmine_press', '地雷管推举', 'Landmine Press', '[]', 'shoulders', '["chest","triceps"]', 'barbell', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_landmine_romanian_deadlift', '地雷管罗马尼亚硬拉', 'Landmine Romanian Deadlift', '[]', 'legs', '["glutes","lower_back"]', 'barbell', 'strength', 'weight_reps', 120, 20, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_landmine_squat', '地雷管深蹲', 'Landmine Squat', '[]', 'legs', '["glutes","core"]', 'barbell', 'strength', 'weight_reps', 120, 20, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_lateral_shuffle', '侧向滑步', 'Lateral Shuffle', '[]', 'legs', '["glutes","calves"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_leg_swings_stretch', '摆腿', 'Leg Swings', '[]', 'legs', '["glutes","hamstrings","quads"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_lying_hamstring_walkout', '仰卧腘绳肌走', 'Lying Hamstring Walkout', '[]', 'legs', '["glutes","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_machine_glute_kickback', '器械后踢腿', 'Machine Glute Kickback', '[]', 'legs', '["hamstrings"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_meadows_row', '梅多斯划船', 'Meadows Row', '[]', 'back', '["biceps","rear_delts"]', 'barbell', 'strength', 'weight_reps', 120, 20, 2.5, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_negative_pull_up', '离心引体向上', 'Negative Pull-up', '["退让引体"]', 'back', '["biceps","upper_back","forearms"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_neutral_grip_pull_up', '对握引体向上', 'Neutral-Grip Pull-up', '["锤式引体"]', 'back', '["biceps","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_nordic_hamstring_curl', '北欧腘绳肌弯举', 'Nordic Hamstring Curl', '["北欧挺"]', 'legs', '["glutes","calves"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_pike_push_up', '派克俯卧撑', 'Pike Push-up', '["屈体俯卧撑"]', 'shoulders', '["triceps","chest","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_pistol_squat', '单腿深蹲', 'Pistol Squat', '["手枪深蹲"]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_plank_shoulder_tap', '平板支撑交替摸肩', 'Plank Shoulder Tap', '[]', 'core', '["front_delts","chest"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '平板姿势下交替摸肩，髋别左右摇；摇了就减小幅度。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_plate_front_raise', '杠铃片前平举', 'Plate Front Raise', '[]', 'shoulders', '["chest"]', 'barbell', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_prone_t_raise', '俯卧 T 字举', 'Prone T Raise', '[]', 'back', '["rear_delts","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_prone_y_raise', '俯卧 Y 字举', 'Prone Y Raise', '[]', 'back', '["rear_delts","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_push_press', '借力推举', 'Push Press', '[]', 'shoulders', '["triceps","quads"]', 'barbell', 'strength', 'weight_reps', 90, 20, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_push_up_shoulder_tap', '俯卧撑交替摸肩', 'Push-up Shoulder Tap', '[]', 'core', '["chest","front_delts","triceps"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_hyperextension', '反向山羊挺身', 'Reverse Hyperextension', '[]', 'legs', '["hamstrings","lower_back"]', 'machine', 'strength', 'reps_only', 60, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_snow_angel', '俯卧反向雪天使', 'Reverse Snow Angel', '[]', 'back', '["rear_delts","lower_back","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_rowing', '划船机', 'Rowing', '["划船"]', 'back', '["quads"]', 'machine', 'cardio', 'distance_time', 60, NULL, 0, 2000, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_running', '跑步', 'Running', '["户外跑"]', 'legs', '[]', 'bodyweight', 'cardio', 'distance_time', 60, NULL, 0, 5000, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_scapular_pull_up', '肩胛引体向上', 'Scapular Pull-up', '[]', 'back', '["upper_back","forearms","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_scapular_push_up', '肩胛俯卧撑', 'Scapular Push-up', '[]', 'back', '["chest","front_delts","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_seal_jack', '海豹跳', 'Seal Jack', '[]', 'legs', '["front_delts","quads"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_seated_forward_fold_stretch', '坐姿体前屈', 'Seated Forward Fold', '[]', 'legs', '["lats","calves"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_seated_knee_tuck', '坐姿收膝', 'Seated Knee Tuck', '[]', 'core', '["quads"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_shrimp_squat', '虾式深蹲', 'Shrimp Squat', '[]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_side_lying_hip_abduction', '侧卧髋外展', 'Side-Lying Hip Abduction', '[]', 'legs', '["core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_side_lying_leg_raise', '侧卧举腿', 'Side-Lying Leg Raise', '[]', 'legs', '["core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, '侧躺成一条线、脚尖朝前；抬腿别转髋，转髋就练不到臀中肌。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_side_plank_hip_dip', '侧平板转髋', 'Side Plank Hip Dip', '[]', 'core', '["front_delts","glutes"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_dumbbell_tricep_extension', '单臂哑铃臂屈伸', 'Single Arm Dumbbell Tricep Extension', '[]', 'arms', '["front_delts"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_single_dumbbell_skullcrusher', '单哑铃仰卧臂屈伸', 'Single Dumbbell Skullcrusher', '[]', 'arms', '["front_delts"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_box_squat', '单腿箱式深蹲', 'Single-Leg Box Squat', '[]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_sissy_squat', '西西深蹲', 'Sissy Squat', '[]', 'legs', '["core","calves"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_skater_hop', '滑冰跳', 'Skater Hop', '[]', 'legs', '["glutes","calves"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_skater_squat', '滑冰深蹲', 'Skater Squat', '[]', 'legs', '["glutes","hamstrings","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_skierg', '滑雪机', 'SkiErg', '[]', 'back', '["triceps","core"]', 'machine', 'cardio', 'distance_time', 60, NULL, 0, 2000, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_smith_machine_bulgarian_split_squat', '史密斯保加利亚分腿蹲', 'Smith Machine Bulgarian Split Squat', '[]', 'legs', '["glutes","core"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_smith_machine_hip_thrust', '史密斯臀推', 'Smith Machine Hip Thrust', '[]', 'legs', '["hamstrings","core"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_smith_machine_reverse_lunge', '史密斯反向箭步蹲', 'Smith Machine Reverse Lunge', '[]', 'legs', '["glutes","hamstrings","core"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_smith_machine_romanian_deadlift', '史密斯罗马尼亚硬拉', 'Smith Machine Romanian Deadlift', '[]', 'legs', '["glutes","lower_back"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_smith_machine_split_squat', '史密斯分腿蹲', 'Smith Machine Split Squat', '[]', 'legs', '["glutes","core"]', 'machine', 'strength', 'weight_reps', 120, 20, 5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_spider_curl', '蜘蛛弯举', 'Spider Curl', '[]', 'arms', '["forearms"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_sprawl', '扑地起身', 'Sprawl', '[]', 'legs', '["core","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_squat_thrust', '深蹲提膝', 'Squat Thrust', '[]', 'core', '["quads","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_stability_ball_hamstring_curl', '瑞士球腘绳肌弯举', 'Stability Ball Hamstring Curl', '[]', 'legs', '["glutes","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_stair_climber', '爬楼机', 'Stair Climber', '["台阶机"]', 'legs', '[]', 'machine', 'cardio', 'time', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_standing_dumbbell_press', '站姿哑铃推举', 'Standing Dumbbell Press', '["站姿肩推"]', 'shoulders', '["triceps","core"]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, '站姿比坐姿更吃核心；两只哑铃分别推起，不要互相借力。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_standing_quad_stretch', '站姿股四头肌拉伸', 'Standing Quad Stretch', '[]', 'legs', '["glutes"]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_step_down', '台阶下步', 'Step-Down', '[]', 'legs', '["glutes","hamstrings","calves"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_step_up', '哑铃台阶上步', 'Step-Up', '[]', 'legs', '["glutes"]', 'dumbbell', 'strength', 'weight_reps', 120, 8, 2, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_superman', '超人式', 'Superman', '[]', 'back', '["glutes","upper_back","hamstrings"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_superman_hold', '超人式保持', 'Superman Hold', '[]', 'back', '["glutes","upper_back","hamstrings"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_swimming', '游泳', 'Swimming', '[]', 'back', '["front_delts"]', 'bodyweight', 'cardio', 'distance_time', 60, NULL, 0, 800, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_toe_touch', '仰卧摸脚', 'Toe Touch', '[]', 'core', '[]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_torso_twist_stretch', '躯干转体', 'Torso Twists', '[]', 'core', '["lats"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_towel_hamstring_curl', '毛巾腘绳肌弯举', 'Towel Hamstring Curl', '[]', 'legs', '["glutes","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_towel_pull_up', '毛巾引体向上', 'Towel Pull-up', '[]', 'back', '["biceps","forearms","upper_back"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_towel_row', '毛巾划船', 'Towel Row', '[]', 'back', '["biceps","upper_back","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_trap_bar_deadlift', '六角杠硬拉', 'Trap Bar Deadlift', '["陷阱杠硬拉"]', 'legs', '["quads","grip"]', 'barbell', 'strength', 'weight_reps', 120, 20, 2.5, NULL, '六角杠在重心正下方，是最容易学会的硬拉变式；背仍要中立。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_treadmill_incline_walk', '跑步机爬坡走', 'Treadmill Incline Walk', '["爬坡走","坡度快走"]', 'legs', '["glutes"]', 'machine', 'cardio', 'distance_time', 60, NULL, 0, 2000, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_typewriter_push_up', '打字机俯卧撑', 'Typewriter Push-up', '[]', 'chest', '["triceps","front_delts","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_v_up', 'V 字两头起', 'V-Up', '["两头起"]', 'core', '["quads"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_walking', '快走', 'Walking', '[]', 'legs', '[]', 'bodyweight', 'cardio', 'distance_time', 60, NULL, 0, 3000, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_wall_calf_stretch', '靠墙小腿拉伸', 'Wall Calf Stretch', '[]', 'legs', '[]', 'bodyweight', 'stretch', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_wall_handstand_push_up', '靠墙倒立撑', 'Wall Handstand Push-up', '[]', 'shoulders', '["triceps","core","chest"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, category, track_type, default_rest_sec, default_weight_kg, weight_increment, default_target_distance_m, instructions, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_wall_push_up', '靠墙俯卧撑', 'Wall Push-up', '["站立俯卧撑"]', 'chest', '["triceps","front_delts"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_wall_sit', '靠墙静蹲', 'Wall Sit', '[]', 'legs', '["glutes","core"]', 'bodyweight', 'strength', 'time', 60, NULL, 0, NULL, NULL, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_wall_walk', '爬墙', 'Wall Walk', '[]', 'shoulders', '["core","chest","triceps"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_chin_up', '负重反握引体向上', 'Weighted Chin-up', '["负重引体"]', 'arms', '["lats"]', 'bodyweight', 'strength', 'weight_reps', 90, NULL, 0, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_crunch', '负重卷腹', 'Weighted Crunch', '[]', 'core', '[]', 'barbell', 'strength', 'weight_reps', 60, 20, 2.5, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_push_up', '负重俯卧撑', 'Weighted Push-up', '[]', 'chest', '["triceps","core"]', 'bodyweight', 'strength', 'weight_reps', 120, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_russian_twist', '负重俄罗斯转体', 'Weighted Russian Twist', '[]', 'core', '["front_delts"]', 'dumbbell', 'strength', 'weight_reps', 60, 8, 2, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_wide_grip_lat_pulldown', '宽握高位下拉', 'Wide-Grip Lat Pulldown', '[]', 'back', '["biceps"]', 'cable', 'strength', 'weight_reps', 120, 10, 2.5, NULL, '宽握更吃背阔外侧；握太宽行程变短，肩也容易别着。', 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_wide_push_up', '宽距俯卧撑', 'Wide Push-up', '[]', 'chest', '["front_delts","triceps","core"]', 'bodyweight', 'strength', 'reps_only', 60, NULL, 0, NULL, NULL, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_worlds_greatest_stretch', '世界最伟大拉伸', 'World''s Greatest Stretch', '["最伟大拉伸"]', 'legs', '["glutes","hamstrings","upper_back"]', 'bodyweight', 'warmup', 'time', 30, NULL, 0, NULL, NULL, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_wrist_extension', '腕伸展', 'Wrist Extension', '["正握腕弯举"]', 'arms', '[]', 'dumbbell', 'strength', 'weight_reps', 90, 8, 2, NULL, NULL, 1, 42, 1767225600000, 1767225600000, NULL);

COMMIT;

-- 自检：执行后应各返回 351
--   SELECT COUNT(*) FROM exercise WHERE is_builtin = 1;
--   SELECT muscle_group, COUNT(*) FROM exercise WHERE is_builtin = 1 GROUP BY muscle_group;
