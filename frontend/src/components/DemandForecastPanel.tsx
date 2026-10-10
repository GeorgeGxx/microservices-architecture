import React, { useCallback, useEffect, useState } from 'react';
import { AlertTriangle, CalendarDays, Clock3, RefreshCw, TrendingUp } from 'lucide-react';
import { useAuth } from '../context/AuthContext';
import { DemandForecastResponse, fetchDemandForecast } from '../services/demandForecast';

const formatDate = (value: string) => new Intl.DateTimeFormat('en-US', {
  month: 'short',
  day: 'numeric',
  year: 'numeric',
}).format(new Date(`${value}T12:00:00`));

export const DemandForecastPanel: React.FC = () => {
  const { user } = useAuth();
  const [forecast, setForecast] = useState<DemandForecastResponse | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const forecastDays = forecast?.products.flatMap((item) => item.forecasts) ?? [];
  const firstForecastDate = forecastDays[0]?.date ?? forecast?.historyEndDate;
  const lastForecastDate = forecastDays[forecastDays.length - 1]?.date ?? forecast?.historyEndDate;

  const loadForecast = useCallback(async () => {
    setIsLoading(true);
    setError(null);
    try {
      setForecast(await fetchDemandForecast(user?.token));
    } catch (loadError) {
      setError(loadError instanceof Error ? loadError.message : 'Could not load demand forecasts.');
    } finally {
      setIsLoading(false);
    }
  }, [user?.token]);

  useEffect(() => {
    void loadForecast();
  }, [loadForecast]);

  return (
    <section className="space-y-6" aria-labelledby="demand-forecast-title">
      <div className="glass-card p-6 rounded-2xl border border-slate-800">
        <div className="flex flex-col md:flex-row md:items-center justify-between gap-4">
          <div>
            <div className="flex items-center gap-2 text-indigo-400 text-xs font-bold uppercase tracking-wider mb-2">
              <TrendingUp className="w-4 h-4" /> Inventory planning
            </div>
            <h2 id="demand-forecast-title" className="text-xl font-bold text-white">Seven-Day Demand Forecast</h2>
            <p className="mt-1 text-xs text-slate-400">
              Daily model estimates by SKU. Review these signals before making replenishment decisions.
            </p>
          </div>
          <button
            type="button"
            onClick={() => void loadForecast()}
            disabled={isLoading}
            className="px-4 py-2 rounded-xl bg-indigo-600 hover:bg-indigo-700 disabled:opacity-50 text-white text-xs font-bold flex items-center justify-center gap-2"
          >
            <RefreshCw className={`w-4 h-4 ${isLoading ? 'animate-spin' : ''}`} />
            {isLoading ? 'Refreshing...' : 'Refresh forecast'}
          </button>
        </div>
      </div>

      {error && (
        <div role="alert" className="glass-card p-5 rounded-2xl border border-amber-500/30 bg-amber-500/5 flex gap-3">
          <AlertTriangle className="w-5 h-5 text-amber-400 shrink-0" />
          <div>
            <h3 className="text-sm font-bold text-amber-200">Forecast is unavailable</h3>
            <p className="mt-1 text-xs text-slate-300">{error}</p>
            <p className="mt-2 text-xs text-slate-400">
              MLflow and the forecast API start with the normal Docker Compose stack. From the repository root, train the demo model with <code>.\mlops\training.ps1</code>, then refresh this panel. For Kafka-backed data, follow the Local MLOps workflow in the README.
            </p>
          </div>
        </div>
      )}

      {forecast && (
        <>
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4">
            <div className="glass-card p-4 rounded-2xl border border-slate-800">
              <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">Forecast window</div>
              <div className="mt-2 text-sm font-bold text-white">
                {formatDate(firstForecastDate ?? forecast.historyEndDate)}
                {' – '}
                {formatDate(lastForecastDate ?? forecast.historyEndDate)}
              </div>
            </div>
            <div className="glass-card p-4 rounded-2xl border border-slate-800">
              <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">Sales history</div>
              <div className="mt-2 text-sm font-bold text-white">
                {formatDate(forecast.historyStartDate)} – {formatDate(forecast.historyEndDate)}
              </div>
            </div>
            <div className="glass-card p-4 rounded-2xl border border-slate-800">
              <div className="text-[11px] font-bold uppercase tracking-wider text-slate-400">Model run</div>
              <div className="mt-2 flex items-center gap-2 text-sm font-bold text-white">
                <Clock3 className="w-4 h-4 text-indigo-400" /> {formatDate(forecast.modelCreatedAt.slice(0, 10))}
              </div>
            </div>
          </div>

          {forecast.dataSource === 'synthetic' && (
            <div role="status" className="rounded-xl border border-sky-500/30 bg-sky-500/10 px-4 py-3 text-xs text-sky-100">
              Synthetic demo data. These estimates are for validating the workflow and are not operational purchasing advice.
            </div>
          )}

          <div className="grid grid-cols-1 xl:grid-cols-2 gap-4">
            {forecast.products.map((product) => (
              <article key={product.sku} className="glass-card p-5 rounded-2xl border border-slate-800">
                <div className="flex items-start justify-between gap-4">
                  <div>
                    <div className="flex items-center gap-2 text-white font-bold">
                      <CalendarDays className="w-4 h-4 text-indigo-400" />
                      {product.sku}
                    </div>
                    <p className="mt-1 text-[11px] text-slate-500">{product.historyDays} days of dated history</p>
                  </div>
                  {product.status === 'READY' ? (
                    <div className="text-right">
                      <div className="text-[10px] uppercase tracking-wider text-slate-500">7-day total</div>
                      <div className="text-lg font-black text-indigo-300">{product.totalUnits} units</div>
                    </div>
                  ) : (
                    <span className="px-2 py-1 rounded-lg bg-amber-500/10 text-amber-300 text-[10px] font-bold">
                      More history needed
                    </span>
                  )}
                </div>

                {product.forecasts.length > 0 && (
                  <div className="mt-4 grid grid-cols-2 sm:grid-cols-4 gap-2">
                    {product.forecasts.map((day) => (
                      <div key={day.date} className="rounded-xl bg-slate-950/70 border border-slate-800 p-3">
                        <div className="text-[10px] text-slate-500">{formatDate(day.date)}</div>
                        <div className="mt-1 text-sm font-bold text-white">{day.units} units</div>
                      </div>
                    ))}
                  </div>
                )}
              </article>
            ))}
          </div>

          <p className="text-[11px] text-slate-500">
            Data source: {forecast.dataSource === 'synthetic' ? 'synthetic sample' : 'captured sales'} · Last observed sales date: {formatDate(forecast.historyEndDate)} · MLflow run: {forecast.modelRunId}
          </p>
        </>
      )}
    </section>
  );
};
