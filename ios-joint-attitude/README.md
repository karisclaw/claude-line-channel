# iOS 野外節理位態量測與統計分析 App

以 iPhone 量測地表露頭不連續面（節理／層面／斷層／葉理）位態，
支援野外紀錄與節理組群集分析，供 DFN 建模與邊坡／岩體分類使用。
離線優先。

## 目前進度

| 階段 | 內容 | 狀態 |
|---|---|---|
| **A1** | 位態座標轉換核心 + 單元測試 | ✅ 完成 |
| **A2** | 取樣、靜止偵測、磁干擾品管、校正流程 | ✅ 完成，待檢視 |
| A3 | LiDAR 非接觸式量測（ARKit + RANSAC） | 尚未開始 |
| **B1** | 資料模型（值型別 + SwiftData） | ✅ 完成，待檢視 |
| **B2** | 野外紀錄流程（單手、手套模式、外接鍵） | ✅ 完成，待檢視 |
| **C1** | 投影與等值線（Schmidt/Wulff、Kamb 密度） | ✅ 完成，待檢視 |
| C2 | 分組演算法（fuzzy c-means、密度法、K 的決定） | 尚未開始 |
| C3 | 每組統計（Fisher、Woodcock、Terzaghi、DFN 參數） | 尚未開始 |
| C4 | 圖形（立體投影、玫瑰圖、Woodcock 圖） | 尚未開始 |
| D | 匯出（CSV/GeoJSON/KML/PDF/zip） | 尚未開始 |

分階段交付，每階段結束停下來檢視。**目前停在 C1 結束**。
A1 的六個地質慣例問題已確認，決策紀錄在 `docs/conventions.md`。

## 結構

```
ios-joint-attitude/
├── GeoStructuralKit/
│   ├── Sources/OrientationCore/     A1+A2 位態與取樣，Foundation only
│   ├── Sources/FieldRecord/         B 的值型別，Foundation only
│   ├── Sources/FieldRecordStore/    SwiftData @Model，整檔 #if canImport(SwiftData)
│   ├── Sources/FieldSession/        B2 紀錄流程狀態機，Foundation only
│   ├── Sources/FieldUI/             SwiftUI 畫面，整檔 #if canImport(SwiftUI)
│   ├── Sources/FabricAnalysis/      C 群集分析，Foundation only
│   └── Tests/
├── docs/conventions.md        地質與座標慣例決策紀錄（含對原規格的一處修正）
└── tools/reference_check.py   獨立的 Python 參考實作，交叉驗證 Swift 的數學
```

`GeoStructuralKit` 不 import UIKit、SwiftUI、CoreMotion、CoreLocation 或 ARKit，
只吃四元數、向量與角度這些純數字。App 層負責跟感測器打交道，
把結果餵進來。因此整包可以在任何平台（含 Linux CI）跑測試。

## C1 已實作

- `StereonetProjection` — 等面積（Schmidt）與等角（Wulff），正反投影互為逆函數
- `Stereonet` — 極點／線狀構造投影、大圓跡線、小圓（α95 錐）、原週圓；
  **資料點與曲線用不同的摺疊方式**
- `KambParameters` — 計數圓大小（兩條獨立推導一致到 5.5e-17）、σ、權重與其矩
- `KambDensity` — 密度場與單點密度，全程軸性
- `UniformAxialSample` — 黃金角螺旋，嚴格等面積，用於驗證歸一化

## B2 已實作

- `MeasurementRecorder` — 一顆按鍵的狀態機：閒置→靜止→取樣→複查→儲存；
  **取樣中按第二下是取消，不是重新開始**
- `ReviewPolicy` — 旗標只收回「不看螢幕就確認」這條路，**永不阻止儲存**
- `MeasurementWarning` — 磁干擾／貼合面不一致／分散過大／取樣率不足／無定位／描述矛盾
- `MeasurementContext` — 位置與磁環境，在**叢集結束時**快照而非確認時
- `ControlSizing` — 手套模式的尺寸與單手拇指可及範圍
- `FieldUI` — 薄 SwiftUI 層 + 外接鍵接線（**未執行過**）

