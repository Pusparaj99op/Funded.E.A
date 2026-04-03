//+------------------------------------------------------------------+
//|                                                       Utils.mqh  |
//|                         Funded.E.A Development Team              |
//|                         Utility Functions & Shared Definitions   |
//+------------------------------------------------------------------+
#ifndef UTILS_MQH
#define UTILS_MQH

//+------------------------------------------------------------------+
//| Version & Constants                                               |
//+------------------------------------------------------------------+
#define EA_VERSION          "2.0.0"
#define EA_NAME             "Funded.E.A"
#define EA_MAGIC_PREFIX     "FEA_"
#define EA_SYMBOL           "XAUUSD"

// Maximum constants
#define MAX_TRADES_PER_DAY_HARD_LIMIT  3
#define MIN_TRADES_PER_DAY             1
#define MAX_RISK_PER_TRADE_PCT         1.0    // Hard cap: 1% of balance
#define MIN_RISK_PER_TRADE_PCT         0.25   // Floor: never below 0.25%
#define ACCELERATED_RISK_CAP_PCT       0.75   // Accelerated mode cap
#define DAILY_DD_BUDGET_RATIO          0.60   // Never risk > 60% of daily DD limit
#define DAILY_BUDGET_PROFIT_MULT       2.5    // Never risk > 2.5x required daily profit
#define EXPECTED_LOSS_RATE             0.55   // Default expected loss rate (55%)
#define LATENCY_WARNING_MS             200    // Warn if RTT > 200ms
#define LATENCY_HALT_MS                500    // Halt if RTT > 500ms
#define TRAILING_STOP_UPDATE_MS        1000   // Min interval between SL updates
#define MAX_ORDER_RETRIES              3      // Max retries on order failure
#define ORDER_RETRY_DELAY_MS           500    // Delay between retries
#define EMERGENCY_DD_TIME_SEC          300    // 5 minutes for emergency DD check
#define EMERGENCY_DD_PCT               2.0    // 2% drop in 5 min -> halt
#define EMERGENCY_HALT_DURATION_SEC    1800   // 30 min halt on emergency
#define MONDAY_OPEN_BLOCK_SEC          300    // Block first 5 min of Monday

//+------------------------------------------------------------------+
//| Enumerations                                                      |
//+------------------------------------------------------------------+

//--- Aggressiveness level computed by the Challenge Calibration Engine
enum ENUM_AGGRESSIVENESS_LEVEL
{
   AGG_CONSERVATIVE  = 0,   // Risk-averse: near target or high DD usage
   AGG_BALANCED      = 1,   // Default: normal pace, moderate risk
   AGG_ACCELERATED   = 2,   // Time pressure: increased pace within caps
   AGG_PAUSED        = 3    // Halted: breach risk too high or target met
};

//--- Challenge phase
enum ENUM_CHALLENGE_PHASE
{
   PHASE_1           = 0,   // Phase 1 evaluation
   PHASE_2           = 1,   // Phase 2 verification
   PHASE_LIVE_FUNDED = 2    // Live funded account
};

//--- Funded firm presets
enum ENUM_FIRM_PRESET
{
   FIRM_FTMO         = 0,
   FIRM_THE5ERS      = 1,
   FIRM_APEX         = 2,
   FIRM_MYFUNDEDFX   = 3,
   FIRM_MFF          = 4,
   FIRM_BLUEGUARDIAN = 5,
   FIRM_CUSTOM       = 6
};

//--- Session state
enum ENUM_SESSION_STATE
{
   SESSION_NONE      = 0,   // No active session (outside all windows)
   SESSION_ASIAN     = 1,   // Asian session (00:00-09:00 GMT)
   SESSION_LONDON    = 2,   // London session (07:00-16:00 GMT)
   SESSION_NEWYORK   = 3,   // New York session (12:00-21:00 GMT)
   SESSION_OVERLAP   = 4    // London-NY overlap (12:00-16:00 GMT)
};

//--- Pace status for dashboard display
enum ENUM_PACE_STATUS
{
   PACE_ON_TRACK     = 0,   // Green: on pace or ahead
   PACE_SLIGHTLY_BEHIND = 1,// Yellow: slightly behind
   PACE_BEHIND       = 2,   // Red: significantly behind
   PACE_AHEAD        = 3    // Blue: ahead of schedule
};

//--- Dashboard corner
enum ENUM_DASHBOARD_CORNER
{
   CORNER_TOP_LEFT      = 0,
   CORNER_TOP_RIGHT     = 1,
   CORNER_BOTTOM_LEFT   = 2,
   CORNER_BOTTOM_RIGHT  = 3
};

