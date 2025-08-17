//+------------------------------------------------------------------+
//|                                        Leap_Frog_Trade_Panel.mq5 |
//|                                                       MathewCole |
//|                                            https://www.ColBekATS |
//+------------------------------------------------------------------+
#property copyright "MathewCole"
#property link      "https://www.ColBekATS"
#property version   "1.00"


#include <Trade\Trade.mqh>
#include <Controls\Dialog.mqh>
#include <Controls\Button.mqh>
#include <Controls\Label.mqh>
#include <Controls\Edit.mqh>

enum TSL_TYPE{
   cont,
   snap,
   indicator
};

enum Risk_TYPE{
   Fixed_Risk,
   Martingale
};

enum MARTINGALE_PROG_TYPE{
   fixed_profit,
   Regressive_Progression,
   Custom_input
   
};

string  BUY_TYPE   =  "_BUY_Trade_",  
        SELL_TYPE  =  "_SELL_Trade_";

input group   "GENRAL SETTINGS"
input double     LOT                  =  1.0;            //Lot size
input double     Risk_Percent         =  1  ;            //risk Percent
input double     R2R                  =  5 ;             //Risk to Reward Ratio
input double     Max_TP               =  100;            //MAX target Profit (points)
input double     Max_SL               =  10 ;            //Stop Loss (points)
input double     SL_Buff              =  10 ;            //Stop Loss Buff(points)
input double     Start_Balance        = 100000.0;
input group  "Trailing Stop Settings"
input bool       U_TSl                =  true;           //Use trailing Stop?
input TSL_TYPE   TSL_type             =  snap;           //Trailing Stop Type
input double     TSl                  =  10 ;            //Trailing Stop (%)
input double     TSl_Buff             =  20 ;            //Trailing Stop buffer(%)
input double     HTTP                 =  0.1;            //HTTP ratio crit.         
input group  "Indicator Settings"
input int      Imbalance_Min          = 50 ;
input int      Imbalance_Max          = 300;
input int      Imbalance_Stop         = 1 ;
input int      H_Ashi_Filter          = 5 ;              
input group  "Risk Managment"
input Risk_TYPE  Risk_Type            = Martingale;      // Risk type
input double     Max_DD               = 5         ;      // max Drawdown (%)
input group   "Martingale Numbers"
input MARTINGALE_PROG_TYPE Progression_type = fixed_profit ;
input double     Martingale_Factor    = 0.90        ;
input double     Step_Size            = 1   ;            // Step size
input int        Max_Step             = 15  ;            // maximum number of steps
//input double     Steps[]              = [1,1.2,1.4]      //    
input group  "EA Settings"
input ulong      magicnumber          = 234321244668455525 ;         //EA magic number
input bool       Auto_Trade           = false; 

CTrade    trade         ;
MqlRates  rates[]       ;
double    bid, ask      ;
int       barsTotal = 0 ;
datetime  init_time     ;

//variables loading
double lot = LOT, risk_percent = Risk_Percent,  r2r = R2R , start_balance =  Start_Balance,
       max_Tp = Max_TP  , max_sL = Max_SL , sl_buff =  SL_Buff,  tsl = TSl ,tsl_buff = TSl_Buff , http = HTTP, step_size = Step_Size;    
int    max_step =  Max_Step ; 
int    imbalance_min =  Imbalance_Min ,imbalance_max = Imbalance_Max,  imbalance_stop = Imbalance_Stop ,  h_ashi_filter = H_Ashi_Filter;  
bool   u_tsl = U_TSl , auto_trade =  Auto_Trade ; 
TSL_TYPE   tsl_type = TSL_type ;
Risk_TYPE  risk_type =  Risk_Type ; 

//handles
int       H_ashi_handle  ;
double    H_ashi_clr[] ,H_ashi_open[] , H_ashi_close[] ;
double    h_ashi_size = 0 ;

//Tracking
int    stream1_count       = 1 , stream2_count       = 1; 
double stream1_init_price  = 0 , stream2_init_price  = 0 ,
       tp_stream1          = 0 , sl_stream1          = 0 ,
       tp_stream2          = 0 , sl_stream2          = 0 ;
       //c_profit            = 0 ;// h_profit         = 0 , TSL_ammount = 0, 

//Signal       
bool   buy_trend  = false ,  sell_trend = false , 
       buy_window = false , sell_window = false,
       buy_signal = false , sell_signal = false; 
       
       
//Switches
bool  //stream1_success  = false, stream2_success  = false,
      hasOpen_stream1  = false, hasOpen_stream2  = false,
      use_stream1      = true ,
      buySwitch        = false, sellswitch       = false,
      canTrail         = false;

