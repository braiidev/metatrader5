# STRICT.MD — REGLAS DE ORO DEL SISTEMA

## 1. LA REGLA DEL SEMÁFORO (ENTRADA)
- **SI EL PANEL DICE "OUT" → NO EXISTES.**
- Aunque veas la flecha, si `Acc < 80%` o el panel dice `OUT`, **no tocas el mouse**.
- El edge de este sistema es **filtrar basura**. Operar en horas malas destruye la ventaja matemática.
- **Solo operas si:** Panel dice `IN` + Flecha de color (Verde/Azul/Naranja).

## 2. LA REGLA DEL LOTE EXACTO (RIESGO)
- **El lote que ves en el panel es el que pones. Ni un decimal más.**
- Si el panel dice `Lot: 0.03`, entras con 0.03.
- **Nunca** aumentes el lote para "recuperar" una pérdida (Martingala prohibida).
- **Nunca** bajes el lote por miedo. El sistema está calibrado para ese riesgo exacto.

## 3. TIMEOUT: ¿CERRAR O MOVER A BE?
Esta es la duda más común. Aquí está la regla estricta basada en los datos:

### A. El Breakeven es tu escudo (Automático)
- Si el precio baja **3 pts** a tu favor (Short), mueves el SL a **Entry**.
- Esto convierte una Loss potencial en un $0.
- **Prioridad:** El BE se activa *antes* que el Timeout en la mayoría de los Wins.

### B. El Timeout es tu cuchillo (Manual)
- Si pasan **5 velas M1** y el precio **NO tocó TP ni SL**:
  - **CIERRA LA OPERACIÓN AL MERCADO INMEDIATAMENTE.**
- **¿Por qué?**
  - El sistema tiene un "edge" (ventaja) estadístico que decae con el tiempo.
  - Si en 5 minutos no se fue a favor, la probabilidad de que ganes cae drásticamente.
  - Quedarte ahí esperando es "rezar", no operar.
  - **Excepción:** Si ya estás en Breakeven (SL en Entry), puedes dejar correr, pero la regla estricta es **cerrar** para liberar capital y mente.

## 4. RESUMEN DE EJECUCIÓN (Paso a Paso)

1. **Alerta**: Suena la alerta y ves flecha de color.
2. **Check**: Miras el panel. ¿Dice `IN`? -> Sí. ¿Lote calculado? -> 0.03.
3. **Entrada**: Vendes al cierre de la vela (o apertura de la siguiente).
4. **Órdenes**:
   - Pones **SL** a +20 pts (arriba).
   - Pones **TP** a -10 pts (abajo).
5. **Gestión Activa**:
   - **Escenario A (Rápido)**: El precio baja 3 pts -> Mueves SL a Entry (BE).
   - **Escenario B (Lento)**: Pasan 5 velas y el precio está en medio -> **Cierras manual**.
   - **Escenario C (Win)**: Toca TP -> Cierra solo.
   - **Escenario D (Loss)**: Toca SL -> Cierra solo. Aceptas y esperas la siguiente.

## 5. LO QUE ESTÁ PROHIBIDO
- ❌ Mover el SL en contra (aumentar riesgo).
- ❌ Cerrar antes de tiempo por miedo (dejar correr las pérdidas pequeñas).
- ❌ Entrar en noticias de alto impacto (NFP, CPI, FOMC) aunque haya señal.
- ❌ Operar si el spread es > 30 pts.

---
**IMPRESIÓN RECOMENDADA:** Pega esto frente a tu monitor. No lo leas, **cumplelo**.