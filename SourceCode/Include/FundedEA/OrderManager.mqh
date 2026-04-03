//+------------------------------------------------------------------+
//|                                              OrderManager.mqh    |
//|                         Funded.E.A Development Team              |
//|                         Order Execution & Position Management    |
//+------------------------------------------------------------------+
//| Purpose: Handles all order-related operations:                   |
//|   - Market order execution with slippage control                 |
//|   - Pending order placement (limit orders for OB/FVG entries)    |
//|   - Partial close management (TP1 40%, TP2 40%, runner 20%)     |
//|   - Breakeven move after +1R                                     |
//|   - ATR trailing stop after breakeven                            |
//|   - Time-based exit (8 candles without +0.5R)                    |
//|   - Requote handling with retry logic                            |
//|   - Partial fill handling                                        |
//|   - Order modification with error recovery                      |
//+------------------------------------------------------------------+
#ifndef ORDER_MANAGER_MQH
#define ORDER_MANAGER_MQH

#include "Utils.mqh"
#include "CostModel.mqh"
#include "StrategyEngine.mqh"
#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Trade execution result container                                  |
//+------------------------------------------------------------------+
struct STradeResult
{
   bool     Success;
   ulong    Ticket;
   double   FilledPrice;
   double   FilledLots;
   double   RequestedPrice;
   double   RequestedLots;
   double   SlippagePoints;
   int      RetryCount;
   ENUM_ORDER_REJECTION_REASON RejectionReason;
   int      ErrorCode;
   uint     ExecutionTimeMs;    // Time taken for order execution
   
   void Reset()
   {
      Success = false;
      Ticket = 0;
      FilledPrice = 0;
      FilledLots = 0;
      RequestedPrice = 0;
      RequestedLots = 0;
      SlippagePoints = 0;
      RetryCount = 0;
      RejectionReason = REJECT_NONE;
      ErrorCode = 0;
      ExecutionTimeMs = 0;
   }
};

//+------------------------------------------------------------------+
//| COrderManager - Order Execution & Position Management             |
//+------------------------------------------------------------------+
class COrderManager
{
private:
   //--- Configuration
   string            m_symbol;
   int               m_magicNumber;
   int               m_maxSlippagePips;        // Max slippage in pips
   int               m_maxSlippagePoints;      // Max slippage in points (pips * 10)
   int               m_maxSpreadPoints;        // Max allowed spread
   int               m_deviationPoints;        // Order deviation (slippage tolerance)
   
   //--- Cached symbol info
   double            m_point;
   double            m_tickSize;
   double            m_tickValue;
   int               m_digits;
   double            m_minLot;
   double            m_lotStep;
   
   //--- Trade object (MQL5 CTrade wrapper)
   CTrade            m_trade;
   
   //--- Position management state
   ulong             m_activeTicket;           // Currently managed position ticket
   double            m_activeEntryPrice;       // Entry price of active position
   double            m_activeSL;               // Current SL of active position
   double            m_activeTP;               // Current TP of active position
   double            m_originalSLDistance;      // Original SL distance from entry
   double            m_originalLots;           // Original lot size
   bool              m_isBullish;              // Direction of active position
   bool              m_isAtBreakeven;          // SL moved to BE flag
   int               m_partialCloseStage;      // 0=none, 1=TP1 done, 2=TP2 done
   datetime          m_entryTime;              // Time of entry
   int               m_entryBarIndex;          // Bar index at entry (M5)
   
