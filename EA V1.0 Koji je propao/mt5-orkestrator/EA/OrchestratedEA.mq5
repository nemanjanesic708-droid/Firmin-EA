//+------------------------------------------------------------------+
//|                                                OrchestratedEA.mq5|
//|                     Minimal EA to talk to LAN orchestrator       |
//+------------------------------------------------------------------+
#property strict
#include <Trade/Trade.mqh>

input string InpApiBase = "http://192.168.8.74:8000"; // change to your API server IP:PORT
input string InpApiKey  = "8f1c0b7a5e2d49c1a7b3e68d9f24c6a0f3b2d1e4c7a8b9d0e1f2c3a4b5d6e73";                     // must match .env for bot-1/bot-2/bot-3
input string InpBotId   = "bot-3";
input string InpSymbol  = "EURUSD";

CTrade trade;
int last_ticket = -1;

// Simple helpers
bool HttpPostJson(string url, string json, string &resp)
{
   string headers;
   char data[];
   StringToCharArray(json, data, 0, WHOLE_ARRAY, CP_UTF8);
   char result[];
   string hdrs = "Content-Type: application/json\r\nAuthorization: Bearer " + InpApiKey + "\r\n";
   int status = WebRequest("POST", url, hdrs, 5000, data, result, headers);
   if(status==200 || status==201){
      resp = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      return true;
   }
   PrintFormat("HTTP POST failed: %d %s", status, headers);
   return false;
}

bool HttpGet(string url, string &resp)
{
   string headers;
   char result[];
   string hdrs = "Authorization: Bearer " + InpApiKey + "\r\n";
   int status = WebRequest("GET", url, hdrs, 5000, NULL, result, headers);
   if(status==200){
      resp = CharArrayToString(result, 0, WHOLE_ARRAY, CP_UTF8);
      return true;
   }
   PrintFormat("HTTP GET failed: %d %s", status, headers);
   return false;
}

// naive JSON value extractor (only for demo; use a real JSON lib in production)
string json_get(string src, string key)
{
   string pat = """ + key + "":";
   int i = StringFind(src, pat);
   if(i<0) return "";
   int j = i + StringLen(pat);
   // skip spaces and quotes
   while(j < StringLen(src) && (StringGetCharacter(src, j)==' ' || StringGetCharacter(src, j)=='"')) j++;
   // read until , or } or "
   string out="";
   bool quoted = (StringGetCharacter(src, i + StringLen(pat))=='"');
   for(int k=j; k<StringLen(src); k++){
      ushort ch = StringGetCharacter(src, k);
      if(quoted){
         if(ch=='"') break;
      }else{
         if(ch==',' || ch=='}') break;
      }
      out += (string)StringGetCharacter(src, k);
   }
   return out;
}

int OnInit()
{
   EventSetTimer(1);
   Print("OrchestratedEA started. Ensure Tools->Options->Expert Advisors->'Allow WebRequest for listed URL' includes ", InpApiBase);
   return(INIT_SUCCEEDED);
}

void OnDeinit(const int reason)
{
   EventKillTimer();
}

void OnTimer()
{
   SendHeartbeat();
   PullDecision();
}

void SendHeartbeat()
{
   MqlTick tick;
   if(!SymbolInfoTick(InpSymbol, tick)) return;
   long sp = SymbolInfoInteger(InpSymbol, SYMBOL_SPREAD);
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   string now = TimeToString(TimeCurrent(), TIME_DATE|TIME_SECONDS);
   string payload;
   payload = StringFormat("{"bot_id":"%s","ts":"%s","spread":%ld,"equity":%.2f,"features":{"symbol":"%s","bid":%.5f,"ask":%.5f}}",
                          InpBotId, now, sp, eq, InpSymbol, tick.bid, tick.ask);
   string resp;
   HttpPostJson(InpApiBase + "/heartbeat", payload, resp);
}

void PullDecision()
{
   string resp;
   if(!HttpGet(InpApiBase + "/decisions/next?bot_id=" + InpBotId, resp)) return;

   string action = json_get(resp, "action");
   if(action!="OPEN") return;

   string side = json_get(resp, "side");
   string lot_s = json_get(resp, "lot");
   string sl_s  = json_get(resp, "sl_pips");
   string tp_s  = json_get(resp, "tp_pips");
   string dec_id = json_get(resp, "id");

   double lot = (lot_s=="" ? 0.10 : (double)StringToDouble(lot_s));
   int sl_pips = (sl_s=="" ? 5 : (int)StringToInteger(sl_s));
   int tp_pips = (tp_s=="" ? 10 : (int)StringToInteger(tp_s));

   MqlTick tick; if(!SymbolInfoTick(InpSymbol, tick)) return;
   double point = SymbolInfoDouble(InpSymbol, SYMBOL_POINT);
   double price = (side=="SELL" ? tick.bid : tick.ask);
   double sl = (side=="SELL" ? price + sl_pips*point : price - sl_pips*point);
   double tp = (side=="SELL" ? price - tp_pips*point : price + tp_pips*point);

   trade.SetAsyncMode(false);
   bool ok = false;
   if(side=="SELL") ok = trade.Sell(lot, InpSymbol, price, sl, tp);
   else ok = trade.Buy(lot, InpSymbol, price, sl, tp);

   int ticket = -1;
   if(ok) ticket = (int)trade.ResultOrder();
   // notify orchestrator
   string payload = StringFormat("{"decision_id":"%s","bot_id":"%s","status":"%s","order_ticket":%d}",
                                 dec_id, InpBotId, (ok ? "OPENED" : "REJECTED"), ticket);
   string resp2; HttpPostJson(InpApiBase + "/executions", payload, resp2);
}
//+------------------------------------------------------------------+
