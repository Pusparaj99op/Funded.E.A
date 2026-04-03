//+------------------------------------------------------------------+
//|                                                   FundedEA.mq5   |
//|                         Funded.E.A Development Team              |
//|                         Self-Optimizing Funded Challenge EA      |
//+------------------------------------------------------------------+
#property copyright   "Funded.E.A Development Team"
#property link        "https://github.com/Pusparaj99op/Funded.E.A"
#property version     "2.00"
#property description "Self-Optimizing Expert Advisor for Funded Account Challenges"
#property description "Asset: XAUUSD | Strategy: ICT Smart Money Concepts"
#property description "User sets the GOAL. EA figures out the HOW."
#property strict

//+------------------------------------------------------------------+
//| Include Modules                                                   |
//+------------------------------------------------------------------+
#include <FundedEA/Utils.mqh>
#include <FundedEA/FirmPresets.mqh>
#include <FundedEA/StatePersistence.mqh>
#include <FundedEA/ChallengeEngine.mqh>
#include <FundedEA/RiskManager.mqh>
#include <FundedEA/CostModel.mqh>
#include <FundedEA/SessionManager.mqh>
#include <FundedEA/StrategyEngine.mqh>
#include <FundedEA/OrderManager.mqh>
#include <FundedEA/Dashboard.mqh>

//+------------------------------------------------------------------+
//| Input Parameters - Challenge Configuration                        |
//| These are the ONLY inputs the user provides. Everything else is  |
//| auto-computed by the EA at runtime.                               |
//+------------------------------------------------------------------+

//--- Challenge Parameters (Required)
input group           "═══════ Challenge Parameters ═══════"
input double          InpAccountSize              = 10000.0;  // Account Size ($)
input ENUM_FIRM_PRESET InpFirmPreset              = FIRM_FTMO; // Firm Preset
input double          InpProfitTargetPct          = 8.0;       // Profit Target (%)
input double          InpMaxDailyDrawdownPct      = 5.0;       // Max Daily Drawdown (%)
input double          InpMaxTotalDrawdownPct       = 10.0;      // Max Total Drawdown (%)
input int             InpMinTradingDays           = 5;         // Minimum Trading Days
input int             InpTotalChallengeDays       = 30;        // Total Challenge Days
input ENUM_CHALLENGE_PHASE InpCurrentPhase        = PHASE_1;   // Current Phase
input bool            InpConsistencyRuleEnabled   = false;     // Enable Consistency Rule
input double          InpMaxSingleDayProfitPct    = 40.0;      // Max Single Day Profit (% of Target)

//--- Optional Overrides (Advanced)
input group           "═══════ Advanced Overrides ═══════"
input double          InpForceRiskPerTrade         = 0.0;      // Force Risk/Trade (0=Auto)
input int             InpForceMaxTradesPerDay      = 0;        // Force Max Trades/Day (0=Auto)
input bool            InpDisableAcceleratedMode    = false;    // Disable Accelerated Mode
input int             InpMagicNumber               = 202600;   // Magic Number
input int             InpMaxSlippagePips           = 3;        // Max Slippage (pips)

//--- Session Settings
input group           "═══════ Session Settings ═══════"
input bool            InpTradeLondon               = true;     // Trade London Session
input bool            InpTradeNewYork              = true;     // Trade New York Session
input bool            InpTradeAsian                = false;    // Trade Asian Session
input bool            InpAvoidNewsEvents           = true;     // Avoid News Events
input int             InpNewsBufferMinutes         = 30;       // News Buffer (minutes)
input bool            InpCloseAllOnFriday          = true;     // Close All on Friday
input int             InpFridayCloseHourGMT        = 20;       // Friday Close Hour (GMT)
input int             InpServerTimezoneOffset      = 2;        // Server Timezone Offset (hours from UTC)

//--- Execution Cost Settings
input group           "═══════ Execution & Cost Settings ═══════"
input int             InpMaxAllowedSpreadPoints    = 30;       // Max Allowed Spread (points)
input double          InpCommissionPerLotRT         = 0.0;      // Commission/Lot Round Trip ($)
input bool            InpAvoidWednesdayOvernight   = true;     // Avoid Wednesday Overnight (Triple Swap)
input double          InpMaxAllowedSwapPerTrade    = 5.0;      // Max Allowed Swap/Trade ($)

//--- Dashboard Settings
input group           "═══════ Dashboard Settings ═══════"
input bool            InpShowDashboard             = true;     // Show Dashboard
input ENUM_DASHBOARD_CORNER InpDashboardCorner     = CORNER_TOP_RIGHT;  // Dashboard Corner
input int             InpDashboardFontSize         = 10;       // Dashboard Font Size

