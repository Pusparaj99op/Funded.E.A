//+------------------------------------------------------------------+
//|                                             ChallengeEngine.mqh  |
//|                         Funded.E.A Development Team              |
//|                         Challenge Calibration Engine              |
//+------------------------------------------------------------------+
//| Purpose: The core self-optimization engine that runs at the start|
//|          of each trading day. It recomputes ALL internal params   |
//|          from scratch based on the current account state vs the  |
//|          challenge goal. This is the "brain" of the EA.          |
//|                                                                  |
//| The engine implements the core design principle:                  |
//|   "User sets the GOAL. EA figures out the HOW."                  |
//+------------------------------------------------------------------+
#ifndef CHALLENGE_ENGINE_MQH
#define CHALLENGE_ENGINE_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| CChallengeEngine - Self-Calibration Engine                        |
//+------------------------------------------------------------------+
class CChallengeEngine
{
private:
   //--- Configuration (set once on init)
   SFirmRules           m_firmRules;            // Active firm rules
   ENUM_CHALLENGE_PHASE m_phase;                // Current challenge phase
   double               m_forceRiskPerTrade;    // User override (0=auto)
   int                  m_forceMaxTradesPerDay;  // User override (0=auto)
   bool                 m_disableAccelerated;    // Block accelerated mode
   bool                 m_consistencyEnabled;    // Consistency rule active
   double               m_maxSingleDayProfitPct; // Single day profit cap
   
   //--- Internal computation variables
   double               m_profitTargetPct;       // Active profit target %
   double               m_expectedLossRate;      // Expected loss rate for RR calcs
   double               m_expectedAvgRR;         // Expected average risk:reward
   
   //--- Pace tracking
   double               m_paceRatio;             // Current pace ratio
   double               m_dailyPnLHistory[];     // Last 30 days of daily P&L
   int                  m_daysWithTrades;         // Days that had at least one trade
   
   //--- Logger
   CLogger              m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CChallengeEngine(void)
   {
      m_log.SetPrefix("Engine");
      m_phase = PHASE_1;
      m_forceRiskPerTrade = 0;
      m_forceMaxTradesPerDay = 0;
      m_disableAccelerated = false;
      m_consistencyEnabled = false;
      m_maxSingleDayProfitPct = 40.0;
      m_profitTargetPct = 8.0;
      m_expectedLossRate = EXPECTED_LOSS_RATE;
      m_expectedAvgRR = 1.8; // Conservative estimate of realized RR
      m_paceRatio = 1.0;
      m_daysWithTrades = 0;
      ArrayResize(m_dailyPnLHistory, 0);
   }
   
   //+------------------------------------------------------------------+
   //| Initialize the engine with configuration                          |
   //| Parameters:                                                       |
   //|   state              - reference to master engine state           |
   //|   firmRules           - firm preset rules                         |
   //|   phase               - current challenge phase                   |
   //|   forceRisk           - user override risk (0=auto)               |
   //|   forceMaxTrades      - user override max trades (0=auto)         |
   //|   disableAccelerated  - block accelerated mode                    |
   //|   consistencyEnabled  - enable consistency rule                   |
   //|   maxSingleDayPct     - max single day profit %                   |
   //| Returns: void                                                     |
   //| Side Effects: Sets internal configuration                         |
   //+------------------------------------------------------------------+
   void Initialize(SEngineState &state,
                   const SFirmRules &firmRules,
                   ENUM_CHALLENGE_PHASE phase,
                   double forceRisk,
                   int forceMaxTrades,
                   bool disableAccelerated,
                   bool consistencyEnabled,
                   double maxSingleDayPct)
   {
      m_firmRules = firmRules;
      m_phase = phase;
      m_forceRiskPerTrade = forceRisk;
      m_forceMaxTradesPerDay = forceMaxTrades;
      m_disableAccelerated = disableAccelerated;
      m_consistencyEnabled = consistencyEnabled;
      m_maxSingleDayProfitPct = maxSingleDayPct;
      
      // Set the active profit target % based on phase
      m_profitTargetPct = (phase == PHASE_1) ? firmRules.ProfitTargetPct_Phase1 
                                              : firmRules.ProfitTargetPct_Phase2;
      
      // For LiveFunded, use Phase2 target as a rolling target or set to a conservative % 
      if(phase == PHASE_LIVE_FUNDED)
         m_profitTargetPct = firmRules.ProfitTargetPct_Phase2;
      
      m_log.Info(StringFormat("Engine initialized. Phase: %s | Target: %.1f%% | Firm: %s",
                 PhaseToString(phase), m_profitTargetPct, firmRules.FirmName));
      m_log.Info(StringFormat("  ForceRisk: %.2f%% | ForceMaxTrades: %d | AccelDisabled: %s | Consistency: %s",
                 forceRisk, forceMaxTrades, 
                 disableAccelerated ? "Yes" : "No",
                 consistencyEnabled ? "Yes" : "No"));
   }
   