//--- Order rejection reason (for logging)
enum ENUM_ORDER_REJECTION_REASON
{
   REJECT_NONE              = 0,
   REJECT_SPREAD_TOO_WIDE   = 1,
   REJECT_SLIPPAGE_TOO_HIGH = 2,
   REJECT_REQUOTE           = 3,
   REJECT_LATENCY_TOO_HIGH  = 4,
   REJECT_PARTIAL_FILL      = 5,
   REJECT_TRADE_CONTEXT_BUSY= 6,
   REJECT_NOT_ALLOWED       = 7,
   REJECT_INSUFFICIENT_MARGIN = 8,
   REJECT_BROKER_ERROR      = 9,
   REJECT_MAX_RETRIES       = 10,
   REJECT_DD_LIMIT          = 11,
   REJECT_PAUSED_MODE       = 12,
   REJECT_SETUP_SCORE_LOW   = 13,
   REJECT_COST_TOO_HIGH     = 14,
   REJECT_NEWS_WINDOW       = 15,
   REJECT_FRIDAY_CLOSE      = 16,
   REJECT_DAILY_LIMIT       = 17,
   REJECT_CONSISTENCY_RULE  = 18,
   REJECT_EMERGENCY_HALT    = 19
};

//+------------------------------------------------------------------+
//| Structures                                                        |
//+------------------------------------------------------------------+

//--- Core engine state snapshot (computed daily + updated intraday)
struct SEngineState
{
   // --- Challenge metrics
   double   InitialBalance;
   double   CurrentBalance;
   double   CurrentEquity;
   double   ProfitTargetAmount;
   double   DailyDDLimit;
   double   TotalDDLimit;
   int      TradingDaysCompleted;
   int      TradingDaysRemaining;
   double   ProfitSoFar;
   double   ProfitRemaining;
   double   DailyDDUsedToday;
   double   TotalDDUsed;
   double   PeakEquity;
   double   LowestEquityToday;
   double   DayStartEquity;
   
   // --- Computed outputs
   double   RequiredDailyProfit;
   double   DailyBudget;
   double   RiskPerTrade;        // As percentage of balance
   double   RiskPerTradeUSD;     // Dollar amount
   int      MaxTradesPerDay;
   ENUM_AGGRESSIVENESS_LEVEL AggressivenessLevel;
   ENUM_PACE_STATUS PaceStatus;
   
   // --- Intraday tracking
   int      TradesToday;
   double   DailyProfitToday;
   int      ConsecutiveLosses;
   int      ConsecutiveWins;
   int      LossStreakDampenTradesLeft; // Trades remaining under dampened risk
   bool     DailyTargetMet;
   bool     TradingLockedToday;
   bool     EmergencyHalt;
   datetime EmergencyHaltUntil;
   
   // --- Session info
   ENUM_SESSION_STATE CurrentSession;
   bool     IsNewsWindow;
   bool     IsFridayClose;
   
   // --- Timestamps
   datetime ChallengeStartDate;
   datetime LastCalibrationTime;
   datetime LastTradeCloseTime;
   int      CurrentTradingDay;   // Sequential day counter
   
   //--- Constructor: Initialize all fields
   void Reset()
   {
      InitialBalance = 0;
      CurrentBalance = 0;
      CurrentEquity = 0;
      ProfitTargetAmount = 0;
      DailyDDLimit = 0;
      TotalDDLimit = 0;
      TradingDaysCompleted = 0;
      TradingDaysRemaining = 0;
      ProfitSoFar = 0;
      ProfitRemaining = 0;
      DailyDDUsedToday = 0;
      TotalDDUsed = 0;
      PeakEquity = 0;
      LowestEquityToday = 0;
      DayStartEquity = 0;
      
      RequiredDailyProfit = 0;
      DailyBudget = 0;
      RiskPerTrade = 0;
      RiskPerTradeUSD = 0;
      MaxTradesPerDay = MAX_TRADES_PER_DAY_HARD_LIMIT;
      AggressivenessLevel = AGG_BALANCED;
      PaceStatus = PACE_ON_TRACK;
      
      TradesToday = 0;
      DailyProfitToday = 0;
      ConsecutiveLosses = 0;
      ConsecutiveWins = 0;
      LossStreakDampenTradesLeft = 0;
      DailyTargetMet = false;
      TradingLockedToday = false;
      EmergencyHalt = false;
      EmergencyHaltUntil = 0;
      
      CurrentSession = SESSION_NONE;
      IsNewsWindow = false;
      IsFridayClose = false;
      
      ChallengeStartDate = 0;
      LastCalibrationTime = 0;
      LastTradeCloseTime = 0;
      CurrentTradingDay = 0;
   }
};

