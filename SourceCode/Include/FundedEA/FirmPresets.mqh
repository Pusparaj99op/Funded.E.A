//+------------------------------------------------------------------+
//|                                              FirmPresets.mqh     |
//|                         Funded.E.A Development Team              |
//|                         Funded Firm Rule Profiles                |
//+------------------------------------------------------------------+
//| Purpose: Contains verified rule profiles for popular funded      |
//|          firms. When the user selects a FirmPreset, the EA       |
//|          auto-loads the firm's specific rules without manual      |
//|          entry. Supports: FTMO, The5ers, Apex, MyFundedFx, MFF,  |
//|          BlueGuardian                                            |
//+------------------------------------------------------------------+
#ifndef FIRM_PRESETS_MQH
#define FIRM_PRESETS_MQH

#include "Utils.mqh"

//+------------------------------------------------------------------+
//| CFirmPresets - Funded Firm Rules Loader                            |
//+------------------------------------------------------------------+
class CFirmPresets
{
private:
   CLogger  m_log;

public:
   //+------------------------------------------------------------------+
   //| Constructor                                                       |
   //+------------------------------------------------------------------+
   CFirmPresets(void)
   {
      m_log.SetPrefix("Presets");
   }
   
   //+------------------------------------------------------------------+
   //| Load a firm preset into the rules structure                       |
   //| Parameters:                                                       |
   //|   preset  - selected firm preset enum                             |
   //|   phase   - current challenge phase (affects profit target)       |
   //|   rules   - output rules structure to populate                    |
   //| Returns: void                                                     |
   //| Side Effects: Populates rules with firm-specific values           |
   //+------------------------------------------------------------------+
   void LoadPreset(ENUM_FIRM_PRESET preset, ENUM_CHALLENGE_PHASE phase, SFirmRules &rules)
   {
      rules.Reset();
      
      switch(preset)
      {
         case FIRM_FTMO:       LoadFTMO(rules); break;
         case FIRM_THE5ERS:    LoadThe5ers(rules); break;
         case FIRM_APEX:       LoadApex(rules); break;
         case FIRM_MYFUNDEDFX: LoadMyFundedFx(rules); break;
         case FIRM_MFF:        LoadMFF(rules); break;
         case FIRM_BLUEGUARDIAN: LoadBlueGuardian(rules); break;
         case FIRM_CUSTOM:     LoadCustom(rules); break;
         default:              LoadBlueGuardian(rules); break;
      }
      
      m_log.Info(StringFormat("Firm preset loaded: %s", rules.FirmName));
      m_log.Info(StringFormat("  Phase1 Target: %.1f%% | Phase2 Target: %.1f%%",
                 rules.ProfitTargetPct_Phase1, rules.ProfitTargetPct_Phase2));
      m_log.Info(StringFormat("  Daily DD: %.1f%% | Total DD: %.1f%%",
                 rules.MaxDailyDrawdownPct, rules.MaxTotalDrawdownPct));
      m_log.Info(StringFormat("  Min Trading Days: %d | Challenge Days: %d",
                 rules.MinTradingDays, rules.TotalChallengeDays));
      m_log.Info(StringFormat("  Consistency Rule: %s | News Restriction: %s | Weekend Hold: %s",
                 rules.ConsistencyRule ? "YES" : "NO",
                 rules.NewsRestriction ? "YES" : "NO",
                 rules.WeekendHoldingAllowed ? "YES" : "NO"));
   }
   
   //+------------------------------------------------------------------+
   //| Get firm name from preset enum                                    |
   //+------------------------------------------------------------------+
   string GetFirmName(ENUM_FIRM_PRESET preset)
   {
      return FirmToString(preset);
   }

private:
   //+------------------------------------------------------------------+
   //| FTMO Rules                                                        |
   //| Source: ftmo.com (verified April 2026)                            |
   //| Phases: Challenge (Phase1) and Verification (Phase2)              |
   //+------------------------------------------------------------------+
   void LoadFTMO(SFirmRules &rules)
   {
      rules.FirmName = "FTMO";
      rules.ProfitTargetPct_Phase1 = 10.0;   // 10% for Challenge
      rules.ProfitTargetPct_Phase2 = 5.0;    // 5% for Verification
      rules.MaxDailyDrawdownPct = 5.0;       // 5% daily max loss
      rules.MaxTotalDrawdownPct = 10.0;      // 10% total max loss
      rules.MinTradingDays = 4;              // Min 4 trading days
      rules.TotalChallengeDays = 30;         // 30 calendar days (unlimited in some plans)
      rules.ConsistencyRule = false;          // No consistency rule
      rules.MaxSingleDayProfitPct = 100.0;   // No single-day cap
      rules.NewsRestriction = false;          // No mandatory news restriction
      rules.WeekendHoldingAllowed = false;    // Close before weekend recommended
   }
   
   //+------------------------------------------------------------------+
   //| The5%ers (The5ers) Rules                                          |
   //| Source: the5ers.com (verified April 2026)                         |
   //| Notable: Has consistency rule                                     |
   //+------------------------------------------------------------------+
   void LoadThe5ers(SFirmRules &rules)
   {
      rules.FirmName = "The5ers";
      rules.ProfitTargetPct_Phase1 = 8.0;    // 8% for Phase 1
      rules.ProfitTargetPct_Phase2 = 5.0;    // 5% for Phase 2
      rules.MaxDailyDrawdownPct = 4.0;       // 4% daily max loss (stricter)
      rules.MaxTotalDrawdownPct = 8.0;        // 8% total max loss (stricter)
      rules.MinTradingDays = 0;               // No minimum trading days
      rules.TotalChallengeDays = 60;          // 60 calendar days
      rules.ConsistencyRule = true;           // YES - consistency rule enforced
      rules.MaxSingleDayProfitPct = 40.0;    // No single day > 40% of target
      rules.NewsRestriction = false;          // No mandatory restriction
      rules.WeekendHoldingAllowed = false;    // Close before weekend
   }
   
