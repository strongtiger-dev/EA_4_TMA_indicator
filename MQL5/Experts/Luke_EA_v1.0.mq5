//+------------------------------------------------------------------+
//|                                                  Custom EA.mq5 |
//|                        Strategy with DEMA, TEMA, FRAMA, BB     |
//+------------------------------------------------------------------+

#property copyright "Steven"
#property version   "1.00"
#property strict

#include <Trade/Trade.mqh>
CTrade g_trade;

#define Buy_Available  0
#define Sell_Available 1
#define None           2

#define Buy_Color clrLightBlue
#define Sell_Color clrLightGreen
#define SL_Color  clrWhite
#define Close_Color  clrLightYellow 

// Input parameters
input double    in_g_d_LotSize         = 0.1;
input int       in_g_n_StopLoss        = 250;
input int       in_g_n_TakeProfit      = 0; // 0 = off
//input ENUM_TIMEFRAMES in_g_n_TimeFrame = PERIOD_H1;

// Indicator settings
input int       in_g_n_FRAMA_Period    = 20;
input int       in_g_n_FRAMA_Shift     = 2;
input int       in_g_n_DEMA_Period     = 25;
input int       in_g_n_TEMA_Period     = 9;
input int       in_g_n_BB_Period       = 30;
input int       in_g_n_BB_Shift        = 2;
input double    in_g_d_BB_Deviation    = 1.05;

// Global variables
int             g_n_DEMA_Handle;
int             g_n_TEMA_Handle;
int             g_n_FRAMA_Handle;
int             g_n_BB_Handle;
int             g_n_current_trade_state = None;
int             g_n_magic;

double          g_d_Ask;
double          g_d_Bid;
double          g_arr_d_DEMA[];
double          g_arr_d_TEMA[];
double          g_arr_d_FRAMA[];
double          g_arr_d_BB_Upper[];
double          g_arr_d_BB_Lower[];
double          g_arr_d_BB_Middle[];

bool            g_b_TradeAllowed       = true;
bool            g_b_AvailableBuy       = false;
bool            g_b_AvailableSell      = false;
bool            g_b_is_frama_above_acrossed_BB_middle = false;
bool            g_b_is_frama_below_acrossed_BB_middle = false;
bool            g_b_last_sell_second_mode_closed = false;
bool            g_b_last_buy_second_mode_closed = false;
bool            g_b_was_DEMA_TEMA_below_FRAMA = false;
bool            g_b_was_DEMA_TEMA_above_FRAMA = false;


//+------------------------------------------------------------------+
int OnInit()
  {
   Print("[INIT] Initializing EA...");
   
   setMagicNumber();

   g_n_DEMA_Handle   = iDEMA(_Symbol, _Period, in_g_n_DEMA_Period, 0, PRICE_CLOSE);
   g_n_TEMA_Handle   = iTEMA(_Symbol, _Period, in_g_n_TEMA_Period, 0, PRICE_CLOSE);
   g_n_FRAMA_Handle  = iFrAMA(_Symbol, _Period, in_g_n_FRAMA_Period, in_g_n_FRAMA_Shift, PRICE_CLOSE);
   g_n_BB_Handle     = iBands(_Symbol, _Period, in_g_n_BB_Period, in_g_n_BB_Shift, in_g_d_BB_Deviation, PRICE_CLOSE);

   if(g_n_DEMA_Handle == INVALID_HANDLE || g_n_TEMA_Handle == INVALID_HANDLE || g_n_FRAMA_Handle == INVALID_HANDLE || g_n_BB_Handle == INVALID_HANDLE)
     {
         Print("[INIT] Failed to create indicator handles.");
         return(INIT_FAILED);
     }

   ArraySetAsSeries(g_arr_d_DEMA, true);
   ArraySetAsSeries(g_arr_d_TEMA, true);
   ArraySetAsSeries(g_arr_d_FRAMA, true);
   ArraySetAsSeries(g_arr_d_BB_Upper, true);
   ArraySetAsSeries(g_arr_d_BB_Lower, true);
   ArraySetAsSeries(g_arr_d_BB_Middle, true);
   
   g_n_current_trade_state = None;
   g_b_TradeAllowed       = true;
   g_b_AvailableBuy       = false;
   g_b_AvailableSell      = false;
   g_b_is_frama_above_acrossed_BB_middle = false;
   g_b_is_frama_below_acrossed_BB_middle = false;
   g_b_last_sell_second_mode_closed = false;
   g_b_last_buy_second_mode_closed = false;
   g_b_was_DEMA_TEMA_below_FRAMA = false;
   g_b_was_DEMA_TEMA_above_FRAMA = false;
   
   return(INIT_SUCCEEDED);
  }
  
