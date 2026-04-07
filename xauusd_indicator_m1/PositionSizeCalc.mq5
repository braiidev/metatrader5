//+------------------------------------------------------------------+
//|                                            PositionSizeCalc.mq5  |
//|                                  Calculadora de Tamaño de Posición |
//+------------------------------------------------------------------+
#property copyright "Position Size Calculator"
#property version   "1.00"
#property description "Calcula el lote óptimo basado en riesgo %"

#include <Trade\Trade.mqh>

//--- Input parameters
input group "=== Risk Settings ==="
input double InpRiskPercent      = 1.0;     // Risk Per Trade (%)
input int    InpStopLossPips     = 50;      // Stop Loss (Pips)
input double InpManualEntryPrice = 0.0;     // Manual Entry Price (0=Current)
input double InpTakeProfitPips   = 0.0;     // Take Profit (Pips, 0=Disabled)

input group "=== Lot Settings ==="
input bool   InpRoundDown        = true;    // Round Lot Down (Conservative)
input int    InpLotDecimals      = 2;       // Lot Decimals

input group "=== Panel Settings ==="
input int    InpPanelX           = 10;      // Panel X Position
input int    InpPanelY           = 10;      // Panel Y Offset from Bottom
input color  InpBgColor         = clrBlack; // Background Color
input color  InpTextColor       = clrWhite; // Text Color
input color  InpGreenColor      = clrLime;  // Positive Color
input color  InpRedColor        = clrRed;   // Negative/Stop Color
input color  InpYellowColor     = clrYellow;// Warning Color
input int    InpFontSize        = 10;       // Font Size

//--- Global variables
string panelPrefix = "PSC_";
bool initialized = false;
bool panelVisible = true;

// Trade object
CTrade trade;

//+------------------------------------------------------------------+
//| Expert initialization function                                     |
//+------------------------------------------------------------------+
int OnInit()
{
   trade.SetExpertMagicNumber(123456);
   trade.SetDeviationInPoints(10);
   
   CreatePanel();
   initialized = true;
   
   return(INIT_SUCCEEDED);
}

//+------------------------------------------------------------------+
//| Expert deinitialization function                                   |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
{
   DeletePanel();
}

//+------------------------------------------------------------------+
//| Expert tick function                                               |
//+------------------------------------------------------------------+
void OnTick()
{
   if(!initialized || !panelVisible) return;
   UpdatePanel();
}

//+------------------------------------------------------------------+
//| Chart event handler                                                |
//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
{
   if(id == CHARTEVENT_KEYDOWN && lparam == 87)
   {
      TogglePanel();
   }
   
   if(id == CHARTEVENT_OBJECT_CLICK)
   {
      if(sparam == panelPrefix + "Btn_Buy")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         OpenTrade(ORDER_TYPE_BUY);
      }
      if(sparam == panelPrefix + "Btn_SELL")
      {
         ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
         OpenTrade(ORDER_TYPE_SELL);
      }
   }
}

//+------------------------------------------------------------------+
//| Toggle panel visibility                                            |
//+------------------------------------------------------------------+
void TogglePanel()
{
   panelVisible = !panelVisible;
   
   if(panelVisible)
   {
      DeletePanel();
      CreatePanel();
   }
   else
   {
      for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
      {
         string name = ObjectName(0, i, 0, -1);
         if(StringFind(name, panelPrefix) == 0)
            ObjectDelete(0, name);
      }
      CreateLabel(panelPrefix + "ShowHint", InpPanelX, InpPanelY, "[W] Show Panel", InpGreenColor, InpFontSize);
   }
}