//+------------------------------------------------------------------+
//| Global Module Instances                                           |
//+------------------------------------------------------------------+
CLogger              g_log;                // Global logger
CTimeUtils           g_time;               // Time utilities
CLatencyMeter        g_latency;            // Latency measurement
CSlippageTracker     g_slippage;           // Slippage tracking
CFirmPresets         g_firmPresets;         // Firm presets loader
CStatePersistence    g_persistence;        // State persistence
CChallengeEngine     g_challengeEngine;    // Challenge calibration engine
CRiskManager         g_riskManager;        // Risk management
CCostModel           g_costModel;          // Execution cost model
CSessionManager      g_sessionManager;     // Session & news management
CStrategyEngine      g_strategyEngine;     // Strategy & setup scoring
COrderManager        g_orderManager;       // Order execution & management
CDashboard           g_dashboard;          // On-chart dashboard

//--- Global state
SEngineState         g_state;              // Master engine state
SFirmRules           g_firmRules;          // Active firm rules
bool                 g_initialized = false;// Init success flag
datetime             g_lastDayCheck = 0;   // Last day boundary check
datetime             g_lastEquityCheck = 0;// Last equity timestamp for emergency DD
double               g_equityHistory5Min = 0; // Equity value 5 minutes ago

//+------------------------------------------------------------------+
//| Expert initialization function                                    |
//+------------------------------------------------------------------+
int OnInit()
{
   g_log.SetPrefix(EA_NAME);
   g_log.Info("═══════════════════════════════════════════════");
   g_log.Info(StringFormat("%s v%s Initializing...", EA_NAME, EA_VERSION));
   g_log.Info("═══════════════════════════════════════════════");
   
   //=== STEP 1: Validate Symbol ===
   string currentSymbol = Symbol();
   if(!ValidateSymbol(currentSymbol))
   {
      g_log.Error(StringFormat("FATAL: This EA is designed for XAUUSD only. Current symbol: %s", currentSymbol));
      g_log.Error("Attach the EA to a XAUUSD chart (or GOLD, XAUUSDm variant).");
      return INIT_FAILED;
   }
   g_log.Info(StringFormat("Symbol validated: %s", currentSymbol));
   
   //=== STEP 2: Validate Input Parameters ===
   if(!ValidateInputParameters())
   {
      g_log.Error("FATAL: Input parameter validation failed. EA will not trade.");
      return INIT_FAILED;
   }
   g_log.Info("Input parameters validated successfully.");
   
   //=== STEP 3: Initialize Time Utilities ===
   g_time.SetServerOffset(InpServerTimezoneOffset);
   g_log.Info(StringFormat("Server timezone offset: UTC+%d", InpServerTimezoneOffset));
   
   //=== STEP 4: Load Firm Preset Rules ===
   g_firmPresets.LoadPreset(InpFirmPreset, InpCurrentPhase, g_firmRules);
   
   // Override with user inputs if using Custom preset, or if user explicitly set values
   if(InpFirmPreset == FIRM_CUSTOM)
   {
      g_firmRules.ProfitTargetPct_Phase1 = InpProfitTargetPct;
      g_firmRules.ProfitTargetPct_Phase2 = InpProfitTargetPct;
      g_firmRules.MaxDailyDrawdownPct = InpMaxDailyDrawdownPct;
      g_firmRules.MaxTotalDrawdownPct = InpMaxTotalDrawdownPct;
      g_firmRules.MinTradingDays = InpMinTradingDays;
      g_firmRules.TotalChallengeDays = InpTotalChallengeDays;
      g_firmRules.ConsistencyRule = InpConsistencyRuleEnabled;
      g_firmRules.MaxSingleDayProfitPct = InpMaxSingleDayProfitPct;
   }
   
   g_log.Info(StringFormat("Firm: %s | Phase: %s | Target: %.1f%% | Daily DD: %.1f%% | Total DD: %.1f%%",
              g_firmRules.FirmName, PhaseToString(InpCurrentPhase),
              (InpCurrentPhase == PHASE_1) ? g_firmRules.ProfitTargetPct_Phase1 : g_firmRules.ProfitTargetPct_Phase2,
              g_firmRules.MaxDailyDrawdownPct, g_firmRules.MaxTotalDrawdownPct));
   
   //=== STEP 5: Initialize State ===
   g_state.Reset();
   g_state.InitialBalance = InpAccountSize;
   
   //=== STEP 6: Restore Persisted State ===
   g_persistence.Initialize(InpMagicNumber);
   bool stateRestored = g_persistence.RestoreState(g_state);
   
   if(stateRestored)
   {
      g_log.Info("State restored from previous session.");
      g_log.Info(StringFormat("  Persisted Balance: $%.2f | Days Completed: %d | Peak Equity: $%.2f",
                 g_state.InitialBalance, g_state.TradingDaysCompleted, g_state.PeakEquity));
   }
   else
   {
      g_log.Info("No previous state found. Starting fresh challenge tracking.");
      g_state.InitialBalance = InpAccountSize;
      g_state.ChallengeStartDate = TimeCurrent();
      g_state.PeakEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_state.DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      g_state.LowestEquityToday = AccountInfoDouble(ACCOUNT_EQUITY);
   }
   
   //=== STEP 7: Measure Broker Latency ===
   g_latency.StartupMeasure();
   
   //=== STEP 8: Initialize Sub-modules ===
   g_costModel.Initialize(Symbol(), InpMaxAllowedSpreadPoints, InpCommissionPerLotRT,
                          InpMaxAllowedSwapPerTrade, InpAvoidWednesdayOvernight);
   
   g_sessionManager.Initialize(InpTradeLondon, InpTradeNewYork, InpTradeAsian,
                               InpAvoidNewsEvents, InpNewsBufferMinutes,
                               InpCloseAllOnFriday, InpFridayCloseHourGMT,
                               InpServerTimezoneOffset);
   
   g_riskManager.Initialize(InpMagicNumber, Symbol(), g_firmRules);
   
   g_strategyEngine.Initialize(Symbol(), InpServerTimezoneOffset);
   
   g_orderManager.Initialize(Symbol(), InpMagicNumber, InpMaxSlippagePips, InpMaxAllowedSpreadPoints);
   
   g_challengeEngine.Initialize(g_state, g_firmRules, InpCurrentPhase,
                                InpForceRiskPerTrade, InpForceMaxTradesPerDay,
                                InpDisableAcceleratedMode, InpConsistencyRuleEnabled,
                                InpMaxSingleDayProfitPct);
   
   //=== STEP 9: Initialize Dashboard ===
   if(InpShowDashboard)
   {
      g_dashboard.Initialize(InpDashboardCorner, InpDashboardFontSize,
                             g_firmRules.FirmName, PhaseToString(InpCurrentPhase),
                             InpAccountSize);
   }
   
   //=== STEP 10: Run Initial Calibration ===
   UpdateAccountState();
   g_challengeEngine.Calibrate(g_state);
   
   g_log.Info("═══════════════════════════════════════════════");
   g_log.Info(StringFormat("%s v%s READY", EA_NAME, EA_VERSION));
   g_log.Info(StringFormat("Mode: %s | Risk/Trade: %.2f%% ($%.2f) | Max Trades: %d",
              AggressivenessToString(g_state.AggressivenessLevel),
              g_state.RiskPerTrade, g_state.RiskPerTradeUSD,
              g_state.MaxTradesPerDay));
   g_log.Info("═══════════════════════════════════════════════");
   
   //--- Set timer for periodic checks (every 60 seconds)
   EventSetTimer(60);
   
   g_initialized = true;
   return INIT_SUCCEEDED;
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   g_log.Info(StringFormat("%s shutting down. Reason: %d", EA_NAME, reason));
   
   //--- Save state for persistence
   if(g_initialized)
   {
      g_persistence.SaveState(g_state);
      g_log.Info("State saved successfully.");
   }
   
   //--- Clean up dashboard
   if(InpShowDashboard)
      g_dashboard.Destroy();
   
   //--- Kill timer
   EventKillTimer();
   
   g_log.Info(StringFormat("%s shutdown complete.", EA_NAME));
}

