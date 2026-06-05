//+------------------------------------------------------------------+
//|                                           DrawingToolbox.mq5     |
//|                                                  Braiidev (mod)  |
//+------------------------------------------------------------------+
#property indicator_chart_window
#property indicator_plots 0
#property description "Drawing Toolbox: HLine, VLine, Trend, Rect, Text, Dot, Fibo zone, HProj."
#property description "Motions:\n [w][Shift-w] line-width | [s] line-style | [c] line-color | [r] line-right-ray\n [x] angled 0 level-line | [y] copy selected line | [p] paste selected line\n [ESC] cancel action"


//--- Keyboard: W=width, C=color, S=style, R=ray toggle, X=horizontal, D=desc cycle, Y=copy, P=paste, ESC=cancel ---
input group "--- Toolbox ---"
input color  InpButtonColor    = clrDimGray;
input color  InpActiveColor    = clrDarkOrange;
input color  InpClearBtnColor  = clrMaroon;
input int    InpButtonSize     = 30;
input int    InpButtonSpacing  = 3;
input int    InpPanelX         = 10;   // X from left
input int    InpPanelY         = 10;   // Y from bottom

input group "--- Drawing Style ---"
input color  InpDrawColor      = clrDarkOrange;
input int    InpDrawWidth      = 1;
input ENUM_LINE_STYLE InpDrawStyle = STYLE_SOLID;
input int    InpArrowCode      = 159;
input int    InpArrowSize      = 3;

input group "--- Fibo Levels ---"
input color  InpFiboSellColor  = clrDarkRed;
input color  InpFiboMidColor   = clrGhostWhite;
input color  InpFiboBuyColor   = clrDarkGreen;

//--- Archivo de persistencia (guarda/restaura estado entre sesiones MT5)
#define SETTINGS_FILE "DrawingToolbox_settings.txt"

//=== VARIABLES GLOBALES ===//
string buttons[]        = {"HLine", "VLine", "Trend", "Rect", "Text", "Dot", "Fibo", "HProj", "ClearAll", "Show"};
string button_labels[]  = {"-", "|", "/", "#", "TXT", ".", "%", "→", "C", "<<"};
string active_tool      = "";
int    click_count      = 0;
datetime first_time;
double first_price;
bool   SwitchToolbox    = true;

int    panel_x          = 0;
int    panel_y          = 0;

//=== COPY/PASTE ===//
bool   g_copy_mode = false;
string g_selected_obj = "";
string g_copied_obj_name = "";
int    g_copied_type = -1;
double g_copied_p1 = 0, g_copied_p2 = 0;
datetime g_copied_t1 = 0, g_copied_t2 = 0;
string g_copied_text = "";
int    g_copied_arrow = 159;
color  g_copied_color = clrDarkOrange;
int    g_copied_width = 1;
ENUM_LINE_STYLE g_copied_style = STYLE_SOLID;

//=== EDIT PALETTE ===//
color g_palette[] = {clrDarkOrange, clrRed, clrLime, clrBlue, clrYellow, clrWhite, clrCyan, clrMagenta, clrGray, clrGoldenrod};

//=== DESCRIPTION CYCLER ===//
string g_desc_cycle[] = {"", "AA", "BB", "AB", "BA", "BoS", "CHoCH"};
string g_desc_cycle_rect[] = {"", "OB", "FVG", "iFVG", "RANGE"};

//+------------------------------------------------------------------+
int OnInit()
 {
  int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
  int btn_total    = ArraySize(buttons);
  int total_height = btn_total * (InpButtonSize + InpButtonSpacing);

  panel_x = InpPanelX;
  panel_y = chart_height - total_height - InpPanelY;

  // Clean stale objects from previous versions
  int ot = ObjectsTotal(0);
  for(int i=ot-1; i>=0; i--)
   {
    string nm = ObjectName(0, i);
    if(StringFind(nm, "TB_TXT_") == 0 || StringFind(nm, "TB_DESC_") == 0)
      ObjectDelete(0, nm);
   }

  CreatePanel();

  // Restaura visibilidad del toolbox
  LoadSettings();
  if(!SwitchToolbox)
  {
   for(int k=0; k<ArraySize(buttons); k++)
    {
     if(buttons[k] != "Show")
      {
       ObjectSetInteger(0, buttons[k], OBJPROP_XDISTANCE, -1000);
       ObjectSetInteger(0, buttons[k], OBJPROP_YDISTANCE, -1000);
      }
    }
   ObjectSetString(0, "Show", OBJPROP_TEXT, ButtonLabel("Show"));
   ObjectSetString(0, "Show", OBJPROP_TOOLTIP, SwitchToolbox ? "Hide toolbox" : "Show toolbox");
  }

  ChartRedraw();
  return(INIT_SUCCEEDED);
 }