//+------------------------------------------------------------------+
//| Calculate position size                                            |
//+------------------------------------------------------------------+
double CalculateLotSize(double stopLossPips, double &riskAmount, double &pipValue, double &riskPerPip)
{
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Risk amount in currency
   riskAmount = (balance * InpRiskPercent) / 100.0;
   
   // Get symbol info
   string symbol = _Symbol;
   double point = SymbolInfoDouble(symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(symbol, SYMBOL_DIGITS);
   double lotStep = SymbolInfoDouble(symbol, SYMBOL_VOLUME_STEP);
   double minLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MIN);
   double maxLot = SymbolInfoDouble(symbol, SYMBOL_VOLUME_MAX);
   
   // Calculate pip value
   double tickValue = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_VALUE);
   double tickSize = SymbolInfoDouble(symbol, SYMBOL_TRADE_TICK_SIZE);
   
   // Pip size depends on symbol type
   double pipSize = point;
   if(digits == 3 || digits == 5)
      pipSize = point * 10;
   
   // Pip value per 1 lot
   pipValue = (tickValue / tickSize) * pipSize;
   
   // Risk per pip
   riskPerPip = riskAmount / stopLossPips;
   
   // Calculate lot size
   double lotSize = riskPerPip / pipValue;
   
   // Round to lot step
   lotSize = MathFloor(lotSize / lotStep) * lotStep;
   
   // Apply rounding preference
   if(InpRoundDown)
   {
      double multiplier = MathPow(10, InpLotDecimals);
      lotSize = MathFloor(lotSize * multiplier) / multiplier;
   }
   
   // Clamp to min/max
   lotSize = MathMax(minLot, MathMin(maxLot, lotSize));
   
   return lotSize;
}

//+------------------------------------------------------------------+
//| Get current price                                                  |
//+------------------------------------------------------------------+
double GetEntryPrice(ENUM_ORDER_TYPE type)
{
   if(InpManualEntryPrice > 0)
      return InpManualEntryPrice;
   
   if(type == ORDER_TYPE_BUY)
      return SymbolInfoDouble(_Symbol, SYMBOL_ASK);
   else
      return SymbolInfoDouble(_Symbol, SYMBOL_BID);
}

//+------------------------------------------------------------------+
//| Calculate SL price                                                 |
//+------------------------------------------------------------------+
double CalculateSLPrice(ENUM_ORDER_TYPE type, double entryPrice)
{
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double pipSize = point;
   if(digits == 3 || digits == 5)
      pipSize = point * 10;
   
   double slDistance = InpStopLossPips * pipSize;
   
   if(type == ORDER_TYPE_BUY)
      return NormalizeDouble(entryPrice - slDistance, digits);
   else
      return NormalizeDouble(entryPrice + slDistance, digits);
}

//+------------------------------------------------------------------+
//| Calculate TP price                                                 |
//+------------------------------------------------------------------+
double CalculateTPPrice(ENUM_ORDER_TYPE type, double entryPrice)
{
   if(InpTakeProfitPips <= 0) return 0;
   
   double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   double pipSize = point;
   if(digits == 3 || digits == 5)
      pipSize = point * 10;
   
   double tpDistance = InpTakeProfitPips * pipSize;
   
   if(type == ORDER_TYPE_BUY)
      return NormalizeDouble(entryPrice + tpDistance, digits);
   else
      return NormalizeDouble(entryPrice - tpDistance, digits);
}

//+------------------------------------------------------------------+
//| Open trade with calculated size                                    |
//+------------------------------------------------------------------+
void OpenTrade(ENUM_ORDER_TYPE type)
{
   double riskAmount = 0, pipValue = 0, riskPerPip = 0;
   double lotSize = CalculateLotSize(InpStopLossPips, riskAmount, pipValue, riskPerPip);
   
   double entryPrice = GetEntryPrice(type);
   double slPrice = CalculateSLPrice(type, entryPrice);
   double tpPrice = CalculateTPPrice(type, entryPrice);
   
   // Normalize lot size
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   lotSize = NormalizeDouble(MathFloor(lotSize / lotStep) * lotStep, 2);
   
   if(lotSize < SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN))
   {
      Print("Position Size Calculator: Lot size too small");
      return;
   }
   
   bool result = false;
   if(type == ORDER_TYPE_BUY)
      result = trade.Buy(lotSize, _Symbol, entryPrice, slPrice, tpPrice > 0 ? tpPrice : 0);
   else
      result = trade.Sell(lotSize, _Symbol, entryPrice, slPrice, tpPrice > 0 ? tpPrice : 0);
   
   if(result)
      Print("Position Size Calculator: Order opened - ", DoubleToString(lotSize, 2), " lots");
   else
      Print("Position Size Calculator: Order failed - ", trade.ResultRetcodeDescription());
}

