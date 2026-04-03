//+------------------------------------------------------------------+
//|                                                Dashboard.mqh     |
//|                         Funded.E.A Development Team              |
//|                         On-Chart Real-Time GUI Panel             |
//+------------------------------------------------------------------+
//| Purpose: Renders an advanced, real-time dashboard panel on the   |
//|          chart using ObjectCreate(). Updates dynamically on each |
//|          tick with color-coded status indicators.                |
//|                                                                  |
//| Sections:                                                        |
//|   1. Header & Challenge Status                                   |
//|   2. Progress Bar (visual % complete)                            |
//|   3. Drawdown Usage Bars (Daily & Total)                         |
//|   4. Engine Status (Mode, Risk, Trades)                          |
//|   5. Execution Metrics (Spread, Slippage, Latency, Costs)       |
//|   6. Session & News Status                                       |
//|   7. Last Trade Info                                             |
//+------------------------------------------------------------------+
#ifndef DASHBOARD_MQH
#define DASHBOARD_MQH

#include "Utils.mqh"
#include "CostModel.mqh"

//+------------------------------------------------------------------+
//| Dashboard layout constants                                        |
//+------------------------------------------------------------------+
#define DASH_PREFIX        "FEA_DASH_"      // Object name prefix
#define DASH_BG_NAME       "FEA_DASH_BG"    // Background panel
#define DASH_LINE_HEIGHT   18               // Pixels between lines
#define DASH_PADDING_X     12               // Horizontal padding
#define DASH_PADDING_Y     8                // Vertical padding
#define DASH_PANEL_WIDTH   380              // Panel width in pixels
#define DASH_MAX_LINES     28               // Maximum display lines
#define DASH_SEPARATOR     "─────────────────────────────────"

//+------------------------------------------------------------------+
//| CDashboard - On-Chart Real-Time Panel                             |
//+------------------------------------------------------------------+
class CDashboard
{
private:
   //--- Configuration
   ENUM_DASHBOARD_CORNER m_corner;           // Panel corner position
   int               m_fontSize;             // Font size
   string            m_fontName;             // Font name
   string            m_firmName;             // Firm name for header
   string            m_phaseName;            // Phase name for header
   double            m_accountSize;          // Account size for header
   
   //--- Layout
   int               m_startX;               // Panel start X (from corner)
   int               m_startY;               // Panel start Y (from corner)
   int               m_currentLine;          // Current line being drawn
   long              m_chartID;              // Chart ID
   
   //--- Color scheme
   color             m_clrBackground;        // Panel background
   color             m_clrBorder;            // Panel border
   color             m_clrHeader;            // Header text
   color             m_clrLabel;             // Label text (dim)
   color             m_clrValue;             // Value text (bright)
   color             m_clrGreen;             // Good/safe status
   color             m_clrYellow;            // Caution status
   color             m_clrRed;               // Alert/danger status
   color             m_clrBlue;              // Info/ahead status
   color             m_clrSeparator;         // Separator line color
   color             m_clrMuted;             // Dimmed/secondary text
   
   //--- State tracking
   bool              m_initialized;          // Dashboard created
   int               m_objectCount;          // Count of created objects
   
   //--- Logger
   CLogger           m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CDashboard(void)
   {
      m_log.SetPrefix("Dashboard");
      m_corner = CORNER_TOP_RIGHT;
      m_fontSize = 10;
      m_fontName = "Consolas";
      m_firmName = "FTMO";
      m_phaseName = "Phase 1";
      m_accountSize = 10000;
      m_startX = 15;
      m_startY = 25;
      m_currentLine = 0;
      m_chartID = 0;
      m_initialized = false;
      m_objectCount = 0;
      
      // Color scheme: Dark theme with neon accents
      m_clrBackground = C'18,18,24';        // Deep dark blue-black
      m_clrBorder = C'45,45,65';            // Subtle border
      m_clrHeader = C'0,200,255';           // Cyan header
      m_clrLabel = C'140,140,160';          // Dim grey labels
      m_clrValue = C'220,220,235';          // Bright white values
      m_clrGreen = C'0,230,118';            // Neon green
      m_clrYellow = C'255,193,7';           // Warm yellow
      m_clrRed = C'255,61,87';             // Vibrant red
      m_clrBlue = C'33,150,243';           // Info blue
      m_clrSeparator = C'55,55,75';        // Dim separator
      m_clrMuted = C'100,100,120';         // Very dim text
   }
   