void setMagicNumber()
{
   string s_symbol= _Symbol;
   ulong n_magicValue = 0;
   int cur;
   for ( int i = 0 ; i < s_symbol.Length() ; i++)
   {
      cur = s_symbol.GetChar(i) - 'A';
      n_magicValue += n_magicValue * 10 + cur;
   }
   g_trade.SetExpertMagicNumber(n_magicValue);
   g_n_magic = n_magicValue;
}

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   Print("[DEINIT] EA Deinitialized.");
  }

//+------------------------------------------------------------------+
void OnTick()
  {
   CopyBuffer(g_n_DEMA_Handle, 0, 0, 6, g_arr_d_DEMA);
   CopyBuffer(g_n_TEMA_Handle, 0, 0, 6, g_arr_d_TEMA);
   CopyBuffer(g_n_FRAMA_Handle, 0, 0, 6, g_arr_d_FRAMA);
   CopyBuffer(g_n_BB_Handle, 0, 0, 6, g_arr_d_BB_Middle);
   CopyBuffer(g_n_BB_Handle, 1, 0, 6, g_arr_d_BB_Upper);
   CopyBuffer(g_n_BB_Handle, 2, 0, 6, g_arr_d_BB_Lower);
   
   g_d_Ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
   g_d_Bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);   

   check_for_availability();
   check_for_open();
   check_for_close();
  }
  
//+------------------------------------------------------------------+
void OnTradeTransaction(const MqlTradeTransaction& trans,
                        const MqlTradeRequest& request,
                        const MqlTradeResult& result) {
    if ( trans.type == TRADE_TRANSACTION_DEAL_ADD ) {
        if ( HistoryDealSelect(trans.deal) ) {

            long n_reason = HistoryDealGetInteger(trans.deal, DEAL_REASON);
            long n_type = HistoryDealGetInteger(trans.deal, DEAL_TYPE);
            long n_magic = HistoryDealGetInteger(trans.deal, DEAL_MAGIC);

            if ( n_reason == DEAL_REASON_SL && n_magic == g_n_magic) {
               // Closed by Stop Loss
               double d_deal_profit = HistoryDealGetDouble(trans.deal, DEAL_PROFIT);
               double d_deal_close_price = HistoryDealGetDouble(trans.deal, DEAL_SL);
               DrawLabelAuto(" SL_Close",d_deal_close_price, TimeCurrent(), SL_Color);
            } 
        }
    }
}
  

//+------------------------------------------------------------------+
bool is_new_bar()
{
   static datetime g_dt_last_bar_time = 0; // store the last bar time

   datetime dt_current_bar_time = iTime(_Symbol, _Period, 0); // time of current bar

   if (dt_current_bar_time != g_dt_last_bar_time)
   {
      g_dt_last_bar_time = dt_current_bar_time; // update stored time
      return true; // it's a new bar
   }

   return false; // still within the same bar
}

void check_for_update()
{
   if ( is_DEMA_TEMA_Above_FRAMA() )
   {
      g_b_was_DEMA_TEMA_above_FRAMA = true;
      if ( g_b_was_DEMA_TEMA_below_FRAMA )
         g_b_was_DEMA_TEMA_below_FRAMA = false;
   }
   if ( is_DEMA_TEMA_Below_FRAMA() )
   {
      g_b_was_DEMA_TEMA_below_FRAMA = true;
      if ( g_b_was_DEMA_TEMA_above_FRAMA )
         g_b_was_DEMA_TEMA_above_FRAMA = false;
   }
}

//+------------------------------------------------------------------+
void check_for_open()
  {
     if(is_new_bar())
     {
         check_for_update();
         if( g_b_AvailableBuy )
            check_for_open_buy();
         if( g_b_AvailableSell )
            check_for_open_sell();
     }
  }
  
