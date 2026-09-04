import { Injectable, effect, signal } from '@angular/core';

export type AppTheme = 'dark' | 'light';

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  private readonly THEME_KEY = 'msa_theme';
  readonly currentTheme = signal<AppTheme>(this.getInitialTheme());

  constructor() {
    // Apply theme changes to document root whenever signal changes
    effect(() => {
      const theme = this.currentTheme();
      document.documentElement.setAttribute('data-theme', theme);
      try {
        localStorage.setItem(this.THEME_KEY, theme);
      } catch {
        // Handle private browsing or storage quota errors gracefully
      }
    });
  }

  setTheme(theme: AppTheme): void {
    this.currentTheme.set(theme);
  }

  cycleTheme(): void {
    const nextTheme: AppTheme = this.currentTheme() === 'dark' ? 'light' : 'dark';
    this.setTheme(nextTheme);
  }

  private getInitialTheme(): AppTheme {
    try {
      const saved = localStorage.getItem(this.THEME_KEY) as AppTheme;
      if (saved && ['dark', 'light'].includes(saved)) {
        return saved;
      }
    } catch {
      // Fallback
    }

    if (typeof window !== 'undefined' && window.matchMedia && window.matchMedia('(prefers-color-scheme: light)').matches) {
      return 'light';
    }
    return 'dark';
  }
}