//+------------------------------------------------------------------+
//| Create the panel objects                                           |
//+------------------------------------------------------------------+
void CreatePanel()
{
   DeletePanel();
   
   int startY = InpPanelY;
   int x = InpPanelX;
   
   // Header
   CreateLabel(panelPrefix + "BG_Bottom", x, startY, "═══════════════════════════════════", InpBgColor, InpFontSize);
   CreateLabel(panelPrefix + "Header", x, startY + 15, "═══ POSITION SIZE CALC ═══", InpYellowColor, InpFontSize);
   
   // Inputs section
   CreateLabel(panelPrefix + "Lbl_Symbol", x, startY + 32, "Symbol:", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_Balance", x, startY + 47, "Balance:", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_RiskPct", x, startY + 62, "Risk %:", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_SL", x, startY + 77, "Stop Loss:", InpTextColor, InpFontSize);
   
   CreateLabel(panelPrefix + "Sep1", x, startY + 87, "───────────────────────────────", InpTextColor, InpFontSize);
   
   // Results section
   CreateLabel(panelPrefix + "Lbl_RiskAmt", x, startY + 102, "Risk Amount:", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_PipVal", x, startY + 117, "Pip Value (1 lot):", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_RiskPerPip", x, startY + 132, "Risk/Pip:", InpTextColor, InpFontSize);
   
   CreateLabel(panelPrefix + "Lbl_LotSize", x, startY + 152, "Lot Size:", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_Entry", x, startY + 167, "Entry Price:", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_SLPrice", x, startY + 182, "SL Price:", InpTextColor, InpFontSize);
   CreateLabel(panelPrefix + "Lbl_TPPrice", x, startY + 197, "TP Price:", InpTextColor, InpFontSize);
   
   CreateLabel(panelPrefix + "Sep2", x, startY + 207, "───────────────────────────────", InpTextColor, InpFontSize);
   
   // Trade buttons
   CreateButton(panelPrefix + "Btn_BUY", x, startY + 222, "BUY", InpGreenColor, InpFontSize);
   CreateButton(panelPrefix + "Btn_SELL", x + 120, startY + 222, "SELL", InpRedColor, InpFontSize);
   
   // Footer
   CreateLabel(panelPrefix + "BG_Top", x, startY + 245, "═══════════════════════════════════", InpBgColor, InpFontSize);
   CreateLabel(panelPrefix + "ToggleHint", x + 220, startY + 245, "[W]", InpTextColor, InpFontSize);
}

//+------------------------------------------------------------------+
//| Update panel with current values                                   |
//+------------------------------------------------------------------+
void UpdatePanel()
{
   int startY = InpPanelY;
   int x = InpPanelX;
   
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   
   // Calculate values
   double riskAmount = 0, pipValue = 0, riskPerPip = 0;
   double lotSize = CalculateLotSize(InpStopLossPips, riskAmount, pipValue, riskPerPip);
   
   double buyEntry = GetEntryPrice(ORDER_TYPE_BUY);
   double sellEntry = GetEntryPrice(ORDER_TYPE_SELL);
   double buySL = CalculateSLPrice(ORDER_TYPE_BUY, buyEntry);
   double sellSL = CalculateSLPrice(ORDER_TYPE_SELL, sellEntry);
   double buyTP = CalculateTPPrice(ORDER_TYPE_BUY, buyEntry);
   double sellTP = CalculateTPPrice(ORDER_TYPE_SELL, sellEntry);
   
   int digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   
   // Update values
   UpdateLabel(panelPrefix + "Val_Symbol", x + 120, startY + 32, _Symbol, InpTextColor);
   UpdateLabel(panelPrefix + "Val_Balance", x + 120, startY + 47, DoubleToString(balance, 2), InpTextColor);
   UpdateLabel(panelPrefix + "Val_RiskPct", x + 120, startY + 62, DoubleToString(InpRiskPercent, 2) + "%", InpYellowColor);
   UpdateLabel(panelPrefix + "Val_SL", x + 120, startY + 77, IntegerToString(InpStopLossPips) + " pips", InpRedColor);
   
   UpdateLabel(panelPrefix + "Val_RiskAmt", x + 120, startY + 102, "$" + DoubleToString(riskAmount, 2), InpRedColor);
   UpdateLabel(panelPrefix + "Val_PipVal", x + 120, startY + 117, "$" + DoubleToString(pipValue, 2), InpTextColor);
   UpdateLabel(panelPrefix + "Val_RiskPerPip", x + 120, startY + 132, "$" + DoubleToString(riskPerPip, 2), InpTextColor);
   
   UpdateLabel(panelPrefix + "Val_LotSize", x + 120, startY + 152, DoubleToString(lotSize, 2) + " lots", InpGreenColor);
   
   // Buy side
   UpdateLabel(panelPrefix + "Val_Entry", x + 120, startY + 167, "B:" + DoubleToString(buyEntry, digits) + " / S:" + DoubleToString(sellEntry, digits), InpTextColor);
   UpdateLabel(panelPrefix + "Val_SLPrice", x + 120, startY + 182, "B:" + DoubleToString(buySL, digits) + " / S:" + DoubleToString(sellSL, digits), InpRedColor);
   
   if(InpTakeProfitPips > 0)
   {
      UpdateLabel(panelPrefix + "Val_TPPrice", x + 120, startY + 197, "B:" + DoubleToString(buyTP, digits) + " / S:" + DoubleToString(sellTP, digits), InpGreenColor);
   }
   else
   {
      UpdateLabel(panelPrefix + "Val_TPPrice", x + 120, startY + 197, "Disabled", InpTextColor);
   }
}

//+------------------------------------------------------------------+
//| Create a text label                                                |
//+------------------------------------------------------------------+
void CreateLabel(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_LABEL, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Consolas");
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   }
}