//+------------------------------------------------------------------+
//| Expert tick function - Main execution loop                        |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!g_initialized) return;
   
   //=== STEP 1: Update Account State ===
   UpdateAccountState();
   
   //=== STEP 2: New Day Check & Recalibration ===
   CheckNewTradingDay();
   
   //=== STEP 3: Emergency Drawdown Check ===
   if(CheckEmergencyDrawdown()) return;
   
   //=== STEP 4: Emergency Halt Check ===
   if(g_state.EmergencyHalt)
   {
      if(TimeCurrent() < g_state.EmergencyHaltUntil)
         return; // Still in emergency halt period
      else
      {
         g_state.EmergencyHalt = false;
         g_log.Info("Emergency halt period ended. Resuming operations.");
      }
   }
   
   //=== STEP 5: Enforce Adaptive Behavior Rules (Intraday) ===
   EnforceAdaptiveBehavior();
   
   //=== STEP 6: Manage Open Positions ===
   ManageOpenPositions();
   
   //=== STEP 7: Check if Trading is Allowed ===
   if(!CanOpenNewTrade()) return;
   
   //=== STEP 8: Look for New Trade Setups ===
   EvaluateAndExecuteSetup();
   
   //=== STEP 9: Update Dashboard ===
   if(InpShowDashboard)
      UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Timer function - Periodic maintenance                             |
//+------------------------------------------------------------------+
void OnTimer()
{
   if(!g_initialized) return;
   
   //--- Update latency measurement periodically
   g_latency.MeasureRTT();
   
   //--- Update session state
   g_state.CurrentSession = g_time.GetCurrentSession();
   
   //--- Check session manager for Friday close / Wednesday swap
   g_sessionManager.OnTimer(g_state, g_orderManager, InpMagicNumber, Symbol());
   
   //--- Periodic state save (every timer tick = 60 seconds)
   g_persistence.SaveState(g_state);
   
   //--- Update dashboard if visible
   if(InpShowDashboard)
      UpdateDashboard();
}

//+------------------------------------------------------------------+
//| Trade transaction handler                                         |
//+------------------------------------------------------------------+
void OnTrade()
{
   if(!g_initialized) return;
   
   //--- A trade event occurred; update counters
   UpdateTradeCounters();
}