//--- Setup score breakdown for transparency
struct SSetupScore
{
   int      TotalScore;         // 0-100
   int      TrendAlignment;     // 0 or 20
   int      OrderBlockZone;     // 0 or 20
   int      FVGPresence;        // 0 or 15
   int      FibConfluence;      // 0 or 15
   int      LiquiditySweep;     // 0 or 15
   int      SessionBonus;       // 0 or 10
   int      VolumeSpike;        // 0 or 5
   int      MinScoreRequired;   // Threshold based on aggressiveness
   bool     IsBullish;          // Trade direction
   double   SuggestedSL;        // Suggested stop loss price
   double   SuggestedEntry;     // Suggested entry price
   double   SuggestedTP1;       // 1:1 RR
   double   SuggestedTP2;       // 1:2 RR
   double   SuggestedTP3;       // Fib extension
   double   SLDistancePoints;   // SL distance in points
   
   void Reset()
   {
      TotalScore = 0;
      TrendAlignment = 0;
      OrderBlockZone = 0;
      FVGPresence = 0;
      FibConfluence = 0;
      LiquiditySweep = 0;
      SessionBonus = 0;
      VolumeSpike = 0;
      MinScoreRequired = 65;
      IsBullish = true;
      SuggestedSL = 0;
      SuggestedEntry = 0;
      SuggestedTP1 = 0;
      SuggestedTP2 = 0;
      SuggestedTP3 = 0;
      SLDistancePoints = 0;
   }
};

//--- Execution cost model per trade
struct STradeCost
{
   double   SpreadCostUSD;      // Spread cost at time of evaluation
   double   CommissionUSD;      // Expected commission (round-trip)
   double   EstSlippageUSD;     // Estimated slippage based on rolling average
   double   EstSwapUSD;         // Estimated swap (0 if intraday)
   double   TotalCostUSD;       // Sum of all costs
   double   MinimumTPRequired;  // TP must be > TotalCost * 3
   int      CurrentSpreadPts;   // Current spread in points
   double   AvgSlippagePts;     // Rolling average slippage in points
   
   void Reset()
   {
      SpreadCostUSD = 0;
      CommissionUSD = 0;
      EstSlippageUSD = 0;
      EstSwapUSD = 0;
      TotalCostUSD = 0;
      MinimumTPRequired = 0;
      CurrentSpreadPts = 0;
      AvgSlippagePts = 0;
   }
};

//--- Firm preset rules container
struct SFirmRules
{
   string   FirmName;
   double   ProfitTargetPct_Phase1;
   double   ProfitTargetPct_Phase2;
   double   MaxDailyDrawdownPct;
   double   MaxTotalDrawdownPct;
   int      MinTradingDays;
   int      TotalChallengeDays;
   bool     ConsistencyRule;
   double   MaxSingleDayProfitPct;
   bool     NewsRestriction;
   bool     WeekendHoldingAllowed;
   
   void Reset()
   {
      FirmName = "Custom";
      ProfitTargetPct_Phase1 = 8.0;
      ProfitTargetPct_Phase2 = 5.0;
      MaxDailyDrawdownPct = 5.0;
      MaxTotalDrawdownPct = 10.0;
      MinTradingDays = 5;
      TotalChallengeDays = 30;
      ConsistencyRule = false;
      MaxSingleDayProfitPct = 40.0;
      NewsRestriction = false;
      WeekendHoldingAllowed = false;
   }
};

//+------------------------------------------------------------------+
//| CLogger - Structured logging utility                              |
//| Purpose: Provides consistent, timestamped, categorized logging    |
//+------------------------------------------------------------------+
class CLogger
{
private:
   string   m_prefix;       // Log prefix (module name)
   bool     m_verbose;      // Enable verbose (debug) logs
   
public:
   //--- Constructor
   CLogger(void) : m_prefix(EA_NAME), m_verbose(false) {}
   CLogger(string prefix, bool verbose=false) : m_prefix(prefix), m_verbose(verbose) {}
   
   //--- Set prefix for module identification
   void SetPrefix(string prefix) { m_prefix = prefix; }
   
   //--- Set verbose mode
   void SetVerbose(bool verbose) { m_verbose = verbose; }
   
   //--- Info level log
   void Info(string message)
   {
      Print("[", m_prefix, "] [INFO] ", message);
   }
   
   //--- Warning level log
   void Warn(string message)
   {
      Print("[", m_prefix, "] [WARN] ", message);
   }
   
   //--- Error level log
   void Error(string message)
   {
      Print("[", m_prefix, "] [ERROR] ", message);
   }
   
   //--- Debug level log (only if verbose)
   void Debug(string message)
   {
      if(m_verbose)
         Print("[", m_prefix, "] [DEBUG] ", message);
   }
   
   //--- Trade-specific log
   void Trade(string message)
   {
      Print("[", m_prefix, "] [TRADE] ", message);
   }
   
   //--- Engine decision log
   void Engine(string message)
   {
      Print("[", m_prefix, "] [ENGINE] ", message);
   }
   
