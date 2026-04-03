//+------------------------------------------------------------------+
//|                                             StrategyEngine.mqh   |
//|                         Funded.E.A Development Team              |
//|                         ICT/SMC Strategy & Setup Scoring         |
//+------------------------------------------------------------------+
//| Purpose: Implements the complete ICT Smart Money Concept strategy|
//|   - H4 trend bias (200 EMA)                                     |
//|   - M15/M30 setup identification (OB, FVG, BOS)                 |
//|   - M5 entry trigger (rejection, divergence, momentum)           |
//|   - Setup scoring 0-100                                          |
//|   - SL/TP calculation based on structure                         |
//|   - Trade management (BE, trailing, time exit, partial close)    |
//+------------------------------------------------------------------+
#ifndef STRATEGY_ENGINE_MQH
#define STRATEGY_ENGINE_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Indicator handle container                                        |
//+------------------------------------------------------------------+
struct SIndicatorHandles
{
   int   hEMA200_H4;       // 200 EMA on H4 (trend filter)
   int   hEMA50_H4;        // 50 EMA on H4 (structure S/R)
   int   hEMA20_M15;       // 20 EMA on M15 (short-term momentum)
   int   hATR14_H4;        // ATR(14) on H4 (volatility, SL sizing)
   int   hATR14_M15;       // ATR(14) on M15 (intraday volatility)
   int   hRSI14_M5;        // RSI(14) on M5 (divergence)
   int   hMACD_M15;        // MACD(12,26,9) on M15 (momentum)
   
   void Reset()
   {
      hEMA200_H4 = INVALID_HANDLE;
      hEMA50_H4 = INVALID_HANDLE;
      hEMA20_M15 = INVALID_HANDLE;
      hATR14_H4 = INVALID_HANDLE;
      hATR14_M15 = INVALID_HANDLE;
      hRSI14_M5 = INVALID_HANDLE;
      hMACD_M15 = INVALID_HANDLE;
   }
};

//+------------------------------------------------------------------+
//| Order Block structure                                             |
//+------------------------------------------------------------------+
struct SOrderBlock
{
   double   HighPrice;      // OB high
   double   LowPrice;       // OB low
   double   MidPrice;       // OB midpoint
   datetime Time;           // OB formation time
   bool     IsBullish;      // Bullish OB (demand) or Bearish OB (supply)
   bool     IsValid;        // Still unmitigated
   int      TouchCount;     // Times price returned to zone
};

//+------------------------------------------------------------------+
//| Fair Value Gap structure                                          |
//+------------------------------------------------------------------+
struct SFairValueGap
{
   double   HighPrice;      // FVG upper bound
   double   LowPrice;       // FVG lower bound
   datetime Time;           // FVG formation time
   bool     IsBullish;      // Bullish (gap up) or bearish (gap down)
   bool     IsFilled;       // Already filled by price
};

//+------------------------------------------------------------------+
//| CStrategyEngine - ICT/SMC Setup Detection & Scoring               |
//+------------------------------------------------------------------+
class CStrategyEngine
{
private:
   //--- Configuration
   string               m_symbol;
   int                  m_serverOffset;
   
   //--- Indicator handles
   SIndicatorHandles    m_handles;
   
   //--- Cached indicator values
   double               m_ema200H4;          // Current 200 EMA on H4
   double               m_ema50H4;           // Current 50 EMA on H4
   double               m_ema20M15;          // Current 20 EMA on M15
   double               m_atrH4;             // Current ATR(14) on H4
   double               m_atrM15;            // Current ATR(14) on M15
   double               m_rsiM5;             // Current RSI(14) on M5
   double               m_rsiM5_prev;        // Previous RSI(14) on M5
   double               m_macdMain;          // MACD main line
   double               m_macdSignal;        // MACD signal line
   double               m_macdHist;          // MACD histogram
   double               m_macdHist_prev;     // Previous MACD histogram
   
   //--- Detected structures
   SOrderBlock          m_orderBlocks[];      // Active order blocks (max 10)
   SFairValueGap        m_fvgs[];             // Active FVGs (max 10)
   int                  m_maxStructures;      // Max cached structures
   
   //--- Trade management state
   bool                 m_tp1Hit;             // TP1 reached for current trade
   bool                 m_tp2Hit;             // TP2 reached for current trade
   int                  m_candlesInTrade;     // Candles elapsed since entry
   datetime             m_lastTrailUpdate;    // Last trailing stop update time
   
   //--- Logger
   CLogger              m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CStrategyEngine(void)
   {
      m_log.SetPrefix("Strategy");
      m_symbol = "";
      m_serverOffset = 2;
      m_handles.Reset();
      m_maxStructures = 10;
      m_tp1Hit = false;
      m_tp2Hit = false;
      m_candlesInTrade = 0;
      m_lastTrailUpdate = 0;
      
      m_ema200H4 = 0; m_ema50H4 = 0; m_ema20M15 = 0;
      m_atrH4 = 0; m_atrM15 = 0;
      m_rsiM5 = 50; m_rsiM5_prev = 50;
      m_macdMain = 0; m_macdSignal = 0; m_macdHist = 0; m_macdHist_prev = 0;
      
      ArrayResize(m_orderBlocks, 0);
      ArrayResize(m_fvgs, 0);
   }
   