   //--- Logger
   CLogger           m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   COrderManager(void)
   {
      m_log.SetPrefix("Orders");
      m_symbol = "";
      m_magicNumber = 0;
      m_maxSlippagePips = 3;
      m_maxSlippagePoints = 30;
      m_maxSpreadPoints = 30;
      m_deviationPoints = 30;
      m_point = 0.01;
      m_tickSize = 0.01;
      m_tickValue = 1.0;
      m_digits = 2;
      m_minLot = 0.01;
      m_lotStep = 0.01;
      
      ResetActivePosition();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize the order manager                                      |
   //| Parameters:                                                       |
   //|   symbol           - trading symbol                               |
   //|   magicNumber      - EA magic number                              |
   //|   maxSlippagePips  - max acceptable slippage in pips              |
   //|   maxSpreadPoints  - max spread for entry in points               |
   //| Returns: void                                                     |
   //+------------------------------------------------------------------+
   void Initialize(string symbol, int magicNumber, int maxSlippagePips, int maxSpreadPoints)
   {
      m_symbol = symbol;
      m_magicNumber = magicNumber;
      m_maxSlippagePips = maxSlippagePips;
      m_maxSlippagePoints = maxSlippagePips * 10; // XAUUSD: 1 pip = 10 points
      m_maxSpreadPoints = maxSpreadPoints;
      m_deviationPoints = m_maxSlippagePoints;
      
      // Configure CTrade
      m_trade.SetExpertMagicNumber(magicNumber);
      m_trade.SetDeviationInPoints(m_deviationPoints);
      m_trade.SetTypeFilling(ORDER_FILLING_FOK); // Fill or Kill
      m_trade.SetTypeFillingBySymbol(symbol);
      m_trade.SetMarginMode();
      
      // Cache symbol info
      RefreshSymbolInfo();
      
      m_log.Info(StringFormat("OrderManager initialized: %s | Magic=%d | MaxSlip=%d pips | MaxSpread=%d pts",
                 symbol, magicNumber, maxSlippagePips, maxSpreadPoints));
   }
   
   //+------------------------------------------------------------------+
   //| Execute a market trade based on setup score                       |
   //| Parameters:                                                       |
   //|   score   - setup score with entry/SL/TP levels                  |
   //|   lots    - calculated lot size                                   |
   //|   state   - current engine state                                  |
   //| Returns: true if trade was successfully opened                    |
   //| Side Effects: Opens position, sets active position state          |
   //+------------------------------------------------------------------+
   bool ExecuteTrade(const SSetupScore &score, double lots, const SEngineState &state)
   {
      STradeResult result;
      result.Reset();
      
      //--- Pre-flight checks
      if(!PreFlightCheck(result))
         return false;
      
      //--- Determine order type and price
      ENUM_ORDER_TYPE orderType = score.IsBullish ? ORDER_TYPE_BUY : ORDER_TYPE_SELL;
      double entryPrice = score.IsBullish ? SymbolInfoDouble(m_symbol, SYMBOL_ASK) 
                                           : SymbolInfoDouble(m_symbol, SYMBOL_BID);
      
      result.RequestedPrice = entryPrice;
      result.RequestedLots = lots;
      
      //--- Normalize prices
      double sl = CMathUtils::NormalizePrice(m_symbol, score.SuggestedSL);
      double tp = CMathUtils::NormalizePrice(m_symbol, score.SuggestedTP2); // Use TP2 as initial TP
      entryPrice = CMathUtils::NormalizePrice(m_symbol, entryPrice);
      
      //--- Validate stop levels against broker minimum
      int stopLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minStopDist = stopLevel * m_point;
      
      double slDist = MathAbs(entryPrice - sl);
      double tpDist = MathAbs(entryPrice - tp);
      
      if(slDist < minStopDist && minStopDist > 0)
      {
         if(score.IsBullish)
            sl = entryPrice - minStopDist - m_point;
         else
            sl = entryPrice + minStopDist + m_point;
         sl = CMathUtils::NormalizePrice(m_symbol, sl);
         m_log.Warn(StringFormat("SL adjusted to meet min stop level: %.2f", sl));
      }
      
      if(tpDist < minStopDist && minStopDist > 0)
      {
         if(score.IsBullish)
            tp = entryPrice + minStopDist + m_point;
         else
            tp = entryPrice - minStopDist - m_point;
         tp = CMathUtils::NormalizePrice(m_symbol, tp);
         m_log.Warn(StringFormat("TP adjusted to meet min stop level: %.2f", tp));
      }
      
      //--- Execute with retry logic
      bool filled = false;
      int retries = 0;
      
      while(!filled && retries < MAX_ORDER_RETRIES)
      {
         uint startMs = GetTickCount();
         
         // Refresh price on retry
         if(retries > 0)
         {
            entryPrice = score.IsBullish ? SymbolInfoDouble(m_symbol, SYMBOL_ASK)
                                          : SymbolInfoDouble(m_symbol, SYMBOL_BID);
            entryPrice = CMathUtils::NormalizePrice(m_symbol, entryPrice);
            Sleep(ORDER_RETRY_DELAY_MS);
         }
         
         // Build comment string
         string comment = StringFormat("%s|S%d|%s", EA_NAME, score.TotalScore,
                          AggressivenessToString(state.AggressivenessLevel));
         
         // Send order
         bool sent = false;
         if(score.IsBullish)
            sent = m_trade.Buy(lots, m_symbol, entryPrice, sl, tp, comment);
         else
            sent = m_trade.Sell(lots, m_symbol, entryPrice, sl, tp, comment);
         
         uint endMs = GetTickCount();
         result.ExecutionTimeMs = endMs - startMs;
         
         if(sent)
         {
            uint retcode = m_trade.ResultRetcode();
            
            if(retcode == TRADE_RETCODE_DONE || retcode == TRADE_RETCODE_PLACED)
            {
               filled = true;
               result.Success = true;
               result.Ticket = m_trade.ResultDeal();
               result.FilledPrice = m_trade.ResultPrice();
               result.FilledLots = m_trade.ResultVolume();
               
               // Calculate actual slippage
               result.SlippagePoints = MathAbs(result.FilledPrice - result.RequestedPrice);
               
               m_log.Trade(StringFormat("ORDER FILLED: %s %.2f lots at %.2f (req %.2f) | Slip=%.1f pts | Time=%dms | Ticket=%d",
                           score.IsBullish ? "BUY" : "SELL", result.FilledLots, result.FilledPrice,
                           result.RequestedPrice, result.SlippagePoints / m_point,
                           result.ExecutionTimeMs, result.Ticket));
            }
            else if(retcode == TRADE_RETCODE_REQUOTE)
            {
               retries++;
               result.RetryCount = retries;
               m_log.Warn(StringFormat("REQUOTE received (attempt %d/%d). Retrying...", 
                          retries, MAX_ORDER_RETRIES));
               
               if(retries >= 2)
               {
                  m_log.Warn("2 consecutive requotes. Aborting trade - market too unstable.");
                  result.RejectionReason = REJECT_REQUOTE;
                  return false;
               }
               
               // Increase deviation on retry
               m_trade.SetDeviationInPoints(m_deviationPoints + 10);
            }
            else
            {
               // Other error
               result.ErrorCode = (int)retcode;
               retries++;
               m_log.Error(StringFormat("Order failed: retcode=%d (%s). Attempt %d/%d",
                           retcode, m_trade.ResultRetcodeDescription(), retries, MAX_ORDER_RETRIES));
               
               if(retcode == TRADE_RETCODE_NO_MONEY)
               {
                  result.RejectionReason = REJECT_INSUFFICIENT_MARGIN;
                  return false;
               }
            }
         }
         else
         {
            result.ErrorCode = GetLastError();
            retries++;
            m_log.Error(StringFormat("OrderSend failed: error=%d. Attempt %d/%d",
                        result.ErrorCode, retries, MAX_ORDER_RETRIES));
         }
      }
      
      // Restore default deviation
      m_trade.SetDeviationInPoints(m_deviationPoints);
      
      if(!filled)
      {
         result.RejectionReason = REJECT_MAX_RETRIES;
         m_log.Error(StringFormat("Trade abandoned after %d retries.", MAX_ORDER_RETRIES));
         return false;
      }
      
      //--- Check for excessive slippage post-fill
      if(result.SlippagePoints > m_maxSlippagePoints * m_point)
      {
         m_log.Warn(StringFormat("EXCESSIVE SLIPPAGE: %.1f pts (max %d pts). Closing immediately.",
                    result.SlippagePoints / m_point, m_maxSlippagePoints));
         
         // Close the position immediately
         ClosePosition(result.Ticket);
         result.RejectionReason = REJECT_SLIPPAGE_TOO_HIGH;
         return false;
      }
      
      //--- Check for partial fill
      if(result.FilledLots < result.RequestedLots * 0.5)
      {
         m_log.Warn(StringFormat("PARTIAL FILL: %.2f / %.2f lots (< 50%%). Closing - RR invalidated.",
                    result.FilledLots, result.RequestedLots));
         ClosePosition(result.Ticket);
         result.RejectionReason = REJECT_PARTIAL_FILL;
         return false;
      }
      else if(result.FilledLots < result.RequestedLots)
      {
         m_log.Info(StringFormat("Partial fill accepted: %.2f / %.2f lots (>= 50%%).",
                    result.FilledLots, result.RequestedLots));
      }
      
      //--- Set active position state for management
      SetActivePosition(result.Ticket, result.FilledPrice, sl, tp,
                        MathAbs(result.FilledPrice - sl), result.FilledLots, score.IsBullish);
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Manage all open positions (trailing, BE, partial close, time exit)|
   //| Called from OnTick() main loop                                    |
   //| Parameters:                                                       |
   //|   state    - current engine state                                 |
   //|   cost     - cost model for breakeven calculations               |
   //|   strategy - strategy engine for trailing distance               |
   //| Returns: void                                                     |
   //+------------------------------------------------------------------+
   void ManagePositions(SEngineState &state, CCostModel &cost, CStrategyEngine &strategy)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != m_magicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != m_symbol) continue;
         
         // Get position details
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         double currentTP = PositionGetDouble(POSITION_TP);
         double posLots = PositionGetDouble(POSITION_VOLUME);
         double posProfit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         long posType = PositionGetInteger(POSITION_TYPE);
         bool isBuy = (posType == POSITION_TYPE_BUY);
         double currentPrice = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_BID) 
                                      : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         
         // Sync active position state if needed
         if(m_activeTicket == 0 || m_activeTicket != ticket)
         {
            // Recover state for this position
            m_activeTicket = ticket;
            m_activeEntryPrice = openPrice;
            m_activeSL = currentSL;
            m_activeTP = currentTP;
            m_originalLots = posLots;
            m_isBullish = isBuy;
            m_originalSLDistance = MathAbs(openPrice - currentSL);
            if(m_originalSLDistance <= 0) m_originalSLDistance = strategy.GetATR_H4() * 0.75;
         }
         