//+------------------------------------------------------------------+
void OnDeinit(const int reason)
 {
  SaveSettings();
  for(int i=0; i<ArraySize(buttons); i++)
    ObjectDelete(0, buttons[i]);
 }

//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime& time[],
                const double& open[],
                const double& high[],
                const double& low[],
                const double& close[],
                const long& tick_volume[],
                const long& volume[],
                const int& spread[])
 {
  return(rates_total);
 }

//+------------------------------------------------------------------+
//| Guarda visibilidad del toolbox                                    |
//+------------------------------------------------------------------+
void SaveSettings()
{
   int handle = FileOpen(SETTINGS_FILE, FILE_TXT|FILE_CSV|FILE_WRITE, ",");
   if(handle == INVALID_HANDLE) return;

   FileWrite(handle, SwitchToolbox);

   FileClose(handle);
}

//+------------------------------------------------------------------+
//| Restaura visibilidad del toolbox                                  |
//+------------------------------------------------------------------+
void LoadSettings()
{
   int handle = FileOpen(SETTINGS_FILE, FILE_TXT|FILE_CSV|FILE_READ, ",");
   if(handle == INVALID_HANDLE) return;

   SwitchToolbox = (bool)FileReadNumber(handle);

   FileClose(handle);
}

//+------------------------------------------------------------------+
void CreatePanel()
 {
  int btn_total    = ArraySize(buttons);
  int total_height = btn_total * (InpButtonSize + InpButtonSpacing);

  for(int b=0; b<btn_total; b++)
    ObjectDelete(0, buttons[b]);

  for(int i=0; i<btn_total; i++)
   {
    string name = buttons[i];
    if(!ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0))
     {
      ObjectDelete(0, name);
      ObjectCreate(0, name, OBJ_BUTTON, 0, 0, 0);
     }

    ObjectSetInteger(0, name, OBJPROP_CORNER, CORNER_LEFT_UPPER);
    ObjectSetInteger(0, name, OBJPROP_XDISTANCE, panel_x);
    ObjectSetInteger(0, name, OBJPROP_YDISTANCE, panel_y + i*(InpButtonSize+InpButtonSpacing));
    ObjectSetInteger(0, name, OBJPROP_XSIZE, InpButtonSize);
    ObjectSetInteger(0, name, OBJPROP_YSIZE, InpButtonSize);
    ObjectSetInteger(0, name, OBJPROP_BORDER_TYPE, BORDER_FLAT);

    ObjectSetInteger(0, name, OBJPROP_BGCOLOR, ButtonBgColor(name));
    ObjectSetInteger(0, name, OBJPROP_COLOR, clrWhite);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 10);
    ObjectSetString(0, name, OBJPROP_TEXT, ButtonLabel(name));
    ObjectSetString(0, name, OBJPROP_TOOLTIP, ButtonTooltip(name));
   }
 }

//+------------------------------------------------------------------+
void MovePanel(int new_x, int new_y)
 {
  int btn_total = ArraySize(buttons);

  for(int i=0; i<btn_total; i++)
   {
    string name = buttons[i];
    if(ObjectFind(0, name) >= 0)
     {
      ObjectSetInteger(0, name, OBJPROP_XDISTANCE, new_x);
      ObjectSetInteger(0, name, OBJPROP_YDISTANCE, new_y + i*(InpButtonSize+InpButtonSpacing));
     }
   }

  panel_x = new_x;
  panel_y = new_y;
 }

//+------------------------------------------------------------------+
string ButtonLabel(string name)
 {
  if(name == "Show")
    return SwitchToolbox ? ShortToString(0x2193) : ShortToString(0x2191);
  for(int i=0; i<ArraySize(buttons); i++)
   {
    if(buttons[i] == name)
      return button_labels[i];
   }
  return "";
 }

//+------------------------------------------------------------------+
color ButtonBgColor(string name)
 {
  if(name == "ClearAll") return InpClearBtnColor;
  return InpButtonColor;
 }