   //--- Risk event log
   void Risk(string message)
   {
      Print("[", m_prefix, "] [RISK] ", message);
   }
   
   //--- Cost/execution log
   void Cost(string message)
   {
      Print("[", m_prefix, "] [COST] ", message);
   }
   
   //--- Format a double value with specified digits
   string FormatDouble(double value, int digits=2)
   {
      return DoubleToString(value, digits);
   }
   
   //--- Format currency value
   string FormatCurrency(double value)
   {
      return "$" + DoubleToString(value, 2);
   }
   
   //--- Format percentage
   string FormatPct(double value)
   {
      return DoubleToString(value, 2) + "%";
   }
};

//+------------------------------------------------------------------+
//| CTimeUtils - Time-related helper functions                        |
//+------------------------------------------------------------------+
class CTimeUtils
{
private:
   int      m_serverOffset;  // Server timezone offset from GMT in hours
   
public:
   //--- Constructor
   CTimeUtils(void) : m_serverOffset(2) {}
   CTimeUtils(int serverOffset) : m_serverOffset(serverOffset) {}
   
   //--- Set server timezone offset
   void SetServerOffset(int offset) { m_serverOffset = offset; }
   
   //--- Get current GMT time from server time
   datetime GetGMTTime(void)
   {
      return TimeCurrent() - m_serverOffset * 3600;
   }
   
   //--- Get GMT hour from server time
   int GetGMTHour(void)
   {
      MqlDateTime dt;
      datetime gmtTime = GetGMTTime();
      TimeToStruct(gmtTime, dt);
      return dt.hour;
   }
   
   //--- Get day of week (0=Sunday, 5=Friday)
   int GetDayOfWeek(void)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      return dt.day_of_week;
   }
   
   //--- Check if today is a new trading day compared to last known day
   bool IsNewTradingDay(datetime lastKnownDay)
   {
      MqlDateTime dtNow, dtLast;
      TimeToStruct(TimeCurrent(), dtNow);
      TimeToStruct(lastKnownDay, dtLast);
      
      return (dtNow.year != dtLast.year || 
              dtNow.mon != dtLast.mon || 
              dtNow.day != dtLast.day);
   }
   
   //--- Get the start of the current server day (00:00:00)
   datetime GetDayStart(void)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      dt.hour = 0;
      dt.min = 0;
      dt.sec = 0;
      return StructToTime(dt);
   }
   
   //--- Check if it's Friday
   bool IsFriday(void)
   {
      return (GetDayOfWeek() == 5);
   }
   
   //--- Check if it's Monday
   bool IsMonday(void)
   {
      return (GetDayOfWeek() == 1);
   }
   
   //--- Check if it's Wednesday
   bool IsWednesday(void)
   {
      return (GetDayOfWeek() == 3);
   }
   
   //--- Check if within Monday open blocking period (first 5 minutes)
   bool IsMondayOpenBlock(void)
   {
      if(!IsMonday()) return false;
      
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      // Check if within first 5 minutes of Monday
      return (dt.hour == 0 && dt.min < 5);
   }
   
   //--- Get current session state based on GMT hour
   ENUM_SESSION_STATE GetCurrentSession(void)
   {
      int gmtHour = GetGMTHour();
      
      bool isLondon = (gmtHour >= 7 && gmtHour < 16);
      bool isNY     = (gmtHour >= 12 && gmtHour < 21);
      bool isAsian  = (gmtHour >= 0 && gmtHour < 9);
      
      if(isLondon && isNY)
         return SESSION_OVERLAP;
      if(isLondon)
         return SESSION_LONDON;
      if(isNY)
         return SESSION_NEWYORK;
      if(isAsian)
         return SESSION_ASIAN;
         
      return SESSION_NONE;
   }
   
   //--- Get session name string
   string GetSessionName(ENUM_SESSION_STATE session)
   {
      switch(session)
      {
         case SESSION_ASIAN:   return "ASIAN";
         case SESSION_LONDON:  return "LONDON";
         case SESSION_NEWYORK: return "NEW YORK";
         case SESSION_OVERLAP: return "LDN/NY OVERLAP";
         case SESSION_NONE:    return "OFF-HOURS";
         default:              return "UNKNOWN";
      }
   }
   
   //--- Calculate calendar days between two dates
   int CalendarDaysBetween(datetime start, datetime end)
   {
      if(end <= start) return 0;
      return (int)((end - start) / 86400);
   }
   
   //--- Calculate trading days elapsed (weekdays only) since start
   int TradingDaysElapsed(datetime startDate)
   {
      datetime now = TimeCurrent();
      if(now <= startDate) return 0;
      
      int totalDays = CalendarDaysBetween(startDate, now);
      int weeks = totalDays / 7;
      int remainder = totalDays % 7;
      
      int tradingDays = weeks * 5;
      
      MqlDateTime dtStart;
      TimeToStruct(startDate, dtStart);
      int startDow = dtStart.day_of_week;
      
      for(int i = 0; i < remainder; i++)
      {
         int dow = (startDow + i + 1) % 7;
         if(dow != 0 && dow != 6) // Not Sunday or Saturday
            tradingDays++;
      }
      
      return tradingDays;
   }
   
   //--- Check if close to Wednesday overnight swap (22:30 server time)
   bool IsNearWednesdaySwap(int minutesBefore=30)
   {
      if(!IsWednesday()) return false;
      
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      // Check if within minutesBefore of 23:00 server time
      int minutesUntilSwap = (23 * 60) - (dt.hour * 60 + dt.min);
      return (minutesUntilSwap >= 0 && minutesUntilSwap <= minutesBefore);
   }
   
   //--- Check if Friday close time reached
   bool IsFridayCloseTime(int fridayCloseHourGMT)
   {
      if(!IsFriday()) return false;
      int gmtHour = GetGMTHour();
      return (gmtHour >= fridayCloseHourGMT);
   }
};