         double slDistance = m_originalSLDistance;
         double profitDistance = isBuy ? (currentPrice - openPrice) : (openPrice - currentPrice);
         double profitInR = CMathUtils::SafeDiv(profitDistance, slDistance, 0);
         
         //=== Rule 1: Time-based exit (8 M5 candles without +0.5R) ===
         CheckTimeBasedExit(ticket, openPrice, posProfit, profitInR, strategy);
         
         //=== Rule 2: Breakeven move at +1R ===
         if(!m_isAtBreakeven && profitInR >= 1.0)
         {
            double bePrice = cost.GetBreakevenDistance(posLots);
            double newSL;
            
            if(isBuy)
               newSL = openPrice + bePrice + m_point; // Slightly above BE
            else
               newSL = openPrice - bePrice - m_point;
            
            newSL = CMathUtils::NormalizePrice(m_symbol, newSL);
            
            if(ModifyStopLoss(ticket, newSL))
            {
               m_isAtBreakeven = true;
               m_activeSL = newSL;
               m_log.Trade(StringFormat("BREAKEVEN: Ticket %d | SL moved to %.2f (+1R reached, profit=%.1fR)",
                           ticket, newSL, profitInR));
            }
         }
         
         //=== Rule 3: Partial close at TP1 (1:1 RR) - close 40% ===
         if(m_partialCloseStage == 0 && profitInR >= 1.0)
         {
            double closePercent = 0.40;
            double closeLots = CMathUtils::NormalizeLot(m_symbol, posLots * closePercent);
            
            if(closeLots >= m_minLot && closeLots < posLots)
            {
               if(PartialClose(ticket, closeLots))
               {
                  m_partialCloseStage = 1;
                  m_log.Trade(StringFormat("TP1 PARTIAL CLOSE: Ticket %d | Closed %.2f lots (40%%) at %.1fR",
                              ticket, closeLots, profitInR));
               }
            }
            else
            {
               // Position too small for partial close, skip this stage
               m_partialCloseStage = 1;
            }
         }
         
