//+------------------------------------------------------------------+
//|                                          StatePersistence.mqh    |
//|                         Funded.E.A Development Team              |
//|                         State Save/Restore via GlobalVariables   |
//+------------------------------------------------------------------+
//| Purpose: Saves and restores the EA's critical state across        |
//|          MT5 terminal restarts, crashes, and VPS reboots using   |
//|          MQL5 GlobalVariables. This ensures the EA never assumes |
//|          a fresh start and can resume challenge tracking from    |
//|          exactly where it left off.                              |
//|                                                                  |
//| Variables Persisted:                                              |
//|   - InitialBalance                                               |
//|   - TradingDaysCompleted                                         |
//|   - HighestEquityEver (PeakEquity)                               |
//|   - ConsecutiveLosses                                            |
//|   - ConsecutiveWins                                              |
//|   - CurrentAggressivenessMode                                    |
//|   - ChallengeStartDate                                           |
//|   - LastTradeCloseDate                                           |
//|   - DaysWithTrades (actual trading days)                         |
//|   - TotalRealizedPnL (ProfitSoFar from balance delta)            |
//+------------------------------------------------------------------+
#ifndef STATE_PERSISTENCE_MQH
#define STATE_PERSISTENCE_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| CStatePersistence - GlobalVariables State Manager                 |
//+------------------------------------------------------------------+
class CStatePersistence
{
private:
   //--- Variable name prefix (unique per EA instance via magic number)
   string   m_prefix;
   int      m_magicNumber;
   
   //--- Logger
   CLogger  m_log;
   
   //--- Key names
   string   KeyInitialBalance(void)      { return m_prefix + "InitBal"; }
   string   KeyTradingDaysCompleted(void){ return m_prefix + "DaysComp"; }
   string   KeyPeakEquity(void)          { return m_prefix + "PeakEq"; }
   string   KeyConsecutiveLosses(void)   { return m_prefix + "ConsLoss"; }
   string   KeyConsecutiveWins(void)     { return m_prefix + "ConsWins"; }
   string   KeyAggressiveness(void)      { return m_prefix + "AggLevel"; }
   string   KeyChallengeStart(void)      { return m_prefix + "StartDate"; }
   string   KeyLastTradeClose(void)      { return m_prefix + "LastClose"; }
   string   KeyDaysWithTrades(void)      { return m_prefix + "DaysTrad"; }
   string   KeyLossStreakDampen(void)    { return m_prefix + "LossDamp"; }
   string   KeyStateVersion(void)        { return m_prefix + "Version"; }
   
   //--- State version for compatibility checking
   double   m_stateVersion;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CStatePersistence(void)
   {
      m_log.SetPrefix("State");
      m_magicNumber = 0;
      m_prefix = "";
      m_stateVersion = 2.0;
   }
   
   //+------------------------------------------------------------------+
   //| Initialize with magic number to create unique variable names      |
   //| Parameters:                                                       |
   //|   magicNumber - EA magic number for instance isolation            |
   //| Returns: void                                                     |
   //+------------------------------------------------------------------+
   void Initialize(int magicNumber)
   {
      m_magicNumber = magicNumber;
      m_prefix = StringFormat("FEA_%d_", magicNumber);
      m_log.Info(StringFormat("StatePersistence initialized with prefix: %s", m_prefix));
   }
   
   //+------------------------------------------------------------------+
   //| Save current state to GlobalVariables                             |
   //| Parameters:                                                       |
   //|   state - current engine state to persist                         |
   //| Returns: true if all variables saved successfully                 |
   //| Side Effects: Creates/updates GlobalVariables                     |
   //+------------------------------------------------------------------+
   bool SaveState(const SEngineState &state)
   {
      bool success = true;
      
      success &= SaveDouble(KeyInitialBalance(), state.InitialBalance);
      success &= SaveDouble(KeyTradingDaysCompleted(), (double)state.TradingDaysCompleted);
      success &= SaveDouble(KeyPeakEquity(), state.PeakEquity);
      success &= SaveDouble(KeyConsecutiveLosses(), (double)state.ConsecutiveLosses);
      success &= SaveDouble(KeyConsecutiveWins(), (double)state.ConsecutiveWins);
      success &= SaveDouble(KeyAggressiveness(), (double)state.AggressivenessLevel);
      success &= SaveDouble(KeyChallengeStart(), (double)state.ChallengeStartDate);
      success &= SaveDouble(KeyLastTradeClose(), (double)state.LastTradeCloseTime);
      success &= SaveDouble(KeyLossStreakDampen(), (double)state.LossStreakDampenTradesLeft);
      success &= SaveDouble(KeyStateVersion(), m_stateVersion);
      
      if(!success)
         m_log.Warn("Some state variables failed to save. Check GlobalVariables.");
      
      return success;
   }
   
