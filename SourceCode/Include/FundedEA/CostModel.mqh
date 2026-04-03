//+------------------------------------------------------------------+
//|                                                 CostModel.mqh    |
//|                         Funded.E.A Development Team              |
//|                         Execution Cost Model & Accounting        |
//+------------------------------------------------------------------+
//| Purpose: Manages ALL execution costs for XAUUSD trading:         |
//|   - Spread monitoring and filtering                              |
//|   - Slippage estimation and tracking                             |
//|   - Commission calculation and accounting                        |
//|   - Swap/overnight fee tracking                                  |
//|   - Net cost per trade model                                     |
//|   - Cost-aware drawdown accounting                               |
//| Every trade must pass the cost viability check before execution. |
//+------------------------------------------------------------------+
#ifndef COST_MODEL_MQH
#define COST_MODEL_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| Daily cost tracking container                                     |
//+------------------------------------------------------------------+
struct SDailyCosts
{
   double   SpreadPaidTotal;     // Total spread cost paid today ($)
   double   CommissionPaidTotal; // Total commission paid today ($)
   double   SwapAccruedTotal;    // Total swap accrued today ($)
   double   SlippageCostTotal;   // Total slippage cost today ($)
   double   GrossPnLToday;      // Gross P&L before costs
   double   NetPnLToday;        // Net P&L after all costs
   double   TotalCostsToday;    // Sum of all costs today
   int      TradesExecuted;     // Number of trades executed today
   
   void Reset()
   {
      SpreadPaidTotal = 0;
      CommissionPaidTotal = 0;
      SwapAccruedTotal = 0;
      SlippageCostTotal = 0;
      GrossPnLToday = 0;
      NetPnLToday = 0;
      TotalCostsToday = 0;
      TradesExecuted = 0;
   }
   
   void Recalculate()
   {
      TotalCostsToday = SpreadPaidTotal + CommissionPaidTotal 
                      + MathAbs(SwapAccruedTotal) + SlippageCostTotal;
      NetPnLToday = GrossPnLToday - TotalCostsToday;
   }
};

//+------------------------------------------------------------------+
//| CCostModel - Execution Cost Accounting Engine                     |
//+------------------------------------------------------------------+
class CCostModel
{
private:
   //--- Configuration
   string            m_symbol;
   int               m_maxSpreadPoints;       // Max allowed spread in points
   double            m_commissionPerLotRT;     // Commission per lot round trip ($)
   double            m_maxSwapPerTrade;        // Max acceptable swap per trade ($)
   bool              m_avoidWednesdaySwap;     // Avoid triple swap on Wednesday
   
   //--- Cached symbol info
   double            m_point;
   double            m_tickValue;
   double            m_tickSize;
   
   //--- Rolling slippage tracker (last 20 trades)
   double            m_slippageSamples[];
   int               m_maxSlippageSamples;
   double            m_avgSlippage;            // Rolling average slippage in points
   
   //--- Cost tracking
   SDailyCosts       m_dailyCosts;             // Today's cost summary
   double            m_totalCostsAllTime;      // Cumulative costs for the challenge
   int               m_totalTradesAllTime;     // Total trades for the challenge
   
   //--- Logger
   CLogger           m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CCostModel(void)
   {
      m_log.SetPrefix("Cost");
      m_symbol = "";
      m_maxSpreadPoints = 30;
      m_commissionPerLotRT = 0.0;
      m_maxSwapPerTrade = 5.0;
      m_avoidWednesdaySwap = true;
      m_point = 0.01;
      m_tickValue = 1.0;
      m_tickSize = 0.01;
      m_maxSlippageSamples = 20;
      m_avgSlippage = 0;
      m_totalCostsAllTime = 0;
      m_totalTradesAllTime = 0;
      
      ArrayResize(m_slippageSamples, 0);
      m_dailyCosts.Reset();
   }
   