         //=== Rule 4: Partial close at TP2 (1:2 RR) - close 40% of original ===
         if(m_partialCloseStage == 1 && profitInR >= 2.0)
         {
            // Refresh position volume (may have changed after TP1 partial)
            if(PositionSelectByTicket(ticket))
            {
               double remainingLots = PositionGetDouble(POSITION_VOLUME);
               double closeLots = CMathUtils::NormalizeLot(m_symbol, m_originalLots * 0.40);
               
               if(closeLots > remainingLots)
                  closeLots = CMathUtils::NormalizeLot(m_symbol, remainingLots * 0.65);
               
               if(closeLots >= m_minLot && closeLots < remainingLots)
               {
                  if(PartialClose(ticket, closeLots))
                  {
                     m_partialCloseStage = 2;
                     m_log.Trade(StringFormat("TP2 PARTIAL CLOSE: Ticket %d | Closed %.2f lots at %.1fR | Runner remains",
                                 ticket, closeLots, profitInR));
                  }
               }
               else
               {
                  m_partialCloseStage = 2;
               }
            }
         }
         
         //=== Rule 5: ATR trailing stop after breakeven ===
         if(m_isAtBreakeven && m_partialCloseStage >= 1 && strategy.CanUpdateTrailingStop())
         {
            double trailDist = strategy.GetTrailingStopDistance();
            double newTrailSL;
            
            if(isBuy)
            {
               newTrailSL = currentPrice - trailDist;
               // Only move SL up, never down
               if(newTrailSL > m_activeSL + m_point)
               {
                  newTrailSL = CMathUtils::NormalizePrice(m_symbol, newTrailSL);
                  if(ModifyStopLoss(ticket, newTrailSL))
                  {
                     m_activeSL = newTrailSL;
                     m_log.Debug(StringFormat("TRAILING: Ticket %d | SL -> %.2f (trail dist=%.2f)",
                                 ticket, newTrailSL, trailDist));
                  }
               }
            }
            else
            {
               newTrailSL = currentPrice + trailDist;
               if(newTrailSL < m_activeSL - m_point)
               {
                  newTrailSL = CMathUtils::NormalizePrice(m_symbol, newTrailSL);
                  if(ModifyStopLoss(ticket, newTrailSL))
                  {
                     m_activeSL = newTrailSL;
                     m_log.Debug(StringFormat("TRAILING: Ticket %d | SL -> %.2f (trail dist=%.2f)",
                                 ticket, newTrailSL, trailDist));
                  }
               }
            }
         }
         