bool is_DEMA_TEMA_Below_FRAMA()
{
   if(g_arr_d_DEMA[2] < g_arr_d_FRAMA[2] && g_arr_d_TEMA[2] < g_arr_d_FRAMA[2] 
   && g_arr_d_DEMA[3] < g_arr_d_FRAMA[3] && g_arr_d_TEMA[3] < g_arr_d_FRAMA[3]
   && g_arr_d_DEMA[4] < g_arr_d_FRAMA[4] && g_arr_d_TEMA[4] < g_arr_d_FRAMA[4] 
   && g_arr_d_DEMA[5] < g_arr_d_FRAMA[5] && g_arr_d_TEMA[5] < g_arr_d_FRAMA[5]
    )
      return true;
   return false;
}

bool is_DEMA_TEMA_Above_FRAMA()
{
   if ( g_arr_d_DEMA[2] > g_arr_d_FRAMA[2] && g_arr_d_TEMA[2] > g_arr_d_FRAMA[2] 
   &&   g_arr_d_DEMA[3] > g_arr_d_FRAMA[3] && g_arr_d_TEMA[3] > g_arr_d_FRAMA[3]
   &&   g_arr_d_DEMA[4] > g_arr_d_FRAMA[4] && g_arr_d_TEMA[4] > g_arr_d_FRAMA[4] 
   &&   g_arr_d_DEMA[5] > g_arr_d_FRAMA[5] && g_arr_d_TEMA[5] > g_arr_d_FRAMA[5]
    )
      return true;
      
   return false;
}

//high to low
bool is_TEMA_Below_across_FRAMA()
{
   if(  g_arr_d_TEMA[1] < g_arr_d_FRAMA[1] ) //g_arr_d_TEMA[2] > g_arr_d_FRAMA[2] && //&& g_arr_d_TEMA[0] < g_arr_d_FRAMA[0] 
      return true;
   return false;
}

//low to high
bool is_TEMA_Above_across_FRAMA()
{
   if(  g_arr_d_TEMA[1] > g_arr_d_FRAMA[1] ) //g_arr_d_TEMA[2] < g_arr_d_FRAMA[2] && //&& g_arr_d_TEMA[0] > g_arr_d_FRAMA[0]
      return true;
      
   return false;
}

bool is_DEMA_Below_touch_FRAMA()
{
   if (g_arr_d_DEMA[2] > g_arr_d_FRAMA[2] &&  g_arr_d_DEMA[1] <= g_arr_d_FRAMA[1] ) //
      return true;
      
   return false;
}

bool is_DEMA_Above_touch_FRAMA()
{
   if (g_arr_d_DEMA[2] < g_arr_d_FRAMA[2] &&  g_arr_d_DEMA[1] >= g_arr_d_FRAMA[1] ) //
      return true;
      
   return false;
}

//+------------------------------------------------------------------+
void check_for_open_buy()
{
   if(PositionSelect(_Symbol)) return;
   
   if( g_b_was_DEMA_TEMA_below_FRAMA && is_TEMA_Above_across_FRAMA() && is_DEMA_Above_touch_FRAMA() && g_arr_d_DEMA[0] > g_arr_d_BB_Upper[0] ) //&& g_arr_d_FRAMA[1] < g_arr_d_BB_Middle[1] 
     {
         g_trade.Buy(in_g_d_LotSize, _Symbol, 0, g_d_Ask - in_g_n_StopLoss * _Point, 0, "Buy Open");
         Print("[TRADE] Buy Order Placed.");
         //g_b_was_DEMA_TEMA_below_FRAMA = false;
         g_n_current_trade_state = None;
         g_b_AvailableBuy = false;
         DrawLabelAuto(" Buy_Open", g_d_Ask, TimeCurrent(), Buy_Color);
     }
}

void show_parameters()
{
//---

}

//+------------------------------------------------------------------+
void check_for_open_sell()
{
   if(PositionSelect(_Symbol)) return;
   
   if( g_b_was_DEMA_TEMA_above_FRAMA && is_TEMA_Below_across_FRAMA() && is_DEMA_Below_touch_FRAMA() && g_arr_d_DEMA[0] < g_arr_d_BB_Lower[0] ) ///&& g_arr_d_FRAMA[1] > g_arr_d_BB_Middle[1] 
     {
         g_trade.Sell(in_g_d_LotSize, _Symbol, g_d_Bid, g_d_Bid + in_g_n_StopLoss * _Point, 0, "Sell Open");
         Print("[TRADE] Sell Order Placed.");
         //g_b_was_DEMA_TEMA_above_FRAMA = false;
         g_n_current_trade_state = None;
         g_b_AvailableSell = false;
         DrawLabelAuto(" Sell_Open", g_d_Bid, TimeCurrent(), Sell_Color);
     }
}