//+------------------------------------------------------------------+
//| Validate all input parameters on startup                          |
//+------------------------------------------------------------------+
bool ValidateInputParameters()
{
   bool valid = true;
   
   if(InpAccountSize <= 0)
   {
      g_log.Error("AccountSize must be positive.");
      valid = false;
   }
   
   if(InpProfitTargetPct <= 0 || InpProfitTargetPct > 100)
   {
      g_log.Error("ProfitTargetPct must be between 0 and 100.");
      valid = false;
   }
   
   if(InpMaxDailyDrawdownPct <= 0 || InpMaxDailyDrawdownPct > 100)
   {
      g_log.Error("MaxDailyDrawdownPct must be between 0 and 100.");
      valid = false;
   }
   
   if(InpMaxTotalDrawdownPct <= 0 || InpMaxTotalDrawdownPct > 100)
   {
      g_log.Error("MaxTotalDrawdownPct must be between 0 and 100.");
      valid = false;
   }
   
   if(InpMaxDailyDrawdownPct > InpMaxTotalDrawdownPct)
   {
      g_log.Error(StringFormat("MaxDailyDrawdownPct (%.1f%%) cannot exceed MaxTotalDrawdownPct (%.1f%%).",
                  InpMaxDailyDrawdownPct, InpMaxTotalDrawdownPct));
      valid = false;
   }
   
   if(InpTotalChallengeDays <= 0)
   {
      g_log.Error("TotalChallengeDays must be positive.");
      valid = false;
   }
   
   if(InpMinTradingDays < 0)
   {
      g_log.Error("MinTradingDays cannot be negative.");
      valid = false;
   }
   
   if(InpMagicNumber <= 0)
   {
      g_log.Error("MagicNumber must be positive.");
      valid = false;
   }
   
   if(InpMaxSlippagePips < 0)
   {
      g_log.Error("MaxSlippagePips cannot be negative.");
      valid = false;
   }
   
   if(InpMaxAllowedSpreadPoints <= 0)
   {
      g_log.Error("MaxAllowedSpreadPoints must be positive.");
      valid = false;
   }
   
   if(InpForceRiskPerTrade < 0)
   {
      g_log.Error("ForceRiskPerTrade cannot be negative.");
      valid = false;
   }
   
   if(InpForceRiskPerTrade > MAX_RISK_PER_TRADE_PCT)
   {
      g_log.Warn(StringFormat("ForceRiskPerTrade %.2f%% exceeds hard cap %.2f%%. Will be clamped.",
                 InpForceRiskPerTrade, MAX_RISK_PER_TRADE_PCT));
   }
   
   // Check if trading is allowed on the account
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
   {
      g_log.Error("Trading is not allowed in terminal settings. Enable Algo Trading.");
      valid = false;
   }
   
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
   {
      g_log.Error("Trading is not allowed for this EA. Check EA properties.");
      valid = false;
   }
   
   return valid;
}

//+------------------------------------------------------------------+
//| Update current account state snapshot                              |
//+------------------------------------------------------------------+
void UpdateAccountState()
{
   g_state.CurrentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
   g_state.CurrentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   
   //--- Track peak equity (high water mark)
   if(g_state.CurrentEquity > g_state.PeakEquity)
      g_state.PeakEquity = g_state.CurrentEquity;
   
   //--- Track lowest equity today
   if(g_state.CurrentEquity < g_state.LowestEquityToday)
      g_state.LowestEquityToday = g_state.CurrentEquity;
   
   //--- Calculate profit metrics
   g_state.ProfitSoFar = g_state.CurrentBalance - g_state.InitialBalance;
   
   // Determine the correct profit target percentage based on phase
   double targetPct = (InpCurrentPhase == PHASE_1) ? g_firmRules.ProfitTargetPct_Phase1 
                                                    : g_firmRules.ProfitTargetPct_Phase2;
   g_state.ProfitTargetAmount = g_state.InitialBalance * targetPct / 100.0;
   g_state.ProfitRemaining = g_state.ProfitTargetAmount - g_state.ProfitSoFar;
   
   //--- Calculate drawdown limits in dollar terms
   g_state.DailyDDLimit = g_state.InitialBalance * g_firmRules.MaxDailyDrawdownPct / 100.0;
   g_state.TotalDDLimit = g_state.InitialBalance * g_firmRules.MaxTotalDrawdownPct / 100.0;
   
   //--- Calculate daily DD used (equity-based)
   g_state.DailyDDUsedToday = g_state.DayStartEquity - g_state.LowestEquityToday;
   if(g_state.DailyDDUsedToday < 0) g_state.DailyDDUsedToday = 0;
   
   //--- Calculate total DD used (from peak equity)
   g_state.TotalDDUsed = g_state.PeakEquity - MathMin(g_state.PeakEquity, g_state.CurrentEquity);
   if(g_state.TotalDDUsed < 0) g_state.TotalDDUsed = 0;
   
   //--- Update daily P&L (realized + floating)
   double closedPnL = GetClosedPnLToday(InpMagicNumber, Symbol());
   double floatingPnL = GetFloatingPnL(InpMagicNumber, Symbol());
   g_state.DailyProfitToday = closedPnL + floatingPnL;
   
   //--- Update trade count for today
   g_state.TradesToday = CountClosedTradesToday(InpMagicNumber, Symbol()) 
                       + CountOpenPositions(InpMagicNumber, Symbol());
   
   //--- Update session state
   g_state.CurrentSession = g_time.GetCurrentSession();
   
   //--- Calculate trading days remaining
   if(g_state.ChallengeStartDate > 0)
   {
      int calendarDaysElapsed = g_time.CalendarDaysBetween(g_state.ChallengeStartDate, TimeCurrent());
      g_state.TradingDaysRemaining = MathMax(1, g_firmRules.TotalChallengeDays - calendarDaysElapsed);
   }
   else
   {
      g_state.TradingDaysRemaining = g_firmRules.TotalChallengeDays;
   }
}