         //=== Rule 6: Target Proximity BE (at +0.5R when in CONSERVATIVE) ===
         if(state.AggressivenessLevel == AGG_CONSERVATIVE && !m_isAtBreakeven && profitInR >= 0.5)
         {
            double bePrice2 = cost.GetBreakevenDistance(posLots);
            double newSL2;
            
            if(isBuy)
               newSL2 = openPrice + bePrice2;
            else
               newSL2 = openPrice - bePrice2;
            
            newSL2 = CMathUtils::NormalizePrice(m_symbol, newSL2);
            
            if(ModifyStopLoss(ticket, newSL2))
            {
               m_isAtBreakeven = true;
               m_activeSL = newSL2;
               m_log.Trade(StringFormat("CONSERVATIVE BE: Ticket %d at +0.5R (SL=%.2f)", ticket, newSL2));
            }
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Move all positions' SL to breakeven                               |
   //| Called during emergency or winning day lock                       |
   //+------------------------------------------------------------------+
   void MoveAllToBreakeven(int magicNumber, string symbol)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
         if(PositionGetString(POSITION_SYMBOL) != symbol) continue;
         
         double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
         double currentSL = PositionGetDouble(POSITION_SL);
         long posType = PositionGetInteger(POSITION_TYPE);
         bool isBuy = (posType == POSITION_TYPE_BUY);
         double currentPrice = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_BID)
                                      : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
         