double     risk_nums[21] = {0,0.40,0.42,0.45,0.50,0.56,0.64,0.75,0.87,1.03,1.23,1.47,1.77,2.12,2.54,3.05,3.66,4.39,5.27,6.33,7.59} ;
double     stream1_lots = lot ,   stream2_lots =  lot ; 
//ulong      stream1_ticket , stream2_ticket ;
//int        stream_of_last_trade = 1; // 1 or 2 to represent the stream that opened the trade
//ulong      last_ticket = 0;



string  comment_stream_1  = "T_panel Stream_1" ;
string  comment_stream_2  = "T_panel Stream_2";
//string  last_comment;

ENUM_ORDER_TYPE    trade_type = ORDER_TYPE_SELL_LIMIT;



//+------------------------------------------------------------------+
//| Expert initialization function                                   |
//+------------------------------------------------------------------+
int OnInit(){
   
   trade.SetExpertMagicNumber(magicnumber);
   trade.SetDeviationInPoints(10);
   init_time = TimeCurrent();
   
   Load_GUI();

       //Loading handles
   ArraySetAsSeries(rates     ,     true);
   ArraySetAsSeries(H_ashi_clr    , true);
   ArraySetAsSeries(H_ashi_open    , true);
   ArraySetAsSeries(H_ashi_close    , true);
   
   
   string H_ashi_name;
   H_ashi_name        = ChartIndicatorName(0, 0, 0);
   H_ashi_handle     = ChartIndicatorGet(0, 0, H_ashi_name);
   if(H_ashi_handle == INVALID_HANDLE)
      Alert("Heiken-Ashi Smoothed indicator was loaded incorrectly >>> Please Install as 1st Indicator");
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert tick function                                             |
//+------------------------------------------------------------------+
void OnTick(){

    bid = SymbolInfoDouble(_Symbol,SYMBOL_BID);
    ask = SymbolInfoDouble(_Symbol,SYMBOL_ASK);
    
    int bars = iBars(_Symbol,PERIOD_CURRENT);
    if (barsTotal != bars){
    
       CopyRates(_Symbol, PERIOD_CURRENT,0 ,5, rates);
       CopyBuffer(H_ashi_handle, 4, 0, 2, H_ashi_clr);
       CopyBuffer(H_ashi_handle, 0, 0, 2, H_ashi_open);
       CopyBuffer(H_ashi_handle, 3, 0, 2, H_ashi_close);
     
       barsTotal = bars;
       SIGNALS();
       Plot_Imbalance();
       if (auto_trade)
         TRADE_EXECTIONS();  
       
       }
       
       if (auto_trade)
         Closers();
 
}

//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//|////////////   //////    //////  /////////////////                    SIGNALS                     ///////          /////////////////    ///////////////////////|
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+

void SIGNALS(){
   Buy_Signal();
   Sell_Signal();
}

bool Buy_Imb(){
   double imbalance_size  =   MathAbs(rates[1].low - rates[3].high) ;
   if (rates[1].low > rates[3].high && imbalance_size > imbalance_min  &&  imbalance_size < imbalance_max)
      return true;
   return false; 
}

bool Sell_Imb(){
    double imbalance_size  =   MathAbs(rates[1].high - rates[3].low) ;
    if (rates[1].high < rates[3].low && MathAbs(rates[1].high - rates[3].low) > imbalance_min &&  imbalance_size < imbalance_max )
      return true;
   return false; 
}

double  H_ashi_size(){
   h_ashi_size = MathAbs (H_ashi_close[0] -  H_ashi_open[0]) ;
   return  h_ashi_size ;
}


void Buy_Switch(){ 
   if (H_ashi_clr[0] == 1 && H_ashi_clr[1] == 2.0)
     buySwitch = true ;
   else if  ( H_ashi_clr[0] == 2  ) 
     buySwitch = false;  
}

void Sell_Switch(){ 
   if (H_ashi_clr[0] == 2 && H_ashi_clr[1] == 1.0)
     sellswitch = true; 
   else if  ( H_ashi_clr[0] == 1 ) 
     sellswitch = false;    
}


bool Buy_trend(){
   if( H_ashi_clr[0] == 1.0 || H_ashi_size() < h_ashi_filter  )
       return true;
   return false;
}

bool Sell_trend(){
   if( H_ashi_clr[0] == 2.0 || H_ashi_size() < h_ashi_filter )
       return true;
   return false;
}




void BuyWindow(){

   //Print(" trade_type != ORDER_TYPE_BUY " , trade_type != ORDER_TYPE_BUY  ) ; 
   //Print(" buySwitch " , buySwitch  ) ;  
   //Print("  Buy_trend() " ,  Buy_trend()  ) ; 
   //Print(" !Has_Open_Type(POSITION_TYPE_BUY) " ,  !Has_Open_Type(POSITION_TYPE_BUY)  ) ;
   //Print(" ::::::::::: ::::::::::::: ::::::::::::: ::::::::::::: :::::::::::::") ;
   if (trade_type != ORDER_TYPE_BUY && buySwitch && Buy_trend()  && !Has_Open_Type(POSITION_TYPE_BUY) ){
      buy_window = true;
   }
}


void SellWindow(){
   if (trade_type != ORDER_TYPE_SELL  &&  sellswitch && Sell_trend() && !Has_Open_Type(POSITION_TYPE_SELL) )
      sell_window = true ;
}

void Buy_Signal(){
   Buy_Switch();
   BuyWindow();
   if( buy_window && Buy_Imb()  && !Has_Open_Type(POSITION_TYPE_BUY)) {   
       buy_signal = true ;
       trade_type = ORDER_TYPE_BUY ;
   }else{
       buy_signal = false;
   }
}


void Sell_Signal(){
   Sell_Switch();
   SellWindow();
   if( sell_window && Sell_Imb() && !Has_Open_Type(POSITION_TYPE_SELL)) {
       sell_signal = true;
       trade_type = ORDER_TYPE_SELL ;
   }else{
       sell_signal= false;
   }    
}

//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//|////////////   //////    //////  /////////////////                TRADE FUNCTIONS                 ///////          /////////////////    ///////////////////////|
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+

void TRADE_EXECTIONS(){
     if (use_stream1)     
      Open_Stream1();
     else
      Open_Stream2();
     
}

void Closers(){
     TakeProfit_Stream1();
     TakeProfit_Stream2();
     StopLoss_Stream1();
     StopLoss_Stream2();
}

void Open_Stream1(){  
   if (!hasOpen_stream1 && (buy_signal || sell_signal) && use_stream1 ){
      trade_type = (buy_signal) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; 
      Stop_levels_Stream1();
      Calc_Lot_Size();
      ExecuteTrade();
      Select_Stream_UI(1);
      Switch_Streams(1);
   }

}
void Open_Stream2(){
   //Print ("", );
   if (!hasOpen_stream2 && (buy_signal || sell_signal) && !use_stream1){
   
      trade_type = (buy_signal) ? ORDER_TYPE_BUY : ORDER_TYPE_SELL; 
      Stop_levels_Stream2();
      Calc_Lot_Size();
      ExecuteTrade();
      Select_Stream_UI(2);
      Switch_Streams(2);
   }

}

void TakeProfit_Stream1(){
   if (Hit_TP(comment_stream_1)){
      ClosePosition(comment_stream_1 );
      Re_setNums_Stream1(true);
      Select_Stream_UI(1);
      Delete_Stops(1);
   }    
}

void StopLoss_Stream1(){
   if (Hit_SL(comment_stream_1)){
      ClosePosition(comment_stream_1 );
      Re_setNums_Stream1(false);
      Select_Stream_UI(1);
      Delete_Stops(1);
   }
} 

void TakeProfit_Stream2(){
   if (Hit_TP(comment_stream_2)){
      ClosePosition( comment_stream_2 );
      Re_setNums_Stream2(true);
      Select_Stream_UI(2);
      Delete_Stops(2);
   }
}

void StopLoss_Stream2(){
   if (Hit_SL(comment_stream_2)){
      ClosePosition( comment_stream_2 );
      Re_setNums_Stream2(false);
      Select_Stream_UI(2);
      Delete_Stops(2);
   }
} 

void TSL_Stream1(){}

void TSL_Stream2(){}


//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//|////////////   //////    //////  /////////////////                TRADE EXECUTIONS                ///////          /////////////////    ///////////////////////|
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
void ExecuteTrade() {
   
   string comment  = (use_stream1) ?  comment_stream_1 : comment_stream_2;
    
   if (trade_type == ORDER_TYPE_BUY){ 
   
         if(trade.PositionOpen(_Symbol, ORDER_TYPE_BUY , lot, ask, 0,0,comment)){
            Print("Trade executed: ", (trade_type == ORDER_TYPE_BUY) ? "Buy" : "Sell", " Lot: ", lot);
            if (use_stream1)
               setNums_Stream1();
            else 
               setNums_Stream2();
         } else{
            Print("Trade failed: ", trade.ResultRetcode());
         }
    }else{    
        if(trade.PositionOpen(_Symbol, ORDER_TYPE_SELL , lot, bid, 0,0,comment)){
            Print("Trade executed: ", (trade_type == ORDER_TYPE_BUY) ? "Buy" : "Sell", " Lot: ", lot);
            if (use_stream1)
               setNums_Stream1();
            else 
               setNums_Stream2();
        } else{
            Print("Trade failed: ", trade.ResultRetcode());
    }
   }
   
     
}
void ClosePosition(string comment) {
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if (!PositionSelectByTicket(ticket))
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != magicnumber)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetString(POSITION_COMMENT)!= comment)
         continue ; 

      if (!trade.PositionClose(ticket)) {
            Print("Failed to closed" , comment," Ticket: ", ticket, ", Error: ", GetLastError());
         } else {
            Print("Successfully closed" , comment," Ticket: ", ticket);
         }
      }
}