//+------------------------------------------------------------------+
void check_for_close()
  {
   if(PositionSelect(_Symbol))
     {
         if(PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY)
            check_for_close_buy();
         else
            check_for_close_sell();
     }
  }
  
bool is_FRAMA_Above_BB_Upper()
{
   if( g_arr_d_FRAMA[2] > g_arr_d_BB_Upper[2] && g_arr_d_FRAMA[3] > g_arr_d_BB_Upper[3] && g_arr_d_FRAMA[4] > g_arr_d_BB_Upper[4] && g_arr_d_FRAMA[5] > g_arr_d_BB_Upper[5])
   {
      return true;
   }
   return false;
}

bool is_FRAMA_Below_BB_Upper()
{
   if( g_arr_d_FRAMA[2] < g_arr_d_BB_Upper[2] && g_arr_d_FRAMA[3] < g_arr_d_BB_Upper[3] && g_arr_d_FRAMA[4] < g_arr_d_BB_Upper[4] && g_arr_d_FRAMA[5] < g_arr_d_BB_Upper[5] )
   {
      return true;
   }
   return false;
}

bool is_FRAMA_Above_BB_Lower()
{
   if( g_arr_d_FRAMA[2] > g_arr_d_BB_Lower[2] && g_arr_d_FRAMA[3] > g_arr_d_BB_Lower[3] && g_arr_d_FRAMA[4] > g_arr_d_BB_Lower[4] && g_arr_d_FRAMA[5] > g_arr_d_BB_Lower[5])
   {
      return true;
   }
   return false;
}

bool is_FRAMA_Below_BB_Lower()
{
   if( g_arr_d_FRAMA[2] < g_arr_d_BB_Lower[2] && g_arr_d_FRAMA[3] < g_arr_d_BB_Lower[3] && g_arr_d_FRAMA[4] < g_arr_d_BB_Lower[4] && g_arr_d_FRAMA[5] < g_arr_d_BB_Lower[5])
   {
      return true;
   }
   return false;
}

bool is_TEMA_Below_across_BBUpper()
{
   if(  g_arr_d_TEMA[1] < g_arr_d_BB_Upper[1] ) //g_arr_d_TEMA[2] > g_arr_d_BB_Upper[2] && //&& g_arr_d_TEMA[0] < g_arr_d_BB_Upper[0]
      return true;
   return false;
}

//low to high
bool is_TEMA_Above_across_BBLower()
{
   if(  g_arr_d_TEMA[1] > g_arr_d_BB_Lower[1] ) //g_arr_d_TEMA[2] < g_arr_d_BB_Lower[2] && && g_arr_d_TEMA[0] > g_arr_d_BB_Lower[0]
      return true;
      
   return false;
}

bool is_DEMA_Below_touch_BBUpper()
{
   if ( g_arr_d_DEMA[2] > g_arr_d_BB_Upper[2] && g_arr_d_DEMA[1] <= g_arr_d_BB_Upper[1] ) //
      return true;
      
   return false;
}

bool is_DEMA_Above_touch_BBLower()
{
   if ( g_arr_d_DEMA[2] < g_arr_d_BB_Lower[2] && g_arr_d_DEMA[1] >= g_arr_d_BB_Lower[1] ) // 
      return true;
      
   return false;
}


//+------------------------------------------------------------------+
void check_for_close_buy()
  {
   if(( is_FRAMA_Above_BB_Upper() && is_TEMA_Below_across_FRAMA() && is_DEMA_Below_touch_FRAMA() ) || //
      ( is_FRAMA_Below_BB_Upper() && is_TEMA_Below_across_BBUpper() && is_DEMA_Below_touch_BBUpper() )) //
     {
         g_trade.PositionClose(_Symbol);
         Print("[TRADE] Buy Closed.");
         
         DrawLabelAuto(" Buy_Close", g_d_Bid, TimeCurrent(), Close_Color);
         
         if ( is_FRAMA_Below_BB_Upper() )
         {
            g_b_last_buy_second_mode_closed = true;
            g_b_is_frama_above_acrossed_BB_middle = false;
            g_b_is_frama_below_acrossed_BB_middle = false;
            //g_b_last_buy_second_mode_closed = false;
            g_b_last_sell_second_mode_closed = false;
         }
     }
  }