         // Only move to BE if trade is in profit
         bool inProfit = isBuy ? (currentPrice > openPrice) : (currentPrice < openPrice);
         if(!inProfit) continue;
         
         // Check if SL is already at or past breakeven
         if(isBuy && currentSL >= openPrice) continue;
         if(!isBuy && currentSL <= openPrice && currentSL > 0) continue;
         
         double newSL = CMathUtils::NormalizePrice(m_symbol, openPrice + (isBuy ? m_point : -m_point));
         
         if(ModifyStopLoss(ticket, newSL))
         {
            m_log.Trade(StringFormat("EMERGENCY BE: Ticket %d moved SL to %.2f", ticket, newSL));
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Close all open positions (for Friday close, challenge end, etc.)  |
   //+------------------------------------------------------------------+
   void CloseAllPositions(int magicNumber, string symbol)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
         if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
         
         ClosePosition(ticket);
      }
      
      ResetActivePosition();
   }
   
   //+------------------------------------------------------------------+
   //| Close a specific position by ticket                               |
   //| Returns: true if successfully closed                              |
   //+------------------------------------------------------------------+
   bool ClosePosition(ulong ticket)
   {
      if(!PositionSelectByTicket(ticket))
      {
         m_log.Warn(StringFormat("Position %d not found for close.", ticket));
         return false;
      }
      
      int retries = 0;
      bool closed = false;
      
      while(!closed && retries < MAX_ORDER_RETRIES)
      {
         if(m_trade.PositionClose(ticket, m_deviationPoints))
         {
            uint retcode = m_trade.ResultRetcode();
            if(retcode == TRADE_RETCODE_DONE)
            {
               closed = true;
               m_log.Trade(StringFormat("Position %d closed successfully.", ticket));
               
               if(ticket == m_activeTicket)
                  ResetActivePosition();
            }
            else
            {
               retries++;
               m_log.Warn(StringFormat("Close failed: retcode=%d. Retry %d/%d", 
                          retcode, retries, MAX_ORDER_RETRIES));
               Sleep(ORDER_RETRY_DELAY_MS);
            }
         }
         else
         {
            retries++;
            m_log.Error(StringFormat("PositionClose failed: error=%d. Retry %d/%d",
                        GetLastError(), retries, MAX_ORDER_RETRIES));
            Sleep(ORDER_RETRY_DELAY_MS);
         }
      }
      
      if(!closed)
         m_log.Error(StringFormat("CRITICAL: Failed to close position %d after %d retries!", 
                     ticket, MAX_ORDER_RETRIES));
      
      return closed;
   }
   
   //+------------------------------------------------------------------+
   //| Partial close a position                                          |
   //| Parameters:                                                       |
   //|   ticket    - position ticket                                     |
   //|   closeLots - lots to close                                       |
   //| Returns: true if partial close succeeded                          |
   //+------------------------------------------------------------------+
   bool PartialClose(ulong ticket, double closeLots)
   {
      if(!PositionSelectByTicket(ticket))
      {
         m_log.Warn(StringFormat("Position %d not found for partial close.", ticket));
         return false;
      }
      
      double remainingLots = PositionGetDouble(POSITION_VOLUME);
      if(closeLots >= remainingLots)
      {
         m_log.Warn("Partial close lots >= remaining. Performing full close.");
         return ClosePosition(ticket);
      }
      
      closeLots = CMathUtils::NormalizeLot(m_symbol, closeLots);
      if(closeLots < m_minLot)
      {
         m_log.Warn(StringFormat("Partial close lots %.4f below minimum %.2f. Skipping.", closeLots, m_minLot));
         return false;
      }
      
      bool success = m_trade.PositionClosePartial(ticket, closeLots, m_deviationPoints);
      
      if(success)
      {
         uint retcode = m_trade.ResultRetcode();
         if(retcode == TRADE_RETCODE_DONE)
         {
            m_log.Trade(StringFormat("Partial close: Ticket %d | Closed %.2f / %.2f lots", 
                        ticket, closeLots, remainingLots));
            return true;
         }
         else
         {
            m_log.Error(StringFormat("Partial close retcode: %d (%s)", retcode, m_trade.ResultRetcodeDescription()));
         }
      }
      else
      {
         m_log.Error(StringFormat("Partial close failed: error=%d", GetLastError()));
      }
      
      return false;
   }