//+------------------------------------------------------------------+
string ButtonTooltip(string name)
 {
  if(name == "Trend")  return "Trend line (2 clicks)";
  if(name == "Rect")   return "Rectangle (2 clicks)";
  if(name == "Fibo")   return "Premium/Discount zone (2 clicks)";
  if(name == "HProj")  return "Horizontal projection (6 candles right)";
  if(name == "ClearAll") return "Clear chart";
  if(name == "Show")   return SwitchToolbox ? "Hide toolbox" : "Show toolbox";
  if(name == "HLine")  return "Horizontal line";
  if(name == "VLine")  return "Vertical line";
  if(name == "Text")   return "Textbox";
  if(name == "Dot")    return "Dot";
  return "";
 }

//+------------------------------------------------------------------+
void ResetButtonColor(int i)
 {
  string name = buttons[i];
  ObjectSetInteger(0, name, OBJPROP_BGCOLOR, ButtonBgColor(name));
  ObjectSetString(0, name, OBJPROP_TEXT, ButtonLabel(name));
  ObjectSetInteger(0, name, OBJPROP_STATE, false);
 }

//+------------------------------------------------------------------+
bool IsInsidePanel(int x, int y)
 {
  int btn_total    = ArraySize(buttons);
  int total_height = btn_total * (InpButtonSize + InpButtonSpacing);

  return (x >= panel_x && x <= panel_x + InpButtonSize &&
          y >= panel_y && y <= panel_y + total_height);
 }