   //+------------------------------------------------------------------+
   //| Initialize the dashboard                                          |
   //| Parameters:                                                       |
   //|   corner    - screen corner for panel placement                   |
   //|   fontSize  - base font size                                      |
   //|   firmName  - firm name for header display                        |
   //|   phaseName - phase name for header display                       |
   //|   acctSize  - account size for header display                     |
   //+------------------------------------------------------------------+
   void Initialize(ENUM_DASHBOARD_CORNER corner, int fontSize,
                   string firmName, string phaseName, double acctSize)
   {
      m_corner = corner;
      m_fontSize = fontSize;
      m_firmName = firmName;
      m_phaseName = phaseName;
      m_accountSize = acctSize;
      m_chartID = ChartID();
      
      // Adjust start position based on corner
      switch(corner)
      {
         case CORNER_TOP_LEFT:
            m_startX = 15;
            m_startY = 25;
            break;
         case CORNER_TOP_RIGHT:
            m_startX = 15;
            m_startY = 25;
            break;
         case CORNER_BOTTOM_LEFT:
            m_startX = 15;
            m_startY = DASH_MAX_LINES * DASH_LINE_HEIGHT + 40;
            break;
         case CORNER_BOTTOM_RIGHT:
            m_startX = 15;
            m_startY = DASH_MAX_LINES * DASH_LINE_HEIGHT + 40;
            break;
      }
      
      m_initialized = true;
      m_log.Info(StringFormat("Dashboard initialized: corner=%d fontSize=%d", corner, fontSize));
   }
   
   //+------------------------------------------------------------------+
   //| Update the dashboard with current state                           |
   //| Parameters:                                                       |
   //|   state    - current engine state                                 |
   //|   cost     - current cost snapshot                                |
   //|   latency  - latency meter for RTT display                       |
   //|   costModel - cost model for daily cost summary                   |
   //+------------------------------------------------------------------+
   void Update(const SEngineState &state, const STradeCost &cost,
               CLatencyMeter &latency, CCostModel &costModel)
   {
      if(!m_initialized) return;
      
      // Reset line counter
      m_currentLine = 0;
      
      // Build and render each section
      RenderBackground();
      RenderHeader(state);
      RenderSeparator();
      RenderChallengeStatus(state);
      RenderSeparator();
      RenderDrawdownStatus(state);
      RenderSeparator();
      RenderEngineStatus(state);
      RenderSeparator();
      RenderExecutionMetrics(cost, latency, costModel);
      RenderSeparator();
      RenderSessionStatus(state);
      RenderSeparator();
      RenderLastTrade(state);
      
      ChartRedraw(m_chartID);
   }
   
   //+------------------------------------------------------------------+
   //| Destroy all dashboard objects                                     |
   //+------------------------------------------------------------------+
   void Destroy(void)
   {
      // Delete all objects with our prefix
      int total = ObjectsTotal(m_chartID, 0);
      for(int i = total - 1; i >= 0; i--)
      {
         string name = ObjectName(m_chartID, i, 0);
         if(StringFind(name, DASH_PREFIX) == 0)
            ObjectDelete(m_chartID, name);
      }
      
      m_initialized = false;
      m_objectCount = 0;
      m_log.Info("Dashboard destroyed.");
   }

private:
   //+------------------------------------------------------------------+
   //| Render the background panel                                       |
   //+------------------------------------------------------------------+
   void RenderBackground(void)
   {
      string bgName = DASH_BG_NAME;
      int totalHeight = DASH_MAX_LINES * DASH_LINE_HEIGHT + DASH_PADDING_Y * 2 + 10;
      
      ENUM_BASE_CORNER baseCorner;
      switch(m_corner)
      {
         case CORNER_TOP_LEFT:     baseCorner = CORNER_LEFT_UPPER; break;
         case CORNER_TOP_RIGHT:    baseCorner = CORNER_RIGHT_UPPER; break;
         case CORNER_BOTTOM_LEFT:  baseCorner = CORNER_LEFT_LOWER; break;
         case CORNER_BOTTOM_RIGHT: baseCorner = CORNER_RIGHT_LOWER; break;
         default:                  baseCorner = CORNER_RIGHT_UPPER; break;
      }
      
      if(ObjectFind(m_chartID, bgName) < 0)
      {
         ObjectCreate(m_chartID, bgName, OBJ_RECTANGLE_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartID, bgName, OBJPROP_CORNER, baseCorner);
         ObjectSetInteger(m_chartID, bgName, OBJPROP_BACK, false);
         ObjectSetInteger(m_chartID, bgName, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartID, bgName, OBJPROP_HIDDEN, true);
      }
      
      ObjectSetInteger(m_chartID, bgName, OBJPROP_XDISTANCE, m_startX - 5);
      ObjectSetInteger(m_chartID, bgName, OBJPROP_YDISTANCE, m_startY - 10);
      ObjectSetInteger(m_chartID, bgName, OBJPROP_XSIZE, DASH_PANEL_WIDTH);
      ObjectSetInteger(m_chartID, bgName, OBJPROP_YSIZE, totalHeight);
      ObjectSetInteger(m_chartID, bgName, OBJPROP_BGCOLOR, m_clrBackground);
      ObjectSetInteger(m_chartID, bgName, OBJPROP_BORDER_COLOR, m_clrBorder);
      ObjectSetInteger(m_chartID, bgName, OBJPROP_BORDER_TYPE, BORDER_FLAT);
      ObjectSetInteger(m_chartID, bgName, OBJPROP_WIDTH, 1);
   }
   
