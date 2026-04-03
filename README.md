# Funded.E.A

**Professional-Grade, Self-Optimizing MetaTrader 5 Expert Advisor**

![Version](https://img.shields.io/badge/Version-2.0.0-blue) ![Platform](https://img.shields.io/badge/Platform-MetaTrader%205%20(MQL5)-brightgreen) ![Asset](https://img.shields.io/badge/Asset-XAUUSD%20(Gold)-orange) 

**Funded.E.A** is a specialized Expert Advisor (EA) built explicitly to pass proprietary firm challenges (e.g., FTMO, The5ers, Apex, MFF). Its core innovation is a fully autonomous **Challenge Calibration Engine** that translates the funded firm's rules into optimal, safe daily trading behaviors.

## 🎯 Core Design Philosophy 

> *"User sets the GOAL. EA figures out the HOW."*

The typical EA requires endless optimization and manual tweaking of risk profiles. With **Funded.E.A**, you provide only your challenge boundaries—such as the Profit Target, Max Drawdown, and Duration—and the EA dynamically computes:

* **Optimal Risk Per Trade** based on the target, days left, and current P&L.
* **Maximum Trades Per Day** to spread risk and prevent overtrading.
* **Aggressiveness Level** (Conservative / Balanced / Accelerated) relative to your current progress.
* **Trade Management Adjustments**, accounting for real-world costs like slippage and swap fees.

---

## 🛠 Features

### 🧠 Challenge Calibration Engine
The engine evaluates the account equity and the progress towards the target every day:
* **Aggressiveness Scaling**: Slows down to *Conservative* risk when you are near the profit target (to lock in the win), or speeds up to *Accelerated* risk if you're running out of time.
* **Winning Day Lock**: Auto-halts trading if your daily profit comfortably exceeds your required daily average.
* **Drawdown Proximity Guard**: Drops volume dramatically if you approach the daily loss limit.

### 📈 Smart Money Concept (SMC) Strategy
* **Macro Trend Filter**: Evaluates M15/H4 structural biases and checks whether price is above/below the H4 200 EMA to determine pure bullish/bearish bias.
* **Precision Scalping**: Scans for Order Blocks, Fair Value Gaps (FVG), and liquidity sweeps. 
* **Setup Scoring Engine**: Every trade is scored 0–100. The EA dynamically lowers the acceptable threshold when more aggressiveness is required, or strictly demands a 75+ "A-grade" setup when preserving capital.

### 🛡 Execution & Cost Model Safety
Unlike standard EAs that assume a perfect environment, this system accurately accommodates real trading conditions on XAUUSD:
* **Cost-Aware Risk Management**: Automatically deduces spread, latency slippage, commission, and swap. The EA denies entries if a trade's minimum net Risk/Reward is impacted by execution fees.
* **Slippage & Requote Handling**: Monitors MqlTradeRequest deviations and aborts entries in unstable conditions.
* **High-Impact News Shield**: Proactively blocks setups during high-impact news windows.

### 🖥 Real-Time On-Chart Dashboard
Features an intuitive Heads-Up Display (HUD) directly on your MT5 charts:
* Progress Bars: Tracks challenge profit achieved, days used, and current engine pacing.
* DD Used Tracker: Visual Daily and Total drawdown expenditure.
* Engine Mode Tracker: Displays real-time risk allocation per trade.

---

## ⚙️ Getting Started

You do not need to optimize indicator periods or manual stop-loss distances. You simply enter your firm's rules.

### Input Parameters:
* `AccountSize`: Your starting balance (e.g., $100,000)
* `FirmPreset`: Instantly load rules for your prop firm (FTMO, The5ers, Apex, MyFundedFx, Custom)
* `ProfitTargetPct`: e.g., 8.0 for Phase 1
* `MaxDailyDrawdownPct`: e.g., 5.0
* `MaxTotalDrawdownPct`: e.g., 10.0
* `MinTradingDays` / `TotalChallengeDays`: The duration rules for your challenge.

*The EA is designed entirely around capital preservation. A flat day is infinitely better than a blown challenge.*

---

## 💻 Tech Stack & Architecture
Modular MQL5 structure broken down into robust components:
* `ChallengeEngine.mqh` - Pacing and self-calibration logic.
* `RiskManager.mqh` - Drawdown constraints and lot sizing.
* `StrategyEngine.mqh` - SMC trend analysis, setup scoring, and trigger logic.
* `CostModel.mqh` - Active accounting for Latency, Spread, Swap, and Commission. 

*Created for MetaTrader 5. Requires an ECN broker and a low-latency VPS (<10ms) for optimal XAUUSD SMC order execution.*