//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
//|/////////////////                       SETTERS                     ///////////////////////|
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+


void setNums_Stream1(){
     if (trade_type == ORDER_TYPE_BUY) 
      stream1_init_price = ask;
     else
      stream1_init_price = bid;
     
     
     buySwitch = false ;
     stream1_count ++ ;
     use_stream1 = !use_stream1 ;
     hasOpen_stream1 =  true ; 
}

void setNums_Stream2(){
     if (trade_type == ORDER_TYPE_BUY)  
      stream2_init_price = ask;
     else
      stream2_init_price = bid;
     
     
     sellswitch = false;
     stream2_count ++ ;
     use_stream1 = !use_stream1 ;
     hasOpen_stream2 =  true ; 
}

void Stop_levels_Stream1(){
   
    if (auto_trade) {
      if (trade_type == ORDER_TYPE_BUY){
         sl_stream1 = rates[2].open - (Price_diff_To_Points(ask,rates[2].open)*(sl_buff /100));
         tp_stream1 = bid + (Price_diff_To_Points(ask,rates[2].open) * r2r);
         Print("TP is  :: :: :: " , tp_stream1);
         Print("SL is  :: :: :: " , sl_stream1);
         
      }else{
         sl_stream1 = rates[2].open + (Price_diff_To_Points(ask,rates[2].open)*(sl_buff /100));
         tp_stream1 = ask - (Price_diff_To_Points(ask,rates[2].open) * r2r);
      }
    }else{
      double sl_stream1_line_price =  ObjectGetDouble(0, "StopLossLine_Stream1", OBJPROP_PRICE);
      if (trade_type == ORDER_TYPE_BUY){
         sl_stream1 =  sl_stream1_line_price- (Price_diff_To_Points(ask,sl_stream1_line_price)*(sl_buff /100));
         tp_stream1 = bid + (Price_diff_To_Points(ask,sl_stream1_line_price * r2r));
      }else{
         sl_stream1 = sl_stream1_line_price + (Price_diff_To_Points(ask,sl_stream1_line_price)*(sl_buff /100));
         tp_stream1 = ask - (Price_diff_To_Points(ask,sl_stream1_line_price) * r2r);
      }
    }
}