//+------------------------------------------------------------------+
void OnChartEvent(const int id, const long &lparam, const double &dparam, const string &sparam)
  {
// --- Recentrar si cambia tamanio del grafico ---
  if(id == CHARTEVENT_CHART_CHANGE)
   {
    if(SwitchToolbox)
     {
      int chart_height = (int)ChartGetInteger(0, CHART_HEIGHT_IN_PIXELS);
      int btn_total    = ArraySize(buttons);
      int total_height = btn_total * (InpButtonSize + InpButtonSpacing);
      MovePanel(panel_x, chart_height - total_height - InpPanelY);
     }
    ChartRedraw();
    return;
   }

// --- Teclas ---
  if(id == CHARTEVENT_KEYDOWN)
   {
    int key = (int)lparam;

    // ESC → cancela tool activa
    if(key == 27)
     {
      if(active_tool != "")
       {
        ResetToolState();
        ChartRedraw();
       }
      return;
     }

    // C → ciclo color (requiere objeto seleccionado)
    if(key == 67 && g_selected_obj != "" && ObjectFind(0, g_selected_obj) >= 0)
     {
      EditSelectedObjectColor(g_selected_obj);
      ChartRedraw();
      Print("Color changed: ", g_selected_obj);
      return;
     }

    // W → aumentar width (Shift+W → disminuir)
    if(key == 87 && g_selected_obj != "" && ObjectFind(0, g_selected_obj) >= 0)
     {
      int delta = TerminalInfoInteger(TERMINAL_KEYSTATE_SHIFT) ? -1 : 1;
      EditSelectedObjectWidth(g_selected_obj, delta);
      ChartRedraw();
      Print("Width changed: ", g_selected_obj);
      return;
     }

    // S → ciclo line style
    if(key == 83 && g_selected_obj != "" && ObjectFind(0, g_selected_obj) >= 0)
     {
      EditSelectedObjectStyle(g_selected_obj);
      ChartRedraw();
      Print("Style changed: ", g_selected_obj);
      return;
     }

    // D → cycle description label
    if(key == 68 && g_selected_obj != "" && ObjectFind(0, g_selected_obj) >= 0)
     {
      CycleObjectDescription(g_selected_obj);
      ChartRedraw();
      return;
     }

    // R → toggle ray right (only for trendlines)
    if(key == 82 && g_selected_obj != "" && ObjectFind(0, g_selected_obj) >= 0)
     {
      ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(0, g_selected_obj, OBJPROP_TYPE);
      if(otype == OBJ_TREND)
       {
        bool ray = ObjectGetInteger(0, g_selected_obj, OBJPROP_RAY_RIGHT);
        ObjectSetInteger(0, g_selected_obj, OBJPROP_RAY_RIGHT, !ray);
        Print("Ray right: ", g_selected_obj, " = ", !ray);
       }
      ChartRedraw();
      return;
     }

    // X → force horizontal (price2 = price1) for 2-point objects
    if(key == 88 && g_selected_obj != "" && ObjectFind(0, g_selected_obj) >= 0)
     {
      ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(0, g_selected_obj, OBJPROP_TYPE);
      if(otype == OBJ_TREND || otype == OBJ_RECTANGLE || otype == OBJ_FIBO)
       {
        double p1 = ObjectGetDouble(0, g_selected_obj, OBJPROP_PRICE, 0);
        ObjectSetDouble(0, g_selected_obj, OBJPROP_PRICE, 1, p1);
        Print("Horizontal: ", g_selected_obj);
       }
      ChartRedraw();
      return;
     }

    // Y → copy selected object
    if(key == 89 && g_selected_obj != "" && ObjectFind(0, g_selected_obj) >= 0)
     {
      CopySelectedObject();
      ChartRedraw();
      Print("Copied: ", g_selected_obj);
      return;
     }

    // P → paste (at right edge of chart)
    if(key == 80 && g_copy_mode && g_copied_obj_name != "")
     {
      datetime paste_time = iTime(_Symbol, PERIOD_CURRENT, 0);
      if(paste_time <= 0) paste_time = TimeCurrent();
      else paste_time += PeriodSeconds() * 3;
      PasteObject(paste_time, g_copied_p1);
      g_copy_mode = false;
      g_copied_obj_name = "";
      g_copied_type = -1;
      ResetToolState();
      ChartRedraw();
      Print("Pasted at right edge");
      return;
     }
   }

// --- Clic en un boton ---
  if(id == CHARTEVENT_OBJECT_CLICK)
   {
// --- Click on a TB_ drawing object → select it for copy ---
    if(StringFind(sparam, "TB_") == 0)
     {
      g_selected_obj = sparam;
      ObjectSetInteger(0, sparam, OBJPROP_STATE, false);
      return;
     }

    for(int i=0; i<ArraySize(buttons); i++)
     {
      if(sparam != buttons[i]) continue;

// Boton ClearAll
      if(sparam == "ClearAll")
       {
        ClearAllDrawings();
        ResetToolState();
        Print("Todos los objetos TB_ eliminados.");
        return;
       }

// Boton Show
      if(sparam == "Show")
       {
        SwitchToolbox = !SwitchToolbox;

        if(!SwitchToolbox)
         {
          for(int k=0; k<ArraySize(buttons); k++)
           {
            if(buttons[k] != "Show")
             {
              ObjectSetInteger(0, buttons[k], OBJPROP_XDISTANCE, -1000);
              ObjectSetInteger(0, buttons[k], OBJPROP_YDISTANCE, -1000);
             }
           }
         }
        else
         {
          MovePanel(panel_x, panel_y);
         }

        ObjectSetString(0, "Show", OBJPROP_TEXT, ButtonLabel("Show"));
        ObjectSetString(0, "Show", OBJPROP_TOOLTIP, SwitchToolbox ? "Hide toolbox" : "Show toolbox");
        ChartRedraw();
        return;
       }

// Seleccion de herramienta
      if(click_count > 0)
       {
        click_count = 0;
        active_tool = "";
       }

      active_tool   = buttons[i];
      click_count   = 0;
      first_time    = 0;
      first_price   = 0;

      // If entering a drawing tool, cancel copy/paste
      g_copy_mode = false;
      g_copied_obj_name = "";
      g_selected_obj = "";

      for(int j=0; j<ArraySize(buttons); j++)
       {
        if(j == i)
         {
          ObjectSetInteger(0, buttons[j], OBJPROP_BGCOLOR, InpActiveColor);
          ObjectSetInteger(0, buttons[j], OBJPROP_STATE, true);
         }
        else
         {
          ResetButtonColor(j);
         }
       }
      ChartRedraw();
      return;
     }
   }

// --- Clic en el grafico ---
  if(id == CHARTEVENT_CLICK)
   {
    int x = (int)lparam;
    int y = (int)dparam;

    if(SwitchToolbox && IsInsidePanel(x, y))
      return;

    datetime click_time;
    double click_price;
    int subwindow = 0;

    if(!ChartXYToTimePrice(0, x, y, subwindow, click_time, click_price))
      return;

// --- Paste mode ---
    if(g_copy_mode && g_copied_obj_name != "")
     {
      PasteObject(click_time, click_price);
      g_copy_mode = false;
      g_copied_obj_name = "";
      g_copied_type = -1;
      ResetToolState();
      ChartRedraw();
      return;
     }

    if(active_tool == "")
      return;

    if(active_tool == "Trend" || active_tool == "Rect" || active_tool == "Fibo")
     {
      if(click_count == 0)
       {
        first_time  = click_time;
        first_price = click_price;
        click_count = 1;
       }
      else
       {
        DrawTwoPointObject(active_tool, first_time, first_price, click_time, click_price);
        ResetToolState();
       }
      ChartRedraw();
      return;
     }

    DrawOnePointObject(active_tool, click_time, click_price);
    ResetToolState();
    ChartRedraw();
   }
 }

