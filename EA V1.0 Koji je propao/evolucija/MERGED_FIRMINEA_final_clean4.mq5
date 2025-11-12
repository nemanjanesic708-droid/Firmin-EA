//+------------------------------------------------------------------+

//|            FIRMINEA_V3.91_PANEL_ML_FIX2.mq5                      |

//| EURUSD EA: EMA+RSI (+H1 confirm opcionalno) + Panel + Online ML  |

//| Fixes: CloseTF helper umesto Close[], OnChartEvent = void,        |

//|        MQL5-friendly array potpis (double &x[] / const double[]) |

//+------------------------------------------------------------------+

#property version   "3.91"

#property strict

#property indicator_chart_window



#include <Trade/Trade.mqh>

CTrade trade;



//============================= INPUTS ===============================//

input int      StrategyMode_input     = 0;    // 0=Scalp(M15),1=Swing(M30)

input bool     LongsAllowed_input     = true;

input bool     ShortsAllowed_input    = true;



input bool     UseRiskBasedLots_input = true;

input double   RiskPercent_input      = 2.0;

input double   ManualLots_input       = 0.10;



input bool     UseMultiplier_input    = false;

input double   LotMultiplier_input    = 1.50;

input double   MaxLots_input          = 2.00;



input bool     UseDynamicStops_input  = true;

input int      FixedSL_Pips_input     = 20;

input int      FixedTP_Pips_input     = 30;

input int      ATR_Period_input       = 14;

input double   ATR_SL_Mult_input      = 1.5;

input double   ATR_TP_RR_input        = 1.5;



input bool     UseTrailing_input      = true;

input double   ATR_Trail_Mult_input   = 1.0;



input int      MagicNumber_input      = 25082025;

input int      Slippage_input         = 5;

input int      MaxSpreadPoints_input  = 25;



input bool     UseTimeFilter_input    = false;

input int      StartHour_input        = 8;

input int      EndHour_input          = 20;



input int      MinBarsBetween_input   = 1;



input int      MaxOpenPositions_input = 1;

input int      MaxLongs_input         = 1;

input int      MaxShorts_input        = 1

;



input bool     CloseOnMicroProfit_input = true;

input double   MicroProfitAmount_input  = 0.50; // account currency



// EMA/RSI (eased)

input int      EMA_fast_input         = 9;

input int      EMA_slow_input         = 21;

input int      RSI_period_input       = 7;

input double   RSI_buy_thresh_input   = 48.0;

input double   RSI_sell_thresh_input  = 52.0;



input bool     UseH1Confirm_input     = false;

input bool     DebugMode_input        = true;

// ===== ML (on-line logisticka) =====

input bool     UseML_input            = true;

input int      ML_DecisionMode_input  = 0;     // 0=OR, 1=AND, 2=ML-only

input double   ML_Th_Buy_input        = 0.55;

input double   ML_Th_Sell_input       = 0.55;

input double   ML_LearnRate_input     = 0.02;

input double   ML_L2_input            = 0.0001;

input int      ML_MinSamplesUse_input = 15;



//=========================== RUNTIME VARS ===========================//

int g_StrategyMode;

bool g_LongsAllowed, g_ShortsAllowed;



bool g_UseRiskBasedLots;

double g_RiskPercent, g_ManualLots;



bool g_UseMultiplier;

double g_LotMultiplier, g_MaxLots;



bool g_UseDynamicStops;

int  g_FixedSL_Pips, g_FixedTP_Pips, g_ATR_Period;

double g_ATR_SL_Mult, g_ATR_TP_RR;



bool g_UseTrailing; double g_ATR_Trail_Mult;



int g_MagicNumber, g_Slippage, g_MaxSpreadPoints;

bool g_UseTimeFilter; int g_StartHour, g_EndHour;



int g_MinBarsBetween;



int g_MaxOpenPositions, g_MaxLongs, g_MaxShorts;



bool g_CloseOnMicroProfit; double g_MicroProfitAmount;



int g_EMA_fast, g_EMA_slow, g_RSI_period;

double g_RSI_buy_thresh, g_RSI_sell_thresh;



bool g_UseH1Confirm, g_DebugMode;



double g_nextLotBoost = 1.0;

double g_EffectiveRiskPercent = 0.0;



string GVBASE;

// ===== ML RUNTIME =====

#define MLN 9

bool   g_UseML; int g_MLDecisionMode;

double g_ML_Th_Buy, g_ML_Th_Sell, g_ML_LR, g_ML_L2;

int    g_ML_MinSamples;



double wBuy[MLN], wSell[MLN];

int    g_TrainedSamples=0;

string g_WeightsFile;



struct SFeat { ulong pos_id; bool isBuy; double x[MLN]; };

SFeat g_feats[512];

int   g_featCount=0;



//============================= HELPERS ==============================//

double ReadBufSingle(int handle,int buf=0,int shift=0){

   if(handle==INVALID_HANDLE) return 0.0;

   double b[]; ArraySetAsSeries(b,true);

   int c=CopyBuffer(handle,buf,shift,1,b);

   IndicatorRelease(handle);

   if(c<=0) return 0.0;

   return b[0];

}

double EMAval(ENUM_TIMEFRAMES tf,int period,int shift=0){ return ReadBufSingle(iMA(_Symbol,tf,period,0,MODE_EMA,PRICE_CLOSE),0,shift); }