   //+------------------------------------------------------------------+
   //| Render header section                                             |
   //+------------------------------------------------------------------+
   void RenderHeader(const SEngineState &state)
   {
      // Line 1: EA name, version, phase, firm
      string header = StringFormat("  %s v%s │ %s │ %s $%s",
                      EA_NAME, EA_VERSION, m_phaseName, m_firmName,
                      FormatNumber(m_accountSize));
      DrawText("header", header, m_clrHeader, m_fontSize + 1);
   }
   
   //+------------------------------------------------------------------+
   //| Render challenge status section                                   |
   //+------------------------------------------------------------------+
   void RenderChallengeStatus(const SEngineState &state)
   {
      double progressPct = CMathUtils::SafeDiv(state.ProfitSoFar, state.ProfitTargetAmount, 0) * 100.0;
      progressPct = CMathUtils::Clamp(progressPct, 0, 100);
      
      // Profit target line
      DrawText("target", StringFormat("  Profit Target:  $%.2f  │  Achieved: $%.2f (%.1f%%)",
               state.ProfitTargetAmount, state.ProfitSoFar, progressPct),
               m_clrValue, m_fontSize);
      
      // Progress bar
      string bar = "  Progress:    " + BuildProgressBar(progressPct, 22) + 
                   StringFormat(" %.0f%%", progressPct);
      DrawText("progress", bar, GetProgressColor(progressPct), m_fontSize);
      
      // Days info
      string daysText = StringFormat("  Days:        %d completed  │  %d remaining  │  %d min",
                        state.TradingDaysCompleted, state.TradingDaysRemaining,
                        0); // MinTradingDays would be passed separately
      DrawText("days", daysText, m_clrValue, m_fontSize);
      
      // Pace status
      string paceStr = PaceToString(state.PaceStatus);
      color paceColor = m_clrGreen;
      switch(state.PaceStatus)
      {
         case PACE_ON_TRACK: paceColor = m_clrGreen; paceStr += " ✓"; break;
         case PACE_AHEAD:    paceColor = m_clrBlue; paceStr += " ▲"; break;
         case PACE_SLIGHTLY_BEHIND: paceColor = m_clrYellow; paceStr += " ▼"; break;
         case PACE_BEHIND:   paceColor = m_clrRed; paceStr += " ▼▼"; break;
      }
      DrawText("pace", "  Pace Status: " + paceStr, paceColor, m_fontSize);
   }
   
