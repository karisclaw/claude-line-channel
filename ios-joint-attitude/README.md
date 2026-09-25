# iOS 野外節理位態量測與統計分析 App

以 iPhone 量測地表露頭不連續面（節理／層面／斷層／葉理）位態，
支援野外紀錄與節理組群集分析，供 DFN 建模與邊坡／岩體分類使用。
離線優先。

## 目前進度

| 階段 | 內容 | 狀態 |
|---|---|---|
| **A1** | 位態座標轉換核心 + 單元測試 | ✅ 完成，待檢視 |
| A2 | 取樣、靜止偵測、磁干擾品管、校正流程 | 尚未開始 |
| A3 | LiDAR 非接觸式量測（ARKit + RANSAC） | 尚未開始 |
| B | SwiftData 資料模型與野外紀錄 UI | 尚未開始 |
| C | 群集分析（投影、分組、統計、圖形） | 尚未開始 |
| D | 匯出（CSV/GeoJSON/KML/PDF/zip） | 尚未開始 |

分階段交付，每階段結束停下來檢視。**目前停在 A1 結束**，
`docs/conventions.md` 末尾有六個待確認的地質慣例問題。

## 結構

```
ios-joint-attitude/
├── GeoStructuralKit/          Swift package，純運算，不依賴 UI 或任何 framework
│   ├── Sources/OrientationCore/
│   └── Tests/OrientationCoreTests/
├── docs/conventions.md        地質與座標慣例決策紀錄（含對原規格的一處修正）
└── tools/reference_check.py   獨立的 Python 參考實作，交叉驗證 Swift 的數學
```

`GeoStructuralKit` 不 import UIKit、SwiftUI、CoreMotion、CoreLocation 或 ARKit，
只吃四元數、向量與角度這些純數字。App 層負責跟感測器打交道，
把結果餵進來。因此整包可以在任何平台（含 Linux CI）跑測試。

## A1 已實作

- `Vector3` / `Quaternion` — NWU 世界座標系，含 CoreMotion `CMQuaternion` 的分量順序橋接
- `PlaneOrientation` — 面狀構造：傾角／傾向／走向（右手定則）、朝上法向量、下半球極點、
  傾向線、走向線、視傾角、兩面夾角、兩面交線、垂直面的確定形式與 180° 替代描述
- `LineOrientation` — 線狀構造：trend／plunge、與面的夾角、面內 rake
- `DeviceAttitude` — 裝置姿態 → 位態（接觸式用 `+Z`，線狀構造用 `−Y`，軸可切換）
- `ReferenceFrame` — ARKit `.gravityAndHeading` 與 ENU 轉入 NWU
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
| `testSignFlippedSamplesGiveTheSameMean` | 軸性平均：符號相反的樣本不會相消（對照組算術平均只剩 0.021） |
| `testGirdleFabricEigenvalues` | 環帶型 fabric 的特徵值退化情況 |
| `testARKitMappingPreservesHandedness` | ARKit 轉換行列式為 +1，不鏡射 |