   //+------------------------------------------------------------------+
   //| Main Calibration Function - Runs at start of each trading day    |
   //| Purpose: Recompute all dynamic parameters from scratch           |
   //| Parameters:                                                       |
   //|   state - reference to master engine state (read + write)        |
   //| Returns: void                                                     |
   //| Side Effects: Modifies state with all computed outputs            |
   //+------------------------------------------------------------------+
   void Calibrate(SEngineState &state)
   {
      m_log.Engine("═══ CALIBRATION CYCLE START ═══");
      
      //=== Phase 1: Compute core challenge metrics ===
      ComputeChallengeMetrics(state);
      
      //=== Phase 2: Compute required daily profit ===
      ComputeRequiredDailyProfit(state);
      
      //=== Phase 3: Compute daily risk budget ===
      ComputeDailyBudget(state);
      
      //=== Phase 4: Compute max trades per day ===
      ComputeMaxTradesPerDay(state);
      
      //=== Phase 5: Compute risk per trade ===
      ComputeRiskPerTrade(state);
      
      //=== Phase 6: Determine aggressiveness level ===
      DetermineAggressivenessLevel(state);
      
      //=== Phase 7: Apply aggressiveness overrides ===
      ApplyAggressivenessOverrides(state);
      
      //=== Phase 8: Compute pace status ===
      ComputePaceStatus(state);
      
      //=== Phase 9: Apply user overrides (if any) ===
      ApplyUserOverrides(state);
      
      //=== Phase 10: Final validation & clamping ===
      FinalValidation(state);
      
      state.LastCalibrationTime = TimeCurrent();
      
      m_log.Engine("═══ CALIBRATION CYCLE COMPLETE ═══");
      m_log.Engine(StringFormat("  Mode: %s | Risk: %.2f%% ($%.2f) | MaxTrades: %d | DailyTarget: $%.2f",
                   AggressivenessToString(state.AggressivenessLevel),
                   state.RiskPerTrade, state.RiskPerTradeUSD,
                   state.MaxTradesPerDay, state.RequiredDailyProfit));
   }

private:
   //+------------------------------------------------------------------+
   //| Phase 1: Compute core challenge metrics                           |
   //| Purpose: Calculate profit progress, DD usage, days remaining      |
   //+------------------------------------------------------------------+
   void ComputeChallengeMetrics(SEngineState &state)
   {
      // Profit target in dollar terms
      state.ProfitTargetAmount = state.InitialBalance * m_profitTargetPct / 100.0;
      
      // Current progress
      state.ProfitSoFar = state.CurrentBalance - state.InitialBalance;
      state.ProfitRemaining = state.ProfitTargetAmount - state.ProfitSoFar;
      if(state.ProfitRemaining < 0) state.ProfitRemaining = 0;
      
      // Drawdown limits in dollar terms
      state.DailyDDLimit = state.InitialBalance * m_firmRules.MaxDailyDrawdownPct / 100.0;
      state.TotalDDLimit = state.InitialBalance * m_firmRules.MaxTotalDrawdownPct / 100.0;
      
      // Drawdown usage
      state.DailyDDUsedToday = state.DayStartEquity - state.LowestEquityToday;
      if(state.DailyDDUsedToday < 0) state.DailyDDUsedToday = 0;
      
      state.TotalDDUsed = state.PeakEquity - MathMin(state.PeakEquity, state.CurrentEquity);
      if(state.TotalDDUsed < 0) state.TotalDDUsed = 0;
      
      m_log.Debug(StringFormat("Metrics: ProfitSoFar=$%.2f | ProfitRemaining=$%.2f | " +
                  "DailyDD=$%.2f/$%.2f | TotalDD=$%.2f/$%.2f",
                  state.ProfitSoFar, state.ProfitRemaining,
                  state.DailyDDUsedToday, state.DailyDDLimit,
                  state.TotalDDUsed, state.TotalDDLimit));
   }
   
