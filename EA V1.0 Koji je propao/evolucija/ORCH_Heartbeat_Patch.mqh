// ORCH_Heartbeat_Patch.mqh
// Drop-in replacement for ORCH_SendHeartbeat() with:
// - ISO-8601 UTC timestamp
// - Authorization: Bearer header
// - Proper uchar buffers (no trailing NUL)
// - Safe decimal formatting

void ORCH_SendHeartbeat()
{
   // --- symbol/account data
   string sym = (StringLen(ORCH_ORCH_Symbol) > 0 ? ORCH_ORCH_Symbol : _Symbol);

   double bid = 0.0, ask = 0.0;
   SymbolInfoDouble(sym, SYMBOL_BID, bid);
   SymbolInfoDouble(sym, SYMBOL_ASK, ask);

   double spread = ask - bid;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);

   // ISO-8601 UTC (Z)
   MqlDateTime g; TimeToStruct(TimeGMT(), g);
   string ts_iso = StringFormat("%04d-%02d-%02dT%02d:%02d:%02dZ",
                                g.year, g.mon, g.day, g.hour, g.min, g.sec);

   // Build JSON (numbers with '.' decimal separator)
   string payload =
      "{"
        "\"bot_id\":\"" + ORCH_ORCH_BotId + "\","
        "\"ts\":\"" + ts_iso + "\","
        "\"spread\":" + DoubleToString(spread, 10) + ","
        "\"equity\":" + DoubleToString(equity, 2) + ","
        "\"features\":{"
           "\"symbol\":\"" + sym + "\","
           "\"bid\":" + DoubleToString(bid, 6) + ","
           "\"ask\":" + DoubleToString(ask, 6) +
        "}"
      "}";

   // Endpoint + headers
   string url = ORCH_ORCH_ApiBase + "/heartbeat";
   string headers =
      "Content-Type: application/json\r\n"
      "Authorization: Bearer " + ORCH_ORCH_ApiKey + "\r\n";

   // Convert to bytes (UTF-8) and REMOVE trailing NUL
   uchar data[];
   int n = StringToCharArray(payload, data, 0, WHOLE_ARRAY, CP_UTF8);
   if(n > 0) ArrayResize(data, n - 1);

   // Send
   uchar result[];
   string result_headers;
   ResetLastError();
   int rc = WebRequest("POST", url, headers, 5000, data, result, result_headers);

   if(rc == -1)
   {
      PrintFormat("[HB] WebRequest error=%d hdr=%s", GetLastError(), result_headers);
      return;
   }

   if(StringFind(result_headers, " 200 ") != -1 || StringFind(result_headers, " 201 ") != -1)
   {
      Print("[HB] OK");
   }
   else
   {
      PrintFormat("[HB] HTTP hdr=%s body=%s",
                  result_headers,
                  CharArrayToString(result, 0, ArraySize(result)));
   }
}
