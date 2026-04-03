//+------------------------------------------------------------------+
//|                                               RiskManager.mqh    |
//|                         Funded.E.A Development Team              |
//|                         Risk Management & Position Sizing        |
//+------------------------------------------------------------------+
//| Purpose: Handles all risk-related calculations:                  |
//|   - Position sizing (lots) from risk % and SL distance           |
//|   - Real-time drawdown monitoring and halt logic                 |
//|   - Margin validation before order placement                     |
//|   - Trade eligibility checks from a risk perspective             |
//|   - Anti-pyramiding enforcement                                  |
//| All monetary calculations use double precision.                  |
//+------------------------------------------------------------------+
#ifndef RISK_MANAGER_MQH
#define RISK_MANAGER_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| CRiskManager - Position Sizing & Drawdown Control                 |
//+------------------------------------------------------------------+
class CRiskManager
{
private:
   //--- Configuration
   int               m_magicNumber;          // EA magic number
   string            m_symbol;               // Trading symbol
   SFirmRules        m_firmRules;            // Firm-specific rules
   
   //--- Cached symbol properties
   double            m_tickValue;            // Value per tick per lot
   double            m_tickSize;             // Smallest price movement
   double            m_point;                // Symbol point size
   double            m_minLot;               // Minimum lot size
   double            m_maxLot;               // Maximum lot size
   double            m_lotStep;              // Lot size increment
   int               m_digits;               // Price digits
   double            m_contractSize;         // Contract size
   int               m_stopLevel;            // Minimum stop distance in points
   
   //--- Risk tracking
   double            m_dailyRiskUsed;        // Total risk deployed today ($)
   double            m_maxDailyRiskAllowed;  // Daily risk cap ($)
   double            m_weeklyPnL;            // Week's running P&L
   
   //--- Logger
   CLogger           m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CRiskManager(void)
   {
      m_log.SetPrefix("Risk");
      m_magicNumber = 0;
      m_symbol = "";
      m_tickValue = 1.0;
      m_tickSize = 0.01;
      m_point = 0.01;
      m_minLot = 0.01;
      m_maxLot = 100.0;
      m_lotStep = 0.01;
      m_digits = 2;
      m_contractSize = 100.0;
      m_stopLevel = 0;
      m_dailyRiskUsed = 0;
      m_maxDailyRiskAllowed = 0;
      m_weeklyPnL = 0;
   }
   
   //+------------------------------------------------------------------+
   //| Initialize risk manager with symbol and firm rules                |
   //| Parameters:                                                       |
   //|   magicNumber - EA magic number for position filtering            |
   //|   symbol      - trading symbol (XAUUSD)                           |
   //|   firmRules   - firm-specific rules for DD limits                 |
   //| Returns: void                                                     |
   //| Side Effects: Caches all symbol properties                        |
   //+------------------------------------------------------------------+
   void Initialize(int magicNumber, string symbol, const SFirmRules &firmRules)
   {
      m_magicNumber = magicNumber;
      m_symbol = symbol;
      m_firmRules = firmRules;
      
      // Cache symbol properties
      RefreshSymbolProperties();
      
      m_log.Info(StringFormat("RiskManager initialized for %s | MagicNumber: %d", symbol, magicNumber));
      m_log.Info(StringFormat("  TickValue: $%.4f | TickSize: %.5f | Point: %.5f | Digits: %d",
                 m_tickValue, m_tickSize, m_point, m_digits));
      m_log.Info(StringFormat("  Lots: Min=%.2f Max=%.2f Step=%.2f | StopLevel: %d pts",
                 m_minLot, m_maxLot, m_lotStep, m_stopLevel));
      m_log.Info(StringFormat("  ContractSize: %.0f | DD Limits: Daily=%.1f%% Total=%.1f%%",
                 m_contractSize, firmRules.MaxDailyDrawdownPct, firmRules.MaxTotalDrawdownPct));
   }
   
