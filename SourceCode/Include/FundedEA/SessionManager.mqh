//+------------------------------------------------------------------+
//|                                            SessionManager.mqh    |
//|                         Funded.E.A Development Team              |
//|                         Session Filtering & News Shield          |
//+------------------------------------------------------------------+
//| Purpose: Manages all time-based trading filters:                 |
//|   - Session filtering (London, New York, Asian)                  |
//|   - Friday close enforcement                                    |
//|   - Wednesday triple swap avoidance                              |
//|   - News event shield (high-impact event blocking)               |
//|   - Monday open blocking (first 5 minutes)                      |
//|   - Session-end position management                              |
//+------------------------------------------------------------------+
#ifndef SESSION_MANAGER_MQH
#define SESSION_MANAGER_MQH

#include "Utils.mqh"
#include "OrderManager.mqh"

//+------------------------------------------------------------------+
//| High-impact news event structure                                  |
//+------------------------------------------------------------------+
struct SNewsEvent
{
   string   EventName;       // Event name (e.g., "FOMC", "NFP")
   datetime EventTime;       // Scheduled event time (server time)
   int      ImpactLevel;     // 1=Low, 2=Medium, 3=High
   string   Currency;        // Affected currency ("USD", "XAU")
};

//+------------------------------------------------------------------+
//| CSessionManager - Session & News Filtering                        |
//+------------------------------------------------------------------+
class CSessionManager
{
private:
   //--- Configuration
   bool              m_tradeLondon;           // Allow London session trading
   bool              m_tradeNewYork;          // Allow New York session trading
   bool              m_tradeAsian;            // Allow Asian session trading
   bool              m_avoidNews;             // Block entries near news
   int               m_newsBufferMinutes;     // Minutes before/after news to block
   bool              m_closeOnFriday;         // Force close positions on Friday
   int               m_fridayCloseHourGMT;    // Hour (GMT) to close on Friday
   int               m_serverOffset;          // Server timezone offset from UTC
   
   //--- News calendar (manually populated for high-impact events)
   SNewsEvent        m_upcomingNews[];         // Upcoming high-impact events
   int               m_maxNewsEvents;          // Max events to track
   datetime          m_lastNewsUpdate;         // Last time news list was updated
   
   //--- State tracking
   bool              m_fridayCloseExecuted;   // Friday close already executed this week
   bool              m_wednesdayCloseExecuted;// Wednesday close already executed
   datetime          m_lastFridayCloseDate;   // Date of last Friday close
   
   //--- Time utilities
   CTimeUtils        m_time;
   
   //--- Logger
   CLogger           m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CSessionManager(void)
   {
      m_log.SetPrefix("Session");
      m_tradeLondon = true;
      m_tradeNewYork = true;
      m_tradeAsian = false;
      m_avoidNews = true;
      m_newsBufferMinutes = 30;
      m_closeOnFriday = true;
      m_fridayCloseHourGMT = 20;
      m_serverOffset = 2;
      m_maxNewsEvents = 20;
      m_fridayCloseExecuted = false;
      m_wednesdayCloseExecuted = false;
      m_lastFridayCloseDate = 0;
      m_lastNewsUpdate = 0;
      
      ArrayResize(m_upcomingNews, 0);
   }
   