//+------------------------------------------------------------------+
//| CMathUtils - Mathematical helper functions                        |
//+------------------------------------------------------------------+
class CMathUtils
{
public:
   //--- Clamp a value between min and max
   static double Clamp(double value, double minVal, double maxVal)
   {
      if(value < minVal) return minVal;
      if(value > maxVal) return maxVal;
      return value;
   }
   
   //--- Clamp an integer between min and max
   static int ClampInt(int value, int minVal, int maxVal)
   {
      if(value < minVal) return minVal;
      if(value > maxVal) return maxVal;
      return value;
   }
   
   //--- Safe division (avoid divide by zero)
   static double SafeDiv(double numerator, double denominator, double defaultVal=0.0)
   {
      if(MathAbs(denominator) < 1e-10) return defaultVal;
      return numerator / denominator;
   }
   
   //--- Calculate percentage
   static double Percentage(double part, double whole)
   {
      return SafeDiv(part, whole, 0.0) * 100.0;
   }
   
   //--- Round to step (for lot sizing)
   static double RoundToStep(double value, double step)
   {
      if(step <= 0) return value;
      return MathFloor(value / step) * step;
   }
   
   //--- Normalize lot size to broker specifications
   static double NormalizeLot(string symbol, double lots)
   {
      double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
      double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
      double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
      
      lots = RoundToStep(lots, lotStep);
      lots = Clamp(lots, minLot, maxLot);
      
      return NormalizeDouble(lots, (int)MathCeil(-MathLog10(lotStep)));
   }
   
   //--- Normalize price to broker tick size
   static double NormalizePrice(string symbol, double price)
   {
      double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
      if(tickSize <= 0) return NormalizeDouble(price, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
      return NormalizeDouble(MathRound(price / tickSize) * tickSize, (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS));
   }
   
   //--- Calculate linear interpolation
   static double Lerp(double a, double b, double t)
   {
      t = Clamp(t, 0.0, 1.0);
      return a + (b - a) * t;
   }
   
   //--- Simple moving average of an array
   static double ArrayAverage(double &arr[], int count=-1)
   {
      int size = ArraySize(arr);
      if(size == 0) return 0;
      if(count <= 0 || count > size) count = size;
      
      double sum = 0;
      for(int i = size - count; i < size; i++)
         sum += arr[i];
      
      return sum / count;
   }
};

//+------------------------------------------------------------------+
//| CLatencyMeter - Measures broker round-trip time                   |
//+------------------------------------------------------------------+
class CLatencyMeter
{
private:
   double   m_lastRTT;           // Last measured RTT in ms
   double   m_avgRTT;            // Rolling average RTT
   double   m_rttSamples[];      // RTT sample history
   int      m_maxSamples;        // Max samples to keep
   CLogger  m_log;
   
public:
   //--- Constructor
   CLatencyMeter(void) : m_lastRTT(0), m_avgRTT(0), m_maxSamples(20)
   {
      m_log.SetPrefix("Latency");
      ArrayResize(m_rttSamples, 0);
   }
   
   //--- Measure broker round-trip time by querying account info
   double MeasureRTT(void)
   {
      uint startTick = GetTickCount();
      
      // Perform a lightweight broker query to measure RTT
      double balance = AccountInfoDouble(ACCOUNT_BALANCE);
      
      uint endTick = GetTickCount();
      m_lastRTT = (double)(endTick - startTick);
      
      // Add to sample history
      int size = ArraySize(m_rttSamples);
      if(size >= m_maxSamples)
      {
         // Shift array left (remove oldest)
         for(int i = 0; i < size - 1; i++)
            m_rttSamples[i] = m_rttSamples[i + 1];
         m_rttSamples[size - 1] = m_lastRTT;
      }
      else
      {
         ArrayResize(m_rttSamples, size + 1);
         m_rttSamples[size] = m_lastRTT;
      }
      
      // Update average
      m_avgRTT = CMathUtils::ArrayAverage(m_rttSamples);
      
      return m_lastRTT;
   }
   