//+------------------------------------------------------------------+
void CopySelectedObject()
 {
  if(g_selected_obj == "") return;
  if(ObjectFind(0, g_selected_obj) < 0) { g_selected_obj = ""; return; }

  g_copied_type = (int)ObjectGetInteger(0, g_selected_obj, OBJPROP_TYPE);
  g_copied_color = (color)ObjectGetInteger(0, g_selected_obj, OBJPROP_COLOR);
  g_copied_width = (int)ObjectGetInteger(0, g_selected_obj, OBJPROP_WIDTH);
  g_copied_style = (ENUM_LINE_STYLE)ObjectGetInteger(0, g_selected_obj, OBJPROP_STYLE);

  g_copied_t1 = (datetime)ObjectGetInteger(0, g_selected_obj, OBJPROP_TIME, 0);
  g_copied_p1 = ObjectGetDouble(0, g_selected_obj, OBJPROP_PRICE, 0);

  // 2-point objects
  ENUM_OBJECT type = (ENUM_OBJECT)g_copied_type;
  if(type == OBJ_TREND || type == OBJ_RECTANGLE || type == OBJ_FIBO)
   {
    g_copied_t2 = (datetime)ObjectGetInteger(0, g_selected_obj, OBJPROP_TIME, 1);
    g_copied_p2 = ObjectGetDouble(0, g_selected_obj, OBJPROP_PRICE, 1);
   }
  else
   {
    g_copied_t2 = g_copied_t1;
    g_copied_p2 = g_copied_p1;
   }

  // Text content
  if(type == OBJ_TEXT)
    g_copied_text = ObjectGetString(0, g_selected_obj, OBJPROP_TEXT);

  // Arrow code
  if(type == OBJ_ARROW)
    g_copied_arrow = (int)ObjectGetInteger(0, g_selected_obj, OBJPROP_ARROWCODE);

  g_copy_mode = true;
  g_copied_obj_name = g_selected_obj;
  Print("Copied: ", g_selected_obj);
 }

