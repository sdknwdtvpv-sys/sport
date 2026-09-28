-- 练了么 · 内置动作库种子数据（自动生成，请勿手改）
-- 修改请编辑 seed/parts/*.json 后重新运行：node seed/build.mjs
-- 动作总数：165
-- 生成时间戳：1767225600000（固定值，保证可复现）

BEGIN TRANSACTION;

-- 幂等：只清理内置动作，用户自定义动作（is_builtin = 0）与其历史记录不受影响
DELETE FROM exercise WHERE is_builtin = 1;

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_bb_bench_press', '杠铃卧推', 'Barbell Bench Press', '["平板卧推","卧推","bp","bench"]', 'chest', '["triceps","front_delts"]', 'barbell', 'weight_reps', 120, 40, 2.5, 1, 100, 1767225600000, 1767225600000, NULL),
  ('ex_bb_incline_bench_press', '上斜杠铃卧推', 'Incline Barbell Bench Press', '["上斜卧推","上斜杠铃推胸"]', 'chest', '["front_delts","triceps"]', 'barbell', 'weight_reps', 120, 35, 2.5, 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_bb_decline_bench_press', '下斜杠铃卧推', 'Decline Barbell Bench Press', '["下斜卧推"]', 'chest', '["triceps"]', 'barbell', 'weight_reps', 120, 35, 2.5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_smith_bench_press', '史密斯卧推', 'Smith Machine Bench Press', '["史密斯平板卧推"]', 'chest', '["triceps","front_delts"]', 'machine', 'weight_reps', 120, 30, 5, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_smith_incline_press', '史密斯上斜卧推', 'Smith Machine Incline Press', '[]', 'chest', '["front_delts","triceps"]', 'machine', 'weight_reps', 120, 25, 5, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_bb_floor_press', '地板卧推', 'Barbell Floor Press', '["地板推胸"]', 'chest', '["triceps"]', 'barbell', 'weight_reps', 120, 40, 2.5, 1, 46, 1767225600000, 1767225600000, NULL),
  ('ex_db_bench_press', '哑铃卧推', 'Dumbbell Bench Press', '["平板哑铃卧推","哑铃平板卧推"]', 'chest', '["triceps","front_delts"]', 'dumbbell', 'weight_reps', 120, 12, 2, 1, 95, 1767225600000, 1767225600000, NULL),
  ('ex_db_incline_press', '上斜哑铃卧推', 'Incline Dumbbell Press', '["上斜哑铃推举"]', 'chest', '["front_delts","triceps"]', 'dumbbell', 'weight_reps', 120, 10, 2, 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_db_decline_press', '下斜哑铃卧推', 'Decline Dumbbell Press', '[]', 'chest', '["triceps"]', 'dumbbell', 'weight_reps', 120, 10, 2, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_db_close_grip_press', '窄距哑铃卧推', 'Close-Grip Dumbbell Press', '["窄距哑铃推胸"]', 'chest', '["triceps"]', 'dumbbell', 'weight_reps', 120, 10, 2, 1, 44, 1767225600000, 1767225600000, NULL),
  ('ex_db_swissball_press', '瑞士球哑铃卧推', 'Swiss Ball Dumbbell Press', '["健身球卧推"]', 'chest', '["triceps","core"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_db_fly', '哑铃飞鸟', 'Dumbbell Fly', '["平板飞鸟","飞鸟"]', 'chest', '["shoulders"]', 'dumbbell', 'weight_reps', 90, 8, 2, 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_db_incline_fly', '上斜哑铃飞鸟', 'Incline Dumbbell Fly', '["上斜飞鸟"]', 'chest', '["shoulders"]', 'dumbbell', 'weight_reps', 90, 6, 2, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_cable_crossover', '绳索夹胸', 'Cable Crossover', '["龙门架夹胸","绳索飞鸟","龙门架飞鸟"]', 'chest', '["shoulders"]', 'cable', 'weight_reps', 90, 10, 2.5, 1, 82, 1767225600000, 1767225600000, NULL),
  ('ex_cable_low_fly', '低位绳索夹胸', 'Low Cable Crossover', '["低位夹胸","下斜绳索夹胸"]', 'chest', '[]', 'cable', 'weight_reps', 90, 10, 2.5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_cable_high_fly', '高位绳索夹胸', 'High Cable Crossover', '["高位夹胸","上斜绳索夹胸"]', 'chest', '[]', 'cable', 'weight_reps', 90, 10, 2.5, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_machine_pec_deck', '蝴蝶机夹胸', 'Pec Deck Fly', '["蝴蝶机","夹胸机"]', 'chest', '["shoulders"]', 'machine', 'weight_reps', 90, 25, 5, 1, 80, 1767225600000, 1767225600000, NULL),
  ('ex_machine_chest_press', '器械推胸', 'Chest Press Machine', '["坐姿推胸"]', 'chest', '["triceps","front_delts"]', 'machine', 'weight_reps', 120, 30, 5, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_machine_incline_press', '上斜器械推胸', 'Incline Chest Press Machine', '[]', 'chest', '["front_delts","triceps"]', 'machine', 'weight_reps', 120, 25, 5, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_machine_single_chest_press', '单臂器械推胸', 'Single-Arm Chest Press', '[]', 'chest', '["core"]', 'machine', 'weight_reps', 90, 15, 5, 1, 30, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_dip', '双杠臂屈伸', 'Chest Dip', '["双杠","臂屈伸","双杠撑"]', 'chest', '["triceps","front_delts"]', 'bodyweight', 'reps_only', 120, NULL, 0, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_dip', '负重双杠臂屈伸', 'Weighted Dip', '["负重双杠"]', 'chest', '["triceps","front_delts"]', 'bodyweight', 'weight_reps', 120, 10, 2.5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_push_up', '俯卧撑', 'Push-up', '["伏地挺身","掌上压"]', 'chest', '["triceps","front_delts","abs"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_incline_push_up', '上斜俯卧撑', 'Incline Push-up', '["高台俯卧撑"]', 'chest', '["triceps","front_delts"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_decline_push_up', '下斜俯卧撑', 'Decline Push-up', '["脚抬高俯卧撑"]', 'chest', '["front_delts","triceps"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_db_pullover', '哑铃仰卧屈臂上拉', 'Dumbbell Pullover', '["仰卧上拉","上拉"]', 'chest', '["lats","triceps"]', 'dumbbell', 'weight_reps', 90, 15, 2, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_pull_up', '引体向上', 'Pull-up', '["正握引体","引体"]', 'back', '["lats","biceps"]', 'bodyweight', 'reps_only', 120, NULL, 0, 1, 95, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_pull_up', '负重引体向上', 'Weighted Pull-up', '["负重引体"]', 'back', '["lats","biceps"]', 'bodyweight', 'weight_reps', 120, 10, 2.5, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_chin_up', '反握引体向上', 'Chin-up', '["反手引体","窄握引体"]', 'back', '["lats","biceps"]', 'bodyweight', 'reps_only', 120, NULL, 0, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_assisted_pull_up', '辅助引体向上', 'Assisted Pull-up', '["引体辅助","器械引体"]', 'back', '["lats","biceps"]', 'machine', 'assisted_reps', 90, 30, 5, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_lat_pulldown', '高位下拉', 'Lat Pulldown', '["下拉","宽握下拉"]', 'back', '["lats","biceps"]', 'cable', 'weight_reps', 90, 40, 2.5, 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_close_grip_pulldown', '窄握高位下拉', 'Close-Grip Lat Pulldown', '["窄距下拉","V把下拉"]', 'back', '["lats","biceps"]', 'cable', 'weight_reps', 90, 40, 2.5, 1, 64, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_grip_pulldown', '反握高位下拉', 'Reverse-Grip Lat Pulldown', '["反手下拉"]', 'back', '["lats","biceps"]', 'cable', 'weight_reps', 90, 35, 2.5, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_pulldown', '单臂高位下拉', 'Single-Arm Lat Pulldown', '[]', 'back', '["lats","biceps"]', 'cable', 'weight_reps', 90, 20, 2.5, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_seated_cable_row', '坐姿绳索划船', 'Seated Cable Row', '["坐姿划船","绳索划船"]', 'back', '["lats","traps","biceps"]', 'cable', 'weight_reps', 90, 35, 2.5, 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_cable_row', '单臂绳索划船', 'Single-Arm Cable Row', '["单臂坐姿划船"]', 'back', '["lats","biceps"]', 'cable', 'weight_reps', 90, 20, 2.5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_wide_cable_row', '宽握坐姿划船', 'Wide-Grip Cable Row', '["宽握划船"]', 'back', '["traps","rear_delts","lats"]', 'cable', 'weight_reps', 90, 35, 2.5, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_bb_row', '杠铃划船', 'Barbell Row', '["俯身划船","划船"]', 'back', '["lats","traps","biceps","lower_back"]', 'barbell', 'weight_reps', 120, 40, 2.5, 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_grip_bb_row', '反握杠铃划船', 'Reverse-Grip Barbell Row', '["反手划船"]', 'back', '["lats","biceps","lower_back"]', 'barbell', 'weight_reps', 120, 35, 2.5, 1, 46, 1767225600000, 1767225600000, NULL),
  ('ex_pendlay_row', '潘德雷划船', 'Pendlay Row', '["触地划船"]', 'back', '["lats","traps","lower_back"]', 'barbell', 'weight_reps', 120, 40, 2.5, 1, 45, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_t_bar_row', 'T杠划船', 'T-Bar Row', '["T杆划船"]', 'back', '["lats","traps","biceps"]', 'barbell', 'weight_reps', 120, 30, 2.5, 1, 68, 1767225600000, 1767225600000, NULL),
  ('ex_wide_t_bar_row', '宽握T杠划船', 'Wide-Grip T-Bar Row', '[]', 'back', '["shoulders"]', 'barbell', 'weight_reps', 120, 30, 2.5, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_one_arm_db_row', '单臂哑铃划船', 'One-Arm Dumbbell Row', '["哑铃划船"]', 'back', '["lats","biceps","obliques"]', 'dumbbell', 'weight_reps', 90, 12, 2, 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_two_arm_db_row', '双臂哑铃划船', 'Two-Arm Dumbbell Row', '["俯身双臂划船"]', 'back', '["arms"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_chest_supported_row', '胸托划船', 'Chest-Supported Row', '["海豹划船","上斜凳划船"]', 'back', '["lats","traps","biceps"]', 'machine', 'weight_reps', 90, 30, 5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_machine_row', '器械划船', 'Seated Row Machine', '["坐姿器械划船"]', 'back', '["lats","biceps"]', 'machine', 'weight_reps', 90, 35, 5, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_machine_row', '单臂器械划船', 'Single-Arm Machine Row', '[]', 'back', '["arms"]', 'machine', 'weight_reps', 90, 20, 5, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_inverted_row', '澳式划船', 'Inverted Row', '["反向划船","自重划船"]', 'back', '["lats","biceps","abs"]', 'bodyweight', 'reps_only', 90, NULL, 0, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_deadlift', '硬拉', 'Deadlift', '["屈腿硬拉","传统硬拉","dl"]', 'back', '["hamstrings","glutes","lower_back","traps"]', 'barbell', 'weight_reps', 180, 50, 2.5, 1, 98, 1767225600000, 1767225600000, NULL),
  ('ex_sumo_deadlift', '相扑硬拉', 'Sumo Deadlift', '["宽站距硬拉"]', 'back', '["glutes","quads","lower_back"]', 'barbell', 'weight_reps', 180, 50, 2.5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_rack_pull', '架上硬拉', 'Rack Pull', '["半程硬拉"]', 'back', '["traps","lower_back","glutes"]', 'barbell', 'weight_reps', 180, 60, 2.5, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_straight_arm_pulldown', '直臂下压', 'Straight-Arm Pulldown', '["直臂下拉"]', 'back', '["lats","triceps"]', 'cable', 'weight_reps', 60, 20, 2.5, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_face_pull', '面拉', 'Face Pull', '["绳索面拉"]', 'back', '["rear_delts","traps"]', 'cable', 'weight_reps', 60, 15, 2.5, 1, 66, 1767225600000, 1767225600000, NULL),
  ('ex_bb_shrug', '杠铃耸肩', 'Barbell Shrug', '["耸肩"]', 'back', '["traps","forearms"]', 'barbell', 'weight_reps', 90, 40, 2.5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_db_shrug', '哑铃耸肩', 'Dumbbell Shrug', '[]', 'back', '["traps","forearms"]', 'dumbbell', 'weight_reps', 90, 20, 2, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_farmer_walk', '农夫行走', 'Farmer''s Walk', '["农夫走","负重行走"]', 'back', '["forearms","traps","abs"]', 'dumbbell', 'weight_reps', 120, 20, 2, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_bb_squat', '杠铃深蹲', 'Barbell Back Squat', '["深蹲","后蹲","squat"]', 'legs', '["glutes","core","lower_back"]', 'barbell', 'weight_reps', 180, 40, 2.5, 1, 100, 1767225600000, 1767225600000, NULL),
  ('ex_front_squat', '前蹲', 'Front Squat', '["颈前深蹲"]', 'legs', '["glutes","abs"]', 'barbell', 'weight_reps', 180, 30, 2.5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_goblet_squat', '高脚杯深蹲', 'Goblet Squat', '["杯式深蹲","哑铃深蹲"]', 'legs', '["glutes","abs"]', 'dumbbell', 'weight_reps', 90, 16, 2, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_smith_squat', '史密斯深蹲', 'Smith Machine Squat', '[]', 'legs', '[]', 'machine', 'weight_reps', 120, 40, 5, 1, 58, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_hack_squat', '哈克深蹲', 'Hack Squat', '["倒蹬深蹲"]', 'legs', '["glutes"]', 'machine', 'weight_reps', 120, 40, 5, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_box_squat', '箱式深蹲', 'Box Squat', '["坐箱深蹲"]', 'legs', '["glutes","lower_back"]', 'barbell', 'weight_reps', 150, 40, 2.5, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_pause_squat', '暂停深蹲', 'Pause Squat', '["停顿深蹲"]', 'legs', '["glutes","abs"]', 'barbell', 'weight_reps', 180, 35, 2.5, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_bodyweight_squat', '徒手深蹲', 'Bodyweight Squat', '["自重深蹲","空蹲"]', 'legs', '[]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_leg_press', '腿举', 'Leg Press', '["倒蹬","腿推"]', 'legs', '["quads","glutes"]', 'machine', 'weight_reps', 120, 60, 5, 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_press', '单腿腿举', 'Single-Leg Press', '[]', 'legs', '["quads","glutes"]', 'machine', 'weight_reps', 120, 30, 5, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_bulgarian_split_squat', '保加利亚分腿蹲', 'Bulgarian Split Squat', '["分腿蹲","保加利亚蹲"]', 'legs', '["glutes","quads"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_static_lunge', '静态分腿蹲', 'Static Lunge', '["原地弓步蹲"]', 'legs', '["core"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 44, 1767225600000, 1767225600000, NULL),
  ('ex_walking_lunge', '箭步蹲', 'Walking Lunge', '["行走箭步蹲","弓步蹲"]', 'legs', '["glutes","quads","abs"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_lunge', '反向箭步蹲', 'Reverse Lunge', '["后撤步箭步蹲"]', 'legs', '["core"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_bb_lunge', '杠铃箭步蹲', 'Barbell Lunge', '[]', 'legs', '["core"]', 'barbell', 'weight_reps', 120, 30, 2.5, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_lateral_lunge', '侧向弓步', 'Lateral Lunge', '["侧弓步"]', 'legs', '[]', 'dumbbell', 'reps_only', 90, 8, 2, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_leg_extension', '腿屈伸', 'Leg Extension', '["坐姿腿屈伸","腿伸展"]', 'legs', '["quads"]', 'machine', 'weight_reps', 90, 25, 5, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_extension', '单腿腿屈伸', 'Single-Leg Extension', '[]', 'legs', '["quads"]', 'machine', 'weight_reps', 60, 15, 5, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_lying_leg_curl', '俯卧腿弯举', 'Lying Leg Curl', '["腿弯举"]', 'legs', '["hamstrings"]', 'machine', 'weight_reps', 90, 25, 5, 1, 76, 1767225600000, 1767225600000, NULL),
  ('ex_seated_leg_curl', '坐姿腿弯举', 'Seated Leg Curl', '[]', 'legs', '["hamstrings"]', 'machine', 'weight_reps', 90, 25, 5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_rdl', '罗马尼亚硬拉', 'Romanian Deadlift', '["rdl","直腿罗马尼亚"]', 'legs', '["hamstrings","glutes","lower_back"]', 'barbell', 'weight_reps', 120, 40, 2.5, 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_stiff_leg_deadlift', '直腿硬拉', 'Stiff-Leg Deadlift', '["直腿拉"]', 'legs', '["hamstrings","glutes","lower_back"]', 'barbell', 'weight_reps', 120, 40, 2.5, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_rdl', '单腿罗马尼亚硬拉', 'Single-Leg RDL', '["单腿硬拉"]', 'legs', '["hamstrings","glutes","obliques"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_hip_thrust', '臀推', 'Barbell Hip Thrust', '["杠铃臀推","臀冲"]', 'legs', '["glutes","hamstrings"]', 'barbell', 'weight_reps', 120, 40, 2.5, 1, 80, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_machine_hip_thrust', '器械臀推', 'Machine Hip Thrust', '[]', 'legs', '["glutes","hamstrings"]', 'machine', 'weight_reps', 120, 40, 5, 1, 46, 1767225600000, 1767225600000, NULL),
  ('ex_glute_bridge', '臀桥', 'Glute Bridge', '[]', 'legs', '["glutes","hamstrings"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_glute_bridge', '负重臀桥', 'Weighted Glute Bridge', '[]', 'legs', '["glutes","hamstrings"]', 'barbell', 'weight_reps', 90, 30, 2.5, 1, 36, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_glute_bridge', '单腿臀桥', 'Single-Leg Glute Bridge', '[]', 'legs', '["glutes","hamstrings"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 35, 1767225600000, 1767225600000, NULL),
  ('ex_hip_abduction', '髋外展', 'Hip Abduction', '["器械外展","坐姿外展"]', 'legs', '["abductors"]', 'machine', 'weight_reps', 60, 30, 5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_hip_adduction', '髋内收', 'Hip Adduction', '["器械内收","坐姿内收"]', 'legs', '["adductors"]', 'machine', 'weight_reps', 60, 30, 5, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_standing_calf_raise', '站姿提踵', 'Standing Calf Raise', '["提踵"]', 'legs', '["calves"]', 'machine', 'weight_reps', 60, 40, 5, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_seated_calf_raise', '坐姿提踵', 'Seated Calf Raise', '[]', 'legs', '["calves"]', 'machine', 'weight_reps', 60, 30, 5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_leg_press_calf_raise', '腿举提踵', 'Leg Press Calf Raise', '[]', 'legs', '["calves"]', 'machine', 'weight_reps', 60, 60, 5, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_single_leg_calf_raise', '单腿站姿提踵', 'Single-Leg Calf Raise', '["单腿提踵"]', 'legs', '["calves"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_smith_calf_raise', '史密斯提踵', 'Smith Machine Calf Raise', '[]', 'legs', '["calves"]', 'machine', 'weight_reps', 60, 40, 5, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_bb_ohp', '杠铃站姿推举', 'Overhead Press', '["站姿推举","推举","ohp","实力举","军事推举"]', 'shoulders', '["front_delts","triceps","abs"]', 'barbell', 'weight_reps', 150, 25, 2.5, 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_seated_bb_press', '坐姿杠铃推举', 'Seated Barbell Press', '["颈前推举"]', 'shoulders', '["front_delts","triceps"]', 'barbell', 'weight_reps', 150, 25, 2.5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_db_shoulder_press', '哑铃推举', 'Dumbbell Shoulder Press', '["坐姿哑铃推举","肩推","哑铃肩推"]', 'shoulders', '["front_delts","triceps"]', 'dumbbell', 'weight_reps', 120, 8, 2, 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_db_press', '单臂哑铃推举', 'One-Arm Dumbbell Press', '[]', 'shoulders', '["front_delts","obliques"]', 'dumbbell', 'weight_reps', 120, 10, 2, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_arnold_press', '阿诺德推举', 'Arnold Press', '["阿诺德"]', 'shoulders', '["front_delts","side_delts","triceps"]', 'dumbbell', 'weight_reps', 120, 8, 2, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_smith_shoulder_press', '史密斯推举', 'Smith Machine Shoulder Press', '[]', 'shoulders', '["front_delts","triceps"]', 'machine', 'weight_reps', 120, 20, 5, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_machine_shoulder_press', '器械推肩', 'Machine Shoulder Press', '["推肩机"]', 'shoulders', '["front_delts","triceps"]', 'machine', 'weight_reps', 120, 25, 5, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_handstand_push_up', '倒立撑', 'Handstand Push-up', '["靠墙倒立撑"]', 'shoulders', '["front_delts","triceps","abs"]', 'bodyweight', 'reps_only', 120, NULL, 0, 1, 20, 1767225600000, 1767225600000, NULL),
  ('ex_db_lateral_raise', '哑铃侧平举', 'Dumbbell Lateral Raise', '["侧平举","侧举"]', 'shoulders', '["side_delts"]', 'dumbbell', 'weight_reps', 60, 5, 2, 1, 95, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_cable_lateral_raise', '绳索侧平举', 'Cable Lateral Raise', '[]', 'shoulders', '["side_delts"]', 'cable', 'weight_reps', 60, 5, 2.5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_machine_lateral_raise', '器械侧平举', 'Machine Lateral Raise', '[]', 'shoulders', '["side_delts"]', 'machine', 'weight_reps', 60, 15, 5, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_cable_lateral', '单臂绳索侧平举', 'Single-Arm Cable Lateral Raise', '[]', 'shoulders', '["side_delts"]', 'cable', 'weight_reps', 60, 5, 2.5, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_lean_away_lateral', '斜托侧平举', 'Lean-Away Lateral Raise', '["单手斜托侧平举"]', 'shoulders', '["side_delts"]', 'dumbbell', 'weight_reps', 60, 6, 2, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_smith_lateral_raise', '史密斯侧平举', 'Smith Machine Lateral Raise', '[]', 'shoulders', '["side_delts"]', 'machine', 'weight_reps', 60, 10, 5, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_db_front_raise', '哑铃前平举', 'Dumbbell Front Raise', '["前平举"]', 'shoulders', '["front_delts"]', 'dumbbell', 'weight_reps', 60, 6, 2, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_bb_front_raise', '杠铃前平举', 'Barbell Front Raise', '[]', 'shoulders', '["front_delts"]', 'barbell', 'weight_reps', 60, 15, 2.5, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_cable_front_raise', '绳索前平举', 'Cable Front Raise', '[]', 'shoulders', '["front_delts"]', 'cable', 'weight_reps', 60, 7.5, 2.5, 1, 44, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_cable_front', '单臂绳索前平举', 'Single-Arm Cable Front Raise', '[]', 'shoulders', '["front_delts"]', 'cable', 'weight_reps', 60, 5, 2.5, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_bent_over_db_fly', '俯身哑铃飞鸟', 'Bent-Over Reverse Fly', '["反向飞鸟","后束飞鸟"]', 'shoulders', '["rear_delts","traps"]', 'dumbbell', 'weight_reps', 60, 5, 2, 1, 78, 1767225600000, 1767225600000, NULL),
  ('ex_bent_over_cable_fly', '俯身绳索飞鸟', 'Bent-Over Cable Fly', '["绳索反向飞鸟"]', 'shoulders', '["rear_delts","traps"]', 'cable', 'weight_reps', 60, 5, 2.5, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_pec_deck', '反向蝴蝶机', 'Reverse Pec Deck', '["反向蝴蝶机飞鸟","后束器械"]', 'shoulders', '["rear_delts","traps"]', 'machine', 'weight_reps', 60, 15, 5, 1, 66, 1767225600000, 1767225600000, NULL),
  ('ex_upright_row', '直立划船', 'Upright Row', '[]', 'shoulders', '["traps","side_delts","biceps"]', 'barbell', 'weight_reps', 90, 20, 2.5, 1, 52, 1767225600000, 1767225600000, NULL),
  ('ex_bb_curl', '杠铃弯举', 'Barbell Curl', '["弯举"]', 'arms', '["biceps","forearms"]', 'barbell', 'weight_reps', 90, 20, 2.5, 1, 90, 1767225600000, 1767225600000, NULL),
  ('ex_ez_bar_curl', 'EZ杠弯举', 'EZ-Bar Curl', '["曲杠弯举"]', 'arms', '["biceps","forearms"]', 'barbell', 'weight_reps', 90, 20, 2.5, 1, 68, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_bb_curl', '反握杠铃弯举', 'Reverse Barbell Curl', '["反握弯举"]', 'arms', '["forearms","biceps"]', 'barbell', 'weight_reps', 90, 15, 2.5, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_db_curl', '哑铃弯举', 'Dumbbell Curl', '["坐姿哑铃弯举"]', 'arms', '["biceps"]', 'dumbbell', 'weight_reps', 90, 8, 2, 1, 88, 1767225600000, 1767225600000, NULL),
  ('ex_db_alternating_curl', '哑铃交替弯举', 'Alternating Dumbbell Curl', '["交替弯举"]', 'arms', '["biceps"]', 'dumbbell', 'weight_reps', 90, 8, 2, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_hammer_curl', '锤式弯举', 'Hammer Curl', '["锤式"]', 'arms', '["biceps","forearms"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 82, 1767225600000, 1767225600000, NULL),
  ('ex_incline_hammer_curl', '斜托锤式弯举', 'Incline Hammer Curl', '[]', 'arms', '["biceps","forearms"]', 'dumbbell', 'weight_reps', 90, 8, 2, 1, 36, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_cable_hammer_curl', '绳索锤式弯举', 'Cable Hammer Curl', '["绳索锤式"]', 'arms', '["biceps","forearms"]', 'cable', 'weight_reps', 60, 15, 2.5, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_concentration_curl', '集中弯举', 'Concentration Curl', '[]', 'arms', '["biceps"]', 'dumbbell', 'weight_reps', 60, 8, 2, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_preacher_curl', '牧师凳弯举', 'Preacher Curl', '["斜托弯举","牧师椅弯举"]', 'arms', '["biceps"]', 'barbell', 'weight_reps', 90, 15, 2.5, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_incline_db_curl', '斜托哑铃弯举', 'Incline Dumbbell Curl', '["上斜弯举"]', 'arms', '["biceps"]', 'dumbbell', 'weight_reps', 90, 8, 2, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_zottman_curl', '佐特曼弯举', 'Zottman Curl', '[]', 'arms', '["biceps","forearms"]', 'dumbbell', 'weight_reps', 90, 8, 2, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_cable_curl', '绳索弯举', 'Cable Curl', '[]', 'arms', '["biceps"]', 'cable', 'weight_reps', 60, 15, 2.5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_cable_reverse_curl', '绳索反握弯举', 'Cable Reverse Curl', '[]', 'arms', '["forearms","biceps"]', 'cable', 'weight_reps', 60, 12.5, 2.5, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_machine_curl', '器械弯举', 'Machine Curl', '[]', 'arms', '["biceps"]', 'machine', 'weight_reps', 90, 20, 5, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_cable_pushdown', '绳索下压', 'Cable Triceps Pushdown', '["下压","三头下压"]', 'arms', '["triceps"]', 'cable', 'weight_reps', 60, 20, 2.5, 1, 92, 1767225600000, 1767225600000, NULL),
  ('ex_straight_bar_pushdown', '直杆下压', 'Straight-Bar Pushdown', '["横杆下压"]', 'arms', '["triceps"]', 'cable', 'weight_reps', 60, 20, 2.5, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_grip_pushdown', '反握下压', 'Reverse-Grip Pushdown', '[]', 'arms', '["triceps","forearms"]', 'cable', 'weight_reps', 60, 15, 2.5, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_pushdown', '单臂绳索下压', 'Single-Arm Pushdown', '[]', 'arms', '["triceps"]', 'cable', 'weight_reps', 60, 10, 2.5, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_close_grip_bench', '窄握卧推', 'Close-Grip Bench Press', '["窄距卧推","窄握推胸"]', 'arms', '["triceps","front_delts"]', 'barbell', 'weight_reps', 120, 30, 2.5, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_close_grip_smith', '窄握史密斯卧推', 'Close-Grip Smith Press', '[]', 'arms', '["triceps","front_delts"]', 'machine', 'weight_reps', 120, 25, 5, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_skull_crusher', '仰卧臂屈伸', 'Skull Crusher', '["碎颅式","法式卧推"]', 'arms', '["triceps"]', 'barbell', 'weight_reps', 90, 15, 2.5, 1, 70, 1767225600000, 1767225600000, NULL),
  ('ex_overhead_db_extension', '哑铃颈后臂屈伸', 'Overhead Dumbbell Extension', '["颈后臂屈伸"]', 'arms', '["triceps"]', 'dumbbell', 'weight_reps', 90, 10, 2, 1, 68, 1767225600000, 1767225600000, NULL),
  ('ex_overhead_cable_extension', '绳索过顶臂屈伸', 'Overhead Cable Extension', '["绳索颈后臂屈伸"]', 'arms', '["triceps"]', 'cable', 'weight_reps', 60, 15, 2.5, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_single_arm_overhead_cable', '单臂绳索过顶臂屈伸', 'Single-Arm Overhead Cable Extension', '[]', 'arms', '["triceps"]', 'cable', 'weight_reps', 60, 10, 2.5, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_machine_triceps_extension', '器械臂屈伸', 'Machine Triceps Extension', '[]', 'arms', '["triceps"]', 'machine', 'weight_reps', 60, 20, 5, 1, 48, 1767225600000, 1767225600000, NULL),
  ('ex_triceps_kickback', '哑铃俯身臂屈伸', 'Triceps Kickback', '["后踢腿","臂屈伸后踢"]', 'arms', '["triceps"]', 'dumbbell', 'weight_reps', 60, 5, 2, 1, 42, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_diamond_push_up', '窄握俯卧撑', 'Diamond Push-up', '["钻石俯卧撑"]', 'arms', '["triceps","front_delts"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 50, 1767225600000, 1767225600000, NULL),
  ('ex_wrist_curl', '腕弯举', 'Wrist Curl', '["正握腕弯举"]', 'arms', '["forearms"]', 'dumbbell', 'weight_reps', 60, 8, 2, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_wrist_curl', '反向腕弯举', 'Reverse Wrist Curl', '[]', 'arms', '["forearms"]', 'dumbbell', 'weight_reps', 60, 6, 2, 1, 35, 1767225600000, 1767225600000, NULL),
  ('ex_crunch', '卷腹', 'Crunch', '["仰卧卷腹"]', 'core', '["abs"]', 'bodyweight', 'reps_only', 45, NULL, 0, 1, 82, 1767225600000, 1767225600000, NULL),
  ('ex_sit_up', '仰卧起坐', 'Sit-up', '[]', 'core', '["abs","hip_flexors"]', 'bodyweight', 'weight_reps', 45, NULL, 0, 1, 65, 1767225600000, 1767225600000, NULL),
  ('ex_reverse_crunch', '反向卷腹', 'Reverse Crunch', '[]', 'core', '["abs"]', 'bodyweight', 'reps_only', 45, NULL, 0, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_side_crunch', '侧卷腹', 'Side Crunch', '["侧腹卷腹"]', 'core', '["obliques"]', 'bodyweight', 'weight_reps', 45, NULL, 0, 1, 45, 1767225600000, 1767225600000, NULL),
  ('ex_heel_touch', '仰卧交替触踝', 'Heel Touch', '["触踝"]', 'core', '["obliques"]', 'bodyweight', 'weight_reps', 45, NULL, 0, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_hanging_leg_raise', '悬垂举腿', 'Hanging Leg Raise', '["单杠举腿"]', 'core', '["abs","hip_flexors"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 72, 1767225600000, 1767225600000, NULL),
  ('ex_hanging_knee_raise', '悬垂举膝', 'Hanging Knee Raise', '["单杠举膝"]', 'core', '["abs","hip_flexors"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_hanging_side_leg_raise', '悬垂侧举腿', 'Hanging Side Leg Raise', '[]', 'core', '["obliques","hip_flexors"]', 'bodyweight', 'weight_reps', 60, NULL, 0, 1, 30, 1767225600000, 1767225600000, NULL),
  ('ex_lying_leg_raise', '仰卧举腿', 'Lying Leg Raise', '[]', 'core', '["abs","hip_flexors"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 60, 1767225600000, 1767225600000, NULL),
  ('ex_plank', '平板支撑', 'Plank', '["平板"]', 'core', '["abs","obliques"]', 'bodyweight', 'time', 60, NULL, 0, 1, 85, 1767225600000, 1767225600000, NULL),
  ('ex_weighted_plank', '负重平板支撑', 'Weighted Plank', '[]', 'core', '["abs","obliques"]', 'bodyweight', 'weight_time', 60, 5, 2.5, 1, 38, 1767225600000, 1767225600000, NULL),
  ('ex_side_plank', '侧平板', 'Side Plank', '["侧桥"]', 'core', '["obliques"]', 'bodyweight', 'time', 60, NULL, 0, 1, 55, 1767225600000, 1767225600000, NULL),
  ('ex_russian_twist', '俄罗斯转体', 'Russian Twist', '["俄式转体"]', 'core', '["obliques"]', 'bodyweight', 'reps_only', 45, NULL, 0, 1, 62, 1767225600000, 1767225600000, NULL),
  ('ex_cable_side_bend', '绳索侧屈', 'Cable Side Bend', '["绳索体侧屈"]', 'core', '["obliques"]', 'cable', 'weight_reps', 45, 15, 2.5, 1, 34, 1767225600000, 1767225600000, NULL),
  ('ex_ab_wheel', '健腹轮', 'Ab Wheel Rollout', '["腹肌轮","健腹轮跪姿"]', 'core', '["abs","hip_flexors"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 58, 1767225600000, 1767225600000, NULL),
  ('ex_cable_crunch', '绳索卷腹', 'Cable Crunch', '["跪姿绳索卷腹"]', 'core', '["abs"]', 'cable', 'weight_reps', 60, 25, 2.5, 1, 66, 1767225600000, 1767225600000, NULL),
  ('ex_machine_crunch', '器械卷腹', 'Machine Crunch', '[]', 'core', '["abs"]', 'machine', 'weight_reps', 60, 25, 5, 1, 45, 1767225600000, 1767225600000, NULL);

INSERT INTO exercise
  (id, name, name_en, aliases, muscle_group, secondary_muscles, equipment, track_type, default_rest_sec, default_weight_kg, weight_increment, is_builtin, popularity, created_at, updated_at, deleted_at)
VALUES
  ('ex_dead_bug', '死虫', 'Dead Bug', '["死虫式"]', 'core', '["abs"]', 'bodyweight', 'reps_only', 45, NULL, 0, 1, 40, 1767225600000, 1767225600000, NULL),
  ('ex_bird_dog', '鸟狗式', 'Bird Dog', '[]', 'core', '["lower_back","glutes"]', 'bodyweight', 'reps_only', 45, NULL, 0, 1, 32, 1767225600000, 1767225600000, NULL),
  ('ex_mountain_climber', '登山跑', 'Mountain Climber', '["登山者"]', 'core', '["abs","hip_flexors"]', 'bodyweight', 'time', 45, NULL, 0, 1, 42, 1767225600000, 1767225600000, NULL),
  ('ex_pallof_press', '帕洛夫抗旋转', 'Pallof Press', '["抗旋转推"]', 'core', '["obliques","abs"]', 'cable', 'weight_reps', 45, 10, 2.5, 1, 35, 1767225600000, 1767225600000, NULL),
  ('ex_back_extension', '山羊挺身', 'Back Extension', '["罗马椅挺身","背屈伸"]', 'core', '["lower_back","glutes"]', 'bodyweight', 'reps_only', 60, NULL, 0, 1, 60, 1767225600000, 1767225600000, NULL);

COMMIT;

-- 自检：执行后应各返回 165
--   SELECT COUNT(*) FROM exercise WHERE is_builtin = 1;
--   SELECT muscle_group, COUNT(*) FROM exercise WHERE is_builtin = 1 GROUP BY muscle_group;