   //+------------------------------------------------------------------+
   //| Phase 2: Compute required daily profit                            |
   //| Formula: ProfitRemaining / max(TradingDaysRemaining, 1)          |
   //| Purpose: How much EA must earn per remaining day on average       |
   //+------------------------------------------------------------------+
   void ComputeRequiredDailyProfit(SEngineState &state)
   {
      int daysRemaining = MathMax(state.TradingDaysRemaining, 1);
      
      state.RequiredDailyProfit = state.ProfitRemaining / (double)daysRemaining;
      
      // Floor: don't let required daily profit go below a meaningful amount
      // At minimum, we should aim for at least 0.1% of balance per day
      double minDailyProfit = state.InitialBalance * 0.001;
      if(state.RequiredDailyProfit < minDailyProfit && state.ProfitRemaining > 0)
         state.RequiredDailyProfit = minDailyProfit;
      
      // If profit target already met, required daily = 0
      if(state.ProfitSoFar >= state.ProfitTargetAmount)
         state.RequiredDailyProfit = 0;
      
      m_log.Debug(StringFormat("RequiredDailyProfit: $%.2f (Remaining: $%.2f over %d days)",
                  state.RequiredDailyProfit, state.ProfitRemaining, daysRemaining));
   }
   
   //+------------------------------------------------------------------+
   //| Phase 3: Compute daily risk budget                                |
   //| Formula: min(DailyDDLimit * 0.60, RequiredDailyProfit * 2.5)     |
   //| Purpose: Maximum dollar amount EA is allowed to risk today        |
   //| Rationale: Never risk >60% of daily limit; never >2.5x needed    |
   //+------------------------------------------------------------------+
   void ComputeDailyBudget(SEngineState &state)
   {
      // Component 1: 60% of daily drawdown limit (capital preservation)
      double ddBasedBudget = state.DailyDDLimit * DAILY_DD_BUDGET_RATIO;
      
      // Component 2: 2.5x required daily profit (anti-gambling)
      double profitBasedBudget = state.RequiredDailyProfit * DAILY_BUDGET_PROFIT_MULT;
      
      // Take the smaller of the two (conservative approach)
      state.DailyBudget = MathMin(ddBasedBudget, profitBasedBudget);
      
      // Floor: minimum budget should allow at least 1 min-risk trade
      double minBudget = state.InitialBalance * MIN_RISK_PER_TRADE_PCT / 100.0;
      if(state.DailyBudget < minBudget && state.ProfitRemaining > 0)
         state.DailyBudget = minBudget;
      
      // If profit target already hit, budget = minimum (only protection trades)
      if(state.ProfitSoFar >= state.ProfitTargetAmount)
         state.DailyBudget = minBudget;
      
      // Reduce budget proportionally if daily DD already used
      double dailyDDRemainingRatio = 1.0 - CMathUtils::SafeDiv(state.DailyDDUsedToday, state.DailyDDLimit, 0.0);
      dailyDDRemainingRatio = CMathUtils::Clamp(dailyDDRemainingRatio, 0.0, 1.0);
      state.DailyBudget *= dailyDDRemainingRatio;
      
      // Also reduce if total DD is significantly used
      double totalDDRemainingRatio = 1.0 - CMathUtils::SafeDiv(state.TotalDDUsed, state.TotalDDLimit, 0.0);
      totalDDRemainingRatio = CMathUtils::Clamp(totalDDRemainingRatio, 0.0, 1.0);
      
      // Apply a softer scaling for total DD (square root to be less aggressive)
      double totalDDScale = MathSqrt(totalDDRemainingRatio);
      state.DailyBudget *= totalDDScale;
      
      m_log.Debug(StringFormat("DailyBudget: $%.2f (DDBase=$%.2f, ProfBase=$%.2f, DDRemain=%.0f%%, TotalScale=%.2f)",
                  state.DailyBudget, ddBasedBudget, profitBasedBudget,
                  dailyDDRemainingRatio * 100, totalDDScale));
   }
   