   //--- Get last measured RTT
   double GetLastRTT(void) const { return m_lastRTT; }
   
   //--- Get average RTT
   double GetAverageRTT(void) const { return m_avgRTT; }
   
   //--- Check if latency is acceptable for trading
   bool IsLatencyOK(void) const
   {
      return (m_lastRTT < LATENCY_HALT_MS);
   }
   
   //--- Check if latency warrants a warning
   bool IsLatencyWarning(void) const
   {
      return (m_lastRTT >= LATENCY_WARNING_MS && m_lastRTT < LATENCY_HALT_MS);
   }
   
   //--- Get latency status string for dashboard
   string GetLatencyStatus(void)
   {
      if(m_lastRTT < LATENCY_WARNING_MS)
         return StringFormat("%.0fms [OK]", m_lastRTT);
      else if(m_lastRTT < LATENCY_HALT_MS)
         return StringFormat("%.0fms [WARN]", m_lastRTT);
      else
         return StringFormat("%.0fms [HALT]", m_lastRTT);
   }
   
   //--- Initial startup measurement with logging
   void StartupMeasure(void)
   {
      double rtt = MeasureRTT();
      m_log.Info(StringFormat("Broker RTT: %.0fms", rtt));
      
      if(rtt >= LATENCY_HALT_MS)
         m_log.Error(StringFormat("CRITICAL: Broker RTT %.0fms exceeds halt threshold %dms! Market orders blocked.", 
                     rtt, LATENCY_HALT_MS));
      else if(rtt >= LATENCY_WARNING_MS)
         m_log.Warn(StringFormat("HIGH LATENCY: Broker RTT %.0fms exceeds warning threshold %dms. Execution quality degraded.", 
                    rtt, LATENCY_WARNING_MS));
   }
};

//+------------------------------------------------------------------+
//| CSlippageTracker - Rolling average slippage tracker               |
//+------------------------------------------------------------------+
class CSlippageTracker
{
private:
   double   m_slippageSamples[];  // Slippage values in points
   int      m_maxSamples;         // Rolling window size
   double   m_totalSlippage;      // Cumulative slippage this session
   int      m_totalTrades;        // Total trades tracked
   CLogger  m_log;
   
public:
   //--- Constructor
   CSlippageTracker(void) : m_maxSamples(20), m_totalSlippage(0), m_totalTrades(0)
   {
      m_log.SetPrefix("Slippage");
      ArrayResize(m_slippageSamples, 0);
   }
   
   //--- Record a slippage observation (in points)
   void RecordSlippage(double slippagePoints)
   {
      int size = ArraySize(m_slippageSamples);
      if(size >= m_maxSamples)
      {
         for(int i = 0; i < size - 1; i++)
            m_slippageSamples[i] = m_slippageSamples[i + 1];
         m_slippageSamples[size - 1] = slippagePoints;
      }
      else
      {
         ArrayResize(m_slippageSamples, size + 1);
         m_slippageSamples[size] = slippagePoints;
      }
      
      m_totalSlippage += MathAbs(slippagePoints);
      m_totalTrades++;
      
      if(slippagePoints > 10)
         m_log.Warn(StringFormat("High slippage detected: %.1f points", slippagePoints));
   }
   
   //--- Get rolling average slippage (last N trades)
   double GetAverageSlippage(void)
   {
      return CMathUtils::ArrayAverage(m_slippageSamples);
   }
   
   //--- Get cumulative slippage
   double GetTotalSlippage(void) const { return m_totalSlippage; }
   