   //+------------------------------------------------------------------+
   //| Render drawdown status section                                    |
   //+------------------------------------------------------------------+
   void RenderDrawdownStatus(const SEngineState &state)
   {
      // Daily DD
      double dailyPct = CMathUtils::Percentage(state.DailyDDUsedToday, state.DailyDDLimit);
      color dailyColor = GetStatusColor(dailyPct, 50, 70);
      string dailyStatus = (dailyPct < 50) ? "OK" : (dailyPct < 70 ? "WATCH" : (dailyPct < 80 ? "DANGER" : "HALT"));
      
      DrawText("dailydd", StringFormat("  Daily DD:    $%.2f / $%.2f  (%.1f%%)  [%s]",
               state.DailyDDUsedToday, state.DailyDDLimit, dailyPct, dailyStatus),
               dailyColor, m_fontSize);
      
      // Total DD
      double totalPct = CMathUtils::Percentage(state.TotalDDUsed, state.TotalDDLimit);
      color totalColor = GetStatusColor(totalPct, 40, 65);
      string totalStatus = (totalPct < 40) ? "OK" : (totalPct < 65 ? "WATCH" : (totalPct < 85 ? "DANGER" : "HALT"));
      
      DrawText("totaldd", StringFormat("  Total DD:    $%.2f / $%.2f  (%.1f%%)  [%s]",
               state.TotalDDUsed, state.TotalDDLimit, totalPct, totalStatus),
               totalColor, m_fontSize);
      
      // Equity
      DrawText("equity", StringFormat("  Equity:      $%.2f", state.CurrentEquity),
               m_clrValue, m_fontSize);
   }
   
   //+------------------------------------------------------------------+
   //| Render engine status section                                      |
   //+------------------------------------------------------------------+
   void RenderEngineStatus(const SEngineState &state)
   {
      // Mode with color coding
      color modeColor = m_clrGreen;
      switch(state.AggressivenessLevel)
      {
         case AGG_CONSERVATIVE: modeColor = m_clrBlue; break;
         case AGG_BALANCED:     modeColor = m_clrGreen; break;
         case AGG_ACCELERATED:  modeColor = m_clrYellow; break;
         case AGG_PAUSED:       modeColor = m_clrRed; break;
      }
      
      DrawText("mode", "  Mode:        " + AggressivenessToString(state.AggressivenessLevel),
               modeColor, m_fontSize);
      
      // Risk per trade
      DrawText("risk", StringFormat("  Risk/Trade:  %.2f%%  ($%.2f)", 
               state.RiskPerTrade, state.RiskPerTradeUSD),
               m_clrValue, m_fontSize);
      
      // Trades today
      string tradesStr = StringFormat("  Trades:      %d / %d", state.TradesToday, state.MaxTradesPerDay);
      if(state.TradingLockedToday) tradesStr += "  [LOCKED]";
      color tradesColor = state.TradingLockedToday ? m_clrYellow : m_clrValue;
      DrawText("trades", tradesStr, tradesColor, m_fontSize);
      
      // Required today vs earned today
      color earnedColor = (state.DailyProfitToday >= state.RequiredDailyProfit) ? m_clrGreen : m_clrValue;
      string earnedSuffix = "";
      if(state.DailyTargetMet) earnedSuffix = "  ✓ LOCKED";
      
      DrawText("required", StringFormat("  Required:    $%.2f  │  Earned: $%.2f%s",
               state.RequiredDailyProfit, state.DailyProfitToday, earnedSuffix),
               earnedColor, m_fontSize);
   }
   
   //+------------------------------------------------------------------+
   //| Render execution metrics section                                  |
   //+------------------------------------------------------------------+
   void RenderExecutionMetrics(const STradeCost &cost, CLatencyMeter &latency, CCostModel &costModel)
   {
      // Current spread
      int currentSpread = cost.CurrentSpreadPts;
      int maxSpread = costModel.GetMaxSpreadPoints();
      color spreadColor = (currentSpread <= maxSpread) ? m_clrGreen : m_clrRed;
      string spreadStatus = (currentSpread <= maxSpread) ? "OK" : "HIGH";
      
      DrawText("spread", StringFormat("  Spread:      %d pts  [%s]  │  Max: %d",
               currentSpread, spreadStatus, maxSpread),
               spreadColor, m_fontSize);
      
      // Average slippage
      DrawText("slippage", StringFormat("  Avg Slip:    %.1f pts  (last 20 trades)",
               cost.AvgSlippagePts / SymbolInfoDouble(Symbol(), SYMBOL_POINT)),
               m_clrValue, m_fontSize);
      
      // Latency
      string latencyStr = latency.GetLatencyStatus();
      color latencyColor = latency.IsLatencyOK() ? 
                           (latency.IsLatencyWarning() ? m_clrYellow : m_clrGreen) : m_clrRed;
      DrawText("latency", "  Broker RTT:  " + latencyStr, latencyColor, m_fontSize);
      
      // Daily costs summary
      SDailyCosts dailyCosts = costModel.GetDailyCosts();
      double dragPct = costModel.GetCostDragPct();
      
      DrawText("costs", StringFormat("  Costs Today: $%.2f  (%.1f%% drag vs gross)",
               dailyCosts.TotalCostsToday, dragPct),
               (dragPct < 5) ? m_clrMuted : m_clrYellow, m_fontSize);
   }
   