void  Stop_levels_Stream2(){
   
    if (auto_trade) {
      if (trade_type == ORDER_TYPE_BUY){
         sl_stream2 = rates[2].open - (Price_diff_To_Points(ask,rates[2].open)*(sl_buff /100));
         tp_stream2 = bid + (Price_diff_To_Points(ask,rates[2].open) * r2r);
      }else{
         sl_stream2 = rates[2].open + (Price_diff_To_Points(ask,rates[2].open)*(sl_buff /100));
         tp_stream2 = ask - (Price_diff_To_Points(ask,rates[2].open) * r2r);
      }
    }else{
      double sl_stream1_line_price =  ObjectGetDouble(0, "StopLossLine_Stream1", OBJPROP_PRICE);
      if (trade_type == ORDER_TYPE_BUY){
         sl_stream2 =  sl_stream1_line_price- (Price_diff_To_Points(ask,sl_stream1_line_price)*(sl_buff /100));
         tp_stream2 = bid + (Price_diff_To_Points(ask,sl_stream1_line_price * r2r));
      }else{
         sl_stream2 = sl_stream1_line_price + (Price_diff_To_Points(ask,sl_stream1_line_price)*(sl_buff /100));
         tp_stream2 = ask - (Price_diff_To_Points(ask,sl_stream1_line_price) * r2r);
      }
    }
}


// maybe have 3 for this >>>>   one for regular charting and the other for auto_trade ==  true  
void Calc_Lot_Size(){

   //risk_percent = StringToDouble(m_editRisk.Text());
   risk_percent = (use_stream1 ) ? risk_nums[stream1_count] : risk_nums[stream2_count] ;
   double risk_amt = start_balance * (risk_percent / 100.0);
   m_editRisk.Text(DoubleToString(risk_percent,2));
   double sl_stream1_line_price =  ObjectGetDouble(0, "StopLossLine_Stream1", OBJPROP_PRICE);
    double  total_sl;
   
   double ask_or_bid =  (trade_type ==  ORDER_TYPE_BUY) ?  bid : ask ;
   
   if (auto_trade){
         total_sl =  Price_diff_To_Points(sl_stream1 ,ask_or_bid);
   }else{
         total_sl = ( sl_stream1_line_price < bid)
                          ? Price_diff_To_Points(sl_stream1_line_price- (Price_diff_To_Points(ask,sl_stream1_line_price)*(sl_buff /100))  ,ask_or_bid)
                          : Price_diff_To_Points(sl_stream1_line_price+ (Price_diff_To_Points(ask,sl_stream1_line_price)*(sl_buff /100))  ,ask_or_bid) 
                          ;
   }
         
   lot = risk_amt / (total_sl / _Point);
   lot = NormalizeDouble(lot, 3); 
   
   if(lot ==   0.000) lot = 0.001 ;
   
   if  (use_stream1) 
      stream1_lots =  lot; // *(times multiple) or  select rcalculate  
   else
      stream2_lots =  lot; // *times multiple or selecct recalculate  
   
   m_editLot.Text(DoubleToString(lot,3));
    
}