## B1 已實作

- `MeasurementRecord` / `StationRecord` / `ProjectRecord` — 純值型別，可測、可匯出
- ISRM 描述欄位 — 粗糙度（I–IX + JRC）、張開度、充填物、風化（W1–W6）、
  **含水（無充填／有充填兩張表，各 I–V，不可混淆）**、延續性、間距、端點；
  **每個級距界線都寫成數值範圍並有測試釘住**
- `DiscontinuityType` — 15 種標準類型 + `other(String)`；帶狀類型另有厚度欄位
- `SurveyGeometry` / `SamplingElement` — 測線／鑽孔／測窗／trace map／3D 表面模型／選擇性；
  一個 `samplingEfficiency(for:)` 統管三種幾何（線用 `|pole·s|`、面用 `|pole×m|`、
  3D 用面積加權），權重上限與盲區政策留給 C
- `ApertureObservation` 等 — 區分「量測值」與「目測分級」，不壓平成同一個欄位
- `SurveyGeometry` — scanline / window / selective，供 Terzaghi 修正
- `CarryForwardPolicy` — 複製上一筆設定，並明確規定六件永不繼承的東西
- `MeasurementLocation` — 包含 `CLLocation` 負精度代表無效的處理
- `FieldRecordStore` — SwiftData `@Model`，每個模型存「一個 blob + 幾個查詢欄」

## A2 已實作

- `MotionSample` — `CMDeviceMotion` 一帧的純資料形式（姿態、使用者加速度、角速度）
- `StillnessDetector` — 滑動視窗靜止偵測，用加速度**向量**標準差 + 陀螺儀峰值
- `BurstCollector` — 靜止後連續取樣的狀態機，收集中移動則整批丟棄重來；
  輸出平均位態、角度標準差、實際到達率
- `MagneticEnvironment` / `MagneticAssessment` — 場強與校正精度判定磁干擾，
  並說明它只影響方位不影響傾角
- `CalibrationCheck` — 水平／垂直／任意參考面檢核，誤差拆成重力與磁力兩部分
- `MagnetometerCoverage` — 8 字形校正的八分區覆蓋率
- `PlacementCrossCheck` — 由接觸衝量交叉檢查貼合面，**只警告不自動切換**

## A1 已實作

- `Vector3` / `Quaternion` — NWU 世界座標系，含 CoreMotion `CMQuaternion` 的分量順序橋接
- `PlaneOrientation` — 面狀構造：傾角／傾向／走向（右手定則）、朝上法向量、下半球極點、
  傾向線、走向線、視傾角、兩面夾角、兩面交線、垂直面的確定形式與 180° 替代描述
- `LineOrientation` — 線狀構造：trend／plunge、與面的夾角、面內 rake
- `DeviceAttitude` — 裝置姿態 → 位態（接觸式用 `+Z`，線狀構造用 `−Y`，軸可切換）
- `ReferenceFrame` — ARKit `.gravityAndHeading` 與 ENU 轉入 NWU
- `QuadrantBearing` / `CompassQuadrant` — 象限記法 `N30°E, 45°SE` 的產生與解析
- `MagneticDeclination` — 真北／磁北互轉，磁偏角東偏為正
- `DevicePlacement` / `DeviceEdge` / `MeasurementGeometry` — 以野外動作命名的手機擺放方式，
  量測前選擇並隨紀錄儲存
- `AttitudeConvention` — 慣例版本章，供紀錄標記
- `SymmetricMatrix3` — 方位張量與 Jacobi 特徵分解（A2 的平均與 C3 的 Woodcock 共用）
- `AxialStatistics` — 一次取樣的軸性平均與離散度

退化情況一律打旗標而不是硬給數字：水平面沒有傾向、垂直線沒有 trend、
垂直面的傾向有 ±180° 二義性。

