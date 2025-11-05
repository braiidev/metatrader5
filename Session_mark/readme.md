# 🕒 Session Mark — Indicador para MetaTrader 5

**Autor:** Braiidev  
**Versión:** 1.25  
**Plataforma:** MetaTrader 5  
**Archivo:** `Session Mark.mq5`

---

## 📌 Descripción

**Session Mark** es un indicador visual diseñado para marcar automáticamente:

- Líneas verticales diarias (separadores de sesión).  
- Aperturas de las principales sesiones del mercado: **Tokio, Londres y NYSE**.  
- Rangos diarios (`High` / `Low`) de los últimos **3 días**: Hoy, Ayer y Antes de Ayer.  

Además, incluye un **botón interactivo** que permite activar o desactivar las líneas verticales sin necesidad de abrir la ventana de configuración del indicador.

---

## ⚙️ Parámetros de entrada

| Parámetro | Tipo | Descripción |
|------------|------|-------------|
| `Tokio` | `bool` | Muestra la apertura de la sesión de Tokio |
| `London` | `bool` | Muestra la apertura de la sesión de Londres |
| `Nyse` | `bool` | Muestra la apertura de la sesión de Nueva York |
| `Indice` | `bool` | Ajusta las horas si se utiliza en índices en lugar de pares Forex |

---

## 🧭 Funcionamiento

- El indicador detecta automáticamente las **00:00** del servidor y marca una línea vertical para cada nuevo día.  
- Dibuja las líneas de apertura de sesión configuradas según el horario del servidor.  
- Muestra los rangos de precios (`High` y `Low`) de los últimos **3 días**.  
- Al hacer clic en el botón **“Vlines: ON/OFF”**, se alterna la visibilidad de las líneas verticales **solo en el gráfico actual**.  

> 💾 El estado ON/OFF se guarda globalmente al cerrar el indicador (`OnDeinit`), evitando bloqueos al cambiar de timeframe o gráfico.

---

## 🎨 Colores por defecto

| Elemento | Color |
|-----------|--------|
| Rango de Hoy | 🔴 `clrOrangeRed` |
| Rango de Ayer | 🟠 `clrOrange` |
| Rango de Antes de Ayer | ⚫ `clrDimGray` |
| Sesiones Tokio / Londres / NYSE | Tonos suaves de verde, azul y rojo |
| Separadores diarios | Gris oscuro (`C'22,22,22'`) |

---

## 💡 Recomendaciones

- Usar en **timeframes menores a D1** para aprovechar las marcas de sesión.  
- Compatible con **Forex** e **índices**, ajusta automáticamente los horarios según el parámetro `Indice`.  
- Ideal para análisis **intradiario** y seguimiento de **volatilidad por sesión**.  

---

## 📁 Estructura general del código

- **`OnInit()`** → Limpia objetos previos, carga el estado global y dibuja el botón.  
- **`OnCalculate()`** → Dibuja separadores y rangos diarios dinámicos.  
- **`OnChartEvent()`** → Gestiona el botón toggle de visibilidad.  
- **`OnDeinit()`** → Guarda el estado global y limpia objetos del gráfico.  

---

## 🧩 Licencia

Código abierto para uso educativo y personal.  
© 2025 — **Braiidev**  
📎 [@braiidev-github-instagram](https://instagram.com/braiidev)

---