//+------------------------------------------------------------------+
void PasteObject(datetime t, double p)
 {
  if(g_copied_obj_name == "") return;

  ENUM_OBJECT type = (ENUM_OBJECT)g_copied_type;
  string new_name = StringFormat("TB_%s_%d", EnumToString(type), TimeLocal());
  StringReplace(new_name, "OBJ_", "");

  datetime t1 = t;
  double p1 = p;
  datetime t2 = t + (g_copied_t2 - g_copied_t1);
  double p2 = p + (g_copied_p2 - g_copied_p1);

  if(type == OBJ_HLINE)
   {
    ObjectCreate(0, new_name, OBJ_HLINE, 0, 0, p1);
   }
  else if(type == OBJ_VLINE)
   {
    ObjectCreate(0, new_name, OBJ_VLINE, 0, t1, 0);
   }
  else if(type == OBJ_TEXT)
   {
    ObjectCreate(0, new_name, OBJ_TEXT, 0, t1, p1);
    ObjectSetString(0, new_name, OBJPROP_TEXT, g_copied_text);
   }
  else if(type == OBJ_ARROW)
   {
    ObjectCreate(0, new_name, OBJ_ARROW, 0, t1, p1);
    ObjectSetInteger(0, new_name, OBJPROP_ARROWCODE, g_copied_arrow);
   }
  else if(type == OBJ_TREND)
   {
    ObjectCreate(0, new_name, OBJ_TREND, 0, t1, p1, t2, p2);
   }
  else if(type == OBJ_RECTANGLE)
   {
    ObjectCreate(0, new_name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
   }
  else if(type == OBJ_FIBO)
   {
    ObjectCreate(0, new_name, OBJ_FIBO, 0, t1, p1, t2, p2);
    // Copy fibo levels
    int levels = (int)ObjectGetInteger(0, g_copied_obj_name, OBJPROP_LEVELS);
    ObjectSetInteger(0, new_name, OBJPROP_LEVELS, levels);
    for(int lv = 0; lv < levels; lv++)
     {
      double val = ObjectGetDouble(0, g_copied_obj_name, OBJPROP_LEVELVALUE, lv);
      color lc = (color)ObjectGetInteger(0, g_copied_obj_name, OBJPROP_LEVELCOLOR, lv);
      ENUM_LINE_STYLE ls = (ENUM_LINE_STYLE)ObjectGetInteger(0, g_copied_obj_name, OBJPROP_LEVELSTYLE, lv);
      int lw = (int)ObjectGetInteger(0, g_copied_obj_name, OBJPROP_LEVELWIDTH, lv);
      string lt = ObjectGetString(0, g_copied_obj_name, OBJPROP_LEVELTEXT, lv);
      ObjectSetDouble(0, new_name, OBJPROP_LEVELVALUE, lv, val);
      ObjectSetInteger(0, new_name, OBJPROP_LEVELCOLOR, lv, lc);
      ObjectSetInteger(0, new_name, OBJPROP_LEVELSTYLE, lv, ls);
      ObjectSetInteger(0, new_name, OBJPROP_LEVELWIDTH, lv, lw);
      ObjectSetString(0, new_name, OBJPROP_LEVELTEXT, lv, lt);
     }
   }
  else
   {
    Print("Cannot paste object type: ", type);
    return;
   }

  ApplyCommonStyle(new_name);
  Print("Pasted: ", new_name);
 }

//+------------------------------------------------------------------+
void ResetToolState()
 {
  active_tool = "";
  click_count = 0;
  first_time  = 0;
  first_price = 0;

  for(int i=0; i<ArraySize(buttons); i++)
   {
    ResetButtonColor(i);
    ObjectSetInteger(0, buttons[i], OBJPROP_STATE, false);
   }
 }

//+------------------------------------------------------------------+
void DrawOnePointObject(string tool, datetime t, double p)
 {
  string name = StringFormat("TB_%s_%d", tool, TimeLocal());

  if(tool == "HLine")
    ObjectCreate(0, name, OBJ_HLINE, 0, 0, p);
  else if(tool == "VLine")
    ObjectCreate(0, name, OBJ_VLINE, 0, t, 0);
  else if(tool == "Text")
   {
     ObjectCreate(0, name, OBJ_TEXT, 0, t, p);
     ObjectSetString(0, name, OBJPROP_TEXT, DoubleToString(p, _Digits));
   }
  else if(tool == "Dot")
   {
    ObjectCreate(0, name, OBJ_ARROW, 0, t, p);
    ObjectSetInteger(0, name, OBJPROP_ARROWCODE, InpArrowCode);
    ObjectSetInteger(0, name, OBJPROP_FONTSIZE, InpArrowSize);
   }
  else if(tool == "HProj")
   {
    datetime t2 = t + PeriodSeconds() * 10;
    ObjectCreate(0, name, OBJ_TREND, 0, t, p, t2, p);
    ObjectSetInteger(0, name, OBJPROP_RAY_RIGHT, false);
   }
  else
    return;

  ApplyCommonStyle(name);
 }

//+------------------------------------------------------------------+
void DrawTwoPointObject(string tool, datetime t1, double p1, datetime t2, double p2)
 {
  string name = StringFormat("TB_%s_%d", tool, TimeLocal());

  if(tool == "Trend")
    ObjectCreate(0, name, OBJ_TREND, 0, t1, p1, t2, p2);
  else if(tool == "Rect")
    ObjectCreate(0, name, OBJ_RECTANGLE, 0, t1, p1, t2, p2);
  else if(tool == "Fibo")
   {
    ObjectCreate(0, name, OBJ_FIBO, 0, t1, p1, t2, p2);
    ObjectSetInteger(0, name, OBJPROP_LEVELS, 3);

    ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 0, 0);
    ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 0, InpFiboSellColor);
    ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 0, InpDrawStyle);
    ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 0, InpDrawWidth);
    ObjectSetString(0, name, OBJPROP_LEVELTEXT,  0, "SellZone");

    ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 1, 0.5);
    ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 1, InpFiboMidColor);
    ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 1, InpDrawStyle);
    ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 1, InpDrawWidth);
    ObjectSetString(0, name, OBJPROP_LEVELTEXT,  1, "50%%");

    ObjectSetDouble(0, name, OBJPROP_LEVELVALUE, 2, 1);
    ObjectSetInteger(0, name, OBJPROP_LEVELCOLOR, 2, InpFiboBuyColor);
    ObjectSetInteger(0, name, OBJPROP_LEVELSTYLE, 2, InpDrawStyle);
    ObjectSetInteger(0, name, OBJPROP_LEVELWIDTH, 2, InpDrawWidth);
    ObjectSetString(0, name, OBJPROP_LEVELTEXT,  2, "BuyZone");
   }
  else
    return;

  ApplyCommonStyle(name);
 }