double RSIval(ENUM_TIMEFRAMES tf,int period,int shift=0){ return ReadBufSingle(iRSI(_Symbol,tf,period,PRICE_CLOSE),0,shift); }

double ATRval(ENUM_TIMEFRAMES tf,int period,int shift=0){ return ReadBufSingle(iATR(_Symbol,tf,period),0,shift); }



// NEW: helper umesto Close[]

double CloseTF(ENUM_TIMEFRAMES tf, int shift){

   double buf[];

   if(CopyClose(_Symbol, tf, shift, 1, buf) < 1) return 0.0;

   return buf[0];

}



int    DigitsPips(){ int d=(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS); return (d==3||d==5)?10:1; }

double PipsToPoints(int pips){ return (double)pips*DigitsPips(); }

double GetSpreadPoints(){ double a=SymbolInfoDouble(_Symbol,SYMBOL_ASK), b=SymbolInfoDouble(_Symbol,SYMBOL_BID); if(a<=0||b<=0) return 9999; return (a-b)/_Point; }

bool   SpreadOK(){ return GetSpreadPoints()<=g_MaxSpreadPoints; }

bool   TimeOK(){ if(!g_UseTimeFilter) return true; MqlDateTime t; TimeToStruct(TimeCurrent(),t); return (t.hour>=g_StartHour && t.hour<g_EndHour); }



void CountPositions(int &total,int &buyCnt,int &sellCnt){

   total=0; buyCnt=0; sellCnt=0;

   int n=(int)PositionsTotal();

   for(int i=0;i<n;i++){

      ulong ticket=PositionGetTicket(i); if(ticket==0) continue;

      if(!PositionSelectByTicket(ticket)) continue;

      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

      if((int)PositionGetInteger(POSITION_MAGIC)!=g_MagicNumber) continue;

      int typ=(int)PositionGetInteger(POSITION_TYPE);

      total++; if(typ==POSITION_TYPE_BUY) buyCnt++; else if(typ==POSITION_TYPE_SELL) sellCnt++;

   }

}



bool PointValue(double &perPoint){

   double tv=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);

   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);

   if(tv<=0||ts<=0) return false;

   perPoint=(tv/ts)*_Point; return true;

}

double NormalizeLots(double lots){

   double minL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);

   double maxL=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);

   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);

   lots=MathMax(minL,MathMin(maxL,lots));

   if(step>0) lots=MathRound(lots/step)*step;

   return lots;

}

double CalcLotsByRisk(double sl_points){

   double perPoint; if(!PointValue(perPoint)||sl_points<=0) return NormalizeLots(g_ManualLots*g_nextLotBoost);

   double bal=AccountInfoDouble(ACCOUNT_BALANCE);

   double riskAmt=bal*g_EffectiveRiskPercent/100.0;

   double lossPerLot=sl_points*perPoint;

   double lots=riskAmt/MathMax(1e-8,lossPerLot);

   lots*=g_nextLotBoost;

   if(g_UseMultiplier) lots=MathMin(lots,g_MaxLots);

   return NormalizeLots(lots);

}



void UpdateNextLotBoost(){

   if(!g_UseMultiplier){ g_nextLotBoost=1.0; return; }

   HistorySelect(TimeCurrent()-86400*30, TimeCurrent());

   int deals=(int)HistoryDealsTotal(); if(deals==0){ g_nextLotBoost=1.0; return; }

   int last_t=0; double last_prof=0; bool found=false;

   for(int ii=deals-1;ii>=0;ii--){

      ulong d=HistoryDealGetTicket(ii); if(d==0) continue;

      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;

      if((int)HistoryDealGetInteger(d,DEAL_MAGIC)!=g_MagicNumber) continue;

      int t=(int)HistoryDealGetInteger(d,DEAL_TIME);

      if(t>last_t){ last_t=t; last_prof=HistoryDealGetDouble(d,DEAL_PROFIT); found=true; }

   }

   g_nextLotBoost = (found && last_prof<0.0) ? MathMin(g_LotMultiplier,g_MaxLots) : 1.0;

}

void UpdateLearningRisk(){

   int wins=0,losses=0,total=0;

   HistorySelect(TimeCurrent()-86400*30, TimeCurrent());

   int deals=(int)HistoryDealsTotal(); if(deals==0){ g_EffectiveRiskPercent=g_RiskPercent; return; }

   for(int ii=deals-1;ii>=0;ii--){

      ulong d=HistoryDealGetTicket(ii); if(d==0) continue;

      if(HistoryDealGetString(d,DEAL_SYMBOL)!=_Symbol) continue;

      if((int)HistoryDealGetInteger(d,DEAL_MAGIC)!=g_MagicNumber) continue;

      double p=HistoryDealGetDouble(d,DEAL_PROFIT);

      total++; if(p>0) wins++; else if(p<0) losses++;

      if(total>=50) break;

   }

   if(total==0){ g_EffectiveRiskPercent=g_RiskPercent; return; }

   double lossRate=(double)losses/(double)total;

   double strict=1.0;

   if(lossRate>0.5) strict=MathMin(3.0,strict+0.2);

   else if(lossRate<0.25) strict=MathMax(0.5,strict-0.1);

   g_EffectiveRiskPercent=g_RiskPercent/strict;

   if(g_EffectiveRiskPercent<0.25) g_EffectiveRiskPercent=0.25;

}