//+------------------------------------------------------------------+
//| Update or create a label                                           |
//+------------------------------------------------------------------+
void UpdateLabel(string name, int x, int y, string text, color clr)
{
   if(ObjectFind(0, name) < 0)
   {
      CreateLabel(name, x, y, text, clr, InpFontSize);
   }
   else
   {
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
   }
}

//+------------------------------------------------------------------+
//| Create a clickable button                                          |
//+------------------------------------------------------------------+
void CreateButton(string name, int x, int y, string text, color clr, int fontSize)
{
   if(ObjectFind(0, name) < 0)
   {
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, y);
      ObjectSetInteger(0, name, OBJPROP_XSIZE, 100);
      ObjectSetInteger(0, name, OBJPROP_YSIZE, 22);
      ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_LOWER);
      ObjectSetInteger(0, name, OBJPROP_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_BGCOLOR, clrBlack);
      ObjectSetInteger(0, name, OBJPROP_BORDER_COLOR, clr);
      ObjectSetInteger(0, name, OBJPROP_FONTSIZE, fontSize);
      ObjectSetString(0, name, OBJPROP_FONT, "Arial Bold");
      ObjectSetString(0, name, OBJPROP_TEXT, text);
      ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
   }
}

//+------------------------------------------------------------------+
//| Delete all panel objects                                           |
//+------------------------------------------------------------------+
void DeletePanel()
{
   for(int i = ObjectsTotal(0, 0, -1) - 1; i >= 0; i--)
   {
      string name = ObjectName(0, i, 0, -1);
      if(StringFind(name, panelPrefix) == 0)
         ObjectDelete(0, name);
   }
}
//+------------------------------------------------------------------+