//+------------------------------------------------------------------+
//| Check for new trading day and recalibrate if needed               |
//+------------------------------------------------------------------+
void CheckNewTradingDay()
{
   if(g_lastDayCheck == 0)
   {
      g_lastDayCheck = TimeCurrent();
      RunDayStartCalibration();
      return;
   }
   
   if(g_time.IsNewTradingDay(g_lastDayCheck))
   {
      g_log.Info("═══ NEW TRADING DAY DETECTED ═══");
      g_lastDayCheck = TimeCurrent();
      RunDayStartCalibration();
   }
}

//+------------------------------------------------------------------+
//| Run full calibration at the start of each trading day             |
//+------------------------------------------------------------------+
void RunDayStartCalibration()
{
   //--- Reset daily tracking variables
   g_state.DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
   g_state.LowestEquityToday = g_state.DayStartEquity;
   g_state.DailyProfitToday = 0;
   g_state.TradesToday = 0;
   g_state.DailyTargetMet = false;
   g_state.TradingLockedToday = false;
   
   //--- Update consecutive loss/win counters from trade history
   g_state.ConsecutiveLosses = CountRecentConsecutiveLosses(InpMagicNumber, Symbol());
   g_state.ConsecutiveWins = CountRecentConsecutiveWins(InpMagicNumber, Symbol());
   
   //--- Increment trading days if we traded yesterday
   // (Only count days where at least one trade was closed)
   if(g_state.LastTradeCloseTime > 0)
   {
      MqlDateTime dtLast, dtNow;
      TimeToStruct(g_state.LastTradeCloseTime, dtLast);
      TimeToStruct(TimeCurrent(), dtNow);
      if(dtLast.day != dtNow.day || dtLast.mon != dtNow.mon || dtLast.year != dtNow.year)
      {
         // If the last trade close was on a different day, check if that day should count
         // TradingDaysCompleted is managed by persistence and engine
      }
   }
   
   //--- Run the Challenge Calibration Engine
   g_challengeEngine.Calibrate(g_state);
   
   //--- Log calibration results
   g_log.Engine("═══ DAY START CALIBRATION RESULTS ═══");
   g_log.Engine(StringFormat("  Balance: $%.2f | Equity: $%.2f | Profit So Far: $%.2f (%.1f%%)",
                g_state.CurrentBalance, g_state.CurrentEquity, g_state.ProfitSoFar,
                CMathUtils::Percentage(g_state.ProfitSoFar, g_state.ProfitTargetAmount)));
   g_log.Engine(StringFormat("  Required Daily: $%.2f | Daily Budget: $%.2f",
                g_state.RequiredDailyProfit, g_state.DailyBudget));
   g_log.Engine(StringFormat("  Risk/Trade: %.2f%% ($%.2f) | Max Trades: %d",
                g_state.RiskPerTrade, g_state.RiskPerTradeUSD, g_state.MaxTradesPerDay));
   g_log.Engine(StringFormat("  Mode: %s | Days Left: %d | Days Completed: %d",
                AggressivenessToString(g_state.AggressivenessLevel),
                g_state.TradingDaysRemaining, g_state.TradingDaysCompleted));
   g_log.Engine(StringFormat("  Daily DD Used: $%.2f / $%.2f (%.1f%%)",
                g_state.DailyDDUsedToday, g_state.DailyDDLimit,
                CMathUtils::Percentage(g_state.DailyDDUsedToday, g_state.DailyDDLimit)));
   g_log.Engine(StringFormat("  Total DD Used: $%.2f / $%.2f (%.1f%%)",
                g_state.TotalDDUsed, g_state.TotalDDLimit,
                CMathUtils::Percentage(g_state.TotalDDUsed, g_state.TotalDDLimit)));
   
   //--- Save state after calibration
   g_persistence.SaveState(g_state);
}