//+------------------------------------------------------------------+
void ApplyCommonStyle(string name)
 {
  if(ObjectFind(0, name) == -1)
    return;

  ObjectSetInteger(0, name, OBJPROP_STYLE, InpDrawStyle);
  ObjectSetInteger(0, name, OBJPROP_COLOR, InpDrawColor);
  ObjectSetInteger(0, name, OBJPROP_WIDTH, InpDrawWidth);
  ObjectSetInteger(0, name, OBJPROP_SELECTABLE, true);
  ObjectSetInteger(0, name, OBJPROP_SELECTED, true);
  ObjectSetInteger(0, name, OBJPROP_HIDDEN, false);
  ObjectSetInteger(0, name, OBJPROP_BACK, false);
 }

//+------------------------------------------------------------------+
void ClearAllDrawings()
 {
  int total = ObjectsTotal(0);
  for(int i = total - 1; i >= 0; i--)
   {
    string name = ObjectName(0, i);
    if(StringFind(name, "TB_") == 0)
      ObjectDelete(0, name);
   }
  g_selected_obj = "";
  g_copy_mode = false;
  g_copied_obj_name = "";
  ChartRedraw();
 }

//+------------------------------------------------------------------+
void EditSelectedObjectColor(string name)
 {
  color current = (color)ObjectGetInteger(0, name, OBJPROP_COLOR);
  int idx = -1;
  int total = ArraySize(g_palette);
  for(int i=0; i<total; i++)
   {
    if(g_palette[i] == current) { idx = i; break; }
   }
  int next = (idx + 1) % total;
  ObjectSetInteger(0, name, OBJPROP_COLOR, g_palette[next]);
 }

//+------------------------------------------------------------------+
void EditSelectedObjectWidth(string name, int delta)
 {
  int w = (int)ObjectGetInteger(0, name, OBJPROP_WIDTH);
  w += delta;
  if(w < 1) w = 1;
  if(w > 5) w = 5;
  ObjectSetInteger(0, name, OBJPROP_WIDTH, w);
 }

//+------------------------------------------------------------------+
void EditSelectedObjectStyle(string name)
 {
  int s = (int)ObjectGetInteger(0, name, OBJPROP_STYLE);
  s++;
  if(s > 4) s = 0;
  ObjectSetInteger(0, name, OBJPROP_STYLE, s);
 }

//+------------------------------------------------------------------+
void CycleObjectDescription(string obj_name)
  {
   string cycle[];
   ENUM_OBJECT otype = (ENUM_OBJECT)ObjectGetInteger(0, obj_name, OBJPROP_TYPE);
   if(otype == OBJ_RECTANGLE)
      ArrayCopy(cycle, g_desc_cycle_rect);
   else
      ArrayCopy(cycle, g_desc_cycle);

   int total = ArraySize(cycle);
   int idx = 0;

   // Read current OBJPROP_TEXT to find index
   string cur = ObjectGetString(0, obj_name, OBJPROP_TEXT);
   for(int i=0; i<total; i++)
    { if(cycle[i] == cur) { idx = (i+1) % total; break; } }

   string new_text = cycle[idx];
   ObjectSetString(0, obj_name, OBJPROP_TEXT, new_text);
   Print("Desc: ", obj_name, " = ", new_text == "" ? "(empty)" : new_text);
  }

//+------------------------------------------------------------------+