void Re_setNums_Stream1(bool win){
     
     if (win)
      stream1_count = 1 ;

     
     //GUI element delete

     
     tp_stream1 =0 ;
     sl_stream1 =0 ;
     stream1_init_price = 0;
     hasOpen_stream1 =  false ; 
}


void Re_setNums_Stream2(bool win){
     
     if (win)
      stream2_count = 1 ;

     
     tp_stream2 =0 ;
     sl_stream2 =0 ;
     stream2_init_price = 0;
     hasOpen_stream2 =  false ; 
}



//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//|////////////   //////    //////  /////////////////             TRACKERS AND INFO               //////////          /////////////////    ///////////////////////|
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+ 

void Trackers(){
   //CurrentProfit();
   
   
}



//double CurrentProfit(){
//   
//   double tradeprofit = 0 ,totalProfit = 0, dealCommisions = 0;
//   for (int i =0; i <= PositionsTotal(); i++) {
//      ulong posTicket = PositionGetTicket(i);
//      if (!PositionSelectByTicket(posTicket))
//         continue;
//      ulong magic  = PositionGetInteger(POSITION_MAGIC);
//      long PosID = PositionGetInteger(POSITION_IDENTIFIER);
//       
//      if (magic != magicnumber)
//       continue;
//      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
//       continue;
//
//       
//
//            HistorySelect(POSITION_TIME,TimeCurrent());
//            for  (int  j= 0 ; j < HistoryDealsTotal() ; j++ ){
//               ulong dealticket = HistoryDealGetTicket(j);
//               if(HistoryDealGetInteger(dealticket,DEAL_POSITION_ID) == PosID){
//                  dealCommisions = HistoryDealGetDouble(dealticket,DEAL_COMMISSION) *2;
//                  break;
//               }
//            }
//      tradeprofit =  PositionGetDouble(POSITION_PROFIT)+ PositionGetDouble(POSITION_SWAP) + dealCommisions; 
//      totalProfit += tradeprofit ; 
//      trade_count ++; 
//      
//      
//   }
//      
//   h_profit = MathMax(totalProfit, h_profit); 
//   c_profit = totalProfit;
//   
//   return totalProfit;
//      
//}


bool Hit_TP(string comment){ 

    for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if (!PositionSelectByTicket(ticket))
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != magicnumber)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetString(POSITION_COMMENT)!= comment)
         continue ; 
         
      double tp_ = (comment == comment_stream_1) ? tp_stream1 : tp_stream2 ;
        
      if (tp_> 0){
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
            if (ask >= tp_stream1 && tp_stream1 > 0){
               Print ("Hit TP");
               return true ; 
            }
         }else{
            if (ask <= tp_stream1 && tp_stream1 > 0){
               Print ("Hit TP");
               return true ; 
            }
         }
      }
   }
   return false;
}

bool Hit_SL( string comment){
     
   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if (!PositionSelectByTicket(ticket))
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != magicnumber)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetString(POSITION_COMMENT)!= comment)
         continue ; 
    
      double sl_ = (comment == comment_stream_1) ? sl_stream1 : sl_stream2 ; 
      
      if (sl_ > 0) {
         if (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY){
            if (ask <= sl_ && sl_ > 0){
               Print ("Hit SL");
               return true ; 
            }
         }else{
            if (ask >= sl_ && sl_ > 0){
               Print ("Hit SL");
               return true ; 
            }
         }
       } 
   }
   return false;
}


bool Hit_TSL(){
   
   //
   return false;
}