//+------------------------------------------------------------------+
//| Check for emergency drawdown (2% in 5 minutes)                   |
//+------------------------------------------------------------------+
bool CheckEmergencyDrawdown()
{
   datetime now = TimeCurrent();
   
   // Initialize the 5-minute equity reference
   if(g_lastEquityCheck == 0 || (now - g_lastEquityCheck) >= EMERGENCY_DD_TIME_SEC)
   {
      g_equityHistory5Min = g_state.CurrentEquity;
      g_lastEquityCheck = now;
   }
   
   // Check for rapid equity drop
   if(g_equityHistory5Min > 0)
   {
      double dropPct = CMathUtils::Percentage(g_equityHistory5Min - g_state.CurrentEquity, g_equityHistory5Min);
      if(dropPct >= EMERGENCY_DD_PCT)
      {
         g_state.EmergencyHalt = true;
         g_state.EmergencyHaltUntil = now + EMERGENCY_HALT_DURATION_SEC;
         
         g_log.Error(StringFormat("EMERGENCY HALT: Equity dropped %.1f%% in under 5 minutes! " +
                     "($%.2f -> $%.2f). Halting all trading for %d minutes.",
                     dropPct, g_equityHistory5Min, g_state.CurrentEquity,
                     EMERGENCY_HALT_DURATION_SEC / 60));
         
         // Move all open SL to breakeven if possible
         g_orderManager.MoveAllToBreakeven(InpMagicNumber, Symbol());
         
         g_persistence.SaveState(g_state);
         return true;
      }
   }
   
   return false;
}

//+------------------------------------------------------------------+
//| Enforce Adaptive Behavior Rules (runs on every tick)              |
//+------------------------------------------------------------------+
void EnforceAdaptiveBehavior()
{
   //=== Rule 1: Drawdown Proximity Guard ===
   double dailyDDPct = CMathUtils::Percentage(g_state.DailyDDUsedToday, g_state.DailyDDLimit);
   double totalDDPct = CMathUtils::Percentage(g_state.TotalDDUsed, g_state.TotalDDLimit);
   
   // 80% daily DD or 85% total DD -> PAUSED
   if(dailyDDPct >= 80.0 || totalDDPct >= 85.0)
   {
      if(g_state.AggressivenessLevel != AGG_PAUSED)
      {
         g_state.AggressivenessLevel = AGG_PAUSED;
         g_state.TradingLockedToday = true;
         g_log.Risk(StringFormat("PAUSED: Drawdown proximity guard triggered. Daily DD: %.1f%% | Total DD: %.1f%%",
                    dailyDDPct, totalDDPct));
      }
   }
   
   //=== Rule 2: Winning Day Lock ===
   if(!g_state.DailyTargetMet && g_state.RequiredDailyProfit > 0)
   {
      if(g_state.DailyProfitToday > g_state.RequiredDailyProfit * 1.5)
      {
         g_state.DailyTargetMet = true;
         g_state.TradingLockedToday = true;
         g_log.Trade(StringFormat("WINNING DAY LOCK: Daily profit $%.2f exceeds 1.5x required ($%.2f). No new trades.",
                     g_state.DailyProfitToday, g_state.RequiredDailyProfit * 1.5));
         
         // Move all open SL to breakeven
         g_orderManager.MoveAllToBreakeven(InpMagicNumber, Symbol());
      }
   }
   
   //=== Rule 3: Losing Streak Dampener ===
   // Handled in RiskManager via g_state.ConsecutiveLosses and LossStreakDampenTradesLeft
   
   //=== Rule 4: Target Proximity Lock ===
   if(g_state.ProfitTargetAmount > 0)
   {
      double profitProgressPct = CMathUtils::Percentage(g_state.ProfitSoFar, g_state.ProfitTargetAmount);
      
      // >= 90% of target -> CONSERVATIVE, 1 trade max
      if(profitProgressPct >= 90.0 && g_state.AggressivenessLevel != AGG_PAUSED)
      {
         if(g_state.AggressivenessLevel != AGG_CONSERVATIVE)
         {
            g_log.Risk("TARGET PROXIMITY LOCK: Profit >= 90% of target. Switching to CONSERVATIVE.");
         }
         g_state.AggressivenessLevel = AGG_CONSERVATIVE;
         g_state.MaxTradesPerDay = 1;
         g_state.RiskPerTrade = MIN_RISK_PER_TRADE_PCT;
         g_state.RiskPerTradeUSD = g_state.CurrentBalance * g_state.RiskPerTrade / 100.0;
      }
      
      // Exceeded target by 1%+ -> HALT (challenge won, preserve it)
      if(g_state.ProfitSoFar >= g_state.ProfitTargetAmount * 1.01)
      {
         if(g_state.AggressivenessLevel != AGG_PAUSED)
         {
            g_log.Info("CHALLENGE TARGET EXCEEDED BY 1%+! Halting all trading to preserve the win.");
            g_state.AggressivenessLevel = AGG_PAUSED;
            g_state.TradingLockedToday = true;
         }
      }
   }
   
   //=== Rule 5: Total DD > 70% -> CONSERVATIVE for rest of challenge ===
   if(totalDDPct >= 70.0 && g_state.AggressivenessLevel != AGG_PAUSED)
   {
      g_state.AggressivenessLevel = AGG_CONSERVATIVE;
      g_log.Risk("TOTAL DD > 70% of limit. CONSERVATIVE mode for remainder of challenge.");
   }
   
   //=== Rule 6: Consistency Rule Guard ===
   if(InpConsistencyRuleEnabled && g_state.ProfitTargetAmount > 0)
   {
      double maxSingleDayProfit = g_state.ProfitTargetAmount * InpMaxSingleDayProfitPct / 100.0;
      if(g_state.DailyProfitToday >= maxSingleDayProfit * 0.90) // 90% of single-day cap
      {
         g_state.TradingLockedToday = true;
         g_log.Risk(StringFormat("CONSISTENCY RULE: Daily profit $%.2f approaching single-day cap $%.2f. Locked.",
                    g_state.DailyProfitToday, maxSingleDayProfit));
         
         // Move open trades to breakeven to prevent exceeding
         g_orderManager.MoveAllToBreakeven(InpMagicNumber, Symbol());
      }
   }
}