//========================== SIGNAL & STOPS ==========================//

int GetPrimarySignal(){

   ENUM_TIMEFRAMES tf=(g_StrategyMode==0?PERIOD_M15:PERIOD_M30);

   double ef=EMAval(tf,g_EMA_fast,0);

   double es=EMAval(tf,g_EMA_slow,0);

   double r =RSIval(tf,g_RSI_period,0);

   if(ef==0||es==0) return 0;

   int sig=0;

   if(ef>es && r<=g_RSI_buy_thresh)  sig= 1;

   if(ef<es && r>=g_RSI_sell_thresh) sig=-1;

   if(sig!=0 && g_UseH1Confirm){

      double h1f=EMAval(PERIOD_H1,g_EMA_fast,0);

      double h1s=EMAval(PERIOD_H1,g_EMA_slow,0);

      if(h1f==0||h1s==0) return 0;

      if(sig==1 && !(h1f>h1s)) return 0;

      if(sig==-1&& !(h1f<h1s)) return 0;

   }

   if(g_DebugMode) PrintFormat("DEBUG BaseSig: ef=%.5f es=%.5f rsi=%.1f -> %d",ef,es,r,sig);

   return sig;

}

void ComputeStopsPrices(bool isBuy,double &sl,double &tp){

   double entry=isBuy?SymbolInfoDouble(_Symbol,SYMBOL_ASK):SymbolInfoDouble(_Symbol,SYMBOL_BID);

   double slp=0,tpn=0;

   if(g_UseDynamicStops){

      double atr=ATRval((g_StrategyMode==0?PERIOD_M15:PERIOD_H1), g_ATR_Period, 0);

      if(atr<=0){ sl=0; tp=0; return; }

      slp=(atr/_Point)*g_ATR_SL_Mult;

      tpn=slp*g_ATR_TP_RR;

   }else{

      slp=PipsToPoints(g_FixedSL_Pips);

      tpn=PipsToPoints(g_FixedTP_Pips);

   }

   if(isBuy){ sl=entry-slp*_Point; tp=entry+tpn*_Point; }

   else     { sl=entry+slp*_Point; tp=entry-tpn*_Point; }

}



//============================= ML CORE ==============================//

double Sigmoid(double z){ return 1.0/(1.0+MathExp(-z)); }

double Dot(const double &w[], const double &x[]){ double s=0; for(int i=0;i<MLN;i++) s+=w[i]*x[i]; return s; }

double Clamp01(double v){ if(v<0) return 0; if(v>1) return 1; return v; }



void BuildFeatures(double &x[]){

   ENUM_TIMEFRAMES tf=(ENUM_TIMEFRAMES)Period();

   double rsi =RSIval(tf,g_RSI_period,0);

   double ef0 =EMAval(tf,g_EMA_fast,0), ef1=EMAval(tf,g_EMA_fast,1);

   double es0 =EMAval(tf,g_EMA_slow,0);

   double atr =ATRval(tf,g_ATR_Period,0);

   double c0  =CloseTF(tf,0);

   double c3  =CloseTF(tf,3);



   double pxchg   = (c0>0&&c3>0)? (c0-c3)/c3 : 0.0;  pxchg   = MathMax(-0.05,MathMin(0.05,pxchg));

   double emaSpr  = (es0!=0)? (ef0-es0)/es0 : 0.0;   emaSpr  = MathMax(-0.05,MathMin(0.05,emaSpr));

   double emaAcc  = (ef1!=0)? (ef0-ef1)/ef1 : 0.0;   emaAcc  = MathMax(-0.05,MathMin(0.05,emaAcc));

   double rsiN    = rsi/100.0;                       if(!MathIsValidNumber(rsiN)) rsiN=0.5;

   double rsiSlope= (RSIval(tf,g_RSI_period,0)-RSIval(tf,g_RSI_period,1))/100.0;

   rsiSlope=MathMax(-0.5,MathMin(0.5,rsiSlope));

   double atrN    = (c0>0? atr/c0 : 0.0);            atrN    = MathMin(0.10,MathMax(0.0,atrN));

   double spN     = MathMin(3.0, MathMax(0.0, GetSpreadPoints()/10.0));

   double h1      = (!g_UseH1Confirm?0.0:(EMAval(PERIOD_H1,g_EMA_fast,0)>EMAval(PERIOD_H1,g_EMA_slow,0)?1.0:-1.0));



   x[0]=1.0;

   x[1]=Clamp01(0.5 + pxchg*10.0);

   x[2]=Clamp01(0.5 + emaSpr*10.0);

   x[3]=Clamp01(0.5 + emaAcc*10.0);

   x[4]=Clamp01(rsiN);

   x[5]=Clamp01(0.5 + rsiSlope);

   x[6]=Clamp01(atrN*10.0);

   x[7]=Clamp01(spN/3.0);

   x[8]=h1; // -1..1

}



double ML_ProbBuy (const double &x[]){ return Sigmoid(Dot(wBuy ,x)); }

double ML_ProbSell(const double &x[]){ return Sigmoid(Dot(wSell,x)); }