## 跑測試

```sh
cd GeoStructuralKit
swift test
```

需要 Swift 6 toolchain（Xcode 16+，或 Linux 上的 swift.org toolchain）。

**注意**：撰寫此階段的環境無法安裝 Swift toolchain（網路政策擋掉 swift.org 下載），
因此 `swift test` **尚未實際執行過**。所有數學與每一個測試的期望值，
都先用 `tools/reference_check.py`（逐行對照的 Python 移植版）跑過驗證。
該腳本與 Swift 任一方改動時，另一方與兩邊的期望值都要同步：

```sh
python3 tools/reference_check.py
```

請在有 Xcode 的機器上跑一次 `swift test`；若有編譯錯誤請貼給我，
數值本身應該是對的。

## 測試涵蓋

| 測試 | 內容 |
|---|---|
| `testRoundTripFromSynthesizedAttitudeMeetsAccuracyRequirement` | 9 傾角 × 9 傾向 × 4 手機轉角合成四元數反推，規格要求 < 0.01°，實測最差 2.8e-14° |
| `testUpwardNormalLeansTowardTheDipDirection` | 用獨立定義的坡面釘住法向量方向，即第 2 節的修正 |
| `testResultIsInvariantUnderPhoneRollAboutTheFaceNormal` | 手機貼在岩面上怎麼轉都不影響結果 |
| `testMeasuringEitherFaceGivesTheSameAttitude` | 量岩面正面或反面（懸垂面）結果相同 |
| `testVerticalPlaneDescriptionsAlwaysDenoteTheSamePlane` | 垂直面傾向可能因雜訊翻 180°，但它指的平面不變；`canonicalized` 消除跳動 |
| `testPlaneJustOffVerticalIsRecoveredFromEitherFace` | 89.7° 的面從任一面量都得到正確位態 |
| `testDipDirectionIsContinuousApproachingVertical` | 88° → 90° 傾向連續 |
| `testPoleTrendAndPlungeMatchTheStandardStereonetRelation` | 極點的教科書關係 `trend = dipDir+180`、`plunge = 90−dip` |
| `testApparentDipEqualsThePlungeOfTheSectionIntersection` | 視傾角公式用「與垂直剖面的交線」獨立驗證，不共用程式碼 |
| `testIntersectionLiesInBothPlanes` | 900 組掃描，交線必同時位於兩面內 |
| `testEigenDecompositionSatisfiesItsDefiningProperties` | 200 個矩陣驗 `Av = λv`、正交性、跡不變 |
| `testExactlyHorizontalNormalGivesTheSameAttitudeFromEitherFace` | 垂直分量恰為 `0.0` 時 `0.0`/`-0.0` 不影響結果 |
| `testDegenerateQuaternionIsRejectedRatherThanReadAsHorizontal` | 壞掉的感測器樣本回傳 nil，不會被當成水平節理 |
| `testQuadrantNotationRoundTripsForEveryInclinedPlane` | 象限記法 1080 組字串往返 |
| `testDipQuadrantAlongTheStrikeIsRejected` | 字母落在走向線上時拒絕解析，不憑空猜傾向 |
| `testDeclinationDerivedFromAHeadingPair` | 磁偏角跨越北方 0/360 時仍正確（單純相減會得到 350 而不是 −10）|
| `testOutwardNormalPointsAwayFromTheRockNotIntoIt` | 手機立在水平面上時外法向量必須朝上 —— 位態斷言抓不到符號錯誤 |
| `testOnlyThreeContactAxesCanChangeAnAttitude` | 六種貼法收斂成三個位態 |
| `testSteadyRockingIsNotMistakenForStillness` | 等幅度擺動：幅度標準差 8.9e-18 g（會誤判靜止）vs 向量標準差 0.051 g |
| `testMovementDuringTheBurstDiscardsItAndStartsAgain` | 叢集中途移動整批丟棄並自動重來 |
| `testShortfallInSampleRateIsFlaggedNotHidden` | 到達率不足時打旗標而非隱藏 |
| `testNegativeHeadingAccuracyMeansInvalidNotExcellent` | CoreLocation 用負值表示無效，不是精度極好 |
| `testGentlePlacementProducesNoOpinion` | 輕放時交叉檢查不表態，不憑空指定軸 |
| `testTheCheckOffersNoWayToOverrideTheSelection` | 交叉檢查沒有任何修正 API |
| `testClassesTileTheirScaleWithoutGapsOrOverlaps` | ISRM 級距不重疊不留縫（原張開度表有重疊） |
| `testTheAttitudeIsNeverCarriedForward` | 三種 carry-forward 政策都不繼承位態 |
| `testNegativeAccuracyMeansNoFixNotAPerfectOne` | `CLLocation` 負精度代表無定位，不是精度極佳 |
| `testEstimatedObservationHasNoMeasuredValue` | 目測分級不會憑空產生一個數字 |
| `testSeepageObservationCarriesWhichScaleWasUsed` | 兩張含水表共用評等號，存下來的值自己說明來自哪張 |
| `testSeepageScaleIsCheckedAgainstTheRecordedFilling` | 用錯表會被回報 |
| `testTheOverlappingPublishedApertureClassIsStorableButNeverDerived` | 原表重疊的 `wide` 可存不可導出 |
| `testThePlaneAndLineFormulasInvertEachOther` | 面／線公式互為顛倒 —— B1 第一版的真實錯誤 |
| `testWindowEfficiencyIsTheSineOfTheDihedralAngle` | 測窗效率 = sin(兩面夾角)，以 trace 間距獨立驗證 |
| `testOneFacetSurfaceModelMatchesTheWindowExactly` | 面積加權法單 facet 時與測窗公式完全相同（1.1e-16）|
| `testSurfaceModelShowsTheBlindZoneOfASingleOrientationExposure` | 單一朝向露頭對平行節理組全盲 |
| `testSecondPressWhileMeasuringCancelsRatherThanRestarting` | 取樣中第二次按壓是取消 —— 取消可復原，遺失量測不行 |
| `testAFlaggedMeasurementRefusesABlindPressButStillSaves` | 旗標收回盲操作，但螢幕上確認永遠能存 |
| `testTheContextIsSnapshottedWhenTheBurstFinishesNotAtConfirmation` | 走開才確認時，定位仍屬於原本那條節理 |
| `testAutoConfirmStillStopsForAFlaggedMeasurement` | 自動確認仍會為旗標停下 |
| `testRepeatPressesWithinTheIntervalAreIgnored` | 鍵盤連發與冷手雙擊不會取消剛開始的量測 |
| `testTheTwoDerivationsOfTheCountingCircleAgree` | Kamb 計數圓的統計推導與幾何推導一致（1e-12）|
| `testAUniformSampleAveragesToTheSigmaCriterion` | 均勻樣本的密度場平均值回到 3σ —— 歸一化的端對端檢核 |
| `testDensitySaturatesOnceTheSetIsTighterThanTheCountingCircle` | 密度封頂在 N/σ，截頂的峰值不代表集中度 |
| `testFlippingHalfTheInputLeavesTheFieldUnchanged` | 翻轉一半樣本後密度場必須位元相同 |
| `testNumericalMomentsReproduceTheClosedFormForTheHardCircle` | 平滑權重的 σ 尺度建立在能還原解析式的數值矩上 |
| `testSmallCircleCrossingTheHorizonSplitsIntoTwoArcs` | 跨越地平面的錐面分成兩段，不可連起來 |
| `testSignFlippedSamplesGiveTheSameMean` | 軸性平均：符號相反的樣本不會相消（對照組算術平均只剩 0.021） |
| `testGirdleFabricEigenvalues` | 環帶型 fabric 的特徵值退化情況 |
| `testARKitMappingPreservesHandedness` | ARKit 轉換行列式為 +1，不鏡射 |