   //+------------------------------------------------------------------+
   //| Initialize the cost model                                         |
   //| Parameters:                                                       |
   //|   symbol            - trading symbol                              |
   //|   maxSpreadPoints   - max allowed spread in points for entry      |
   //|   commissionPerLot  - commission per lot round trip ($)           |
   //|   maxSwapPerTrade   - max acceptable swap per trade ($)           |
   //|   avoidWedSwap      - avoid triple swap on Wednesday              |
   //| Returns: void                                                     |
   //+------------------------------------------------------------------+
   void Initialize(string symbol, int maxSpreadPoints, double commissionPerLot,
                   double maxSwapPerTrade, bool avoidWedSwap)
   {
      m_symbol = symbol;
      m_maxSpreadPoints = maxSpreadPoints;
      m_commissionPerLotRT = commissionPerLot;
      m_maxSwapPerTrade = maxSwapPerTrade;
      m_avoidWednesdaySwap = avoidWedSwap;
      
      RefreshSymbolInfo();
      
      m_log.Info(StringFormat("CostModel initialized: MaxSpread=%d pts | Commission=$%.2f/lot RT | MaxSwap=$%.2f",
                 maxSpreadPoints, commissionPerLot, maxSwapPerTrade));
   }
   
   //+------------------------------------------------------------------+
   //| Refresh cached symbol information                                 |
   //+------------------------------------------------------------------+
   void RefreshSymbolInfo(void)
   {
      m_point = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_tickValue = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      m_tickSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      
      if(m_point <= 0) m_point = 0.01;
      if(m_tickValue <= 0) m_tickValue = 1.0;
      if(m_tickSize <= 0) m_tickSize = 0.01;
   }
   
   //+------------------------------------------------------------------+
   //| Check if current spread is acceptable for trading                 |
   //| Returns: true if spread is within allowed limits                  |
   //+------------------------------------------------------------------+
   bool IsSpreadAcceptable(void)
   {
      int currentSpread = GetCurrentSpreadPoints();
      return (currentSpread <= m_maxSpreadPoints);
   }
   