   //--- Get trade count
   int GetTradeCount(void) const { return m_totalTrades; }
};

//+------------------------------------------------------------------+
//| Helper Functions (Global scope)                                   |
//+------------------------------------------------------------------+

//--- Get aggressiveness level name string
string AggressivenessToString(ENUM_AGGRESSIVENESS_LEVEL level)
{
   switch(level)
   {
      case AGG_CONSERVATIVE: return "CONSERVATIVE";
      case AGG_BALANCED:     return "BALANCED";
      case AGG_ACCELERATED:  return "ACCELERATED";
      case AGG_PAUSED:       return "PAUSED";
      default:               return "UNKNOWN";
   }
}

//--- Get phase name string
string PhaseToString(ENUM_CHALLENGE_PHASE phase)
{
   switch(phase)
   {
      case PHASE_1:           return "Phase 1";
      case PHASE_2:           return "Phase 2";
      case PHASE_LIVE_FUNDED: return "Live Funded";
      default:                return "Unknown";
   }
}

//--- Get firm name string
string FirmToString(ENUM_FIRM_PRESET firm)
{
   switch(firm)
   {
      case FIRM_FTMO:       return "FTMO";
      case FIRM_THE5ERS:    return "The5ers";
      case FIRM_APEX:       return "Apex";
      case FIRM_MYFUNDEDFX: return "MyFundedFx";
      case FIRM_MFF:        return "MFF";
      case FIRM_BLUEGUARDIAN: return "BlueGuardian";
      case FIRM_CUSTOM:     return "Custom";
      default:              return "Unknown";
   }
}

//--- Get pace status string
string PaceToString(ENUM_PACE_STATUS pace)
{
   switch(pace)
   {
      case PACE_ON_TRACK:        return "ON TRACK";
      case PACE_SLIGHTLY_BEHIND: return "SLIGHTLY BEHIND";
      case PACE_BEHIND:          return "BEHIND";
      case PACE_AHEAD:           return "AHEAD";
      default:                   return "UNKNOWN";
   }
}

//--- Get rejection reason string
string RejectionToString(ENUM_ORDER_REJECTION_REASON reason)
{
   switch(reason)
   {
      case REJECT_NONE:               return "None";
      case REJECT_SPREAD_TOO_WIDE:    return "Spread Too Wide";
      case REJECT_SLIPPAGE_TOO_HIGH:  return "Slippage Too High";
      case REJECT_REQUOTE:            return "Requote";
      case REJECT_LATENCY_TOO_HIGH:   return "Latency Too High";
      case REJECT_PARTIAL_FILL:       return "Partial Fill Rejected";
      case REJECT_TRADE_CONTEXT_BUSY: return "Trade Context Busy";
      case REJECT_NOT_ALLOWED:        return "Trading Not Allowed";
      case REJECT_INSUFFICIENT_MARGIN:return "Insufficient Margin";
      case REJECT_BROKER_ERROR:       return "Broker Error";
      case REJECT_MAX_RETRIES:        return "Max Retries Exceeded";
      case REJECT_DD_LIMIT:           return "Drawdown Limit";
      case REJECT_PAUSED_MODE:        return "EA Paused";
      case REJECT_SETUP_SCORE_LOW:    return "Setup Score Too Low";
      case REJECT_COST_TOO_HIGH:      return "Execution Cost Too High";
      case REJECT_NEWS_WINDOW:        return "News Window Active";
      case REJECT_FRIDAY_CLOSE:       return "Friday Close";
      case REJECT_DAILY_LIMIT:        return "Daily Trade Limit";
      case REJECT_CONSISTENCY_RULE:   return "Consistency Rule";
      case REJECT_EMERGENCY_HALT:     return "Emergency Halt";
      default:                        return "Unknown";
   }
}

//--- Build a progress bar string [████████░░░░░░░░░░░]
string BuildProgressBar(double percentage, int totalChars=20)
{
   percentage = CMathUtils::Clamp(percentage, 0.0, 100.0);
   int filledChars = (int)MathRound(percentage / 100.0 * totalChars);
   int emptyChars = totalChars - filledChars;
   
   string bar = "[";
   for(int i = 0; i < filledChars; i++) bar += "█";
   for(int i = 0; i < emptyChars; i++) bar += "░";
   bar += "]";
   
   return bar;
}

//--- Get color based on percentage thresholds
color GetStatusColor(double percentage, double greenMax=50.0, double yellowMax=75.0)
{
   if(percentage <= greenMax) return clrLime;
   if(percentage <= yellowMax) return clrYellow;
   return clrRed;
}

//--- Get inverse color (green=good for high values like profit progress)
color GetProgressColor(double percentage, double redMax=30.0, double yellowMax=70.0)
{
   if(percentage <= redMax) return clrRed;
   if(percentage <= yellowMax) return clrYellow;
   return clrLime;
}

//--- Validate symbol is XAUUSD or equivalent
bool ValidateSymbol(string symbol)
{
   // Check common XAUUSD variants
   string upper = symbol;
   StringToUpper(upper);
   
   if(StringFind(upper, "XAUUSD") >= 0) return true;
   if(StringFind(upper, "GOLD") >= 0) return true;
   
   return false;
}

//--- Get XAUUSD tick value per lot (in account currency)
double GetTickValuePerLot(string symbol)
{
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0)
   {
      // Fallback: XAUUSD typical tick value = $0.01 per 0.01 lot per point (i.e. $1 per lot per point)
      Print("[Utils] WARNING: TickValue unavailable, using XAUUSD default $1.0/lot/point");
      tickValue = 1.0;
   }
   return tickValue;
}

//--- Calculate points to USD for given lot size
double PointsToUSD(string symbol, double points, double lots)
{
   double tickValue = GetTickValuePerLot(symbol);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
   
   return (points / tickSize) * tickValue * lots;
}