   //+------------------------------------------------------------------+
   //| Phase 4: Compute max trades per day                               |
   //| Formula: DailyBudget / ExpectedProfitPerTrade, clamped 1-3       |
   //| Purpose: Spread effort across multiple trades without overtrading |
   //+------------------------------------------------------------------+
   void ComputeMaxTradesPerDay(SEngineState &state)
   {
      // Estimate expected profit per trade based on risk per trade and avg RR
      // Start with a rough estimate: if we risk X per trade with expected RR of 1.8 and 45% win rate
      // Expected profit per trade = (WinRate * AvgWin) - (LossRate * AvgLoss)
      //                           = (0.45 * 1.8R) - (0.55 * 1.0R) = 0.81R - 0.55R = 0.26R per trade
      
      double expectedEdgePerTrade = 0.26; // Expected profit in R-multiple per trade
      
      // How many trades to reach required daily profit?
      // RequiredDailyProfit = MaxTrades * RiskPerTrade$ * ExpectedEdge
      // So MaxTrades = RequiredDailyProfit / (EstRiskPerTrade$ * ExpectedEdge)
      
      // Use midpoint risk (0.5% of balance) for initial estimate
      double estRiskUSD = state.InitialBalance * 0.005;
      double estProfitPerTrade = estRiskUSD * expectedEdgePerTrade;
      
      int suggestedTrades = 3; // Default
      if(estProfitPerTrade > 0)
      {
         suggestedTrades = (int)MathCeil(state.RequiredDailyProfit / estProfitPerTrade);
      }
      
      // Clamp between 1 and 3 (hard limit)
      state.MaxTradesPerDay = CMathUtils::ClampInt(suggestedTrades, 
                                                    MIN_TRADES_PER_DAY, 
                                                    MAX_TRADES_PER_DAY_HARD_LIMIT);
      
      m_log.Debug(StringFormat("MaxTradesPerDay: %d (suggested=%d, estProfitPerTrade=$%.2f)",
                  state.MaxTradesPerDay, suggestedTrades, estProfitPerTrade));
   }
   
   //+------------------------------------------------------------------+
   //| Phase 5: Compute risk per trade                                   |
   //| Formula: DailyBudget / (MaxTradesPerDay * ExpectedLossRate)      |
   //| Constraints: Min 0.25%, Max 1.0% of balance (hard caps)         |
   //| Purpose: Optimal risk sizing that balances speed and safety       |
   //+------------------------------------------------------------------+
   void ComputeRiskPerTrade(SEngineState &state)
   {
      // Base formula: distribute daily budget across expected losing trades
      double riskUSD = CMathUtils::SafeDiv(state.DailyBudget, 
                                           (double)state.MaxTradesPerDay * m_expectedLossRate,
                                           state.InitialBalance * 0.005);
      
      // Convert to percentage of current balance
      double riskPct = CMathUtils::SafeDiv(riskUSD, state.CurrentBalance, 0.005) * 100.0;
      
      //--- Apply scaling factors based on challenge progress ---
      
      // Scale 1: Reduce risk as profit target approaches
      // When ProfitSoFar is 80%+ of target, scale risk down
      double profitProgress = CMathUtils::SafeDiv(state.ProfitSoFar, state.ProfitTargetAmount, 0.0);
      if(profitProgress > 0.7)
      {
         // Linear scale from 100% at 70% progress to 50% at 100% progress
         double profitScale = CMathUtils::Lerp(1.0, 0.5, (profitProgress - 0.7) / 0.3);
         riskPct *= profitScale;
         m_log.Debug(StringFormat("RiskScale (ProfitProximity): %.2f (progress=%.1f%%)", 
                     profitScale, profitProgress * 100));
      }
      
      // Scale 2: Reduce risk as drawdown usage increases
      double totalDDPct = CMathUtils::SafeDiv(state.TotalDDUsed, state.TotalDDLimit, 0.0);
      if(totalDDPct > 0.4)
      {
         // Linear scale from 100% at 40% DD to 40% at 80% DD
         double ddScale = CMathUtils::Lerp(1.0, 0.4, (totalDDPct - 0.4) / 0.4);
         ddScale = CMathUtils::Clamp(ddScale, 0.3, 1.0);
         riskPct *= ddScale;
         m_log.Debug(StringFormat("RiskScale (DDUsage): %.2f (totalDD=%.1f%%)", ddScale, totalDDPct * 100));
      }
      
      // Scale 3: Slight boost if behind pace but still have DD buffer
      if(profitProgress < 0.3 && state.TradingDaysRemaining <= 10 && totalDDPct < 0.3)
      {
         // Gently increase risk when behind schedule but DD is healthy
         double paceBoost = 1.15; // 15% boost
         riskPct *= paceBoost;
         m_log.Debug(StringFormat("RiskScale (PaceBoost): %.2f", paceBoost));
      }
      
      // Scale 4: Reduce risk during LiveFunded phase (capital preservation paramount)
      if(m_phase == PHASE_LIVE_FUNDED)
      {
         riskPct *= 0.75; // 25% reduction for live funded
         m_log.Debug("RiskScale (LiveFunded): 0.75");
      }
      
      //--- Apply hard constraints ---
      riskPct = CMathUtils::Clamp(riskPct, MIN_RISK_PER_TRADE_PCT, MAX_RISK_PER_TRADE_PCT);
      
      // Calculate the dollar amount
      state.RiskPerTrade = riskPct;
      state.RiskPerTradeUSD = state.CurrentBalance * riskPct / 100.0;
      
      m_log.Debug(StringFormat("RiskPerTrade: %.2f%% ($%.2f) [range: %.2f%% - %.2f%%]",
                  state.RiskPerTrade, state.RiskPerTradeUSD,
                  MIN_RISK_PER_TRADE_PCT, MAX_RISK_PER_TRADE_PCT));
   }
   