   //+------------------------------------------------------------------+
   //| Initialize session manager                                        |
   //| Parameters:                                                       |
   //|   tradeLondon       - allow London session                        |
   //|   tradeNY           - allow New York session                      |
   //|   tradeAsian        - allow Asian session                         |
   //|   avoidNews         - block near news events                      |
   //|   newsBuffer        - minutes buffer around news                  |
   //|   closeOnFriday     - force close on Friday                       |
   //|   fridayHourGMT     - Friday close hour in GMT                    |
   //|   serverOffset      - server UTC offset                           |
   //| Returns: void                                                     |
   //+------------------------------------------------------------------+
   void Initialize(bool tradeLondon, bool tradeNY, bool tradeAsian,
                   bool avoidNews, int newsBuffer,
                   bool closeOnFriday, int fridayHourGMT,
                   int serverOffset)
   {
      m_tradeLondon = tradeLondon;
      m_tradeNewYork = tradeNY;
      m_tradeAsian = tradeAsian;
      m_avoidNews = avoidNews;
      m_newsBufferMinutes = newsBuffer;
      m_closeOnFriday = closeOnFriday;
      m_fridayCloseHourGMT = fridayHourGMT;
      m_serverOffset = serverOffset;
      
      m_time.SetServerOffset(serverOffset);
      
      // Build initial news calendar
      BuildNewsCalendar();
      
      m_log.Info(StringFormat("SessionManager initialized: London=%s NY=%s Asian=%s | News=%s (%dmin buffer)",
                 tradeLondon ? "ON" : "OFF", tradeNY ? "ON" : "OFF", tradeAsian ? "ON" : "OFF",
                 avoidNews ? "ON" : "OFF", newsBuffer));
      m_log.Info(StringFormat("  FridayClose=%s at %d:00 GMT | ServerOffset=UTC+%d",
                 closeOnFriday ? "ON" : "OFF", fridayHourGMT, serverOffset));
   }
   
