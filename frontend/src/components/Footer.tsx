import React from 'react';
import { Sparkles, Activity, ShieldCheck, Cpu } from 'lucide-react';

export const Footer: React.FC = () => {
  return (
    <footer className="w-full border-t border-slate-800/80 bg-slate-950/80 py-10 mt-20 text-xs text-slate-500">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="grid grid-cols-1 md:grid-cols-4 gap-8 mb-8">
          <div>
            <div className="flex items-center gap-2 mb-3">
              <div className="w-6 h-6 rounded-lg bg-indigo-600 flex items-center justify-center text-white">
                <Sparkles className="w-3.5 h-3.5" />
              </div>
              <span className="font-bold text-slate-200">Novashop Architecture</span>
            </div>
            <p className="text-slate-400 leading-relaxed text-xs">
              Cloud-Native Distributed E-Commerce platform orchestrating Spring Boot 4.0.8, Java 21 LTS,
              Apollo Router v2, and React 19 with TailwindCSS v4.
            </p>
          </div>

          <div>
            <h4 className="font-semibold text-slate-300 uppercase tracking-wider text-[11px] mb-3">
              Core Subgraphs
            </h4>
            <ul className="space-y-1.5 text-slate-400">
              <li className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                <span>products-service (:8004)</span>
              </li>
              <li className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                <span>inventory-service (:8001)</span>
              </li>
              <li className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                <span>orders-service (:8003)</span>
              </li>
              <li className="flex items-center gap-1.5">
                <span className="w-1.5 h-1.5 rounded-full bg-emerald-400" />
                <span>notification-service (:8002)</span>
              </li>
            </ul>
          </div>

          <div>
            <h4 className="font-semibold text-slate-300 uppercase tracking-wider text-[11px] mb-3">
              Telemetry & Ops
            </h4>
            <ul className="space-y-1.5 text-slate-400">
              <li className="flex items-center gap-1.5">
                <Activity className="w-3 h-3 text-indigo-400" />
                <span>Grafana LGTM Stack</span>
              </li>
              <li className="flex items-center gap-1.5">
                <Cpu className="w-3 h-3 text-amber-400" />
                <span>OpenTelemetry Tracing</span>
              </li>
              <li className="flex items-center gap-1.5">
                <ShieldCheck className="w-3 h-3 text-emerald-400" />
                <span>Keycloak 26 OIDC & PKCE</span>
              </li>
            </ul>
          </div>

          <div>
            <h4 className="font-semibold text-slate-300 uppercase tracking-wider text-[11px] mb-3">
              Gateway SLA
            </h4>
            <div className="p-3 rounded-xl bg-slate-900 border border-slate-800 text-[11px] space-y-1">
              <div className="flex justify-between">
                <span>Edge Gateway:</span>
                <span className="text-slate-200 font-mono">Apollo Router v2.16.3</span>
              </div>
              <div className="flex justify-between">
                <span>Federation Spec:</span>
                <span className="text-slate-200 font-mono">v2.3.0</span>
              </div>
              <div className="flex justify-between">
                <span>Sub-Graph Latency:</span>
                <span className="text-emerald-400 font-mono">&lt; 15ms</span>
              </div>
            </div>
          </div>
        </div>

        <div className="pt-6 border-t border-slate-800/80 flex flex-col sm:flex-row justify-between items-center gap-4 text-[11px]">
          <span>© 2026 Novashop Inc. Engineered by GeorgeGxx. Enterprise MIT Licensed.</span>
          <div className="flex gap-4">
            <span className="hover:text-slate-300 transition">Terms</span>
            <span className="hover:text-slate-300 transition">Privacy</span>
            <span className="hover:text-slate-300 transition">GraphQL Docs</span>
          </div>
        </div>
      </div>
    </footer>
  );
};