void ML_Update(double &w[], const double &x[], double y){

   double p=Sigmoid(Dot(w,x));

   double err=(y-p);

   for(int i=0;i<MLN;i++) w[i]+= g_ML_LR*(err*x[i] - g_ML_L2*w[i]);

}



void SaveWeights(){

   int h=FileOpen(g_WeightsFile, FILE_WRITE|FILE_TXT|FILE_COMMON);

   if(h==INVALID_HANDLE) return;

   for(int i=0;i<MLN;i++) FileWrite(h, DoubleToString(wBuy[i],10));

   FileWrite(h,"SEP");

   for(int i=0;i<MLN;i++) FileWrite(h, DoubleToString(wSell[i],10));

   FileWrite(h,"SAMPLES", IntegerToString(g_TrainedSamples));

   FileClose(h);

}

void LoadWeights(){

   int h=FileOpen(g_WeightsFile, FILE_READ|FILE_TXT|FILE_COMMON);

   if(h==INVALID_HANDLE){

      MathSrand((uint)TimeLocal());

      for(int i=0;i<MLN;i++){ wBuy[i]=(MathRand()/32767.0-0.5)*0.02; wSell[i]=(MathRand()/32767.0-0.5)*0.02; }

      g_TrainedSamples=0; return;

   }

   for(int i=0;i<MLN;i++) wBuy[i]=StringToDouble(FileReadString(h));

   string sep=FileReadString(h);

   if(sep!="SEP"){ FileClose(h); return; }

   for(int i=0;i<MLN;i++) wSell[i]=StringToDouble(FileReadString(h));

   string mark=FileReadString(h);

   if(mark=="SAMPLES") g_TrainedSamples=(int)StringToInteger(FileReadString(h));

   FileClose(h);

}



void StoreActiveFeat(ulong pos_id,bool isBuy,const double &x[]){

   for(int i=0;i<g_featCount;i++){

      if(g_feats[i].pos_id==pos_id){

         g_feats[i].isBuy=isBuy;

         for(int k=0;k<MLN;k++) g_feats[i].x[k]=x[k];

         return;

      }

   }

   if(g_featCount<512){

      g_feats[g_featCount].pos_id=pos_id;

      g_feats[g_featCount].isBuy=isBuy;

      for(int k=0;k<MLN;k++) g_feats[g_featCount].x[k]=x[k];

      g_featCount++;

   }

}

bool PopActiveFeat(ulong pos_id,bool &isBuy,double &x[]){

   for(int i=0;i<g_featCount;i++){

      if(g_feats[i].pos_id==pos_id){

         isBuy=g_feats[i].isBuy;

         for(int k=0;k<MLN;k++) x[k]=g_feats[i].x[k];

         g_featCount--;

         if(i<g_featCount) g_feats[i]=g_feats[g_featCount];

         return true;

      }

   }

   return false;

}



//============================== TRADING =============================//

void TryOpenSignal(){

   if(!SpreadOK()) { if(g_DebugMode) Print("DEBUG: spread high"); return; }

   if(g_UseTimeFilter && !TimeOK()) { if(g_DebugMode) Print("DEBUG: time filter"); return; }



   int baseSig=GetPrimarySignal();

   if(baseSig==0 && !g_UseML) return;



   double x[MLN]; BuildFeatures(x);

   double pb=ML_ProbBuy(x), ps=ML_ProbSell(x);

   bool mlBuy  = (pb>=g_ML_Th_Buy);

   bool mlSell = (ps>=g_ML_Th_Sell);

   if(g_TrainedSamples<g_ML_MinSamples){ mlBuy=false; mlSell=false; }



   bool wantBuy=false, wantSell=false;

   if(g_UseML){

      if(     g_MLDecisionMode==0){ wantBuy=(baseSig==1)||mlBuy;  wantSell=(baseSig==-1)||mlSell; }

      else if(g_MLDecisionMode==1){ wantBuy=(baseSig==1)&&mlBuy;  wantSell=(baseSig==-1)&&mlSell; }

      else                        { wantBuy=mlBuy;                wantSell=mlSell; }

   }else{

      wantBuy=(baseSig==1); wantSell=(baseSig==-1);

   }



   int total,bCnt,sCnt; CountPositions(total,bCnt,sCnt);

   if(total>=g_MaxOpenPositions) { if(g_DebugMode) Print("DEBUG: total limit"); return; }

   if(wantBuy  && bCnt>=g_MaxLongs)  wantBuy=false;

   if(wantSell && sCnt>=g_MaxShorts) wantSell=false;

   if(!wantBuy && !wantSell) return;



   trade.SetExpertMagicNumber(g_MagicNumber);

   trade.SetDeviationInPoints(g_Slippage);



   if(wantBuy && g_LongsAllowed){

      double sl=0,tp=0; ComputeStopsPrices(true,sl,tp);

      if(sl>0 && tp>0){

         double slpts=MathAbs((SymbolInfoDouble(_Symbol,SYMBOL_ASK)-sl)/_Point);

         if(slpts<=0) slpts=PipsToPoints(g_FixedSL_Pips);

         double lots=g_UseRiskBasedLots? CalcLotsByRisk(slpts) : NormalizeLots(g_ManualLots*g_nextLotBoost);

         lots=MathMin(lots,g_MaxLots);

         bool ok=trade.Buy(lots,_Symbol,0.0,sl,tp);

         if(!ok){ if(g_DebugMode) PrintFormat("BUY FAIL err=%u rc=%d",GetLastError(),trade.ResultRetcode()); ResetLastError(); }

         else   { if(g_DebugMode) PrintFormat("BUY OK lots=%.2f pb=%.3f base=%d",lots,pb,baseSig); }

      }

   }

   if(wantSell && g_ShortsAllowed){

      double sl=0,tp=0; ComputeStopsPrices(false,sl,tp);

      if(sl>0 && tp>0){

         double slpts=MathAbs((sl-SymbolInfoDouble(_Symbol,SYMBOL_BID))/_Point);

         if(slpts<=0) slpts=PipsToPoints(g_FixedSL_Pips);

         double lots=g_UseRiskBasedLots? CalcLotsByRisk(slpts) : NormalizeLots(g_ManualLots*g_nextLotBoost);

         lots=MathMin(lots,g_MaxLots);

         bool ok=trade.Sell(lots,_Symbol,0.0,sl,tp);

         if(!ok){ if(g_DebugMode) PrintFormat("SELL FAIL err=%u rc=%d",GetLastError(),trade.ResultRetcode()); ResetLastError(); }

         else   { if(g_DebugMode) PrintFormat("SELL OK lots=%.2f ps=%.3f base=%d",lots,ps,baseSig); }

      }

   }

}