//+------------------------------------------------------------------+
//| Manage existing open positions (trailing, BE, time exits)         |
//+------------------------------------------------------------------+
void ManageOpenPositions()
{
   g_orderManager.ManagePositions(g_state, g_costModel, g_strategyEngine);
}

//+------------------------------------------------------------------+
//| Check if the EA is allowed to open a new trade right now          |
//+------------------------------------------------------------------+
bool CanOpenNewTrade()
{
   //--- Check if EA mode is PAUSED
   if(g_state.AggressivenessLevel == AGG_PAUSED)
      return false;
   
   //--- Check if trading is locked today
   if(g_state.TradingLockedToday)
      return false;
   
   //--- Check if daily trade limit reached
   if(g_state.TradesToday >= g_state.MaxTradesPerDay)
      return false;
   
   //--- Check if we already have an open position (avoid pyramiding)
   if(CountOpenPositions(InpMagicNumber, Symbol()) > 0)
      return false;
   
   //--- Check trade context
   if(!IsTradeAllowed())
   {
      return false;
   }
   
   //--- Check session filter
   if(!g_sessionManager.IsSessionAllowed(g_state.CurrentSession))
      return false;
   
   //--- Check news window
   if(g_sessionManager.IsInNewsWindow())
   {
      g_state.IsNewsWindow = true;
      return false;
   }
   g_state.IsNewsWindow = false;
   
   //--- Check Friday close proximity
   if(g_sessionManager.IsFridayCloseProximity())
   {
      g_state.IsFridayClose = true;
      return false;
   }
   g_state.IsFridayClose = false;
   
   //--- Check Monday open block period
   if(g_time.IsMondayOpenBlock())
      return false;
   
   //--- Check latency
   if(!g_latency.IsLatencyOK())
   {
      g_log.Warn("Latency too high for new entries. Waiting...");
      return false;
   }
   
   //--- Check spread
   int currentSpread = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   if(currentSpread > InpMaxAllowedSpreadPoints)
      return false;
   
   //--- Check Wednesday overnight avoidance
   if(InpAvoidWednesdayOvernight && g_time.IsNearWednesdaySwap(30))
      return false;
   
   //--- All checks passed
   return true;
}

//+------------------------------------------------------------------+
//| Evaluate setup scoring and execute if a valid setup is found      |
//+------------------------------------------------------------------+
void EvaluateAndExecuteSetup()
{
   //--- Get the setup score from the strategy engine
   SSetupScore score;
   score.Reset();
   
   bool setupFound = g_strategyEngine.EvaluateSetup(score, g_state);
   
   if(!setupFound)
      return;
   
   //--- Check minimum score threshold based on aggressiveness
   int minScore = 65; // Default: BALANCED
   switch(g_state.AggressivenessLevel)
   {
      case AGG_CONSERVATIVE: minScore = 75; break;
      case AGG_BALANCED:     minScore = 65; break;
      case AGG_ACCELERATED:  minScore = 55; break;
      case AGG_PAUSED:       return; // Should never reach here
   }
   score.MinScoreRequired = minScore;
   
   if(score.TotalScore < minScore)
   {
      g_log.Debug(StringFormat("Setup score %d below threshold %d (%s mode). Skipping.",
                  score.TotalScore, minScore, AggressivenessToString(g_state.AggressivenessLevel)));
      return;
   }
   
   //--- Calculate lot size from risk manager
   double lotSize = g_riskManager.CalculateLotSize(g_state, score.SLDistancePoints);
   if(lotSize <= 0)
   {
      g_log.Warn("Risk manager returned 0 lot size. Trade skipped.");
      return;
   }
   
   //--- Apply drawdown proximity guard: reduce to min lot if DD >= 70%
   double dailyDDPct = CMathUtils::Percentage(g_state.DailyDDUsedToday, g_state.DailyDDLimit);
   if(dailyDDPct >= 70.0)
   {
      double minLot = SymbolInfoDouble(Symbol(), SYMBOL_VOLUME_MIN);
      lotSize = minLot;
      g_log.Risk(StringFormat("DD Proximity Guard: Reduced lot to minimum %.2f (DD at %.1f%%)", minLot, dailyDDPct));
   }
   
   //--- Apply losing streak dampener
   if(g_state.LossStreakDampenTradesLeft > 0)
   {
      lotSize = CMathUtils::NormalizeLot(Symbol(), lotSize * 0.5);
      g_log.Risk(StringFormat("Loss streak dampener active: Lot halved to %.2f (%d dampened trades left)",
                 lotSize, g_state.LossStreakDampenTradesLeft));
   }
   
   //--- Evaluate execution costs
   STradeCost tradeCost;
   tradeCost.Reset();
   g_costModel.EvaluateTradeCost(tradeCost, lotSize, score.SLDistancePoints, false);
   
   // Check if TP1 covers costs (3:1 minimum vs total cost)
   double tp1Distance = score.SLDistancePoints; // 1:1 RR
   double tp1USD = PointsToUSD(Symbol(), tp1Distance, lotSize);
   if(tp1USD < tradeCost.MinimumTPRequired)
   {
      g_log.Cost(StringFormat("Trade skipped: TP1 ($%.2f) < min required ($%.2f) after costs ($%.2f).",
                 tp1USD, tradeCost.MinimumTPRequired, tradeCost.TotalCostUSD));
      return;
   }
   
   //--- Execute the trade
   bool success = g_orderManager.ExecuteTrade(score, lotSize, g_state);
   
   if(success)
   {
      g_state.TradesToday++;
      
      // Decrement loss streak dampener counter if active
      if(g_state.LossStreakDampenTradesLeft > 0)
         g_state.LossStreakDampenTradesLeft--;
      
      g_log.Trade(StringFormat("TRADE EXECUTED: %s | Score: %d | Lot: %.2f | SL: %.2f | TP1: %.2f | Cost: $%.2f",
                  score.IsBullish ? "BUY" : "SELL", score.TotalScore, lotSize,
                  score.SuggestedSL, score.SuggestedTP1, tradeCost.TotalCostUSD));
      
      g_persistence.SaveState(g_state);
   }
}