   //+------------------------------------------------------------------+
   //| Render session and news status                                    |
   //+------------------------------------------------------------------+
   void RenderSessionStatus(const SEngineState &state)
   {
      // Session
      string sessionName = "UNKNOWN";
      color sessionColor = m_clrMuted;
      
      switch(state.CurrentSession)
      {
         case SESSION_LONDON:
            sessionName = "LONDON [ACTIVE]";
            sessionColor = m_clrGreen;
            break;
         case SESSION_NEWYORK:
            sessionName = "NEW YORK [ACTIVE]";
            sessionColor = m_clrGreen;
            break;
         case SESSION_OVERLAP:
            sessionName = "LDN/NY OVERLAP [ACTIVE]";
            sessionColor = m_clrGreen;
            break;
         case SESSION_ASIAN:
            sessionName = "ASIAN [ACTIVE]";
            sessionColor = m_clrYellow;
            break;
         case SESSION_NONE:
            sessionName = "OFF-HOURS [BLOCKED]";
            sessionColor = m_clrRed;
            break;
      }
      DrawText("session", "  Session:     " + sessionName, sessionColor, m_fontSize);
      
      // News shield status
      color newsColor = state.IsNewsWindow ? m_clrRed : m_clrGreen;
      string newsStr = state.IsNewsWindow ? "BLOCKING" : "CLEAR";
      DrawText("news", "  News Shield: " + newsStr, newsColor, m_fontSize);
      
      // Friday close
      color fridayColor = state.IsFridayClose ? m_clrRed : m_clrMuted;
      string fridayStr = state.IsFridayClose ? "ACTIVE" : "OFF";
      DrawText("friday", "  Friday Lock: " + fridayStr, fridayColor, m_fontSize);
   }
   
   //+------------------------------------------------------------------+
   //| Render last trade info                                            |
   //+------------------------------------------------------------------+
   void RenderLastTrade(const SEngineState &state)
   {
      // Get the most recent closed trade
      string lastTradeStr = "  Last:        No trades yet";
      color lastColor = m_clrMuted;
      
      datetime dayStart = TimeCurrent() - 7 * 86400; // Look back 7 days
      if(HistorySelect(dayStart, TimeCurrent()))
      {
         int totalDeals = HistoryDealsTotal();
         
         // Find the last exit deal
         for(int i = totalDeals - 1; i >= 0; i--)
         {
            ulong ticket = HistoryDealGetTicket(i);
            if(ticket == 0) continue;
            
            long dealEntry = HistoryDealGetInteger(ticket, DEAL_ENTRY);
            if(dealEntry != DEAL_ENTRY_OUT && dealEntry != DEAL_ENTRY_OUT_BY)
               continue;
            
            long dealMagic = HistoryDealGetInteger(ticket, DEAL_MAGIC);
            // Don't filter by magic here to show any relevant trade
            
            double profit = HistoryDealGetDouble(ticket, DEAL_PROFIT)
                          + HistoryDealGetDouble(ticket, DEAL_SWAP)
                          + HistoryDealGetDouble(ticket, DEAL_COMMISSION);
            
            long dealType = HistoryDealGetInteger(ticket, DEAL_TYPE);
            string direction = (dealType == DEAL_TYPE_BUY) ? "SELL" : "BUY"; // Exit is opposite
            
            double volume = HistoryDealGetDouble(ticket, DEAL_VOLUME);
            string symbol = HistoryDealGetString(ticket, DEAL_SYMBOL);
            
            string resultStr = (profit >= 0) ? "WIN" : "LOSS";
            lastColor = (profit >= 0) ? m_clrGreen : m_clrRed;
            
            lastTradeStr = StringFormat("  Last: %s %s  %+.2f  [%s]",
                           direction, symbol, profit, resultStr);
            break;
         }
      }
      
      DrawText("lasttrade", lastTradeStr, lastColor, m_fontSize);
   }
   