   //+------------------------------------------------------------------+
   //| Get current spread in points                                      |
   //+------------------------------------------------------------------+
   int GetCurrentSpreadPoints(void)
   {
      return (int)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD);
   }
   
   //+------------------------------------------------------------------+
   //| Get current spread in USD for a given lot size                    |
   //+------------------------------------------------------------------+
   double GetSpreadCostUSD(double lots)
   {
      int spreadPoints = GetCurrentSpreadPoints();
      double spreadTicks = (double)spreadPoints * m_point / m_tickSize;
      return spreadTicks * m_tickValue * lots;
   }
   
   //+------------------------------------------------------------------+
   //| Calculate commission cost for given lot size                       |
   //| Returns: Commission in USD (round trip)                           |
   //+------------------------------------------------------------------+
   double GetCommissionCost(double lots)
   {
      return m_commissionPerLotRT * lots;
   }
   
   //+------------------------------------------------------------------+
   //| Get estimated slippage cost based on rolling average              |
   //| Returns: Estimated slippage in USD                                |
   //+------------------------------------------------------------------+
   double GetEstimatedSlippageCostUSD(double lots)
   {
      double avgSlippageTicks = m_avgSlippage / m_tickSize;
      if(avgSlippageTicks <= 0 && ArraySize(m_slippageSamples) == 0)
      {
         // Default estimate: 3 points slippage
         avgSlippageTicks = 3.0 * m_point / m_tickSize;
      }
      return avgSlippageTicks * m_tickValue * lots;
   }
   
   //+------------------------------------------------------------------+
   //| Get estimated swap cost for holding position                      |
   //| Parameters:                                                       |
   //|   lots        - position size                                     |
   //|   isBullish   - trade direction                                   |
   //|   holdingDays - expected holding days (0 for intraday)            |
   //| Returns: Estimated swap cost in USD (absolute value)              |
   //+------------------------------------------------------------------+
   double GetEstimatedSwapCost(double lots, bool isBullish, int holdingDays=0)
   {
      if(holdingDays <= 0) return 0; // Intraday: no swap
      
      // Get swap rate from broker
      double swapRate;
      if(isBullish)
         swapRate = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_LONG);
      else
         swapRate = SymbolInfoDouble(m_symbol, SYMBOL_SWAP_SHORT);
      
      // Swap mode (typically in points for XAUUSD)
      int swapMode = (int)SymbolInfoInteger(m_symbol, SYMBOL_SWAP_MODE);
      
      double dailySwapUSD = 0;
      
      switch(swapMode)
      {
         case SYMBOL_SWAP_MODE_POINTS:
            // Swap is in points per lot per night
            dailySwapUSD = MathAbs(swapRate) * m_point / m_tickSize * m_tickValue * lots;
            break;
         case SYMBOL_SWAP_MODE_CURRENCY_SYMBOL:
         case SYMBOL_SWAP_MODE_CURRENCY_DEPOSIT:
            // Swap is already in currency per lot per night
            dailySwapUSD = MathAbs(swapRate) * lots;
            break;
         case SYMBOL_SWAP_MODE_INTEREST_CURRENT:
         case SYMBOL_SWAP_MODE_INTEREST_OPEN:
            // Swap as annual interest rate
            {
               double price = SymbolInfoDouble(m_symbol, SYMBOL_BID);
               double contractSize = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_CONTRACT_SIZE);
               dailySwapUSD = MathAbs(swapRate) / 100.0 / 365.0 * price * contractSize * lots;
            }
            break;
         default:
            // Assume points mode as default
            dailySwapUSD = MathAbs(swapRate) * m_point / m_tickSize * m_tickValue * lots;
            break;
      }
      
      return dailySwapUSD * holdingDays;
   }
   
   //+------------------------------------------------------------------+
   //| Evaluate total cost for a proposed trade                          |
   //| Purpose: Determine if a trade is cost-viable (TP > Cost*3)      |
   //| Parameters:                                                       |
   //|   cost [out]        - populated cost structure                    |
   //|   lots              - proposed lot size                           |
   //|   slDistancePoints  - SL distance in points                      |
   //|   isOvernight       - will trade be held overnight?               |
   //| Returns: void                                                     |
   //| Side Effects: Populates cost structure                            |
   //+------------------------------------------------------------------+
   void EvaluateTradeCost(STradeCost &cost, double lots, double slDistancePoints, bool isOvernight)
   {
      cost.Reset();
      
      // Spread cost
      cost.CurrentSpreadPts = GetCurrentSpreadPoints();
      cost.SpreadCostUSD = GetSpreadCostUSD(lots);
      
      // Commission cost
      cost.CommissionUSD = GetCommissionCost(lots);
      
      // Estimated slippage cost
      cost.AvgSlippagePts = m_avgSlippage;
      cost.EstSlippageUSD = GetEstimatedSlippageCostUSD(lots);
      
      // Estimated swap cost
      cost.EstSwapUSD = isOvernight ? GetEstimatedSwapCost(lots, true, 1) : 0;
      
      // Total cost
      cost.TotalCostUSD = cost.SpreadCostUSD + cost.CommissionUSD 
                        + cost.EstSlippageUSD + cost.EstSwapUSD;
      
      // Minimum TP requirement: TP1 must yield > TotalCost * 3 (3:1 vs costs)
      cost.MinimumTPRequired = cost.TotalCostUSD * 3.0;
      
      m_log.Debug(StringFormat("TradeCost: Spread=$%.2f Commission=$%.2f Slip=$%.2f Swap=$%.2f | Total=$%.2f | MinTP=$%.2f",
                  cost.SpreadCostUSD, cost.CommissionUSD, cost.EstSlippageUSD, 
                  cost.EstSwapUSD, cost.TotalCostUSD, cost.MinimumTPRequired));
   }
   
   //+------------------------------------------------------------------+
   //| Check if a trade passes cost viability                            |
   //| Rule: TP1 must yield > TotalCost * 3                             |
   //| Parameters:                                                       |
   //|   tp1USD - expected TP1 profit in USD                             |
   //|   cost   - evaluated cost for the trade                          |
   //| Returns: true if trade is cost-viable                             |
   //+------------------------------------------------------------------+
   bool IsTradeCostViable(double tp1USD, const STradeCost &cost)
   {
      if(tp1USD <= 0)
      {
         m_log.Warn("TP1 value is zero or negative. Trade not cost-viable.");
         return false;
      }
      
      bool viable = (tp1USD >= cost.MinimumTPRequired);
      
      if(!viable)
      {
         m_log.Cost(StringFormat("Trade NOT cost-viable: TP1=$%.2f < MinRequired=$%.2f (TotalCost=$%.2f * 3)",
                    tp1USD, cost.MinimumTPRequired, cost.TotalCostUSD));
      }
      
      return viable;
   }
   
   //+------------------------------------------------------------------+
   //| Record slippage observation after a trade fill                    |
   //| Parameters:                                                       |
   //|   requestedPrice - price requested in order                       |
   //|   filledPrice    - actual fill price                              |
   //|   isBullish      - trade direction                                |
   //+------------------------------------------------------------------+
   void RecordSlippage(double requestedPrice, double filledPrice, bool isBullish)
   {
      double slippagePrice = 0;
      
      if(isBullish)
         slippagePrice = filledPrice - requestedPrice; // Positive = negative slippage for buy
      else
         slippagePrice = requestedPrice - filledPrice; // Positive = negative slippage for sell
      
      double slippagePoints = MathAbs(slippagePrice);
      
      // Add to rolling window
      int size = ArraySize(m_slippageSamples);
      if(size >= m_maxSlippageSamples)
      {
         // Shift left
         for(int i = 0; i < size - 1; i++)
            m_slippageSamples[i] = m_slippageSamples[i + 1];
         m_slippageSamples[size - 1] = slippagePoints;
      }
      else
      {
         ArrayResize(m_slippageSamples, size + 1);
         m_slippageSamples[size] = slippagePoints;
      }
      
      // Update rolling average
      m_avgSlippage = 0;
      size = ArraySize(m_slippageSamples);
      for(int i = 0; i < size; i++)
         m_avgSlippage += m_slippageSamples[i];
      m_avgSlippage /= (double)size;
      
      // Update daily cost tracking
      double slippageCostUSD = slippagePoints / m_tickSize * m_tickValue;
      m_dailyCosts.SlippageCostTotal += slippageCostUSD;
      
      // Log significant slippage
      if(slippagePoints > 10 * m_point) // More than 1 pip
      {
         m_log.Cost(StringFormat("Slippage: %.1f pts (%s). Requested=%.2f Filled=%.2f",
                    slippagePoints / m_point, 
                    slippagePrice > 0 ? "NEGATIVE" : "POSITIVE",
                    requestedPrice, filledPrice));
      }
   }
   
   //+------------------------------------------------------------------+
   //| Record costs from a closed trade (from deal history)              |
   //| Parameters:                                                       |
   //|   dealTicket - closed deal ticket number                          |
   //|   lots       - trade lot size                                     |
   //+------------------------------------------------------------------+
   void RecordClosedTradeCosts(ulong dealTicket, double lots)
   {
      // Read commission from deal history
      double commission = HistoryDealGetDouble(dealTicket, DEAL_COMMISSION);
      double swap = HistoryDealGetDouble(dealTicket, DEAL_SWAP);
      double profit = HistoryDealGetDouble(dealTicket, DEAL_PROFIT);
      
      // Spread cost (estimated from the entry as it's already embedded in P&L)
      // The actual spread cost was already paid at entry
      
      // Update daily tracking
      m_dailyCosts.CommissionPaidTotal += MathAbs(commission);
      m_dailyCosts.SwapAccruedTotal += swap;
      m_dailyCosts.GrossPnLToday += profit;
      m_dailyCosts.TradesExecuted++;
      m_dailyCosts.Recalculate();
      
      // Update lifetime tracking
      m_totalCostsAllTime += MathAbs(commission) + MathAbs(swap);
      m_totalTradesAllTime++;
      
      m_log.Cost(StringFormat("Trade closed: Profit=$%.2f | Commission=$%.2f | Swap=$%.2f | Lots=%.2f",
                 profit, commission, swap, lots));
   }
   
   //+------------------------------------------------------------------+
   //| Record spread cost at trade entry                                 |
   //| Parameters:                                                       |
   //|   lots - trade lot size                                           |
   //+------------------------------------------------------------------+
   void RecordEntrySpreadCost(double lots)
   {
      double spreadCost = GetSpreadCostUSD(lots);
      m_dailyCosts.SpreadPaidTotal += spreadCost;
      m_dailyCosts.Recalculate();
      
      m_log.Debug(StringFormat("Spread cost at entry: $%.2f (lots=%.2f, spread=%d pts)",
                  spreadCost, lots, GetCurrentSpreadPoints()));
   }
   
   //+------------------------------------------------------------------+
   //| Get the current swap accrued on all open positions                 |
   //| Parameters:                                                       |
   //|   magicNumber - EA magic number for filtering                     |
   //|   symbol      - trading symbol                                    |
   //| Returns: Total floating swap in USD                               |
   //+------------------------------------------------------------------+
   double GetFloatingSwap(int magicNumber, string symbol)
   {
      double totalSwap = 0;
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
         if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
         
         totalSwap += PositionGetDouble(POSITION_SWAP);
      }
      return totalSwap;
   }
   
   //+------------------------------------------------------------------+
   //| Check if floating swap exceeds maximum allowed per trade          |
   //| Returns: true if swap is excessive                                |
   //+------------------------------------------------------------------+
   bool IsSwapExcessive(int magicNumber, string symbol)
   {
      for(int i = PositionsTotal() - 1; i >= 0; i--)
      {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0) continue;
         if(PositionGetInteger(POSITION_MAGIC) != magicNumber) continue;
         if(symbol != "" && PositionGetString(POSITION_SYMBOL) != symbol) continue;
         
         double swap = MathAbs(PositionGetDouble(POSITION_SWAP));
         if(swap >= m_maxSwapPerTrade)
         {
            m_log.Warn(StringFormat("Swap excessive on ticket %d: $%.2f >= max $%.2f",
                       ticket, swap, m_maxSwapPerTrade));
            return true;
         }
      }
      return false;
   }
   
   //+------------------------------------------------------------------+
   //| Get daily costs summary                                           |
   //+------------------------------------------------------------------+
   SDailyCosts GetDailyCosts(void) const { return m_dailyCosts; }
   
   //+------------------------------------------------------------------+
   //| Get cost drag percentage (costs as % of gross P&L)                |
   //+------------------------------------------------------------------+
   double GetCostDragPct(void)
   {
      if(MathAbs(m_dailyCosts.GrossPnLToday) < 0.01)
         return 0;
      return CMathUtils::Percentage(m_dailyCosts.TotalCostsToday, 
                                     MathAbs(m_dailyCosts.GrossPnLToday));
   }
   
   //+------------------------------------------------------------------+
   //| Get rolling average slippage in points                            |
   //+------------------------------------------------------------------+
   double GetAverageSlippagePoints(void) const { return m_avgSlippage; }
   
   //+------------------------------------------------------------------+
   //| Get total lifetime costs                                          |
   //+------------------------------------------------------------------+
   double GetTotalCostsAllTime(void) const { return m_totalCostsAllTime; }
   
   //+------------------------------------------------------------------+
   //| Get total lifetime trades                                         |
   //+------------------------------------------------------------------+
   int GetTotalTradesAllTime(void) const { return m_totalTradesAllTime; }
   
   //+------------------------------------------------------------------+
   //| Get commission per lot round trip                                  |
   //+------------------------------------------------------------------+
   double GetCommissionPerLotRT(void) const { return m_commissionPerLotRT; }
   
   //+------------------------------------------------------------------+
   //| Get max allowed spread in points                                  |
   //+------------------------------------------------------------------+
   int GetMaxSpreadPoints(void) const { return m_maxSpreadPoints; }
   
   //+------------------------------------------------------------------+
   //| Check if Wednesday swap avoidance is needed                       |
   //+------------------------------------------------------------------+
   bool ShouldAvoidWednesdaySwap(void) const { return m_avoidWednesdaySwap; }
   
   //+------------------------------------------------------------------+
   //| Calculate breakeven distance including all costs                  |
   //| Parameters:                                                       |
   //|   lots - position size                                            |
   //| Returns: Price distance needed to break even (in price terms)     |
   //+------------------------------------------------------------------+
   double GetBreakevenDistance(double lots)
   {
      // Total cost for this trade
      double totalCost = GetSpreadCostUSD(lots) + GetCommissionCost(lots);
      
      // Convert USD cost to price distance
      if(m_tickValue <= 0 || lots <= 0) return 0;
      double ticks = totalCost / (m_tickValue * lots);
      return ticks * m_tickSize;
   }
   
   //+------------------------------------------------------------------+
   //| Reset daily cost tracking (call at day start)                     |
   //+------------------------------------------------------------------+
   void ResetDailyCosts(void)
   {
      m_dailyCosts.Reset();
      m_log.Debug("Daily cost tracker reset.");
   }
   
   //+------------------------------------------------------------------+
   //| Generate cost summary string for logging                          |
   //+------------------------------------------------------------------+
   string GetCostSummaryString(void)
   {
      return StringFormat("Spread=$%.2f | Comm=$%.2f | Slip=$%.2f | Swap=$%.2f | Total=$%.2f (%.1f%% drag)",
                          m_dailyCosts.SpreadPaidTotal,
                          m_dailyCosts.CommissionPaidTotal,
                          m_dailyCosts.SlippageCostTotal,
                          m_dailyCosts.SwapAccruedTotal,
                          m_dailyCosts.TotalCostsToday,
                          GetCostDragPct());
   }
};

#endif // COST_MODEL_MQH