void TrailAndMaintain(){

   if(g_UseTrailing){

      double atr=ATRval((g_StrategyMode==0?PERIOD_M15:PERIOD_H1), g_ATR_Period, 0);

      if(atr>0){

         double trail=atr*g_ATR_Trail_Mult;

         int n=(int)PositionsTotal();

         for(int i=0;i<n;i++){

            ulong t=PositionGetTicket(i); if(t==0) continue;

            if(!PositionSelectByTicket(t)) continue;

            if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

            if((int)PositionGetInteger(POSITION_MAGIC)!=g_MagicNumber) continue;

            int type=(int)PositionGetInteger(POSITION_TYPE);

            double sl=PositionGetDouble(POSITION_SL);

            double tp=PositionGetDouble(POSITION_TP);

            double bid=SymbolInfoDouble(_Symbol,SYMBOL_BID);

            double ask=SymbolInfoDouble(_Symbol,SYMBOL_ASK);

            if(type==POSITION_TYPE_BUY){

               double newSL=MathMax(sl, bid - trail);

               if(newSL>sl && newSL<bid) trade.PositionModify(t,newSL,tp);

            }else{

               double newSL=(sl==0.0)? ask + trail : MathMin(sl, ask + trail);

               if((sl==0.0 && newSL>0) || (newSL<sl && newSL>ask)) trade.PositionModify(t,newSL,tp);

            }

         }

      }

   }

   if(g_CloseOnMicroProfit){

      int n=(int)PositionsTotal();

      for(int i=0;i<n;i++){

         ulong t=PositionGetTicket(i); if(t==0) continue;

         if(!PositionSelectByTicket(t)) continue;

         if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;

         if((int)PositionGetInteger(POSITION_MAGIC)!=g_MagicNumber) continue;

         double p=PositionGetDouble(POSITION_PROFIT);

         if(p>=g_MicroProfitAmount){

            if(g_DebugMode) PrintFormat("DEBUG MicroClose %I64u profit=%.2f",t,p);

            trade.PositionClose(t);

         }

      }

   }

}



//============================= SAVE/LOAD ============================//

string GVKey(string k){ return GVBASE + k; }



void SaveSettings(){

   GlobalVariableSet(GVKey("ManualLots"), g_ManualLots);

   GlobalVariableSet(GVKey("RiskPercent"), g_RiskPercent);

   GlobalVariableSet(GVKey("MaxOpen"), (double)g_MaxOpenPositions);

   GlobalVariableSet(GVKey("MaxL"), (double)g_MaxLongs);

   GlobalVariableSet(GVKey("MaxS"), (double)g_MaxShorts);

   GlobalVariableSet(GVKey("EMAfast"), (double)g_EMA_fast);

   GlobalVariableSet(GVKey("EMAslow"), (double)g_EMA_slow);

   GlobalVariableSet(GVKey("RSIper"), (double)g_RSI_period);

   GlobalVariableSet(GVKey("RSIb"), g_RSI_buy_thresh);

   GlobalVariableSet(GVKey("RSIs"), g_RSI_sell_thresh);

   GlobalVariableSet(GVKey("UseH1"), g_UseH1Confirm?1.0:0.0);

   GlobalVariableSet(GVKey("UseML"), g_UseML?1.0:0.0);

   GlobalVariableSet(GVKey("MLMode"), (double)g_MLDecisionMode);

   GlobalVariableSet(GVKey("MLTh"), g_ML_Th_Buy);

}