//--- Calculate USD to points for given lot size  
double USDToPoints(string symbol, double usd, double lots)
{
   double tickValue = GetTickValuePerLot(symbol);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   if(tickSize <= 0) tickSize = SymbolInfoDouble(symbol, SYMBOL_POINT);
   if(tickValue <= 0 || lots <= 0) return 0;
   
   return (usd / (tickValue * lots)) * tickSize;
}

//--- Count open positions with specific magic number
int CountOpenPositions(int magicNumber, string symbol="")
{
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
      
      count++;
   }
   return count;
}

//--- Get total floating P&L for positions with specific magic number
double GetFloatingPnL(int magicNumber, string symbol="")
{
   double totalPnL = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
   {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0) continue;
      
      if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
      if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
      
      totalPnL += PositionGetDouble(POSITION_PROFIT) 
                + PositionGetDouble(POSITION_SWAP);
   }
   return totalPnL;
}

//--- Get closed trades P&L for today (from deal history)
double GetClosedPnLToday(int magicNumber, string symbol="")
{
   datetime dayStart = 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   dayStart = StructToTime(dt);
   
   double totalPnL = 0;
   
   if(!HistorySelect(dayStart, TimeCurrent()))
      return 0;
   
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magicNumber) continue;
      if(symbol != "" && HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol) continue;
      
      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
      {
         totalPnL += HistoryDealGetDouble(ticket, DEAL_PROFIT)
                   + HistoryDealGetDouble(ticket, DEAL_SWAP)
                   + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
      }
   }
   
   return totalPnL;
}

//--- Count closed trades today
int CountClosedTradesToday(int magicNumber, string symbol="")
{
   datetime dayStart = 0;
   MqlDateTime dt;
   TimeToStruct(TimeCurrent(), dt);
   dt.hour = 0; dt.min = 0; dt.sec = 0;
   dayStart = StructToTime(dt);
   
   int count = 0;
   
   if(!HistorySelect(dayStart, TimeCurrent()))
      return 0;
   
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magicNumber) continue;
      if(symbol != "" && HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol) continue;
      
      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry == DEAL_ENTRY_IN)
         count++;
   }
   
   return count;
}

//--- Get the result of the last N closed trades (positive = win, negative = loss)
//--- Returns an array of P&L values (latest at end)
int GetLastTradeResults(int magicNumber, string symbol, double &results[], int maxCount=10)
{
   ArrayResize(results, 0);
   
   datetime weekAgo = TimeCurrent() - 7 * 86400;
   if(!HistorySelect(weekAgo, TimeCurrent()))
      return 0;
   
   // Collect all deal-out entries
   double tempResults[];
   int totalDeals = HistoryDealsTotal();
   for(int i = 0; i < totalDeals; i++)
   {
      ulong ticket = HistoryDealGetTicket(i);
      if(ticket == 0) continue;
      
      if(HistoryDealGetInteger(ticket, DEAL_MAGIC) != magicNumber) continue;
      if(symbol != "" && HistoryDealGetString(ticket, DEAL_SYMBOL) != symbol) continue;
      
      long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
      if(dealEntry == DEAL_ENTRY_OUT || dealEntry == DEAL_ENTRY_OUT_BY)
      {
         double pnl = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                    + HistoryDealGetDouble(ticket, DEAL_SWAP)
                    + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
         
         int size = ArraySize(tempResults);
         ArrayResize(tempResults, size + 1);
         tempResults[size] = pnl;
      }
   }
   
   // Take last maxCount results
   int total = ArraySize(tempResults);
   int startIdx = MathMax(0, total - maxCount);
   int count = total - startIdx;
   
   if(count > 0)
   {
      ArrayResize(results, count);
      for(int i = 0; i < count; i++)
         results[i] = tempResults[startIdx + i];
   }
   
   return ArraySize(results);
}

//--- Count consecutive losses from recent trade history
int CountRecentConsecutiveLosses(int magicNumber, string symbol)
{
   double results[];
   int count = GetLastTradeResults(magicNumber, symbol, results, 10);
   
   int consecutive = 0;
   for(int i = count - 1; i >= 0; i--)
   {
      if(results[i] < 0)
         consecutive++;
      else
         break;
   }
   
   return consecutive;
}

//--- Count consecutive wins from recent trade history
int CountRecentConsecutiveWins(int magicNumber, string symbol)
{
   double results[];
   int count = GetLastTradeResults(magicNumber, symbol, results, 10);
   
   int consecutive = 0;
   for(int i = count - 1; i >= 0; i--)
   {
      if(results[i] > 0)
         consecutive++;
      else
         break;
   }
   
   return consecutive;
}

#endif // UTILS_MQH