   //+------------------------------------------------------------------+
   //| Restore state from GlobalVariables                                |
   //| Parameters:                                                       |
   //|   state - engine state to restore into                            |
   //| Returns: true if state was found and restored                     |
   //| Side Effects: Modifies state with persisted values                |
   //+------------------------------------------------------------------+
   bool RestoreState(SEngineState &state)
   {
      //--- Check if state exists
      if(!GlobalVariableCheck(KeyStateVersion()))
      {
         m_log.Info("No persisted state found. Starting fresh.");
         return false;
      }
      
      //--- Check version compatibility
      double savedVersion = LoadDouble(KeyStateVersion(), 0);
      if(savedVersion < 2.0)
      {
         m_log.Warn(StringFormat("State version mismatch: saved=%.1f, current=%.1f. Starting fresh.",
                    savedVersion, m_stateVersion));
         ClearState();
         return false;
      }
      
      //--- Restore all variables
      double initBal = LoadDouble(KeyInitialBalance(), 0);
      if(initBal <= 0)
      {
         m_log.Warn("Persisted InitialBalance is invalid. Starting fresh.");
         ClearState();
         return false;
      }
      
      state.InitialBalance = initBal;
      state.TradingDaysCompleted = (int)LoadDouble(KeyTradingDaysCompleted(), 0);
      state.PeakEquity = LoadDouble(KeyPeakEquity(), initBal);
      state.ConsecutiveLosses = (int)LoadDouble(KeyConsecutiveLosses(), 0);
      state.ConsecutiveWins = (int)LoadDouble(KeyConsecutiveWins(), 0);
      state.AggressivenessLevel = (ENUM_AGGRESSIVENESS_LEVEL)(int)LoadDouble(KeyAggressiveness(), AGG_BALANCED);
      state.ChallengeStartDate = (datetime)(long)LoadDouble(KeyChallengeStart(), 0);
      state.LastTradeCloseTime = (datetime)(long)LoadDouble(KeyLastTradeClose(), 0);
      state.LossStreakDampenTradesLeft = (int)LoadDouble(KeyLossStreakDampen(), 0);
      
      //--- Set day-start equity from current equity (we're starting a new session)
      state.DayStartEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      state.LowestEquityToday = state.DayStartEquity;
      state.CurrentBalance = AccountInfoDouble(ACCOUNT_BALANCE);
      state.CurrentEquity = AccountInfoDouble(ACCOUNT_EQUITY);
      
      //--- Ensure PeakEquity is at least current equity
      if(state.PeakEquity < state.CurrentEquity)
         state.PeakEquity = state.CurrentEquity;
      
      //--- Validate aggressiveness level range
      if((int)state.AggressivenessLevel < 0 || (int)state.AggressivenessLevel > 3)
         state.AggressivenessLevel = AGG_BALANCED;
      
      //--- Validate challenge start date
      if(state.ChallengeStartDate <= 0 || state.ChallengeStartDate > TimeCurrent())
         state.ChallengeStartDate = TimeCurrent();
      
      m_log.Info("State restored successfully:");
      m_log.Info(StringFormat("  InitialBalance: $%.2f", state.InitialBalance));
      m_log.Info(StringFormat("  TradingDaysCompleted: %d", state.TradingDaysCompleted));
      m_log.Info(StringFormat("  PeakEquity: $%.2f", state.PeakEquity));
      m_log.Info(StringFormat("  ConsecutiveLosses: %d | ConsecutiveWins: %d",
                 state.ConsecutiveLosses, state.ConsecutiveWins));
      m_log.Info(StringFormat("  AggressivenessLevel: %s", AggressivenessToString(state.AggressivenessLevel)));
      m_log.Info(StringFormat("  ChallengeStartDate: %s", TimeToString(state.ChallengeStartDate, TIME_DATE)));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Clear all persisted state (fresh start)                           |
   //| Returns: void                                                     |
   //+------------------------------------------------------------------+
   void ClearState(void)
   {
      DeleteKey(KeyInitialBalance());
      DeleteKey(KeyTradingDaysCompleted());
      DeleteKey(KeyPeakEquity());
      DeleteKey(KeyConsecutiveLosses());
      DeleteKey(KeyConsecutiveWins());
      DeleteKey(KeyAggressiveness());
      DeleteKey(KeyChallengeStart());
      DeleteKey(KeyLastTradeClose());
      DeleteKey(KeyDaysWithTrades());
      DeleteKey(KeyLossStreakDampen());
      DeleteKey(KeyStateVersion());
      
      m_log.Info("All persisted state cleared. Fresh start on next init.");
   }
   
   //+------------------------------------------------------------------+
   //| Check if any persisted state exists for this EA instance          |
   //+------------------------------------------------------------------+
   bool HasPersistedState(void)
   {
      return GlobalVariableCheck(KeyStateVersion());
   }
   
   //+------------------------------------------------------------------+
   //| Increment trading days completed counter                          |
   //| Call this when a day with at least one closed trade ends          |
   //+------------------------------------------------------------------+
   void IncrementTradingDays(SEngineState &state)
   {
      state.TradingDaysCompleted++;
      SaveDouble(KeyTradingDaysCompleted(), (double)state.TradingDaysCompleted);
      m_log.Info(StringFormat("Trading days completed: %d", state.TradingDaysCompleted));
   }
   
   //+------------------------------------------------------------------+
   //| Update peak equity if current equity is higher                    |
   //+------------------------------------------------------------------+
   void UpdatePeakEquity(SEngineState &state, double currentEquity)
   {
      if(currentEquity > state.PeakEquity)
      {
         state.PeakEquity = currentEquity;
         SaveDouble(KeyPeakEquity(), currentEquity);
      }
   }

private:
   //+------------------------------------------------------------------+
   //| Save a double value to GlobalVariables                            |
   //+------------------------------------------------------------------+
   bool SaveDouble(string key, double value)
   {
      datetime result = GlobalVariableSet(key, value);
      if(result == 0)
      {
         m_log.Debug(StringFormat("Failed to save GV: %s = %.4f (error=%d)", key, value, GetLastError()));
         return false;
      }
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Load a double value from GlobalVariables                          |
   //+------------------------------------------------------------------+
   double LoadDouble(string key, double defaultValue)
   {
      if(!GlobalVariableCheck(key))
         return defaultValue;
      
      double value = GlobalVariableGet(key);
      return value;
   }
   
   //+------------------------------------------------------------------+
   //| Delete a GlobalVariable key                                       |
   //+------------------------------------------------------------------+
   void DeleteKey(string key)
   {
      if(GlobalVariableCheck(key))
         GlobalVariableDel(key);
   }
};

#endif // STATE_PERSISTENCE_MQH