//+------------------------------------------------------------------+
//| Update trade counters after OnTrade event                         |
//+------------------------------------------------------------------+
void UpdateTradeCounters()
{
   //--- Re-count today's trades
   int closedToday = CountClosedTradesToday(InpMagicNumber, Symbol());
   int openNow = CountOpenPositions(InpMagicNumber, Symbol());
   g_state.TradesToday = closedToday + openNow;
   
   //--- Update consecutive loss/win from history
   int prevLosses = g_state.ConsecutiveLosses;
   g_state.ConsecutiveLosses = CountRecentConsecutiveLosses(InpMagicNumber, Symbol());
   g_state.ConsecutiveWins = CountRecentConsecutiveWins(InpMagicNumber, Symbol());
   
   //--- Trigger loss streak dampener if 3+ consecutive losses
   if(g_state.ConsecutiveLosses >= 3 && prevLosses < 3)
   {
      g_state.LossStreakDampenTradesLeft = 2;
      g_log.Risk(StringFormat("LOSS STREAK DAMPENER: %d consecutive losses. " +
                 "Risk reduced 50%% for next 2 trades.", g_state.ConsecutiveLosses));
   }
   
   //--- Reset dampener on a win
   if(g_state.ConsecutiveWins > 0 && g_state.LossStreakDampenTradesLeft > 0)
   {
      g_state.LossStreakDampenTradesLeft = 0;
      g_log.Info("Loss streak dampener cleared on winning trade.");
   }
   
   //--- Track last trade close time
   g_state.LastTradeCloseTime = TimeCurrent();
   
   //--- Check if a day with trades should increment TradingDaysCompleted
   // This is done in the day start calibration to avoid double-counting
   
   //--- Recalculate daily P&L
   double closedPnL = GetClosedPnLToday(InpMagicNumber, Symbol());
   double floatingPnL = GetFloatingPnL(InpMagicNumber, Symbol());
   g_state.DailyProfitToday = closedPnL + floatingPnL;
   
   //--- Record slippage for the last trade
   // Slippage tracking is done in OrderManager on fill
}

//+------------------------------------------------------------------+
//| Check if trading is currently allowed by terminal and broker      |
//+------------------------------------------------------------------+
bool IsTradeAllowed()
{
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      return false;
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      return false;
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
      return false;
   if(!SymbolInfoInteger(Symbol(), SYMBOL_TRADE_MODE))
      return false;
   
   return true;
}

//+------------------------------------------------------------------+
//| Update the on-chart dashboard                                     |
//+------------------------------------------------------------------+
void UpdateDashboard()
{
   // Get current cost snapshot
   STradeCost currentCost;
   currentCost.Reset();
   currentCost.CurrentSpreadPts = (int)SymbolInfoInteger(Symbol(), SYMBOL_SPREAD);
   currentCost.AvgSlippagePts = g_slippage.GetAverageSlippage();
   
   g_dashboard.Update(g_state, currentCost, g_latency, g_costModel);
}

//+------------------------------------------------------------------+
//| End of FundedEA.mq5                                               |
//+------------------------------------------------------------------+