   //+------------------------------------------------------------------+
   //| Phase 6: Determine aggressiveness level                           |
   //| Purpose: Classify the current state into behavioral tier          |
   //| Logic:                                                            |
   //|   PAUSED:        DD >= 80% daily or >= 85% total or target met   |
   //|   CONSERVATIVE:  Profit >= 70% or DD >= 60% total                |
   //|   ACCELERATED:   Profit < 30% AND days <= 5 remaining            |
   //|   BALANCED:      Everything else (default)                        |
   //+------------------------------------------------------------------+
   void DetermineAggressivenessLevel(SEngineState &state)
   {
      double profitProgress = CMathUtils::SafeDiv(state.ProfitSoFar, state.ProfitTargetAmount, 0.0);
      double dailyDDPct = CMathUtils::SafeDiv(state.DailyDDUsedToday, state.DailyDDLimit, 0.0);
      double totalDDPct = CMathUtils::SafeDiv(state.TotalDDUsed, state.TotalDDLimit, 0.0);
      
      ENUM_AGGRESSIVENESS_LEVEL previousLevel = state.AggressivenessLevel;
      
      //--- Check PAUSED conditions (highest priority) ---
      if(dailyDDPct >= 0.80 || totalDDPct >= 0.85)
      {
         state.AggressivenessLevel = AGG_PAUSED;
         m_log.Engine(StringFormat("Mode -> PAUSED (DailyDD=%.1f%%, TotalDD=%.1f%%)",
                      dailyDDPct * 100, totalDDPct * 100));
         return;
      }
      
      // Daily target already met
      if(state.DailyTargetMet)
      {
         state.AggressivenessLevel = AGG_PAUSED;
         m_log.Engine("Mode -> PAUSED (Daily target met)");
         return;
      }
      
      // Profit target exceeded
      if(state.ProfitSoFar >= state.ProfitTargetAmount)
      {
         state.AggressivenessLevel = AGG_PAUSED;
         m_log.Engine("Mode -> PAUSED (Challenge target reached!)");
         return;
      }
      
      //--- Check CONSERVATIVE conditions ---
      if(profitProgress >= 0.70 || totalDDPct >= 0.60)
      {
         state.AggressivenessLevel = AGG_CONSERVATIVE;
         m_log.Engine(StringFormat("Mode -> CONSERVATIVE (ProfitProgress=%.1f%%, TotalDD=%.1f%%)",
                      profitProgress * 100, totalDDPct * 100));
         return;
      }
      
      // Target proximity: >= 90% progress -> CONSERVATIVE (handled in adaptive rules too)
      if(profitProgress >= 0.90)
      {
         state.AggressivenessLevel = AGG_CONSERVATIVE;
         m_log.Engine("Mode -> CONSERVATIVE (Target Proximity >= 90%)");
         return;
      }
      
      //--- Check ACCELERATED conditions ---
      if(profitProgress < 0.30 && state.TradingDaysRemaining <= 5 && !m_disableAccelerated)
      {
         state.AggressivenessLevel = AGG_ACCELERATED;
         m_log.Engine(StringFormat("Mode -> ACCELERATED (Progress=%.1f%%, DaysLeft=%d)",
                      profitProgress * 100, state.TradingDaysRemaining));
         return;
      }
      
      //--- Default: BALANCED ---
      state.AggressivenessLevel = AGG_BALANCED;
      
      if(previousLevel != state.AggressivenessLevel)
      {
         m_log.Engine(StringFormat("Mode -> BALANCED (default state, progress=%.1f%%)",
                      profitProgress * 100));
      }
   }
   
