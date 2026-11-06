import React, { Component, ErrorInfo, ReactNode } from 'react';
import { AlertTriangle, RefreshCw } from 'lucide-react';

interface Props {
  children: ReactNode;
  fallback?: ReactNode;
}

interface State {
  hasError: boolean;
  error: Error | null;
  errorInfo: ErrorInfo | null;
}

export class ErrorBoundary extends Component<Props, State> {
  public state: State = {
    hasError: false,
    error: null,
    errorInfo: null,
  };

  public static getDerivedStateFromError(error: Error): State {
    return { hasError: true, error, errorInfo: null };
  }

  public componentDidCatch(error: Error, errorInfo: ErrorInfo) {
    this.setState({ errorInfo });
    // Log uncaught client errors to console with structured context
    console.error('[ErrorBoundary] Uncaught React exception:', error, errorInfo);
  }

  private handleReset = () => {
    this.setState({ hasError: false, error: null, errorInfo: null });
    window.location.reload();
  };

  public render() {
    if (this.state.hasError) {
      if (this.props.fallback) {
        return this.props.fallback;
      }

      return (
        <div className="min-h-screen bg-slate-900 text-slate-100 flex items-center justify-center p-6">
          <div className="max-w-lg w-full bg-slate-800/80 backdrop-blur-md border border-rose-500/30 rounded-2xl p-8 shadow-2xl text-center">
            <div className="inline-flex items-center justify-center w-16 h-16 rounded-full bg-rose-500/10 text-rose-400 mb-6">
              <AlertTriangle className="w-8 h-8" />
            </div>
            <h2 className="text-2xl font-bold mb-2">Something went wrong</h2>
            <p className="text-slate-400 text-sm mb-6 leading-relaxed">
              An unexpected client-side error occurred in the application view. The system state is protected.
            </p>
            {this.state.error && (
              <div className="bg-slate-950/60 rounded-xl p-4 mb-6 text-left border border-slate-700/50 overflow-x-auto">
                <p className="text-xs font-mono text-rose-400 break-words font-semibold">
                  {this.state.error.name}: {this.state.error.message}
                </p>
              </div>
            )}
            <div className="flex gap-3 justify-center">
              <button
                onClick={this.handleReset}
                className="inline-flex items-center gap-2 px-5 py-2.5 rounded-xl font-medium text-sm bg-indigo-600 hover:bg-indigo-500 text-white transition-colors shadow-lg shadow-indigo-600/25"
              >
                <RefreshCw className="w-4 h-4" />
                Reload Application
              </button>
            </div>
          </div>
        </div>
      );
    }

    return this.props.children;
  }
}