void LoadSettings(){

   if(GlobalVariableCheck(GVKey("ManualLots"))) g_ManualLots=GlobalVariableGet(GVKey("ManualLots"));

   if(GlobalVariableCheck(GVKey("RiskPercent"))) g_RiskPercent=GlobalVariableGet(GVKey("RiskPercent"));

   if(GlobalVariableCheck(GVKey("MaxOpen"))) g_MaxOpenPositions=(int)GlobalVariableGet(GVKey("MaxOpen"));

   if(GlobalVariableCheck(GVKey("MaxL"))) g_MaxLongs=(int)GlobalVariableGet(GVKey("MaxL"));

   if(GlobalVariableCheck(GVKey("MaxS"))) g_MaxShorts=(int)GlobalVariableGet(GVKey("MaxS"));

   if(GlobalVariableCheck(GVKey("EMAfast"))) g_EMA_fast=(int)GlobalVariableGet(GVKey("EMAfast"));

   if(GlobalVariableCheck(GVKey("EMAslow"))) g_EMA_slow=(int)GlobalVariableGet(GVKey("EMAslow"));

   if(GlobalVariableCheck(GVKey("RSIper"))) g_RSI_period=(int)GlobalVariableGet(GVKey("RSIper"));

   if(GlobalVariableCheck(GVKey("RSIb"))) g_RSI_buy_thresh=GlobalVariableGet(GVKey("RSIb"));

   if(GlobalVariableCheck(GVKey("RSIs"))) g_RSI_sell_thresh=GlobalVariableGet(GVKey("RSIs"));

   if(GlobalVariableCheck(GVKey("UseH1"))) g_UseH1Confirm=(GlobalVariableGet(GVKey("UseH1"))>0.5);

   if(GlobalVariableCheck(GVKey("UseML"))) g_UseML=(GlobalVariableGet(GVKey("UseML"))>0.5);

   if(GlobalVariableCheck(GVKey("MLMode"))) g_MLDecisionMode=(int)GlobalVariableGet(GVKey("MLMode"));

   if(GlobalVariableCheck(GVKey("MLTh"))) { g_ML_Th_Buy=GlobalVariableGet(GVKey("MLTh")); g_ML_Th_Sell=g_ML_Th_Buy; }

}



//=============================== PANEL ==============================//

void UpdatePanelInfo(){

   // Panel removed.

}



void CreatePanel(){

   // Panel removed.

}



void CreatePopup(){

   // Panel removed.

}



void DestroyPopup(){

   // Panel removed.

}



void ApplyPopupValues(){

   // Panel removed.

}





void OnChartEvent(const int id,const long &lparam,const double &dparam,const string &sparam)

{

   // Panel removed.

return;

}





//============================= EVENTS ===============================//

int OnInit(){

   
   ORCH_OnInit();
g_StrategyMode      = StrategyMode_input;

   g_LongsAllowed      = LongsAllowed_input;

   g_ShortsAllowed     = ShortsAllowed_input;

   g_UseRiskBasedLots  = UseRiskBasedLots_input;

   g_RiskPercent       = RiskPercent_input;

   g_ManualLots        = ManualLots_input;

   g_UseMultiplier     = UseMultiplier_input;

   g_LotMultiplier     = LotMultiplier_input;

   g_MaxLots           = MaxLots_input;

   g_UseDynamicStops   = UseDynamicStops_input;

   g_FixedSL_Pips      = FixedSL_Pips_input;

   g_FixedTP_Pips      = FixedTP_Pips_input;

   g_ATR_Period        = ATR_Period_input;

   g_ATR_SL_Mult       = ATR_SL_Mult_input;

   g_ATR_TP_RR         = ATR_TP_RR_input;

   g_UseTrailing       = UseTrailing_input;

   g_ATR_Trail_Mult    = ATR_Trail_Mult_input;

   g_MagicNumber       = MagicNumber_input;

   g_Slippage          = Slippage_input;

   g_MaxSpreadPoints   = MaxSpreadPoints_input;

   g_UseTimeFilter     = UseTimeFilter_input;

   g_StartHour         = StartHour_input;

   g_EndHour           = EndHour_input;

   g_MinBarsBetween    = MinBarsBetween_input;



   g_MaxOpenPositions  = MaxOpenPositions_input;

   g_MaxLongs          = MaxLongs_input;

   g_MaxShorts         = MaxShorts_input;



   g_CloseOnMicroProfit = CloseOnMicroProfit_input;

   g_MicroProfitAmount  = MicroProfitAmount_input;



   g_EMA_fast          = EMA_fast_input;

   g_EMA_slow          = EMA_slow_input;

   g_RSI_period        = RSI_period_input;

   g_RSI_buy_thresh    = RSI_buy_thresh_input;

   g_RSI_sell_thresh   = RSI_sell_thresh_input;

   g_UseH1Confirm      = UseH1Confirm_input;

   g_DebugMode         = DebugMode_input;



   g_UseML             = UseML_input;

   g_MLDecisionMode    = ML_DecisionMode_input;

   g_ML_Th_Buy         = ML_Th_Buy_input;

   g_ML_Th_Sell        = ML_Th_Sell_input;

   g_ML_LR             = ML_LearnRate_input;

   g_ML_L2             = ML_L2_input;

   g_ML_MinSamples     = ML_MinSamplesUse_input;



   g_EffectiveRiskPercent=g_RiskPercent;



   trade.SetExpertMagicNumber(g_MagicNumber);

   trade.SetDeviationInPoints(g_Slippage);



   GVBASE = StringFormat("FIRMINEA_%s_%d_", _Symbol, g_MagicNumber);

   g_WeightsFile = StringFormat("FIRMINEA_ML_%s_%d.txt", _Symbol, g_MagicNumber);



   LoadSettings();

   LoadWeights();

UpdatePanelInfo();



   if(g_DebugMode){

      MqlDateTime st; TimeToStruct(TimeCurrent(),st);

      PrintFormat("FIRMINEA V3.91 ML FIX2 init %04d-%02d-%02d %02d:%02d:%02d | Mode=%d H1=%s ML=%s MaxOpen=%d",

                  st.year,st.mon,st.day,st.hour,st.min,st.sec,

                  g_StrategyMode, g_UseH1Confirm?"ON":"OFF", g_UseML?"ON":"OFF", g_MaxOpenPositions);

   }

   return(INIT_SUCCEEDED);

}