   //+------------------------------------------------------------------+
   //| Phase 7: Apply mode-specific overrides to risk parameters         |
   //| Purpose: Adjust risk/trade limits based on determined mode        |
   //+------------------------------------------------------------------+
   void ApplyAggressivenessOverrides(SEngineState &state)
   {
      switch(state.AggressivenessLevel)
      {
         case AGG_CONSERVATIVE:
            // Reduce risk to minimum, max 2 trades, strict setups only
            state.RiskPerTrade = CMathUtils::Clamp(state.RiskPerTrade, 
                                                    MIN_RISK_PER_TRADE_PCT, 
                                                    MIN_RISK_PER_TRADE_PCT + 0.10);
            state.RiskPerTradeUSD = state.CurrentBalance * state.RiskPerTrade / 100.0;
            state.MaxTradesPerDay = CMathUtils::ClampInt(state.MaxTradesPerDay, 1, 2);
            
            m_log.Engine(StringFormat("CONSERVATIVE overrides: Risk=%.2f%%, MaxTrades=%d",
                         state.RiskPerTrade, state.MaxTradesPerDay));
            break;
            
         case AGG_BALANCED:
            // Standard: risk around 0.50%, max 3 trades
            // RiskPerTrade already computed, just ensure reasonable bounds
            state.RiskPerTrade = CMathUtils::Clamp(state.RiskPerTrade,
                                                    MIN_RISK_PER_TRADE_PCT,
                                                    0.75);
            state.RiskPerTradeUSD = state.CurrentBalance * state.RiskPerTrade / 100.0;
            state.MaxTradesPerDay = CMathUtils::ClampInt(state.MaxTradesPerDay, 1, 3);
            break;
            
         case AGG_ACCELERATED:
            // Increased pace but capped at 0.75% (hard constraint from spec)
            state.RiskPerTrade = CMathUtils::Clamp(state.RiskPerTrade,
                                                    0.40, 
                                                    ACCELERATED_RISK_CAP_PCT);
            state.RiskPerTradeUSD = state.CurrentBalance * state.RiskPerTrade / 100.0;
            state.MaxTradesPerDay = CMathUtils::ClampInt(state.MaxTradesPerDay, 2, 3);
            
            m_log.Engine(StringFormat("ACCELERATED overrides: Risk=%.2f%% (capped at %.2f%%), MaxTrades=%d",
                         state.RiskPerTrade, ACCELERATED_RISK_CAP_PCT, state.MaxTradesPerDay));
            break;
            
         case AGG_PAUSED:
            // Zero new trades. Existing positions managed for exit only.
            state.MaxTradesPerDay = 0;
            state.TradingLockedToday = true;
            m_log.Engine("PAUSED: No new trades allowed.");
            break;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Phase 8: Compute pace status for dashboard                        |
   //| Formula: PaceRatio = (ProfitSoFar/Target) / (DaysElapsed/Total)  |
   //| Purpose: Show trader if they are on track, behind, or ahead       |
   //+------------------------------------------------------------------+
   void ComputePaceStatus(SEngineState &state)
   {
      // Calculate pace ratio
      double profitProgress = CMathUtils::SafeDiv(state.ProfitSoFar, state.ProfitTargetAmount, 0.0);
      
      int totalDays = m_firmRules.TotalChallengeDays;
      int daysElapsed = totalDays - state.TradingDaysRemaining;
      double timeProgress = CMathUtils::SafeDiv((double)daysElapsed, (double)totalDays, 0.0);
      
      // Avoid division by zero when no time has passed
      if(timeProgress < 0.01)
      {
         m_paceRatio = 1.0;
         state.PaceStatus = PACE_ON_TRACK;
         return;
      }
      
      m_paceRatio = profitProgress / timeProgress;
      
      // Classify pace status
      if(m_paceRatio >= 1.3)
         state.PaceStatus = PACE_AHEAD;
      else if(m_paceRatio >= 0.85)
         state.PaceStatus = PACE_ON_TRACK;
      else if(m_paceRatio >= 0.60)
         state.PaceStatus = PACE_SLIGHTLY_BEHIND;
      else
         state.PaceStatus = PACE_BEHIND;
      
      m_log.Debug(StringFormat("PaceRatio: %.2f | ProfitProgress: %.1f%% | TimeProgress: %.1f%% | Status: %s",
                  m_paceRatio, profitProgress * 100, timeProgress * 100,
                  PaceToString(state.PaceStatus)));
   }
   
   //+------------------------------------------------------------------+
   //| Phase 9: Apply user overrides if specified                        |
   //| Purpose: Honor ForceRiskPerTrade and ForceMaxTradesPerDay         |
   //| Note: Overrides still respect hard caps                           |
   //+------------------------------------------------------------------+
   void ApplyUserOverrides(SEngineState &state)
   {
      // Override risk per trade
      if(m_forceRiskPerTrade > 0)
      {
         double clampedRisk = CMathUtils::Clamp(m_forceRiskPerTrade, 
                                                 MIN_RISK_PER_TRADE_PCT, 
                                                 MAX_RISK_PER_TRADE_PCT);
         
         if(MathAbs(clampedRisk - m_forceRiskPerTrade) > 0.001)
         {
            m_log.Warn(StringFormat("ForceRiskPerTrade %.2f%% clamped to %.2f%% (hard limits)",
                       m_forceRiskPerTrade, clampedRisk));
         }
         
         state.RiskPerTrade = clampedRisk;
         state.RiskPerTradeUSD = state.CurrentBalance * clampedRisk / 100.0;
         m_log.Engine(StringFormat("USER OVERRIDE: RiskPerTrade = %.2f%%", clampedRisk));
      }
      
      // Override max trades per day
      if(m_forceMaxTradesPerDay > 0)
      {
         int clampedTrades = CMathUtils::ClampInt(m_forceMaxTradesPerDay, 
                                                   MIN_TRADES_PER_DAY, 
                                                   MAX_TRADES_PER_DAY_HARD_LIMIT);
         state.MaxTradesPerDay = clampedTrades;
         m_log.Engine(StringFormat("USER OVERRIDE: MaxTradesPerDay = %d", clampedTrades));
      }
   }
   
   //+------------------------------------------------------------------+
   //| Phase 10: Final validation and safety clamping                    |
   //| Purpose: Ensure no computed value violates fundamental limits     |
   //+------------------------------------------------------------------+
   void FinalValidation(SEngineState &state)
   {
      //--- Risk per trade: absolute hard caps
      state.RiskPerTrade = CMathUtils::Clamp(state.RiskPerTrade, 
                                              MIN_RISK_PER_TRADE_PCT, 
                                              MAX_RISK_PER_TRADE_PCT);
      state.RiskPerTradeUSD = state.CurrentBalance * state.RiskPerTrade / 100.0;
      
      //--- Max trades per day: absolute hard cap
      if(state.AggressivenessLevel != AGG_PAUSED)
      {
         state.MaxTradesPerDay = CMathUtils::ClampInt(state.MaxTradesPerDay,
                                                       MIN_TRADES_PER_DAY,
                                                       MAX_TRADES_PER_DAY_HARD_LIMIT);
      }
      
      //--- Daily budget sanity: should never exceed daily DD limit
      if(state.DailyBudget > state.DailyDDLimit * 0.75)
      {
         state.DailyBudget = state.DailyDDLimit * 0.60;
         m_log.Warn("DailyBudget exceeded 75% of DailyDDLimit. Clamped to 60%.");
      }
      
      //--- Ensure RiskPerTradeUSD * MaxTrades doesn't exceed daily budget
      double maxPossibleRisk = state.RiskPerTradeUSD * state.MaxTradesPerDay;
      if(maxPossibleRisk > state.DailyBudget && state.DailyBudget > 0)
      {
         // Reduce risk per trade to fit within budget
         state.RiskPerTradeUSD = state.DailyBudget / (double)state.MaxTradesPerDay;
         state.RiskPerTrade = CMathUtils::SafeDiv(state.RiskPerTradeUSD, state.CurrentBalance, 0.005) * 100.0;
         state.RiskPerTrade = CMathUtils::Clamp(state.RiskPerTrade, MIN_RISK_PER_TRADE_PCT, MAX_RISK_PER_TRADE_PCT);
         state.RiskPerTradeUSD = state.CurrentBalance * state.RiskPerTrade / 100.0;
         
         m_log.Debug(StringFormat("Risk adjusted to fit budget: %.2f%% ($%.2f)",
                     state.RiskPerTrade, state.RiskPerTradeUSD));
      }
      
      //--- RequiredDailyProfit should never be negative
      if(state.RequiredDailyProfit < 0) state.RequiredDailyProfit = 0;
      
      //--- ProfitRemaining should never be negative
      if(state.ProfitRemaining < 0) state.ProfitRemaining = 0;
      
      //--- Validate TradingDaysRemaining
      if(state.TradingDaysRemaining < 0) state.TradingDaysRemaining = 0;
      
      //--- Consistency rule: validate MaxTradesPerDay doesn't allow exceeding single-day cap
      if(m_consistencyEnabled && state.ProfitTargetAmount > 0)
      {
         double maxSingleDayProfit = state.ProfitTargetAmount * m_maxSingleDayProfitPct / 100.0;
         
         // Estimate max profit possible with current settings
         // MaxProfit ≈ MaxTrades * RiskPerTradeUSD * AvgRR * WinRate (all winners scenario)
         double maxEstimatedProfit = state.MaxTradesPerDay * state.RiskPerTradeUSD * m_expectedAvgRR;
         
         if(maxEstimatedProfit > maxSingleDayProfit && state.MaxTradesPerDay > 1)
         {
            // Reduce max trades to comply with consistency
            int safeTrades = (int)MathFloor(maxSingleDayProfit / (state.RiskPerTradeUSD * m_expectedAvgRR));
            safeTrades = CMathUtils::ClampInt(safeTrades, 1, state.MaxTradesPerDay);
            
            if(safeTrades < state.MaxTradesPerDay)
            {
               state.MaxTradesPerDay = safeTrades;
               m_log.Engine(StringFormat("Consistency rule: MaxTrades reduced to %d to stay under single-day cap $%.2f",
                            safeTrades, maxSingleDayProfit));
            }
         }
      }
      
      m_log.Debug("Final validation complete. All parameters within bounds.");
   }

public:
   //+------------------------------------------------------------------+
   //| Get the current pace ratio for external queries                   |
   //+------------------------------------------------------------------+
   double GetPaceRatio(void) const { return m_paceRatio; }
   
   //+------------------------------------------------------------------+
   //| Get the active profit target percentage                           |
   //+------------------------------------------------------------------+
   double GetProfitTargetPct(void) const { return m_profitTargetPct; }
   
   //+------------------------------------------------------------------+
   //| Record daily P&L for historical tracking                          |
   //| Purpose: Maintain a rolling 30-day history for analysis           |
   //| Parameters:                                                       |
   //|   dailyPnL - the net P&L for the completed day                   |
   //+------------------------------------------------------------------+
   void RecordDailyPnL(double dailyPnL)
   {
      int size = ArraySize(m_dailyPnLHistory);
      if(size >= 30)
      {
         // Shift left, drop oldest
         for(int i = 0; i < size - 1; i++)
            m_dailyPnLHistory[i] = m_dailyPnLHistory[i + 1];
         m_dailyPnLHistory[size - 1] = dailyPnL;
      }
      else
      {
         ArrayResize(m_dailyPnLHistory, size + 1);
         m_dailyPnLHistory[size] = dailyPnL;
      }
      
      if(dailyPnL != 0)
         m_daysWithTrades++;
   }
   
   //+------------------------------------------------------------------+
   //| Get the count of actual trading days (days with trades)           |
   //+------------------------------------------------------------------+
   int GetDaysWithTrades(void) const { return m_daysWithTrades; }
   
   //+------------------------------------------------------------------+
   //| Calculate win rate from daily P&L history                         |
   //+------------------------------------------------------------------+
   double GetHistoricalWinRate(void)
   {
      int size = ArraySize(m_dailyPnLHistory);
      if(size == 0) return 0.45; // Default assumption
      
      int wins = 0;
      int total = 0;
      for(int i = 0; i < size; i++)
      {
         if(m_dailyPnLHistory[i] != 0)
         {
            total++;
            if(m_dailyPnLHistory[i] > 0) wins++;
         }
      }
      
      if(total == 0) return 0.45;
      return (double)wins / (double)total;
   }
   
   //+------------------------------------------------------------------+
   //| Get the expected loss rate (dynamic or default)                   |
   //+------------------------------------------------------------------+
   double GetExpectedLossRate(void)
   {
      int size = ArraySize(m_dailyPnLHistory);
      if(size < 5) return m_expectedLossRate; // Not enough data
      
      double winRate = GetHistoricalWinRate();
      double lossRate = 1.0 - winRate;
      
      // Blend historical with default (weighted average)
      return (lossRate * 0.7) + (m_expectedLossRate * 0.3);
   }
};

#endif // CHALLENGE_ENGINE_MQH