   //+------------------------------------------------------------------+
   //| Draw a separator line                                             |
   //+------------------------------------------------------------------+
   void RenderSeparator(void)
   {
      string name = StringFormat("%ssep_%d", DASH_PREFIX, m_currentLine);
      DrawTextRaw(name, "  " + DASH_SEPARATOR, m_clrSeparator, m_fontSize - 2);
   }
   
   //+------------------------------------------------------------------+
   //| Draw text at the current line position                            |
   //| Parameters:                                                       |
   //|   id    - unique identifier for this text element                 |
   //|   text  - text content to display                                 |
   //|   clr   - text color                                              |
   //|   size  - font size                                               |
   //+------------------------------------------------------------------+
   void DrawText(string id, string text, color clr, int size)
   {
      string name = DASH_PREFIX + id;
      DrawTextRaw(name, text, clr, size);
   }
   
   //+------------------------------------------------------------------+
   //| Low-level text drawing using OBJ_LABEL                            |
   //+------------------------------------------------------------------+
   void DrawTextRaw(string name, string text, color clr, int size)
   {
      int yPos = m_startY + m_currentLine * DASH_LINE_HEIGHT;
      
      ENUM_BASE_CORNER baseCorner;
      switch(m_corner)
      {
         case CORNER_TOP_LEFT:     baseCorner = CORNER_LEFT_UPPER; break;
         case CORNER_TOP_RIGHT:    baseCorner = CORNER_RIGHT_UPPER; break;
         case CORNER_BOTTOM_LEFT:  baseCorner = CORNER_LEFT_LOWER; break;
         case CORNER_BOTTOM_RIGHT: baseCorner = CORNER_RIGHT_LOWER; break;
         default:                  baseCorner = CORNER_RIGHT_UPPER; break;
      }
      
      if(ObjectFind(m_chartID, name) < 0)
      {
         ObjectCreate(m_chartID, name, OBJ_LABEL, 0, 0, 0);
         ObjectSetInteger(m_chartID, name, OBJPROP_CORNER, baseCorner);
         ObjectSetInteger(m_chartID, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(m_chartID, name, OBJPROP_HIDDEN, true);
         ObjectSetInteger(m_chartID, name, OBJPROP_BACK, false);
         m_objectCount++;
      }
      
      ObjectSetString(m_chartID, name, OBJPROP_TEXT, text);
      ObjectSetString(m_chartID, name, OBJPROP_FONT, m_fontName);
      ObjectSetInteger(m_chartID, name, OBJPROP_FONTSIZE, size);
      ObjectSetInteger(m_chartID, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(m_chartID, name, OBJPROP_XDISTANCE, m_startX);
      ObjectSetInteger(m_chartID, name, OBJPROP_YDISTANCE, yPos);
      
      // Set anchor based on corner
      ENUM_ANCHOR_POINT anchor;
      switch(m_corner)
      {
         case CORNER_TOP_LEFT:     anchor = ANCHOR_LEFT_UPPER; break;
         case CORNER_TOP_RIGHT:    anchor = ANCHOR_RIGHT_UPPER; break;
         case CORNER_BOTTOM_LEFT:  anchor = ANCHOR_LEFT_LOWER; break;
         case CORNER_BOTTOM_RIGHT: anchor = ANCHOR_RIGHT_LOWER; break;
         default:                  anchor = ANCHOR_RIGHT_UPPER; break;
      }
      ObjectSetInteger(m_chartID, name, OBJPROP_ANCHOR, anchor);
      
      m_currentLine++;
   }
   
   //+------------------------------------------------------------------+
   //| Format number with comma separators (e.g., 10,000)                |
   //+------------------------------------------------------------------+
   string FormatNumber(double value)
   {
      string result = "";
      long intPart = (long)MathFloor(MathAbs(value));
      
      if(intPart == 0) return "0";
      
      string digits = IntegerToString(intPart);
      int len = StringLen(digits);
      
      for(int i = 0; i < len; i++)
      {
         if(i > 0 && (len - i) % 3 == 0)
            result += ",";
         result += StringSubstr(digits, i, 1);
      }
      
      if(value < 0) result = "-" + result;
      
      return result;
   }
};

#endif // DASHBOARD_MQH