void OnDeinit(const int reason){

   
   ORCH_OnDeinit();
// Panel removed.

   SaveSettings();

   SaveWeights();

}



void OnTick(){

   
   ORCH_OnTick();
UpdateNextLotBoost();

   UpdateLearningRisk();

   TryOpenSignal();

   TrailAndMaintain();

   UpdatePanelInfo();

}

void OnTradeTransaction(const MqlTradeTransaction& trans,const MqlTradeRequest& req,const MqlTradeResult& res){

   if(trans.type!=TRADE_TRANSACTION_DEAL_ADD) return;

   if(StringCompare(trans.symbol,_Symbol)!=0) return;



   ulong deal=trans.deal; if(deal==0) return;

   if((int)HistoryDealGetInteger(deal,DEAL_MAGIC)!=g_MagicNumber) return;



   int entry=(int)HistoryDealGetInteger(deal,DEAL_ENTRY);

   int dtype=(int)HistoryDealGetInteger(deal,DEAL_TYPE);

   ulong pos_id=(ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);



   if(entry==DEAL_ENTRY_IN){

      double x[MLN]; BuildFeatures(x);

      bool isBuy=(dtype==DEAL_TYPE_BUY);

      StoreActiveFeat(pos_id,isBuy,x);

      if(g_DebugMode) PrintFormat("ML CAPTURE pos=%I64u dir=%s",pos_id,isBuy?"BUY":"SELL");

      return;

   }

   if(entry==DEAL_ENTRY_OUT){

      bool isBuy=false; double x[MLN];

      if(PopActiveFeat(pos_id,isBuy,x)){

         double profit=HistoryDealGetDouble(deal,DEAL_PROFIT);

         double y=(profit>0.0?1.0:0.0);

         if(isBuy) ML_Update(wBuy,x,y); else ML_Update(wSell,x,y);

         g_TrainedSamples++;

         if((g_TrainedSamples%10)==0) SaveWeights();

         if(g_DebugMode){

            double p=isBuy?ML_ProbBuy(x):ML_ProbSell(x);

            PrintFormat("ML UPDATE pos=%I64u dir=%s profit=%.2f y=%.0f p=%.3f samples=%d",

                        pos_id,isBuy?"BUY":"SELL",profit,y,p,g_TrainedSamples);

         }

      }

   }

}

//+------------------------------------------------------------------+


// ===== Orchestrator Module (ORCH_) =====

// ============================================================================
// ORCHESTRATOR INTEGRATION (Inputs + helpers)
// ============================================================================
CTrade ORCH_trade;

input bool   ORCH_ORCH_Enabled    = true;
input bool   ORCH_ORCH_DriverMode = false;
input string ORCH_ORCH_ApiBase    = "http://192.168.8.71:8000";
input string ORCH_ORCH_ApiKey     = "8f1c0b7a5e2d49c1a7b3e68d9f24c6a0f3b2d1e4c7a8b9d0e1f2c3a4b5d6e71";
input string ORCH_ORCH_BotId      = "bot-1";
input string ORCH_ORCH_Symbol     = "EURUSD";

int    ORCH_lastTicket = -1;
ulong  ORCH_lastDecisionTick = 0;