//+------------------------------------------------------------------+
void check_for_close_sell()
  {
   if(( is_FRAMA_Below_BB_Lower() && is_TEMA_Above_across_FRAMA() && is_DEMA_Above_touch_FRAMA() ) || //
      ( is_FRAMA_Above_BB_Lower() && is_TEMA_Above_across_BBLower() && is_DEMA_Above_touch_BBLower() )) //
     {
         g_trade.PositionClose(_Symbol);
         Print("[TRADE] Sell Closed.");
         DrawLabelAuto(" Sell_Close", g_d_Ask, TimeCurrent(), Close_Color);
         if ( is_FRAMA_Above_BB_Lower() )
         {
            g_b_last_sell_second_mode_closed = true;
            g_b_is_frama_above_acrossed_BB_middle = false;
            g_b_is_frama_below_acrossed_BB_middle = false;
            g_b_last_buy_second_mode_closed = false;
            //g_b_last_sell_second_mode_closed = false;
         }
     }
  }

bool is_FRAMA_Above_Across_BBMiddle()
{
   if( g_arr_d_FRAMA[2] < g_arr_d_BB_Middle[2] && g_arr_d_FRAMA[1] > g_arr_d_BB_Middle[1])
      return true;
   return false;
}

bool is_FRAMA_Below_Across_BBMiddle()
{
   if( g_arr_d_FRAMA[2] > g_arr_d_BB_Middle[2] && g_arr_d_FRAMA[1] < g_arr_d_BB_Middle[1])
      return true;
   return false;
}

//+------------------------------------------------------------------+
void check_for_availability()
  {
      if(g_n_current_trade_state == None)
      {
         if(is_FRAMA_Above_Across_BBMiddle() )
         {
            if( g_b_is_frama_below_acrossed_BB_middle )
            {
               //g_n_current_trade_state = Buy_Available; 
               g_b_AvailableBuy = true;
               //g_b_is_frama_above_acrossed_BB_middle = false;
               //g_b_is_frama_below_acrossed_BB_middle = false;
               g_b_last_buy_second_mode_closed = false;
               //g_b_last_sell_second_mode_closed = false;
               Print("buy_available_mode_1");
            }
            else
               g_b_is_frama_above_acrossed_BB_middle = true;
         }
         
         if(is_FRAMA_Below_Across_BBMiddle() )
         {
            if( g_b_is_frama_above_acrossed_BB_middle )
            {
               //g_n_current_trade_state = Sell_Available; 
               g_b_AvailableSell = true;
               //g_b_is_frama_above_acrossed_BB_middle = false;
               //g_b_is_frama_below_acrossed_BB_middle = false;
               //g_b_last_buy_second_mode_closed = false;
               g_b_last_sell_second_mode_closed = false;
               Print("sell_available_mode_1");
            }
            else
               g_b_is_frama_below_acrossed_BB_middle = true;
         }
//         
         if( g_b_last_buy_second_mode_closed )
         {
            if ( g_arr_d_DEMA[1] > g_arr_d_BB_Upper[1] && g_arr_d_TEMA[1] > g_arr_d_BB_Upper[1])
            {
                //g_n_current_trade_state = Buy_Available;
                g_b_AvailableBuy = true;
                g_b_is_frama_above_acrossed_BB_middle = false;
                g_b_is_frama_below_acrossed_BB_middle = false;
                Print("buy_available_mode_2");
            }
         }
         
         if( g_b_last_sell_second_mode_closed )
         {
            if ( g_arr_d_DEMA[1] < g_arr_d_BB_Lower[1] && g_arr_d_TEMA[1] < g_arr_d_BB_Lower[1] )
            {
               //g_n_current_trade_state = Sell_Available;
               g_b_AvailableSell = true;
               g_b_is_frama_above_acrossed_BB_middle = false;
               g_b_is_frama_below_acrossed_BB_middle = false;
               Print("sell_available_mode_2");
            }
         }  
      }
  }

//+------------------------------------------------------------------+

int tradeLabelCounter = 0;

void DrawLabelAuto(string message, double price, datetime time, color clr = clrWhite)
{
   string name = "TradeNote_" + IntegerToString(tradeLabelCounter++);
   message = "_" + message;
   
   if( ObjectCreate(0, name, OBJ_TEXT, 0, time, price ) )
   {
      ObjectSetString(0, name, OBJPROP_TEXT, message);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
   }
   else{
      Print("Failed to Create label");
   }
}