   //+------------------------------------------------------------------+
   //| Check if the current session allows trading                       |
   //| Parameters:                                                       |
   //|   session - current session state (from CTimeUtils)               |
   //| Returns: true if trading is allowed in current session            |
   //+------------------------------------------------------------------+
   bool IsSessionAllowed(ENUM_SESSION_STATE session)
   {
      switch(session)
      {
         case SESSION_LONDON:
            return m_tradeLondon;
         case SESSION_NEWYORK:
            return m_tradeNewYork;
         case SESSION_OVERLAP:
            return (m_tradeLondon || m_tradeNewYork); // Either session enabled
         case SESSION_ASIAN:
            return m_tradeAsian;
         case SESSION_NONE:
            return false; // Outside all sessions
         default:
            return false;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check if currently in a news window (blocking period)             |
   //| Returns: true if within NewsBufferMinutes of a high-impact event  |
   //+------------------------------------------------------------------+
   bool IsInNewsWindow(void)
   {
      if(!m_avoidNews) return false;
      
      datetime now = TimeCurrent();
      
      // Check against known upcoming events
      for(int i = 0; i < ArraySize(m_upcomingNews); i++)
      {
         if(m_upcomingNews[i].ImpactLevel < 3) continue; // Only block for high-impact
         
         datetime eventTime = m_upcomingNews[i].EventTime;
         datetime blockStart = eventTime - m_newsBufferMinutes * 60;
         datetime blockEnd = eventTime + m_newsBufferMinutes * 60;
         
         if(now >= blockStart && now <= blockEnd)
         {
            m_log.Debug(StringFormat("NEWS WINDOW ACTIVE: %s at %s (block %d min before/after)",
                        m_upcomingNews[i].EventName,
                        TimeToString(eventTime, TIME_DATE | TIME_MINUTES),
                        m_newsBufferMinutes));
            return true;
         }
      }
      
      // Fallback: Check known recurring high-impact time slots
      // These occur on known days/times regardless of calendar
      return IsRecurringNewsWindow();
   }
   
   //+------------------------------------------------------------------+
   //| Check if approaching Friday close time                            |
   //| Returns: true if within 1 hour of Friday close hour               |
   //+------------------------------------------------------------------+
   bool IsFridayCloseProximity(void)
   {
      if(!m_closeOnFriday) return false;
      if(!m_time.IsFriday()) return false;
      
      int gmtHour = m_time.GetGMTHour();
      
      // Block new entries 1 hour before Friday close
      return (gmtHour >= m_fridayCloseHourGMT - 1);
   }
   
   //+------------------------------------------------------------------+
   //| Timer-based session management (called every 60 seconds)          |
   //| Handles: Friday close, Wednesday swap avoidance                  |
   //| Parameters:                                                       |
   //|   state        - engine state reference                           |
   //|   orderMgr     - order manager for position operations            |
   //|   magicNumber  - EA magic number                                  |
   //|   symbol       - trading symbol                                   |
   //+------------------------------------------------------------------+
   void OnTimer(SEngineState &state, COrderManager &orderMgr, int magicNumber, string symbol)
   {
      //=== Friday Close Enforcement ===
      if(m_closeOnFriday && m_time.IsFriday())
      {
         if(m_time.IsFridayCloseTime(m_fridayCloseHourGMT))
         {
            // Check if we already closed today
            MqlDateTime dtNow;
            TimeToStruct(TimeCurrent(), dtNow);
            MqlDateTime dtLastClose;
            TimeToStruct(m_lastFridayCloseDate, dtLastClose);
            
            bool alreadyClosedToday = (dtNow.year == dtLastClose.year && 
                                        dtNow.mon == dtLastClose.mon && 
                                        dtNow.day == dtLastClose.day);
            
            if(!alreadyClosedToday)
            {
               m_log.Info(StringFormat("FRIDAY CLOSE: Closing all positions at %d:00 GMT", m_fridayCloseHourGMT));
               orderMgr.CloseAllPositions(magicNumber, symbol);
               m_lastFridayCloseDate = TimeCurrent();
               state.TradingLockedToday = true;
               state.IsFridayClose = true;
            }
         }
      }
      
      //=== Wednesday Triple Swap Avoidance ===
      if(m_time.IsWednesday())
      {
         // Close positions before 22:30 server time to avoid triple swap
         if(m_time.IsNearWednesdaySwap(30))
         {
            MqlDateTime dtNow;
            TimeToStruct(TimeCurrent(), dtNow);
            MqlDateTime dtLastWed;
            TimeToStruct(m_wednesdayCloseExecuted ? TimeCurrent() : 0, dtLastWed);
            
            // Only execute once per Wednesday
            if(!m_wednesdayCloseExecuted)
            {
               int openCount = CountOpenPositions(magicNumber, symbol);
               if(openCount > 0)
               {
                  m_log.Info("WEDNESDAY SWAP AVOIDANCE: Closing positions to avoid triple swap.");
                  orderMgr.CloseAllPositions(magicNumber, symbol);
                  m_wednesdayCloseExecuted = true;
               }
            }
         }
         else
         {
            // Reset the flag for next Wednesday
            m_wednesdayCloseExecuted = false;
         }
      }
      else
      {
         m_wednesdayCloseExecuted = false;
      }
      
      //=== Update news calendar periodically ===
      datetime now = TimeCurrent();
      if(now - m_lastNewsUpdate > 3600) // Update every hour
      {
         BuildNewsCalendar();
         m_lastNewsUpdate = now;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Get current session name for dashboard display                    |
   //+------------------------------------------------------------------+
   string GetSessionDisplayName(void)
   {
      ENUM_SESSION_STATE session = m_time.GetCurrentSession();
      string name = m_time.GetSessionName(session);
      
      bool isActive = IsSessionAllowed(session);
      return name + (isActive ? " [ACTIVE]" : " [BLOCKED]");
   }
   
   //+------------------------------------------------------------------+
   //| Get news shield status for dashboard                              |
   //+------------------------------------------------------------------+
   string GetNewsStatus(void)
   {
      if(!m_avoidNews) return "DISABLED";
      if(IsInNewsWindow()) return "BLOCKING";
      
      // Check how close the next news event is
      datetime now = TimeCurrent();
      datetime nearestEvent = 0;
      string nearestName = "";
      
      for(int i = 0; i < ArraySize(m_upcomingNews); i++)
      {
         if(m_upcomingNews[i].ImpactLevel < 3) continue;
         if(m_upcomingNews[i].EventTime <= now) continue;
         
         if(nearestEvent == 0 || m_upcomingNews[i].EventTime < nearestEvent)
         {
            nearestEvent = m_upcomingNews[i].EventTime;
            nearestName = m_upcomingNews[i].EventName;
         }
      }
      
      if(nearestEvent > 0)
      {
         int minutesUntil = (int)((nearestEvent - now) / 60);
         if(minutesUntil <= 60)
            return StringFormat("CAUTION (%s in %dm)", nearestName, minutesUntil);
      }
      
      return "CLEAR";
   }
   
   //+------------------------------------------------------------------+
   //| Get Friday close status for dashboard                             |
   //+------------------------------------------------------------------+
   string GetFridayStatus(void)
   {
      if(!m_closeOnFriday) return "DISABLED";
      if(!m_time.IsFriday()) return "OFF";
      
      int gmtHour = m_time.GetGMTHour();
      int hoursUntilClose = m_fridayCloseHourGMT - gmtHour;
      
      if(hoursUntilClose <= 0) return "CLOSED";
      if(hoursUntilClose <= 1) return StringFormat("CLOSING SOON (%dh)", hoursUntilClose);
      
      return StringFormat("%dh until close", hoursUntilClose);
   }
   
   //+------------------------------------------------------------------+
   //| Check if it's currently Monday open block period                  |
   //+------------------------------------------------------------------+
   bool IsMondayOpenBlock(void)
   {
      return m_time.IsMondayOpenBlock();
   }

private:
   //+------------------------------------------------------------------+
   //| Build the news calendar with known high-impact events             |
   //| Purpose: Populate upcoming events for the current week            |
   //| Since MQL5 doesn't have a native news feed, we use               |
   //| time-based heuristics for known recurring events                 |
   //+------------------------------------------------------------------+
   void BuildNewsCalendar(void)
   {
      ArrayResize(m_upcomingNews, 0);
      
      // Try to use MQL5 Economic Calendar (available in MT5 build 2085+)
      if(!BuildFromMQL5Calendar())
      {
         // Fallback: Use known recurring high-impact event schedule
         BuildRecurringSchedule();
      }
      
      m_log.Debug(StringFormat("News calendar built: %d events tracked", ArraySize(m_upcomingNews)));
   }
   
   //+------------------------------------------------------------------+
   //| Attempt to read from MQL5 native Economic Calendar                |
   //+------------------------------------------------------------------+
   bool BuildFromMQL5Calendar(void)
   {
      // MQL5 CalendarValueHistory is available in newer builds
      // We look for USD high-impact events in the next 7 days
      
      MqlCalendarValue values[];
      datetime from = TimeCurrent();
      datetime to = from + 7 * 86400;  // Next 7 days
      
      // CalendarValueHistory requires country code
      // "US" for USD events, and we also care about global Gold events
      int count = CalendarValueHistory(values, from, to, "US");
      
      if(count <= 0) return false;
      
      for(int i = 0; i < count && i < 50; i++)
      {
         // Get event details
         MqlCalendarEvent event;
         if(!CalendarEventById(values[i].event_id, event))
            continue;
         
         // Only track high-impact events
         if(event.importance != CALENDAR_IMPORTANCE_HIGH)
            continue;
         
         // Add to our list
         SNewsEvent newsEvent;
         newsEvent.EventName = event.name;
         newsEvent.EventTime = values[i].time;
         newsEvent.ImpactLevel = 3; // High
         newsEvent.Currency = "USD";
         
         int size = ArraySize(m_upcomingNews);
         if(size < m_maxNewsEvents)
         {
            ArrayResize(m_upcomingNews, size + 1);
            m_upcomingNews[size] = newsEvent;
         }
      }
      
      return (ArraySize(m_upcomingNews) > 0);
   }
   
   //+------------------------------------------------------------------+
   //| Build recurring schedule for known high-impact events             |
   //| Fallback when MQL5 Calendar is unavailable                       |
   //+------------------------------------------------------------------+
   void BuildRecurringSchedule(void)
   {
      datetime now = TimeCurrent();
      MqlDateTime dtNow;
      TimeToStruct(now, dtNow);
      
      // Find the current week's dates
      // We'll populate known recurring events for this week
      
      // NFP - First Friday of month, 8:30 AM ET (13:30 UTC, 15:30 UTC+2)
      // FOMC - Typically 8 times/year, Wednesday 2:00 PM ET (19:00 UTC)
      // CPI - Monthly, typically 2nd week, 8:30 AM ET
      // PPI - Monthly, typically mid-month, 8:30 AM ET
      
      int currentDow = dtNow.day_of_week;
      
      // For each day this week, check known patterns
      for(int dayOffset = 0; dayOffset < 5; dayOffset++)
      {
         datetime targetDate = now + dayOffset * 86400;
         MqlDateTime dtTarget;
         TimeToStruct(targetDate, dtTarget);
         
         // Skip weekends
         if(dtTarget.day_of_week == 0 || dtTarget.day_of_week == 6) continue;
         
         // NFP: First Friday of month
         if(dtTarget.day_of_week == 5 && dtTarget.day <= 7)
         {
            AddRecurringEvent("NFP (Non-Farm Payrolls)", targetDate, 13, 30, 3);
         }
         
         // Weekly: Jobless Claims - Every Thursday 8:30 AM ET
         if(dtTarget.day_of_week == 4)
         {
            AddRecurringEvent("Jobless Claims", targetDate, 13, 30, 2);
         }
         
         // CPI: Usually around 10th-14th of month, Tuesday or Wednesday
         if(dtTarget.day >= 10 && dtTarget.day <= 14 && 
            (dtTarget.day_of_week == 2 || dtTarget.day_of_week == 3))
         {
            AddRecurringEvent("CPI (Consumer Price Index)", targetDate, 13, 30, 3);
         }
         
         // PPI: Usually around 11th-15th, Tuesday or Wednesday
         if(dtTarget.day >= 11 && dtTarget.day <= 15 && 
            (dtTarget.day_of_week == 2 || dtTarget.day_of_week == 3))
         {
            AddRecurringEvent("PPI (Producer Price Index)", targetDate, 13, 30, 3);
         }
         
         // Retail Sales: Usually mid-month
         if(dtTarget.day >= 13 && dtTarget.day <= 17 && dtTarget.day_of_week == 2)
         {
            AddRecurringEvent("Retail Sales", targetDate, 13, 30, 3);
         }
      }
   }
   
   //+------------------------------------------------------------------+
   //| Add a recurring event to the calendar                             |
   //+------------------------------------------------------------------+
   void AddRecurringEvent(string name, datetime date, int utcHour, int utcMinute, int impact)
   {
      MqlDateTime dt;
      TimeToStruct(date, dt);
      dt.hour = utcHour + m_serverOffset; // Convert UTC to server time
      dt.min = utcMinute;
      dt.sec = 0;
      
      SNewsEvent evt;
      evt.EventName = name;
      evt.EventTime = StructToTime(dt);
      evt.ImpactLevel = impact;
      evt.Currency = "USD";
      
      int size = ArraySize(m_upcomingNews);
      if(size < m_maxNewsEvents)
      {
         ArrayResize(m_upcomingNews, size + 1);
         m_upcomingNews[size] = evt;
      }
   }
   
   //+------------------------------------------------------------------+
   //| Check if currently in a known recurring news window               |
   //| Used as fallback when calendar data is unavailable               |
   //+------------------------------------------------------------------+
   bool IsRecurringNewsWindow(void)
   {
      MqlDateTime dt;
      TimeToStruct(TimeCurrent(), dt);
      
      int gmtHour = m_time.GetGMTHour();
      MqlDateTime dtGMT;
      datetime gmtTime = m_time.GetGMTTime();
      TimeToStruct(gmtTime, dtGMT);
      int gmtMin = dtGMT.min;
      
      // NFP: First Friday of month around 13:30 UTC
      if(dt.day_of_week == 5 && dt.day <= 7)
      {
         int minutesFrom1330 = MathAbs((gmtHour * 60 + gmtMin) - (13 * 60 + 30));
         if(minutesFrom1330 <= m_newsBufferMinutes)
            return true;
      }
      
      // FOMC: Check 8 scheduled meetings per year
      // These are hard to predict without a calendar, so we broadly block
      // Wednesday around 19:00 UTC for FOMC months (Jan, Mar, May, Jun, Jul, Sep, Nov, Dec)
      if(dt.day_of_week == 3)
      {
         int fomcMonths[] = {1, 3, 5, 6, 7, 9, 11, 12};
         bool isFomcMonth = false;
         for(int i = 0; i < 8; i++)
         {
            if(dt.mon == fomcMonths[i]) { isFomcMonth = true; break; }
         }
         
         // FOMC usually mid-month on Wednesday
         if(isFomcMonth && dt.day >= 14 && dt.day <= 22)
         {
            int minutesFrom1900 = MathAbs((gmtHour * 60 + gmtMin) - (19 * 60));
            if(minutesFrom1900 <= m_newsBufferMinutes)
               return true;
         }
      }
      
      return false;
   }
};

#endif // SESSION_MANAGER_MQH