   //+------------------------------------------------------------------+
   //| Destructor - release indicator handles                            |
   //+------------------------------------------------------------------+
   ~CStrategyEngine(void)
   {
      ReleaseHandles();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize strategy engine and create indicator handles           |
   //| Parameters:                                                       |
   //|   symbol       - trading symbol                                   |
   //|   serverOffset - broker server UTC offset                         |
   //| Returns: void                                                     |
   //| Side Effects: Creates indicator handles                           |
   //+------------------------------------------------------------------+
   void Initialize(string symbol, int serverOffset)
   {
      m_symbol = symbol;
      m_serverOffset = serverOffset;
      
      // Create indicator handles
      m_handles.hEMA200_H4 = iMA(symbol, PERIOD_H4, 200, 0, MODE_EMA, PRICE_CLOSE);
      m_handles.hEMA50_H4  = iMA(symbol, PERIOD_H4, 50, 0, MODE_EMA, PRICE_CLOSE);
      m_handles.hEMA20_M15 = iMA(symbol, PERIOD_M15, 20, 0, MODE_EMA, PRICE_CLOSE);
      m_handles.hATR14_H4  = iATR(symbol, PERIOD_H4, 14);
      m_handles.hATR14_M15 = iATR(symbol, PERIOD_M15, 14);
      m_handles.hRSI14_M5  = iRSI(symbol, PERIOD_M5, 14, PRICE_CLOSE);
      m_handles.hMACD_M15  = iMACD(symbol, PERIOD_M15, 12, 26, 9, PRICE_CLOSE);
      
      // Validate handles
      bool allValid = true;
      if(m_handles.hEMA200_H4 == INVALID_HANDLE) { m_log.Error("Failed to create EMA(200) H4"); allValid = false; }
      if(m_handles.hEMA50_H4 == INVALID_HANDLE)  { m_log.Error("Failed to create EMA(50) H4"); allValid = false; }
      if(m_handles.hEMA20_M15 == INVALID_HANDLE)  { m_log.Error("Failed to create EMA(20) M15"); allValid = false; }
      if(m_handles.hATR14_H4 == INVALID_HANDLE)   { m_log.Error("Failed to create ATR(14) H4"); allValid = false; }
      if(m_handles.hATR14_M15 == INVALID_HANDLE)   { m_log.Error("Failed to create ATR(14) M15"); allValid = false; }
      if(m_handles.hRSI14_M5 == INVALID_HANDLE)    { m_log.Error("Failed to create RSI(14) M5"); allValid = false; }
      if(m_handles.hMACD_M15 == INVALID_HANDLE)     { m_log.Error("Failed to create MACD M15"); allValid = false; }
      
      if(allValid)
         m_log.Info("All indicator handles created successfully.");
      else
         m_log.Warn("Some indicator handles failed. Strategy will have limited capability.");
   }
   
   //+------------------------------------------------------------------+
   //| Main setup evaluation function                                    |
   //| Purpose: Scan all timeframes for a valid ICT/SMC setup            |
   //| Parameters:                                                       |
   //|   score [out] - populated setup score if found                    |
   //|   state       - current engine state                              |
   //| Returns: true if a valid setup was found                          |
   //| Side Effects: Updates score structure                              |
   //+------------------------------------------------------------------+
   bool EvaluateSetup(SSetupScore &score, const SEngineState &state)
   {
      score.Reset();
      
      //=== Step 0: Refresh all indicator values ===
      if(!RefreshIndicators())
      {
         m_log.Debug("Indicator refresh failed. Skipping setup evaluation.");
         return false;
      }
      
      //=== Step 1: H4 Trend Filter (200 EMA) ===
      double currentPrice = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      bool isBullishBias = (currentPrice > m_ema200H4);
      score.IsBullish = isBullishBias;
      
      // Verify ATR(14) on H4 is within normal range (not an extreme spike)
      if(!IsATRNormal())
      {
         m_log.Debug(StringFormat("ATR abnormal (%.2f). Skipping setup.", m_atrH4));
         return false;
      }
      
      //=== Step 2: Detect M15/M30 structures ===
      DetectOrderBlocks();
      DetectFairValueGaps();
      
      //=== Step 3: Setup Scoring (0-100) ===
      
      // Criterion 1: H4 Trend Alignment (+20)
      bool trendAligned = EvaluateTrendAlignment(currentPrice, isBullishBias);
      if(trendAligned)
         score.TrendAlignment = 20;
      
      // Criterion 2: Order Block Zone (+20)
      SOrderBlock activeOB;
      bool inOBZone = FindActiveOrderBlock(currentPrice, isBullishBias, activeOB);
      if(inOBZone)
         score.OrderBlockZone = 20;
      
      // Criterion 3: Fair Value Gap presence (+15)
      SFairValueGap activeFVG;
      bool hasFVG = FindActiveFVG(currentPrice, isBullishBias, activeFVG);
      if(hasFVG)
         score.FVGPresence = 15;
      
      // Criterion 4: Fibonacci confluence (+15)
      bool hasFibConfluence = CheckFibonacciConfluence(currentPrice, isBullishBias);
      if(hasFibConfluence)
         score.FibConfluence = 15;
      
      // Criterion 5: Liquidity sweep (+15)
      bool hasLiquiditySweep = DetectLiquiditySweep(isBullishBias);
      if(hasLiquiditySweep)
         score.LiquiditySweep = 15;
      
      // Criterion 6: Session bonus (+10)
      if(state.CurrentSession == SESSION_LONDON || 
         state.CurrentSession == SESSION_NEWYORK || 
         state.CurrentSession == SESSION_OVERLAP)
         score.SessionBonus = 10;
      
      // Criterion 7: Volume spike (+5)
      bool hasVolumeSpike = DetectVolumeSpike(isBullishBias);
      if(hasVolumeSpike)
         score.VolumeSpike = 5;
      
      // Calculate total
      score.TotalScore = score.TrendAlignment + score.OrderBlockZone + 
                         score.FVGPresence + score.FibConfluence + 
                         score.LiquiditySweep + score.SessionBonus + 
                         score.VolumeSpike;
      
      //=== Step 4: Check minimum score before entry trigger ===
      // Minimum score check is done in the main EA, but we need at least a basic setup
      if(score.TotalScore < 55) // Absolute minimum even for ACCELERATED
      {
         m_log.Debug(StringFormat("Score too low: %d (min 55). No setup.", score.TotalScore));
         return false;
      }
      
      //=== Step 5: M5 Entry Trigger Confirmation ===
      if(!CheckEntryTrigger(isBullishBias, currentPrice))
      {
         m_log.Debug("No M5 entry trigger confirmed. Setup pending.");
         return false;
      }
      
      //=== Step 6: Calculate SL/TP levels ===
      if(!CalculateEntryLevels(score, isBullishBias, currentPrice, activeOB, activeFVG, inOBZone))
      {
         m_log.Debug("Could not calculate valid entry levels.");
         return false;
      }
      
      m_log.Trade(StringFormat("SETUP FOUND: %s | Score=%d | Entry=%.2f | SL=%.2f | TP1=%.2f | TP2=%.2f",
                  isBullishBias ? "BUY" : "SELL", score.TotalScore,
                  score.SuggestedEntry, score.SuggestedSL, score.SuggestedTP1, score.SuggestedTP2));
      m_log.Debug(StringFormat("  Breakdown: Trend=%d OB=%d FVG=%d Fib=%d Liq=%d Sess=%d Vol=%d",
                  score.TrendAlignment, score.OrderBlockZone, score.FVGPresence,
                  score.FibConfluence, score.LiquiditySweep, score.SessionBonus, score.VolumeSpike));
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Get current H4 ATR value                                          |
   //| Returns: ATR(14) on H4 in price terms                            |
   //+------------------------------------------------------------------+
   double GetATR_H4(void) const { return m_atrH4; }
   
   //+------------------------------------------------------------------+
   //| Get current M15 ATR value                                         |
   //+------------------------------------------------------------------+
   double GetATR_M15(void) const { return m_atrM15; }
   
   //+------------------------------------------------------------------+
   //| Get the current 200 EMA on H4                                     |
   //+------------------------------------------------------------------+
   double GetEMA200_H4(void) const { return m_ema200H4; }
   
   //+------------------------------------------------------------------+
   //| Reset trade management state for new trade                        |
   //+------------------------------------------------------------------+
   void ResetTradeManagement(void)
   {
      m_tp1Hit = false;
      m_tp2Hit = false;
      m_candlesInTrade = 0;
      m_lastTrailUpdate = 0;
   }
   
   //+------------------------------------------------------------------+
   //| Check if TP1 was already hit                                      |
   //+------------------------------------------------------------------+
   bool IsTP1Hit(void) const { return m_tp1Hit; }
   void SetTP1Hit(bool hit) { m_tp1Hit = hit; }
   
   //+------------------------------------------------------------------+
   //| Check if TP2 was already hit                                      |
   //+------------------------------------------------------------------+
   bool IsTP2Hit(void) const { return m_tp2Hit; }
   void SetTP2Hit(bool hit) { m_tp2Hit = hit; }
   
   //+------------------------------------------------------------------+
   //| Increment candle count for time-based exit                        |
   //+------------------------------------------------------------------+
   void IncrementCandleCount(void) { m_candlesInTrade++; }
   int GetCandlesInTrade(void) const { return m_candlesInTrade; }
   
   //+------------------------------------------------------------------+
   //| Check if trailing stop should be updated (min 1sec interval)      |
   //+------------------------------------------------------------------+
   bool CanUpdateTrailingStop(void)
   {
      datetime now = TimeCurrent();
      if((now - m_lastTrailUpdate) >= 1) // At least 1 second apart
      {
         m_lastTrailUpdate = now;
         return true;
      }
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate ATR-based trailing stop distance                        |
   //| Returns: Trailing distance in price terms                        |
   //+------------------------------------------------------------------+
   double GetTrailingStopDistance(void)
   {
      // Use M15 ATR for intraday trailing, scaled by 1.0x
      if(m_atrM15 > 0)
         return m_atrM15 * 1.0;
      
      // Fallback to H4 ATR * 0.5
      if(m_atrH4 > 0)
         return m_atrH4 * 0.5;
      
      // Last resort: fixed distance
      return 3.0; // ~30 points for XAUUSD
   }

private:
   //+------------------------------------------------------------------+
   //| Refresh all indicator values from handles                         |
   //| Returns: true if all critical indicators refreshed                |
   //+------------------------------------------------------------------+
   bool RefreshIndicators(void)
   {
      double buffer[];
      ArraySetAsSeries(buffer, true);
      
      bool success = true;
      
      // EMA 200 H4
      if(m_handles.hEMA200_H4 != INVALID_HANDLE)
      {
         if(CopyBuffer(m_handles.hEMA200_H4, 0, 0, 1, buffer) > 0)
            m_ema200H4 = buffer[0];
         else
            success = false;
      }
      
      // EMA 50 H4
      if(m_handles.hEMA50_H4 != INVALID_HANDLE)
      {
         if(CopyBuffer(m_handles.hEMA50_H4, 0, 0, 1, buffer) > 0)
            m_ema50H4 = buffer[0];
      }
      
      // EMA 20 M15
      if(m_handles.hEMA20_M15 != INVALID_HANDLE)
      {
         if(CopyBuffer(m_handles.hEMA20_M15, 0, 0, 1, buffer) > 0)
            m_ema20M15 = buffer[0];
      }
      
      // ATR 14 H4
      if(m_handles.hATR14_H4 != INVALID_HANDLE)
      {
         if(CopyBuffer(m_handles.hATR14_H4, 0, 0, 1, buffer) > 0)
            m_atrH4 = buffer[0];
         else
            success = false;
      }
      
      // ATR 14 M15
      if(m_handles.hATR14_M15 != INVALID_HANDLE)
      {
         if(CopyBuffer(m_handles.hATR14_M15, 0, 0, 1, buffer) > 0)
            m_atrM15 = buffer[0];
      }
      
      // RSI 14 M5 (current + previous)
      if(m_handles.hRSI14_M5 != INVALID_HANDLE)
      {
         double rsiBuf[];
         ArraySetAsSeries(rsiBuf, true);
         if(CopyBuffer(m_handles.hRSI14_M5, 0, 0, 3, rsiBuf) >= 3)
         {
            m_rsiM5 = rsiBuf[0];
            m_rsiM5_prev = rsiBuf[1];
         }
      }
      
      // MACD M15 (main, signal, histogram)
      if(m_handles.hMACD_M15 != INVALID_HANDLE)
      {
         double macdBuf[], signalBuf[];
         ArraySetAsSeries(macdBuf, true);
         ArraySetAsSeries(signalBuf, true);
         
         if(CopyBuffer(m_handles.hMACD_M15, 0, 0, 2, macdBuf) >= 2 &&
            CopyBuffer(m_handles.hMACD_M15, 1, 0, 2, signalBuf) >= 2)
         {
            m_macdMain = macdBuf[0];
            m_macdSignal = signalBuf[0];
            m_macdHist = m_macdMain - m_macdSignal;
            m_macdHist_prev = macdBuf[1] - signalBuf[1];
         }
      }
      
      return success;
   }
   
   //+------------------------------------------------------------------+
   //| Check if ATR is within acceptable range (not abnormal spike)      |
   //+------------------------------------------------------------------+
   bool IsATRNormal(void)
   {
      if(m_atrH4 <= 0) return false;
      
      // Get ATR history to compare
      double atrHistory[];
      ArraySetAsSeries(atrHistory, true);
      
      if(m_handles.hATR14_H4 != INVALID_HANDLE)
      {
         if(CopyBuffer(m_handles.hATR14_H4, 0, 0, 20, atrHistory) >= 20)
         {
            // Calculate average ATR over last 20 bars
            double avgATR = 0;
            for(int i = 0; i < 20; i++)
               avgATR += atrHistory[i];
            avgATR /= 20.0;
            
            // Current ATR should be within 0.3x to 2.5x of average
            if(m_atrH4 > avgATR * 2.5)
            {
               m_log.Warn(StringFormat("ATR spike: %.2f > 2.5x avg (%.2f). Abnormal volatility.", m_atrH4, avgATR));
               return false;
            }
            if(m_atrH4 < avgATR * 0.3)
            {
               m_log.Debug(StringFormat("ATR too low: %.2f < 0.3x avg (%.2f). Market too quiet.", m_atrH4, avgATR));
               return false;
            }
         }
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Evaluate H4 trend alignment                                       |
   //| Checks: price vs EMA200, EMA50 vs EMA200 ordering                |
   //+------------------------------------------------------------------+
   bool EvaluateTrendAlignment(double currentPrice, bool isBullish)
   {
      if(isBullish)
      {
         // Bullish: Price > EMA200 and EMA50 > EMA200
         return (currentPrice > m_ema200H4 && m_ema50H4 > m_ema200H4);
      }
      else
      {
         // Bearish: Price < EMA200 and EMA50 < EMA200
         return (currentPrice < m_ema200H4 && m_ema50H4 < m_ema200H4);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Detect Order Blocks on M15 timeframe                              |
   //| An OB is the last bearish candle before a bullish impulse (bull)  |
   //| or the last bullish candle before a bearish impulse (bear)        |
   //+------------------------------------------------------------------+
   void DetectOrderBlocks(void)
   {
      ArrayResize(m_orderBlocks, 0);
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, 0, 50, rates);
      if(copied < 10) return;
      
      // Scan for Order Block patterns
      for(int i = 3; i < copied - 2; i++)
      {
         // Bullish OB: bearish candle followed by strong bullish impulse
         bool isBearishCandle = (rates[i].close < rates[i].open);
         bool isStrongBullishMove = false;
         
         if(isBearishCandle)
         {
            // Check if next 1-2 candles show strong bullish impulse
            double impulseRange = rates[i-1].close - rates[i].close;
            double avgRange = GetAverageRange(rates, i, 5);
            isStrongBullishMove = (impulseRange > avgRange * 1.5);
            
            if(isStrongBullishMove)
            {
               // This is a bullish OB
               SOrderBlock ob;
               ob.HighPrice = rates[i].high;
               ob.LowPrice = rates[i].low;
               ob.MidPrice = (ob.HighPrice + ob.LowPrice) / 2.0;
               ob.Time = rates[i].time;
               ob.IsBullish = true;
               ob.IsValid = !HasPriceReturnedBelow(rates, i, ob.LowPrice);
               ob.TouchCount = 0;
               
               if(ob.IsValid)
               {
                  int size = ArraySize(m_orderBlocks);
                  if(size < m_maxStructures)
                  {
                     ArrayResize(m_orderBlocks, size + 1);
                     m_orderBlocks[size] = ob;
                  }
               }
            }
         }
         
         // Bearish OB: bullish candle followed by strong bearish impulse
         bool isBullishCandle = (rates[i].close > rates[i].open);
         bool isStrongBearishMove = false;
         
         if(isBullishCandle)
         {
            double impulseRange = rates[i].close - rates[i-1].close;
            double avgRange = GetAverageRange(rates, i, 5);
            isStrongBearishMove = (impulseRange > avgRange * 1.5);
            
            if(isStrongBearishMove)
            {
               SOrderBlock ob;
               ob.HighPrice = rates[i].high;
               ob.LowPrice = rates[i].low;
               ob.MidPrice = (ob.HighPrice + ob.LowPrice) / 2.0;
               ob.Time = rates[i].time;
               ob.IsBullish = false;
               ob.IsValid = !HasPriceReturnedAbove(rates, i, ob.HighPrice);
               ob.TouchCount = 0;
               
               if(ob.IsValid)
               {
                  int size = ArraySize(m_orderBlocks);
                  if(size < m_maxStructures)
                  {
                     ArrayResize(m_orderBlocks, size + 1);
                     m_orderBlocks[size] = ob;
                  }
               }
            }
         }
      }
      
      m_log.Debug(StringFormat("Detected %d active Order Blocks", ArraySize(m_orderBlocks)));
   }
   
   //+------------------------------------------------------------------+
   //| Detect Fair Value Gaps on M15 timeframe                           |
   //| FVG = gap between candle 1's high and candle 3's low (bullish)   |
   //|    or candle 1's low and candle 3's high (bearish)                |
   //+------------------------------------------------------------------+
   void DetectFairValueGaps(void)
   {
      ArrayResize(m_fvgs, 0);
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, 0, 50, rates);
      if(copied < 5) return;
      
      for(int i = 1; i < copied - 2; i++)
      {
         // Bullish FVG: Candle [i+1].high < Candle [i-1].low (gap up)
         if(rates[i+1].high < rates[i-1].low)
         {
            SFairValueGap fvg;
            fvg.LowPrice = rates[i+1].high;
            fvg.HighPrice = rates[i-1].low;
            fvg.Time = rates[i].time;
            fvg.IsBullish = true;
            fvg.IsFilled = IsFVGFilled(rates, i, fvg);
            
            if(!fvg.IsFilled)
            {
               int size = ArraySize(m_fvgs);
               if(size < m_maxStructures)
               {
                  ArrayResize(m_fvgs, size + 1);
                  m_fvgs[size] = fvg;
               }
            }
         }
         
         // Bearish FVG: Candle [i+1].low > Candle [i-1].high (gap down)
         if(rates[i+1].low > rates[i-1].high)
         {
            SFairValueGap fvg;
            fvg.HighPrice = rates[i+1].low;
            fvg.LowPrice = rates[i-1].high;
            fvg.Time = rates[i].time;
            fvg.IsBullish = false;
            fvg.IsFilled = IsFVGFilled(rates, i, fvg);
            
            if(!fvg.IsFilled)
            {
               int size = ArraySize(m_fvgs);
               if(size < m_maxStructures)
               {
                  ArrayResize(m_fvgs, size + 1);
                  m_fvgs[size] = fvg;
               }
            }
         }
      }
      
      m_log.Debug(StringFormat("Detected %d active Fair Value Gaps", ArraySize(m_fvgs)));
   }
   
   //+------------------------------------------------------------------+
   //| Find an active Order Block near current price (for entry)         |
   //+------------------------------------------------------------------+
   bool FindActiveOrderBlock(double price, bool isBullish, SOrderBlock &result)
   {
      double atr = (m_atrM15 > 0) ? m_atrM15 : 2.0;
      double proximityThreshold = atr * 0.5; // Within 0.5 ATR of OB zone
      
      for(int i = 0; i < ArraySize(m_orderBlocks); i++)
      {
         if(!m_orderBlocks[i].IsValid) continue;
         if(m_orderBlocks[i].IsBullish != isBullish) continue;
         
         if(isBullish)
         {
            // For bullish OB: price should be near or inside the OB (coming from above)
            if(price >= m_orderBlocks[i].LowPrice - proximityThreshold &&
               price <= m_orderBlocks[i].HighPrice + proximityThreshold)
            {
               result = m_orderBlocks[i];
               return true;
            }
         }
         else
         {
            // For bearish OB: price should be near or inside the OB (coming from below)
            if(price >= m_orderBlocks[i].LowPrice - proximityThreshold &&
               price <= m_orderBlocks[i].HighPrice + proximityThreshold)
            {
               result = m_orderBlocks[i];
               return true;
            }
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Find an active FVG near current price                             |
   //+------------------------------------------------------------------+
   bool FindActiveFVG(double price, bool isBullish, SFairValueGap &result)
   {
      double atr = (m_atrM15 > 0) ? m_atrM15 : 2.0;
      double proximityThreshold = atr * 0.3;
      
      for(int i = 0; i < ArraySize(m_fvgs); i++)
      {
         if(m_fvgs[i].IsFilled) continue;
         if(m_fvgs[i].IsBullish != isBullish) continue;
         
         // Price should be inside or very near the FVG
         if(price >= m_fvgs[i].LowPrice - proximityThreshold &&
            price <= m_fvgs[i].HighPrice + proximityThreshold)
         {
            result = m_fvgs[i];
            return true;
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Check Fibonacci 0.618-0.786 retracement confluence                |
   //| Uses recent swing high/low on M30 to calculate fib levels        |
   //+------------------------------------------------------------------+
   bool CheckFibonacciConfluence(double currentPrice, bool isBullish)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M30, 0, 40, rates);
      if(copied < 20) return false;
      
      // Find recent swing high and swing low
      double swingHigh = 0, swingLow = 99999;
      int swingHighIdx = 0, swingLowIdx = 0;
      
      for(int i = 0; i < copied; i++)
      {
         if(rates[i].high > swingHigh) { swingHigh = rates[i].high; swingHighIdx = i; }
         if(rates[i].low < swingLow)   { swingLow = rates[i].low; swingLowIdx = i; }
      }
      
      if(swingHigh <= swingLow) return false;
      
      double range = swingHigh - swingLow;
      
      // Calculate key Fibonacci levels
      double fib618, fib786;
      
      if(isBullish && swingHighIdx < swingLowIdx)
      {
         // Swing low happened first (older), then swing high => retracement down is bullish entry
         fib618 = swingHigh - range * 0.618;
         fib786 = swingHigh - range * 0.786;
         
         // Price should be between fib786 and fib618
         return (currentPrice >= fib786 && currentPrice <= fib618);
      }
      else if(!isBullish && swingLowIdx < swingHighIdx)
      {
         // Swing high happened first (older), then swing low => retracement up is bearish entry
         fib618 = swingLow + range * 0.618;
         fib786 = swingLow + range * 0.786;
         
         return (currentPrice >= fib618 && currentPrice <= fib786);
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Detect liquidity sweep (equal highs/lows taken before reversal)   |
   //| Looks for price taking out a double top/bottom then reversing     |
   //+------------------------------------------------------------------+
   bool DetectLiquiditySweep(bool isBullish)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M15, 0, 30, rates);
      if(copied < 15) return false;
      
      if(isBullish)
      {
         // Bullish: Look for a sweep of recent lows (equal lows taken) then bounce
         // Find equal lows (within 0.5 ATR tolerance)
         double tolerance = (m_atrM15 > 0) ? m_atrM15 * 0.3 : 1.0;
         
         for(int i = 1; i < 10; i++)
         {
            for(int j = i + 3; j < MathMin(i + 15, copied); j++)
            {
               // Two lows at similar levels
               if(MathAbs(rates[i].low - rates[j].low) < tolerance)
               {
                  // Current or recent candle swept below both lows
                  double equalLow = MathMin(rates[i].low, rates[j].low);
                  if(rates[0].low < equalLow && rates[0].close > equalLow)
                  {
                     m_log.Debug(StringFormat("Bullish liquidity sweep detected at %.2f", equalLow));
                     return true;
                  }
                  // Previous candle swept and current bounced
                  if(rates[1].low < equalLow && rates[0].close > rates[1].close)
                  {
                     m_log.Debug(StringFormat("Bullish sweep (prev candle) at %.2f", equalLow));
                     return true;
                  }
               }
            }
         }
      }
      else
      {
         // Bearish: Look for sweep of recent highs then rejection
         double tolerance = (m_atrM15 > 0) ? m_atrM15 * 0.3 : 1.0;
         
         for(int i = 1; i < 10; i++)
         {
            for(int j = i + 3; j < MathMin(i + 15, copied); j++)
            {
               if(MathAbs(rates[i].high - rates[j].high) < tolerance)
               {
                  double equalHigh = MathMax(rates[i].high, rates[j].high);
                  if(rates[0].high > equalHigh && rates[0].close < equalHigh)
                  {
                     m_log.Debug(StringFormat("Bearish liquidity sweep detected at %.2f", equalHigh));
                     return true;
                  }
                  if(rates[1].high > equalHigh && rates[0].close < rates[1].close)
                  {
                     m_log.Debug(StringFormat("Bearish sweep (prev candle) at %.2f", equalHigh));
                     return true;
                  }
               }
            }
         }
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Detect volume spike on M5 in trade direction                      |
   //+------------------------------------------------------------------+
   bool DetectVolumeSpike(bool isBullish)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M5, 0, 20, rates);
      if(copied < 10) return false;
      
      // Calculate average tick volume over last 20 bars
      long avgVolume = 0;
      for(int i = 1; i < copied; i++)
         avgVolume += rates[i].tick_volume;
      avgVolume /= (copied - 1);
      
      if(avgVolume <= 0) return false;
      
      // Current bar volume must be 1.5x average
      bool volumeSpike = (rates[0].tick_volume > avgVolume * 1.5);
      
      if(!volumeSpike) return false;
      
      // Volume must be in trade direction
      bool directionMatch = isBullish ? (rates[0].close > rates[0].open) 
                                       : (rates[0].close < rates[0].open);
      
      return directionMatch;
   }
   
   //+------------------------------------------------------------------+
   //| Check M5 entry trigger conditions                                 |
   //| Trigger 1: Rejection candle pattern                               |
   //| Trigger 2: RSI divergence                                         |
   //| Trigger 3: MACD momentum cross                                    |
   //| Trigger 4: Candle closes back inside key zone                     |
   //| At least one trigger must fire                                    |
   //+------------------------------------------------------------------+
   bool CheckEntryTrigger(bool isBullish, double currentPrice)
   {
      int triggersConfirmed = 0;
      
      //--- Trigger 1: Rejection candle on M5
      if(IsRejectionCandle(isBullish))
         triggersConfirmed++;
      
      //--- Trigger 2: RSI divergence
      if(HasRSIDivergence(isBullish))
         triggersConfirmed++;
      
      //--- Trigger 3: MACD cross/momentum
      if(HasMACDConfirmation(isBullish))
         triggersConfirmed++;
      
      //--- Trigger 4: Candle closes back inside OB/FVG
      if(IsCandleInsideZone(isBullish, currentPrice))
         triggersConfirmed++;
      
      // Need at least 1 trigger confirmed
      return (triggersConfirmed >= 1);
   }
   
   //+------------------------------------------------------------------+
   //| Check for rejection candle pattern on M5                          |
   //| Pin bar, bullish/bearish engulfing at the key zone                |
   //+------------------------------------------------------------------+
   bool IsRejectionCandle(bool isBullish)
   {
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      int copied = CopyRates(m_symbol, PERIOD_M5, 0, 3, rates);
      if(copied < 3) return false;
      
      double body = MathAbs(rates[0].close - rates[0].open);
      double range = rates[0].high - rates[0].low;
      if(range <= 0) return false;
      
      double bodyRatio = body / range;
      
      if(isBullish)
      {
         // Bullish pin bar: small body at top, long lower wick
         double lowerWick = MathMin(rates[0].open, rates[0].close) - rates[0].low;
         double upperWick = rates[0].high - MathMax(rates[0].open, rates[0].close);
         
         bool isPinBar = (bodyRatio < 0.35 && lowerWick > body * 2.0 && rates[0].close > rates[0].open);
         
         // Bullish engulfing
         bool isEngulfing = (rates[0].close > rates[0].open && 
                            rates[1].close < rates[1].open &&
                            rates[0].close > rates[1].open &&
                            rates[0].open < rates[1].close);
         
         return (isPinBar || isEngulfing);
      }
      else
      {
         // Bearish pin bar: small body at bottom, long upper wick
         double upperWick = rates[0].high - MathMax(rates[0].open, rates[0].close);
         
         bool isPinBar = (bodyRatio < 0.35 && upperWick > body * 2.0 && rates[0].close < rates[0].open);
         
         // Bearish engulfing
         bool isEngulfing = (rates[0].close < rates[0].open && 
                            rates[1].close > rates[1].open &&
                            rates[0].close < rates[1].open &&
                            rates[0].open > rates[1].close);
         
         return (isPinBar || isEngulfing);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check for RSI divergence on M5                                    |
   //| Bullish: Price makes lower low, RSI makes higher low             |
   //| Bearish: Price makes higher high, RSI makes lower high           |
   //+------------------------------------------------------------------+
   bool HasRSIDivergence(bool isBullish)
   {
      double rsiBuf[];
      ArraySetAsSeries(rsiBuf, true);
      if(m_handles.hRSI14_M5 == INVALID_HANDLE) return false;
      if(CopyBuffer(m_handles.hRSI14_M5, 0, 0, 10, rsiBuf) < 10) return false;
      
      MqlRates rates[];
      ArraySetAsSeries(rates, true);
      if(CopyRates(m_symbol, PERIOD_M5, 0, 10, rates) < 10) return false;
      
      if(isBullish)
      {
         // Check if price made a lower low but RSI made a higher low
         // Compare bars [0] vs [5-8] range
         double recentPriceLow = rates[0].low;
         double recentRSI = rsiBuf[0];
         
         for(int i = 5; i < 9; i++)
         {
            if(rates[i].low > recentPriceLow && rsiBuf[i] > recentRSI)
            {
               // Price lower but RSI higher = bullish divergence (inverted comparison)
               // Actually: Price lower low AND RSI higher low = bullish divergence
               if(recentPriceLow < rates[i].low && recentRSI > rsiBuf[i])
                  return true;
            }
         }
         
         // Also check if RSI is oversold (< 30) as a simpler confirmation
         if(m_rsiM5 < 30 && m_rsiM5 > m_rsiM5_prev)
            return true;
      }
      else
      {
         // Bearish divergence: Price higher high, RSI lower high
         double recentPriceHigh = rates[0].high;
         double recentRSI = rsiBuf[0];
         
         for(int i = 5; i < 9; i++)
         {
            if(recentPriceHigh > rates[i].high && recentRSI < rsiBuf[i])
               return true;
         }
         
         // RSI overbought (> 70) turning down
         if(m_rsiM5 > 70 && m_rsiM5 < m_rsiM5_prev)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Check MACD momentum confirmation on M15                           |
   //| Bullish: MACD histogram turning positive or crossing up           |
   //| Bearish: MACD histogram turning negative or crossing down         |
   //+------------------------------------------------------------------+
   bool HasMACDConfirmation(bool isBullish)
   {
      if(isBullish)
      {
         // MACD histogram crossing from negative to positive (or increasing)
         return (m_macdHist > 0 && m_macdHist_prev <= 0) || 
                (m_macdMain > m_macdSignal && m_macdHist > m_macdHist_prev);
      }
      else
      {
         // MACD histogram crossing from positive to negative (or decreasing)
         return (m_macdHist < 0 && m_macdHist_prev >= 0) || 
                (m_macdMain < m_macdSignal && m_macdHist < m_macdHist_prev);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check if M5 candle closes back inside OB/FVG zone                 |
   //+------------------------------------------------------------------+
   bool IsCandleInsideZone(bool isBullish, double price)
   {
      // Check against order blocks
      for(int i = 0; i < ArraySize(m_orderBlocks); i++)
      {
         if(!m_orderBlocks[i].IsValid) continue;
         if(m_orderBlocks[i].IsBullish != isBullish) continue;
         
         if(price >= m_orderBlocks[i].LowPrice && price <= m_orderBlocks[i].HighPrice)
            return true;
      }
      
      // Check against FVGs
      for(int i = 0; i < ArraySize(m_fvgs); i++)
      {
         if(m_fvgs[i].IsFilled) continue;
         if(m_fvgs[i].IsBullish != isBullish) continue;
         
         if(price >= m_fvgs[i].LowPrice && price <= m_fvgs[i].HighPrice)
            return true;
      }
      
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate entry, SL, and TP levels for the setup                  |
   //+------------------------------------------------------------------+
   bool CalculateEntryLevels(SSetupScore &score, bool isBullish, double currentPrice,
                             SOrderBlock &ob, SFairValueGap &fvg, bool hasOB)
   {
      double point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      double spread = SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * point;
      
      // Entry: current market price (with spread for buys)
      if(isBullish)
         score.SuggestedEntry = SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      else
         score.SuggestedEntry = SymbolInfoDouble(m_symbol, SYMBOL_BID);
      
      // Stop Loss: 3-5 pips beyond OB wick (or structure)
      double obBuffer = point * 50; // 5 pips = 50 points on XAUUSD (0.1 pip per point)
      
      if(isBullish)
      {
         if(hasOB)
            score.SuggestedSL = ob.LowPrice - obBuffer;
         else
            score.SuggestedSL = currentPrice - m_atrH4 * 0.75; // Fallback: ATR-based
      }
      else
      {
         if(hasOB)
            score.SuggestedSL = ob.HighPrice + obBuffer + spread;
         else
            score.SuggestedSL = currentPrice + m_atrH4 * 0.75 + spread;
      }
      
      // Normalize SL price
      score.SuggestedSL = CMathUtils::NormalizePrice(m_symbol, score.SuggestedSL);
      
      // Calculate SL distance in points
      score.SLDistancePoints = MathAbs(score.SuggestedEntry - score.SuggestedSL);
      
      // Validate SL distance against ATR bounds
      double minSL = m_atrH4 * 0.5;
      double maxSL = m_atrH4 * 1.5;
      
      if(score.SLDistancePoints < minSL)
      {
         // Widen SL to minimum
         if(isBullish)
            score.SuggestedSL = score.SuggestedEntry - minSL;
         else
            score.SuggestedSL = score.SuggestedEntry + minSL;
         score.SLDistancePoints = minSL;
         score.SuggestedSL = CMathUtils::NormalizePrice(m_symbol, score.SuggestedSL);
      }
      
      if(score.SLDistancePoints > maxSL)
      {
         m_log.Warn(StringFormat("SL distance %.2f exceeds ATR*1.5 (%.2f). Trade skipped.", 
                    score.SLDistancePoints, maxSL));
         return false;
      }
      
      // Minimum SL distance must be > spread * 2
      if(score.SLDistancePoints < spread * 2)
      {
         m_log.Warn("SL distance too close to spread. Trade skipped.");
         return false;
      }
      
      // Calculate TP levels
      double slDist = score.SLDistancePoints;
      
      if(isBullish)
      {
         score.SuggestedTP1 = CMathUtils::NormalizePrice(m_symbol, score.SuggestedEntry + slDist * 1.0);  // 1:1
         score.SuggestedTP2 = CMathUtils::NormalizePrice(m_symbol, score.SuggestedEntry + slDist * 2.0);  // 1:2
         score.SuggestedTP3 = CMathUtils::NormalizePrice(m_symbol, score.SuggestedEntry + slDist * 2.618);// Fib ext
      }
      else
      {
         score.SuggestedTP1 = CMathUtils::NormalizePrice(m_symbol, score.SuggestedEntry - slDist * 1.0);
         score.SuggestedTP2 = CMathUtils::NormalizePrice(m_symbol, score.SuggestedEntry - slDist * 2.0);
         score.SuggestedTP3 = CMathUtils::NormalizePrice(m_symbol, score.SuggestedEntry - slDist * 2.618);
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Helper: Get average candle range over N bars                      |
   //+------------------------------------------------------------------+
   double GetAverageRange(MqlRates &rates[], int startIdx, int count)
   {
      double totalRange = 0;
      int actualCount = 0;
      
      for(int i = startIdx; i < startIdx + count && i < ArraySize(rates); i++)
      {
         totalRange += (rates[i].high - rates[i].low);
         actualCount++;
      }
      
      return (actualCount > 0) ? totalRange / actualCount : 1.0;
   }
   
   //+------------------------------------------------------------------+
   //| Helper: Check if price returned below a level after given bar     |
   //+------------------------------------------------------------------+
   bool HasPriceReturnedBelow(MqlRates &rates[], int fromIdx, double level)
   {
      for(int i = 0; i < fromIdx; i++)
      {
         if(rates[i].close < level)
            return true;
      }
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Helper: Check if price returned above a level after given bar     |
   //+------------------------------------------------------------------+
   bool HasPriceReturnedAbove(MqlRates &rates[], int fromIdx, double level)
   {
      for(int i = 0; i < fromIdx; i++)
      {
         if(rates[i].close > level)
            return true;
      }
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Helper: Check if an FVG has been filled by subsequent price       |
   //+------------------------------------------------------------------+
   bool IsFVGFilled(MqlRates &rates[], int fvgIdx, const SFairValueGap &fvg)
   {
      for(int i = 0; i < fvgIdx; i++)
      {
         if(fvg.IsBullish)
         {
            // Bullish FVG filled if price closed below FVG low
            if(rates[i].close < fvg.LowPrice)
               return true;
         }
         else
         {
            // Bearish FVG filled if price closed above FVG high
            if(rates[i].close > fvg.HighPrice)
               return true;
         }
      }
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Release all indicator handles                                     |
   //+------------------------------------------------------------------+
   void ReleaseHandles(void)
   {
      if(m_handles.hEMA200_H4 != INVALID_HANDLE) IndicatorRelease(m_handles.hEMA200_H4);
      if(m_handles.hEMA50_H4 != INVALID_HANDLE)  IndicatorRelease(m_handles.hEMA50_H4);
      if(m_handles.hEMA20_M15 != INVALID_HANDLE)  IndicatorRelease(m_handles.hEMA20_M15);
      if(m_handles.hATR14_H4 != INVALID_HANDLE)   IndicatorRelease(m_handles.hATR14_H4);
      if(m_handles.hATR14_M15 != INVALID_HANDLE)   IndicatorRelease(m_handles.hATR14_M15);
      if(m_handles.hRSI14_M5 != INVALID_HANDLE)    IndicatorRelease(m_handles.hRSI14_M5);
      if(m_handles.hMACD_M15 != INVALID_HANDLE)     IndicatorRelease(m_handles.hMACD_M15);
      m_handles.Reset();
   }
};

#endif // STRATEGY_ENGINE_MQH