private:
   //+------------------------------------------------------------------+
   //| Pre-flight check before order execution                           |
   //+------------------------------------------------------------------+
   bool PreFlightCheck(STradeResult &result)
   {
      // Check trading context
      if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
      {
         m_log.Error("Trading not allowed (MQL).");
         result.RejectionReason = REJECT_NOT_ALLOWED;
         return false;
      }
      
      if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
      {
         m_log.Error("Trading not allowed (Terminal).");
         result.RejectionReason = REJECT_NOT_ALLOWED;
         return false;
      }
      
      // Check spread
      int currentSpread = (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
      if(currentSpread > m_maxSpreadPoints)
      {
         m_log.Warn(StringFormat("Spread too wide: %d pts (max %d). Trade blocked.", 
                    currentSpread, m_maxSpreadPoints));
         result.RejectionReason = REJECT_SPREAD_TOO_WIDE;
         return false;
      }
      
      // Check if trade context is busy
      if(!IsTradeContextFree())
      {
         m_log.Warn("Trade context busy. Waiting...");
         int waitAttempts = 0;
         while(!IsTradeContextFree() && waitAttempts < 10)
         {
            Sleep(100);
            waitAttempts++;
         }
         if(!IsTradeContextFree())
         {
            result.RejectionReason = REJECT_TRADE_CONTEXT_BUSY;
            return false;
         }
      }
      
      return true;
   }
   
   //+------------------------------------------------------------------+
   //| Check if trade context is free                                    |
   //+------------------------------------------------------------------+
   bool IsTradeContextFree(void)
   {
      // In MQL5, trade context is managed internally
      // We check if trading is allowed
      return (bool)MQLInfoInteger(MQL_TRADE_ALLOWED) && 
             (bool)TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) &&
             (bool)AccountInfoInteger(ACCOUNT_TRADE_ALLOWED);
   }
   
   //+------------------------------------------------------------------+
   //| Modify stop loss of a position                                    |
   //+------------------------------------------------------------------+
   bool ModifyStopLoss(ulong ticket, double newSL)
   {
      if(!PositionSelectByTicket(ticket))
         return false;
      
      double currentTP = PositionGetDouble(POSITION_TP);
      double currentSL = PositionGetDouble(POSITION_SL);
      
      // Don't modify if the change is negligible
      if(MathAbs(newSL - currentSL) < m_point)
         return true;
      
      // Validate stop level
      double openPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      int stopLevel = (int)SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      long posType = PositionGetInteger(POSITION_TYPE);
      bool isBuy = (posType == POSITION_TYPE_BUY);
      double currentPrice = isBuy ? SymbolInfoDouble(m_symbol, SYMBOL_BID) 
                                   : SymbolInfoDouble(m_symbol, SYMBOL_ASK);
      
      double minDist = stopLevel * m_point;
      double actualDist = MathAbs(currentPrice - newSL);
      
      if(actualDist < minDist && minDist > 0)
      {
         m_log.Debug(StringFormat("SL modify skipped: dist %.2f < min %.2f", actualDist, minDist));
         return false;
      }
      
      bool result = m_trade.PositionModify(ticket, newSL, currentTP);
      
      if(!result)
      {
         uint retcode = m_trade.ResultRetcode();
         m_log.Debug(StringFormat("SL modify failed: ticket=%d, newSL=%.2f, retcode=%d", 
                     ticket, newSL, retcode));
         return false;
      }
      
      return (m_trade.ResultRetcode() == TRADE_RETCODE_DONE);
   }
   
   //+------------------------------------------------------------------+
   //| Check time-based exit condition (8 M5 candles without +0.5R)     |
   //+------------------------------------------------------------------+
   void CheckTimeBasedExit(ulong ticket, double openPrice, double posProfit, 
                           double profitInR, CStrategyEngine &strategy)
   {
      // Count M5 candles since entry
      if(m_entryTime == 0)
      {
         m_entryTime = (datetime)PositionGetInteger(POSITION_TIME);
         m_entryBarIndex = iBars(m_symbol, PERIOD_M5);
      }
      
      int currentBarIndex = iBars(m_symbol, PERIOD_M5);
      int candlesSinceEntry = currentBarIndex - m_entryBarIndex;
      
      if(candlesSinceEntry < 0) candlesSinceEntry = 0;
      
      // If 8+ M5 candles (40 min) and trade hasn't reached +0.5R, exit
      if(candlesSinceEntry >= 8 && profitInR < 0.5 && m_partialCloseStage == 0)
      {
         m_log.Trade(StringFormat("TIME EXIT: Ticket %d | %d candles without +0.5R (current %.2fR). Closing.",
                     ticket, candlesSinceEntry, profitInR));
         ClosePosition(ticket);
      }
   }
   
   //+------------------------------------------------------------------+
   //| Set active position state for management tracking                 |
   //+------------------------------------------------------------------+
   void SetActivePosition(ulong ticket, double entryPrice, double sl, double tp,
                          double slDistance, double lots, bool isBullish)
   {
      m_activeTicket = ticket;
      m_activeEntryPrice = entryPrice;
      m_activeSL = sl;
      m_activeTP = tp;
      m_originalSLDistance = slDistance;
      m_originalLots = lots;
      m_isBullish = isBullish;
      m_isAtBreakeven = false;
      m_partialCloseStage = 0;
      m_entryTime = TimeCurrent();
      m_entryBarIndex = iBars(m_symbol, PERIOD_M5);
   }
   
   //+------------------------------------------------------------------+
   //| Reset active position state                                       |
   //+------------------------------------------------------------------+
   void ResetActivePosition(void)
   {
      m_activeTicket = 0;
      m_activeEntryPrice = 0;
      m_activeSL = 0;
      m_activeTP = 0;
      m_originalSLDistance = 0;
      m_originalLots = 0;
      m_isBullish = true;
      m_isAtBreakeven = false;
      m_partialCloseStage = 0;
      m_entryTime = 0;
      m_entryBarIndex = 0;
   }
   
   //+------------------------------------------------------------------+
   //| Refresh cached symbol information                                 |
   //+------------------------------------------------------------------+
   void RefreshSymbolInfo(void)
   {
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_digits = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_minLot = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_lotStep = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      
      if(m_point <= 0) m_point = 0.01;
      if(m_tickSize <= 0) m_tickSize = 0.01;
      if(m_tickValue <= 0) m_tickValue = 1.0;
      if(m_minLot <= 0) m_minLot = 0.01;
      if(m_lotStep <= 0) m_lotStep = 0.01;
   }
};

#endif // ORDER_MANAGER_MQH