   //+------------------------------------------------------------------+
   //| Refresh cached symbol properties (call if reconnected)            |
   //+------------------------------------------------------------------+
   void RefreshSymbolProperties(void)
   {
      m_tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_maxLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
      m_stopLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      
      // Fallback defaults for XAUUSD if broker returns 0
      if(m_tickValue <= 0)    m_tickValue = 1.0;
      if(m_tickSize <= 0)     m_tickSize = 0.01;
      if(m_point <= 0)        m_point = 0.01;
      if(m_minLot <= 0)       m_minLot = 0.01;
      if(m_maxLot <= 0)       m_maxLot = 100.0;
      if(m_lotStep <= 0)      m_lotStep = 0.01;
      if(m_contractSize <= 0) m_contractSize = 100.0;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate optimal lot size for a trade                            |
   //| Formula: Lots = (Balance * RiskPct/100) / (SL_Points * TickVal)  |
   //| Parameters:                                                       |
   //|   state           - current engine state (for risk %)             |
   //|   slDistancePoints - stop loss distance in points                 |
   //| Returns: Normalized lot size (0 if invalid)                       |
   //| Side Effects: None                                                |
   //+------------------------------------------------------------------+
   double CalculateLotSize(const SEngineState &state, double slDistancePoints)
   {
      //--- Validate inputs
      if(slDistancePoints <= 0)
      {
         m_log.Error("CalculateLotSize: SL distance is <= 0. Cannot size position.");
         return 0;
      }
      
      if(state.RiskPerTrade <= 0 || state.CurrentBalance <= 0)
      {
         m_log.Error("CalculateLotSize: Risk% or Balance is <= 0.");
         return 0;
      }
      
      //--- Refresh tick value (can change with price/session)
      double currentTickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      if(currentTickValue <= 0) currentTickValue = m_tickValue;
      
      //--- Core formula: Lots = RiskUSD / (SLpoints * TickValue per point per lot)
      // Convert SL points to ticks
      double slTicks = slDistancePoints / m_tickSize;
      
      // Dollar risk per lot at this SL distance
      double riskPerLot = slTicks * currentTickValue;
      
      if(riskPerLot <= 0)
      {
         m_log.Error(StringFormat("CalculateLotSize: riskPerLot = $%.4f (invalid). slTicks=%.1f, tickVal=$%.4f",
                     riskPerLot, slTicks, currentTickValue));
         return 0;
      }
      
      //--- Calculate raw lot size
      double riskUSD = state.RiskPerTradeUSD;
      double rawLots = riskUSD / riskPerLot;
      
      //--- Normalize to broker specifications
      double normalizedLots = CMathUtils::NormalizeLot(m_symbol, rawLots);
      
      //--- Validate against daily budget remaining
      double maxLotsFromBudget = CalculateMaxLotsFromBudget(state, slDistancePoints, currentTickValue);
      if(normalizedLots > maxLotsFromBudget && maxLotsFromBudget > 0)
      {
         normalizedLots = CMathUtils::NormalizeLot(m_symbol, maxLotsFromBudget);
         m_log.Debug(StringFormat("Lot capped by daily budget: %.2f -> %.2f", rawLots, normalizedLots));
      }
      
      //--- Validate margin requirements
      if(!CheckMarginRequirement(normalizedLots))
      {
         // Try to reduce lot size to fit margin
         normalizedLots = FindMaxAffordableLot(normalizedLots);
         if(normalizedLots <= 0)
         {
            m_log.Warn("Insufficient margin for minimum lot size. Trade skipped.");
            return 0;
         }
      }
      
      //--- Final lot validation
      if(normalizedLots < m_minLot)
      {
         m_log.Warn(StringFormat("Calculated lot %.4f below minimum %.2f. Trade skipped.", 
                    normalizedLots, m_minLot));
         return 0;
      }
      
      m_log.Debug(StringFormat("LotSize: %.2f (Risk$=%.2f, SLpts=%.1f, RiskPerLot=$%.2f, Raw=%.4f)",
                  normalizedLots, riskUSD, slDistancePoints, riskPerLot, rawLots));
      
      return normalizedLots;
   }
   
   //+------------------------------------------------------------------+
   //| Check if a new trade is allowed from a risk perspective           |
   //| Parameters:                                                       |
   //|   state - current engine state                                    |
   //| Returns: ENUM_ORDER_REJECTION_REASON (REJECT_NONE if OK)         |
   //| Side Effects: None                                                |
   //+------------------------------------------------------------------+
   ENUM_ORDER_REJECTION_REASON CheckTradeEligibility(const SEngineState &state)
   {
      //--- Check: EA mode is PAUSED
      if(state.AggressivenessLevel == AGG_PAUSED)
         return REJECT_PAUSED_MODE;
      
      //--- Check: Trading locked today
      if(state.TradingLockedToday)
         return REJECT_DAILY_LIMIT;
      
      //--- Check: Daily trade count limit
      if(state.TradesToday >= state.MaxTradesPerDay)
         return REJECT_DAILY_LIMIT;
      
      //--- Check: Daily drawdown proximity (halt at 80%)
      double dailyDDPct = CMathUtils::Percentage(state.DailyDDUsedToday, state.DailyDDLimit);
      if(dailyDDPct >= 80.0)
      {
         m_log.Risk(StringFormat("Daily DD at %.1f%% (halt threshold 80%%). Blocking new trades.", dailyDDPct));
         return REJECT_DD_LIMIT;
      }
      
      //--- Check: Total drawdown proximity (halt at 85%)
      double totalDDPct = CMathUtils::Percentage(state.TotalDDUsed, state.TotalDDLimit);
      if(totalDDPct >= 85.0)
      {
         m_log.Risk(StringFormat("Total DD at %.1f%% (halt threshold 85%%). Blocking new trades.", totalDDPct));
         return REJECT_DD_LIMIT;
      }
      
      //--- Check: Emergency halt
      if(state.EmergencyHalt)
         return REJECT_EMERGENCY_HALT;
      
      //--- Check: No pyramiding - only 1 open position at a time
      int openPositions = CountOpenPositions(m_magicNumber, m_symbol);
      if(openPositions > 0)
      {
         m_log.Debug(StringFormat("Already %d open position(s). No pyramiding allowed.", openPositions));
         return REJECT_DAILY_LIMIT;
      }
      
      //--- Check: Account trade allowed
      if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
         return REJECT_NOT_ALLOWED;
      
      //--- All risk checks passed
      return REJECT_NONE;
   }
   
   //+------------------------------------------------------------------+
   //| Validate that a specific SL distance meets minimum requirements   |
   //| Parameters:                                                       |
   //|   slDistancePoints - proposed SL distance in points               |
   //|   atrValue         - current ATR(14) value in price terms         |
   //| Returns: true if SL distance is valid                             |
   //| Side Effects: None                                                |
   //+------------------------------------------------------------------+
   bool ValidateSLDistance(double slDistancePoints, double atrValue)
   {
      //--- Check against broker minimum stop level
      double minStopDistance = m_stopLevel * m_point;
      if(slDistancePoints < minStopDistance)
      {
         m_log.Warn(StringFormat("SL distance %.1f pts below broker stop level %d pts. Invalid.", 
                    slDistancePoints, m_stopLevel));
         return false;
      }
      
      //--- Check against spread: SL must be > spread * 2
      int currentSpread = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      double spreadDistance = currentSpread * m_point;
      if(slDistancePoints < spreadDistance * 2.0)
      {
         m_log.Warn(StringFormat("SL distance %.1f pts too close to spread (%.1f pts * 2). Risk of noise-trigger.", 
                    slDistancePoints, spreadDistance));
         return false;
      }
      
      //--- Check against ATR bounds: Min ATR*0.5, Max ATR*1.5
      double atrPoints = atrValue; // ATR is already in price points on XAUUSD
      double minATRSL = atrPoints * 0.5;
      double maxATRSL = atrPoints * 1.5;
      
      if(slDistancePoints < minATRSL)
      {
         m_log.Warn(StringFormat("SL distance %.2f below ATR*0.5 minimum (%.2f). Too tight.", 
                    slDistancePoints, minATRSL));
         return false;
      }
      
      if(slDistancePoints > maxATRSL)
      {
         m_log.Warn(StringFormat("SL distance %.2f exceeds ATR*1.5 maximum (%.2f). Structure too wide - skip trade.", 
                    slDistancePoints, maxATRSL));
         return false;
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate TP levels based on SL distance and RR ratios            |
   //| Parameters:                                                       |
   //|   entryPrice - entry price                                        |
   //|   slPrice    - stop loss price                                    |
   //|   isBullish  - trade direction                                    |
   //|   tp1 [out]  - TP1 at 1:1 RR                                     |
   //|   tp2 [out]  - TP2 at 1:2 RR                                     |
   //|   tp3 [out]  - TP3 at Fib 1.272 extension                        |
   //| Returns: true if TPs are valid                                    |
   //| Side Effects: Sets tp1, tp2, tp3                                  |
   //+------------------------------------------------------------------+
   bool CalculateTPLevels(double entryPrice, double slPrice, bool isBullish,
                          double &tp1, double &tp2, double &tp3)
   {
      double slDistance = MathAbs(entryPrice - slPrice);
      if(slDistance <= 0) return false;
      
      if(isBullish)
      {
         tp1 = CMathUtils::NormalizePrice(m_symbol, entryPrice + slDistance * 1.0);  // 1:1 RR
         tp2 = CMathUtils::NormalizePrice(m_symbol, entryPrice + slDistance * 2.0);  // 1:2 RR
         tp3 = CMathUtils::NormalizePrice(m_symbol, entryPrice + slDistance * 2.618); // Fib 1.618 ext of SL * 1.618
      }
      else
      {
         tp1 = CMathUtils::NormalizePrice(m_symbol, entryPrice - slDistance * 1.0);
         tp2 = CMathUtils::NormalizePrice(m_symbol, entryPrice - slDistance * 2.0);
         tp3 = CMathUtils::NormalizePrice(m_symbol, entryPrice - slDistance * 2.618);
      }
      
      // Validate TPs are on the correct side
      if(isBullish && (tp1 <= entryPrice || tp2 <= tp1 || tp3 <= tp2))
      {
         m_log.Error("TP calculation error for BUY: TPs not ascending.");
         return false;
      }
      if(!isBullish && (tp1 >= entryPrice || tp2 >= tp1 || tp3 >= tp2))
      {
         m_log.Error("TP calculation error for SELL: TPs not descending.");
         return false;
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Get the breakeven price for a position                            |
   //| Includes spread and commission costs                              |
   //| Parameters:                                                       |
   //|   openPrice  - original entry price                               |
   //|   isBullish  - trade direction                                    |
   //|   lots       - position size                                      |
   //|   commission - commission per lot round trip                       |
   //| Returns: Breakeven price level                                    |
   //+------------------------------------------------------------------+
   double CalculateBreakevenPrice(double openPrice, bool isBullish, double lots, double commission)
   {
      // Get current spread in price terms
      double spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * m_point;
      
      // Commission in price terms per lot
      double commissionPricePerLot = 0;
      if(lots > 0 && m_tickValue > 0)
      {
         // Convert commission USD to price distance
         commissionPricePerLot = (commission / lots) / m_tickValue * m_tickSize;
      }
      
      // Total cost in price terms
      double totalCostPrice = spread + commissionPricePerLot;
      
      double bePrice;
      if(isBullish)
         bePrice = openPrice + totalCostPrice;
      else
         bePrice = openPrice - totalCostPrice;
      
      return CMathUtils::NormalizePrice(m_symbol, bePrice);
   }
   
   //+------------------------------------------------------------------+
   //| Check if current equity is dangerously close to DD limits         |
   //| Purpose: Real-time intraday guard                                 |
   //| Parameters:                                                       |
   //|   state - current engine state                                    |
   //| Returns: true if within danger zone (should reduce/halt)          |
   //+------------------------------------------------------------------+
   bool IsInDrawdownDangerZone(const SEngineState &state)
   {
      double dailyDDPct = CMathUtils::Percentage(state.DailyDDUsedToday, state.DailyDDLimit);
      double totalDDPct = CMathUtils::Percentage(state.TotalDDUsed, state.TotalDDLimit);
      
      return (dailyDDPct >= 70.0 || totalDDPct >= 70.0);
   }
   
   //+------------------------------------------------------------------+
   //| Get the maximum lot size that stays within daily budget            |
   //| Parameters:                                                       |
   //|   state           - current engine state                          |
   //|   slDistancePoints - SL distance in points                        |
   //|   tickValue       - current tick value per lot                    |
   //| Returns: Maximum affordable lot size for remaining budget         |
   //+------------------------------------------------------------------+
   double CalculateMaxLotsFromBudget(const SEngineState &state, double slDistancePoints, double tickValue)
   {
      // Remaining daily budget
      double budgetRemaining = state.DailyBudget - m_dailyRiskUsed;
      if(budgetRemaining <= 0) return 0;
      
      // Risk per lot at this SL
      double slTicks = slDistancePoints / m_tickSize;
      double riskPerLot = slTicks * tickValue;
      if(riskPerLot <= 0) return 0;
      
      double maxLots = budgetRemaining / riskPerLot;
      return CMathUtils::NormalizeLot(m_symbol, maxLots);
   }
   
   //+------------------------------------------------------------------+
   //| Record risk deployed for a trade (update daily risk tracking)     |
   //| Parameters:                                                       |
   //|   riskUSD - dollar risk for the trade placed                      |
   //+------------------------------------------------------------------+
   void RecordRiskDeployed(double riskUSD)
   {
      m_dailyRiskUsed += riskUSD;
      m_log.Debug(StringFormat("Risk deployed: $%.2f | Total today: $%.2f / $%.2f",
                  riskUSD, m_dailyRiskUsed, m_maxDailyRiskAllowed));
   }
   
   //+------------------------------------------------------------------+
   //| Reset daily risk tracking (call at day start)                     |
   //+------------------------------------------------------------------+
   void ResetDailyRisk(void)
   {
      m_dailyRiskUsed = 0;
      m_log.Debug("Daily risk tracker reset.");
   }
   
   //+------------------------------------------------------------------+
   //| Set the daily risk allowance                                      |
   //+------------------------------------------------------------------+
   void SetDailyRiskAllowance(double budget)
   {
      m_maxDailyRiskAllowed = budget;
   }
   
   //+------------------------------------------------------------------+
   //| Get the minimum stop level in price distance                      |
   //+------------------------------------------------------------------+
   double GetMinStopDistance(void)
   {
      // Refresh stop level (can change)
      m_stopLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      return m_stopLevel * m_point;
   }
   
   //+------------------------------------------------------------------+
   //| Get the point size                                                |
   //+------------------------------------------------------------------+
   double GetPoint(void) const { return m_point; }
   
   //+------------------------------------------------------------------+
   //| Get the tick value                                                |
   //+------------------------------------------------------------------+
   double GetTickValue(void) const { return m_tickValue; }
   
   //+------------------------------------------------------------------+
   //| Get the tick size                                                 |
   //+------------------------------------------------------------------+
   double GetTickSize(void) const { return m_tickSize; }
   
   //+------------------------------------------------------------------+
   //| Get digits                                                        |
   //+------------------------------------------------------------------+
   int GetDigits(void) const { return m_digits; }
   
   //+------------------------------------------------------------------+
   //| Get minimum lot size                                              |
   //+------------------------------------------------------------------+
   double GetMinLot(void) const { return m_minLot; }

private:
   //+------------------------------------------------------------------+
   //| Check if margin is sufficient for the proposed lot size           |
   //| Parameters:                                                       |
   //|   lots - proposed lot size                                        |
   //| Returns: true if margin is sufficient                             |
   //| Side Effects: None                                                |
   //+------------------------------------------------------------------+
   bool CheckMarginRequirement(double lots)
   {
      // Use OrderCalcMargin for accurate margin check
      double requiredMargin = 0;
      double price = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      
      if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, lots, price, requiredMargin))
      {
         m_log.Warn(StringFormat("OrderCalcMargin failed for %.2f lots. Error: %d", lots, GetLastError()));
         // Fallback: conservative estimate
         double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
         double leverage = AccountInfoInteger(ACCOUNT_LEVERAGE);
         if(leverage <= 0) leverage = 100;
         requiredMargin = (lots * m_contractSize * price) / leverage;
         return (freeMargin >= requiredMargin * 1.2); // 20% buffer
      }
      
      double freeMargin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      
      // Require at least 20% margin buffer to avoid margin call risk
      bool sufficient = (freeMargin >= requiredMargin * 1.2);
      
      if(!sufficient)
      {
         m_log.Warn(StringFormat("Margin check failed: Required=$%.2f (with 20%% buffer=$%.2f), Free=$%.2f",
                    requiredMargin, requiredMargin * 1.2, freeMargin));
      }
      
      return sufficient;
   }
   
   //+------------------------------------------------------------------+
   //| Find the maximum lot size that fits within available margin       |
   //| Purpose: Binary search down from proposed lot size                |
   //| Parameters:                                                       |
   //|   startLots - initial proposed lot size to search down from       |
   //| Returns: Maximum affordable lot size (0 if none)                  |
   //+------------------------------------------------------------------+
   double FindMaxAffordableLot(double startLots)
   {
      double testLots = startLots;
      
      // Binary search down
      while(testLots >= m_minLot)
      {
         if(CheckMarginRequirement(testLots))
            return CMathUtils::NormalizeLot(m_symbol, testLots);
         
         testLots -= m_lotStep;
      }
      
      // Even minimum lot doesn't fit
      return 0;
   }
};

#endif // RISK_MANAGER_MQH