bool ORCH_HttpPostJson(string url, string json, string &resp)
{
   string headers;
   uchar data[];  StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
   uchar result[];
   string hdrs = "Content-Type: application/json\r\nAuthorization: Bearer " + ORCH_ORCH_ApiKey + "\r\n";
   int status = WebRequest("POST", url, hdrs, 5000, data, result, headers);
   if(status==200 || status==201){
      resp = CharArrayToString(result, 0, -1, CP_UTF8);
      return true;
   }
   PrintFormat("ORCH POST failed: %d %s", status, headers);
   return false;
}
bool ORCH_HttpGet(string url, string &resp)
{
   string headers;
   uchar result[];
   uchar data[];
   string hdrs = "Authorization: Bearer " + ORCH_ORCH_ApiKey + "\r\n";
   int status = WebRequest("GET", url, hdrs, 5000, data, result, headers);
   if(status==200){
      resp = CharArrayToString(result, 0, -1, CP_UTF8);
      return true;
   }
   PrintFormat("ORCH GET failed: %d %s", status, headers);
   return false;
}
string ORCH_JsonGet(string src, string key)
{
   string pat="\""+key+"\":";
   int i=StringFind(src,pat); if(i<0) return "";
   int j=i+StringLen(pat); while(j<StringLen(src) && (StringGetCharacter(src,j)==' '||StringGetCharacter(src,j)=='\"')) j++;
   bool quoted = (StringGetCharacter(src, i+StringLen(pat))=='\"');
   string out="";
   for(int k=j;k<StringLen(src);k++){ ushort ch=StringGetCharacter(src,k); if(quoted){ if(ch=='\"') break; } else { if(ch==','||ch=='}') break; } out+=(string)ch; }
   return out;
}
void ORCH_SendHeartbeat()
{
   if(!ORCH_ORCH_Enabled) return;
   string sym = (StringLen(ORCH_ORCH_Symbol)>0 ? ORCH_ORCH_Symbol : _Symbol);
   MqlTick tick; if(!SymbolInfoTick(sym, tick)) return;
   long sp = SymbolInfoInteger(sym, SYMBOL_SPREAD);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string now = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string payload = StringFormat("{\"bot_id\":\"%s\",\"ts\":\"%s\",\"spread\":%ld,\"equity\":%.2f,"
                                 "\"features\":{\"symbol\":\"%s\",\"bid\":%.5f,\"ask\":%.5f}}",
                                 ORCH_ORCH_BotId, now, sp, eq, sym, tick.bid, tick.ask);
   string resp; ORCH_HttpPostJson(ORCH_ORCH_ApiBase + "/heartbeat", payload, resp);
}
bool ORCH_PullDecision_AndMaybeTrade()
{
   if(!ORCH_ORCH_Enabled || !ORCH_ORCH_DriverMode) return false;
   if(GetTickCount() - ORCH_lastDecisionTick < 900) return false;

   string resp; if(!ORCH_HttpGet(ORCH_ORCH_ApiBase + "/decisions/next?bot_id=" + ORCH_ORCH_BotId, resp)) return false;
   string action = ORCH_JsonGet(resp, "action");
   if(action!="OPEN") { ORCH_lastDecisionTick = GetTickCount(); return false; }

   string side = ORCH_JsonGet(resp, "side");
   string lot_s= ORCH_JsonGet(resp, "lot");
   string sl_s = ORCH_JsonGet(resp, "sl_pips");
   string tp_s = ORCH_JsonGet(resp, "tp_pips");
   string dec_id = ORCH_JsonGet(resp, "id");

   double lot = (lot_s=="" ? 0.10 : StringToDouble(lot_s));
   int sl_pips = (sl_s=="" ? 5 : (int)StringToInteger(sl_s));
   int tp_pips = (tp_s=="" ?10 : (int)StringToInteger(tp_s));

   string sym = (StringLen(ORCH_ORCH_Symbol)>0 ? ORCH_ORCH_Symbol : _Symbol);
   MqlTick tick; if(!SymbolInfoTick(sym, tick)) return false;
   double point = SymbolInfoDouble(sym, SYMBOL_POINT);
   double price = (side=="SELL" ? tick.bid : tick.ask);
   double sl = (side=="SELL" ? price + sl_pips*point : price - sl_pips*point);
   double tp = (side=="SELL" ? price - tp_pips*point : price + tp_pips*point);

   ORCH_trade.SetAsyncMode(false);
   bool ok = (side=="SELL") ? ORCH_trade.Sell(lot, sym, price, sl, tp)
                            : ORCH_trade.Buy(lot, sym, price, sl, tp);

   int ticket = ok ? (int)ORCH_trade.ResultOrder() : -1;
   string payload = StringFormat("{\"decision_id\":\"%s\",\"bot_id\":\"%s\",\"status\":\"%s\",\"order_ticket\":%d}",
                                 dec_id, ORCH_ORCH_BotId, (ok ? "OPENED" : "REJECTED"), ticket);
   string r2; ORCH_HttpPostJson(ORCH_ORCH_ApiBase + "/executions", payload, r2);

   ORCH_lastDecisionTick = GetTickCount();
   return ok;
}
bool ORCH_ApproveOpen()
{
   if(!ORCH_ORCH_Enabled || ORCH_ORCH_DriverMode) return true;
   string resp; if(!ORCH_HttpGet(ORCH_ORCH_ApiBase + "/decisions/next?bot_id=" + ORCH_ORCH_BotId, resp)) return false;
   return (ORCH_JsonGet(resp, "action")=="OPEN");
}
void ORCH_ReportClosedDeal(long deal_id)
{
   if(!ORCH_ORCH_Enabled) return;
   if(!HistoryDealSelect(deal_id)) return;
   long entry = (long)HistoryDealGetInteger(deal_id, DEAL_ENTRY);
   if(entry!=DEAL_ENTRY_OUT) return;
   double profit = HistoryDealGetDouble(deal_id, DEAL_PROFIT);
   double price  = HistoryDealGetDouble(deal_id, DEAL_PRICE);
   string payload = StringFormat("{\"bot_id\":\"%s\",\"status\":\"CLOSED\",\"exit_price\":%.5f,\"pnl\":%.2f}",
                                 ORCH_ORCH_BotId, price, profit);
   string r; ORCH_HttpPostJson(ORCH_ORCH_ApiBase + "/executions", payload, r);
}
// ORCHESTRATOR INTEGRATION - END

// === ORCH event stubs (added by merge tool) ===
int ORCH_OnInit(){
   // no-op if orchestrator module not providing handlers
   // keep timer optional
   return(INIT_SUCCEEDED);
}
void ORCH_OnTick(){
   // no-op
}
void ORCH_OnDeinit(){
   // no-op
}
// === END ORCH stubs ===