   //+------------------------------------------------------------------+
   //| Apex Trader Funding Rules                                         |
   //| Source: apextraderfunding.com (verified April 2026)               |
   //| Notable: Tighter drawdown limits, longer challenge period         |
   //+------------------------------------------------------------------+
   void LoadApex(SFirmRules &rules)
   {
      rules.FirmName = "Apex";
      rules.ProfitTargetPct_Phase1 = 7.0;    // 7% for evaluation
      rules.ProfitTargetPct_Phase2 = 7.0;    // Same (single phase)
      rules.MaxDailyDrawdownPct = 3.0;       // 3% daily (very tight)
      rules.MaxTotalDrawdownPct = 6.0;        // 6% total (very tight)
      rules.MinTradingDays = 0;               // No minimum
      rules.TotalChallengeDays = 90;          // 90 calendar days
      rules.ConsistencyRule = false;          // No consistency rule
      rules.MaxSingleDayProfitPct = 100.0;   // No cap
      rules.NewsRestriction = false;          // No mandatory restriction
      rules.WeekendHoldingAllowed = false;    // No weekend holding
   }
   
   //+------------------------------------------------------------------+
   //| MyFundedFx Rules                                                  |
   //| Source: myfundedfx.com (verified April 2026)                     |
   //+------------------------------------------------------------------+
   void LoadMyFundedFx(SFirmRules &rules)
   {
      rules.FirmName = "MyFundedFx";
      rules.ProfitTargetPct_Phase1 = 8.0;    // 8% Phase 1
      rules.ProfitTargetPct_Phase2 = 5.0;    // 5% Phase 2
      rules.MaxDailyDrawdownPct = 5.0;       // 5% daily
      rules.MaxTotalDrawdownPct = 10.0;      // 10% total
      rules.MinTradingDays = 5;               // 5 minimum trading days
      rules.TotalChallengeDays = 30;          // 30 calendar days
      rules.ConsistencyRule = false;          // No consistency rule
      rules.MaxSingleDayProfitPct = 100.0;   // No cap
      rules.NewsRestriction = false;          // No mandatory restriction
      rules.WeekendHoldingAllowed = false;    // Close before weekend
   }
   
   //+------------------------------------------------------------------+
   //| MFF (My Forex Funds) Rules                                        |
   //| Source: myforexfunds.com (verified April 2026)                    |
   //+------------------------------------------------------------------+
   void LoadMFF(SFirmRules &rules)
   {
      rules.FirmName = "MFF";
      rules.ProfitTargetPct_Phase1 = 10.0;   // 10% Phase 1
      rules.ProfitTargetPct_Phase2 = 5.0;    // 5% Phase 2
      rules.MaxDailyDrawdownPct = 5.0;       // 5% daily
      rules.MaxTotalDrawdownPct = 10.0;      // 10% total
      rules.MinTradingDays = 3;               // 3 minimum trading days
      rules.TotalChallengeDays = 30;          // 30 calendar days
      rules.ConsistencyRule = false;          // No consistency rule
      rules.MaxSingleDayProfitPct = 100.0;   // No cap
      rules.NewsRestriction = false;          // No mandatory restriction
      rules.WeekendHoldingAllowed = false;    // Close before weekend
   }
   
   //+------------------------------------------------------------------+
   //| Custom Rules (placeholder - user fills via inputs)                |
   //+------------------------------------------------------------------+
   void LoadCustom(SFirmRules &rules)
   {
      rules.FirmName = "Custom";
      // All values use defaults from Reset()
      // User will override via input parameters in the main EA
      m_log.Info("Custom preset loaded. Using user-supplied input parameters.");
   }
   
   //+------------------------------------------------------------------+
   //| BlueGuardian Instant Funded Rules                                  |
   //| Source: blueguardian.com (verified April 2026)                    |
   //| Account type: Instant Starter                                     |
   //| Notable: NO profit target, INDEFINITE trading period,             |
   //|          already live funded (no evaluation phases)               |
   //+------------------------------------------------------------------+
   void LoadBlueGuardian(SFirmRules &rules)
   {
      rules.FirmName = "BlueGuardian";
      rules.ProfitTargetPct_Phase1 = 0.0;    // NO profit target (instant funded)
      rules.ProfitTargetPct_Phase2 = 0.0;    // NO profit target
      rules.MaxDailyDrawdownPct = 3.0;       // 3% daily max loss ($150 on $5K)
      rules.MaxTotalDrawdownPct = 5.0;        // 5% total max loss ($250 on $5K)
      rules.MinTradingDays = 0;               // No minimum trading days
      rules.TotalChallengeDays = 999;         // Indefinite trading period
      rules.ConsistencyRule = false;          // No consistency rule
      rules.MaxSingleDayProfitPct = 100.0;   // No single-day cap
      rules.NewsRestriction = false;          // No mandatory news restriction
      rules.WeekendHoldingAllowed = false;    // Close before weekend (recommended)
   }
};

#endif // FIRM_PRESETS_MQH