bool Has_Open_Type(int type){

   for (int i = PositionsTotal() - 1; i >= 0; i--) {
      ulong ticket = PositionGetTicket(i);
      
      if (!PositionSelectByTicket(ticket))
         continue;
      if (PositionGetInteger(POSITION_MAGIC) != magicnumber)
         continue;
      if (PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if (PositionGetInteger(POSITION_TYPE)!= type)
         continue ; 
      
      return true;
  }
  return false;
}


//+------------------------------------------------------------------+
//| Trade transaction event handler                                  |
//+------------------------------------------------------------------+
//void OnTradeTransaction(const MqlTradeTransaction &trans, const MqlTradeRequest &request, const MqlTradeResult &result){
//       
//
//      CheckLastClosedTradesForProfit();
//      
//      if(    (trans.deal_type == TRADE_TRANSACTION_ORDER_ADD)
//         //||  (trans.deal_type == DEAL_TYPE_SELL || trans.deal_type == DEAL_TYPE_BUY)
//         )
//      {
//            ulong ticket = trans.position;
//            if(ticket == last_ticket){
//                if(PositionSelectByTicket(ticket)){
//                    double profit = PositionGetDouble(POSITION_PROFIT);
//                    
//                     if(stream_of_last_trade == 1){
//                        if(profit < 0)
//                            Select_Stream_UI(1);
//                    }else{
//                        if(profit < 0)
//                            Select_Stream_UI(2);
//                    }
//                         
//                    Print("Trade closed. Stream1: ", stream1_count, " | Stream2: ", stream2_count);
//
//                    use_stream1 = !use_stream1;
//                    last_ticket = 0;
//                }
//            } 
//      }
// }



//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//|////////////   //////    //////  //////////////////////                   GUI               //////////          /////////////////    //////////////////////////|
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//+---------------------------------------------------------------------------------------------------------------------------------------------------------------+
//*********************************************************************************************
//*********************************************************************************************
//*********************************************************************************************
                     //******************************************
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
//|/////////////////                GUI Initializers                   ///////////////////////|
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+


CAppDialog AppWindow;
CButton    m_buttonBuy, m_buttonSell;
CLabel     m_labelRisk, m_labelSLBuffer, m_labelRRRatio, m_labelLot, m_labelS1, m_labelS2;
CEdit      m_editRisk, m_editSLBuffer, m_editRRRatio, m_editLot, m_editS1, m_editS2;

color      active_color = clrLightBlue;
color      default_color = clrWhite;

int       buy_imb_window  = 0 ;
int       sell_imb_window = 0 ;

void Load_GUI(){

   // Create application dialog
   AppWindow.Create(0,"TradePanel",0,20,20,300,300);
      
   // Create and add controls to the panel
   CreateControls();
     
   // Create initial horizontal line for stop loss
   double sl_price = SymbolInfoDouble(_Symbol, SYMBOL_BID) - 100 * _Point;
   ObjectCreate(0, "StopLossLine_Stream1", OBJ_HLINE, 0, 0, sl_price);
   ObjectSetInteger(0, "StopLossLine_Stream1", OBJPROP_COLOR, clrGold);
   ObjectSetInteger(0, "StopLossLine_Stream1", OBJPROP_STYLE, STYLE_DASH);
   ObjectSetInteger(0, "StopLossLine_Stream1", OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, "StopLossLine_Stream1",OBJPROP_SELECTABLE,true);

   
   AppWindow.Run();
   
}
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
//|/////////////////      Create and add controls to the panel         ///////////////////////|
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
bool CreateControls(){

   int x = 10, y = 10, width = 80, height = 20, gap = 5 
   ;

        m_labelRisk.Create(0, "LabelRisk", 0, x, y, x + width, y + height);
        m_labelRisk.Text("Risk (%)");
        AppWindow.Add(m_labelRisk);
        m_editRisk.Create(0, "EditRisk", 0, x + width + gap + 17, y, x + 2 * width, y + height);
        m_editRisk.Text(DoubleToString(risk_percent, 2));
        AppWindow.Add(m_editRisk);
        y += height + gap;

        m_labelSLBuffer.Create(0, "LabelSLBuffer", 0, x, y, x + width, y + height);
        m_labelSLBuffer.Text("sl_ Buffer (%)");
        AppWindow.Add(m_labelSLBuffer);
        m_editSLBuffer.Create(0, "EditSLBuffer", 0, x + width + gap + 17, y, x + 2 * width, y + height);
        m_editSLBuffer.Text(DoubleToString(sl_buff, 2));
        AppWindow.Add(m_editSLBuffer);
        y += height + gap;

        m_labelRRRatio.Create(0, "LabelRRRatio", 0, x, y, x + width, y + height);
        m_labelRRRatio.Text("R:R Ratio");
        AppWindow.Add(m_labelRRRatio);
        m_editRRRatio.Create(0, "EditRRRatio", 0, x + width +  gap + 17, y, x + 2 * width, y + height);
        m_editRRRatio.Text(DoubleToString(r2r, 2));
        AppWindow.Add(m_editRRRatio);
        y += height + gap;

        m_labelLot.Create(0, "LabelLot", 0, x, y, x + width, y + height);
        m_labelLot.Text("Lot Size");
        AppWindow.Add(m_labelLot);
        m_editLot.Create(0, "EditLot", 0, x + width +  gap + 17, y, x + 2 * width, y + height);
        m_editLot.ReadOnly(true);
        m_editLot.Text(DoubleToString(lot, 2));
        AppWindow.Add(m_editLot);
        y += height + gap;

        m_labelS1.Create(0, "LabelS1", 0, x, y, x + width, y + height);
        m_labelS1.Text("Stream 1");
        AppWindow.Add(m_labelS1);
        m_editS1.Create(0, "EditS1", 0, x + width +  gap + 17, y, x + 2 * width, y + height);
        m_editS1.ReadOnly(true);
        m_editS1.Text(IntegerToString(stream1_count));
        AppWindow.Add(m_editS1);
        y += height + gap;

        m_labelS2.Create(0, "LabelS2", 0, x, y, x + width, y + height);
        m_labelS2.Text("Stream 2");
        AppWindow.Add(m_labelS2);
        m_editS2.Create(0, "EditS2", 0, x + width +  gap + 17, y, x + 2 * width, y + height);
        m_editS2.ReadOnly(true);
        m_editS2.Text(IntegerToString(stream2_count));
        AppWindow.Add(m_editS2);
        y += height + gap;

        m_buttonBuy.Create(0, "ButtonBuy", 0, x, y, x + width, y + height);
        m_buttonBuy.Text("Buy");
        AppWindow.Add(m_buttonBuy);

        m_buttonSell.Create(0, "ButtonSell", 0, x + width + gap, y, x + 2 * width, y + height);
        m_buttonSell.Text("Sell");
        AppWindow.Add(m_buttonSell);

        m_editS1.ColorBackground (active_color);
        return true;
    
}

//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
//|/////////////////                     Running GUIs                  ///////////////////////|
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
void Select_Stream_UI( int stream){

          
         if (stream  ==  1  ){
             m_editS1.ColorBackground (default_color);
             m_editS1.Text( IntegerToString( stream1_count) ) ;
             m_editS2.ColorBackground (active_color);
         } else  if (stream  ==  2  ){
             m_editS2.ColorBackground (default_color);
             m_editS2.Text( IntegerToString( stream2_count) ) ;
             m_editS1.ColorBackground (active_color);
        }
            
}

void Plot_Imbalance(){

       ObjectCreate(0,"buy_Imbalance_Window_"  , OBJ_RECTANGLE , 0,rates[3].time, rates[3].high ,rates[1].time ,rates[1].low);
       ObjectSetInteger(0 , "buy_Imbalance_Window_" , OBJPROP_COLOR ,clrBlue);
       
       ObjectCreate(0,"sell_Imbalance_Window_"  , OBJ_RECTANGLE , 0,rates[3].time ,rates[3].low ,rates[1].time, rates[1].high);
       ObjectSetInteger(0 , "sell_Imbalance_Window_" , OBJPROP_COLOR ,clrMagenta);

       
       ObjectCreate(0,"buyImb_line", OBJ_TREND,0,rates[3].time ,rates[3].high ,rates[1].time, rates[1].low);
       ObjectSetInteger(0 , "buyImb_line" , OBJPROP_COLOR ,clrLimeGreen);
       ObjectSetInteger(0 , "buyImb_line", OBJPROP_WIDTH ,2);
       
       ObjectCreate(0,"sellImb_line", OBJ_TREND,0,rates[3].time ,rates[3].low ,rates[1].time, rates[1].high);
       ObjectSetInteger(0 , "sellImb_line" , OBJPROP_COLOR ,clrMagenta);
       ObjectSetInteger(0 , "sellImb_line", OBJPROP_WIDTH ,2);
       
       if ( buy_signal){
         //Print  ("buy_Imbalance_Window_ size is  :: :: :: "  ,  MathAbs(rates[1].low - rates[3].high));
         ObjectDelete(0,"buy_Imbalance_Window_");
         ObjectCreate(0,"buy_Imbalance_Window_" + IntegerToString(buy_imb_window) , OBJ_RECTANGLE , 0 ,rates[3].time, rates[3].high ,rates[1].time ,rates[1].low);
         ObjectSetInteger(0 , "buy_Imbalance_Window_" + IntegerToString(buy_imb_window), OBJPROP_COLOR ,clrBlue);
         ObjectSetInteger(0 , "buy_Imbalance_Window_" + IntegerToString(buy_imb_window), OBJPROP_WIDTH ,2);
         buy_imb_window ++; 
       }
       
       if ( sell_signal){
         //Print  ("sell_Imbalance_Window_ size is  :: :: :: "  ,  MathAbs(rates[1].low - rates[3].high));
         ObjectDelete(0,"sell_Imbalance_Window_");
         ObjectCreate(0,"sell_Imbalance_Window_" + IntegerToString(sell_imb_window) , OBJ_RECTANGLE , 0 ,rates[3].time ,rates[3].low ,rates[1].time, rates[1].high);
         ObjectSetInteger(0 , "sell_Imbalance_Window_" + IntegerToString(sell_imb_window), OBJPROP_COLOR ,clrHotPink);
         ObjectSetInteger(0 , "sell_Imbalance_Window_" + IntegerToString(sell_imb_window), OBJPROP_WIDTH ,2);
         sell_imb_window ++; 
      }
}
 

void Switch_Streams(int stream){
     
     if (stream ==  1){
      
      //Freeze the current stop loss line;
      if (ObjectFind(0,"StopLossLine_Stream1") == 0){
         ObjectSetDouble(0,"StopLossLine_Stream1", OBJPROP_PRICE,sl_stream1);
         ObjectSetInteger(0,"StopLossLine_Stream1", OBJPROP_SELECTABLE, false);
         Print("Made it here  SOMEHOW");
      }

      //Create new stops
      if  (  ObjectFind(0,"StopLossLine_Stream2") <0 ){
         Print("EVEN here ");
         //Create new Stop loss line for next stream  
         if (!ObjectCreate(0, "StopLossLine_Stream2", OBJ_HLINE, 0, 0, bid -100* _Point))
             Print("Int never made this thought" );
         ObjectSetInteger(0, "StopLossLine_Stream2", OBJPROP_COLOR, clrPurple);
         ObjectSetInteger(0, "StopLossLine_Stream2", OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, "StopLossLine_Stream2", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "StopLossLine_Stream2",OBJPROP_SELECTABLE,true);
         
         //Create TP line;
         ObjectCreate(0, "TakeProfitLine_Stream1", OBJ_HLINE, 0, 0, tp_stream1);
         ObjectSetInteger(0, "TakeProfitLine_Stream1", OBJPROP_COLOR, clrBlue);
         ObjectSetInteger(0, "TakeProfitLine_Stream1", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "TakeProfitLine_Stream2",OBJPROP_SELECTABLE,false);
      }
      
     }else{
     
      if (ObjectFind(0,"StopLossLine_Stream2"))
         ObjectSetInteger(0,"StopLossLine_Stream2", OBJPROP_SELECTABLE, false);
      
      //Create new stops
      if  (  !ObjectFind(0,"StopLossLine_Stream1") ){
         //Create new Stop loss line for next stream  
         ObjectCreate(0, "StopLossLine_Stream1", OBJ_HLINE, 0, 0, bid -100* _Point);
         ObjectSetInteger(0, "StopLossLine_Stream1", OBJPROP_COLOR, clrOrange);
         ObjectSetInteger(0, "StopLossLine_Stream1", OBJPROP_STYLE, STYLE_DASH);
         ObjectSetInteger(0, "StopLossLine_Stream1", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "StopLossLine_Stream1",OBJPROP_SELECTABLE,true);
         
         //Create TP line;
         ObjectCreate(0, "TakeProfitLine_Stream2", OBJ_HLINE, 0, 0, tp_stream2);
         ObjectSetInteger(0, "TakeProfitLine_Stream2", OBJPROP_COLOR, clrGreen);
         ObjectSetInteger(0, "TakeProfitLine_Stream2", OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, "TakeProfitLine_Stream2",OBJPROP_SELECTABLE,false);
         
      }

     }
}

void Delete_Stops(int stream){
     
     if(stream == 1){
      ObjectDelete(0, "StopLossLine_Stream1");
      ObjectDelete(0, "TakeProfitLine_Stream1");
     } else{
      ObjectDelete(0, "StopLossLine_Stream2");
      ObjectDelete(0, "TakeProfitLine_Stream2");
     }


}

//+------------------------------------------------------------------+
//| Chart event function                                             |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam) {
   AppWindow.ChartEvent(id, lparam, dparam, sparam);

   if(id == CHARTEVENT_OBJECT_CLICK)
     {
      if(sparam == "ButtonBuy"){
         trade_type =  ORDER_TYPE_BUY ;
         ExecuteTrade();
      }else if(sparam == "ButtonSell"){
         trade_type =  ORDER_TYPE_SELL ;
         ExecuteTrade();
     }
  }
}

//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
//|/////////////////                   Calculators                     ///////////////////////|
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+


int  Price_diff_To_Points( double price_1 , double price_2){

   int points = (int)MathRound( MathAbs (price_1 - price_2));
   return points ; 
   
}
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+
//|/////////////////                       DeInit                      ///////////////////////|
//+-------------------------------------------------------------------------------------------+
//+-------------------------------------------------------------------------------------------+

void OnDeinit(const int reason){

   // Destroy the application dialog
   AppWindow.Destroy(reason);

   // Delete the horizontal line
   ObjectDelete(0, "StopLossLine_Stream1");
} 
