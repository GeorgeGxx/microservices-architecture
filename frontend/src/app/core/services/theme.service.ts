import { Injectable, effect, signal } from '@angular/core';

export type AppTheme = 'dark';

@Injectable({
  providedIn: 'root'
})
export class ThemeService {
  private readonly THEME_KEY = 'msa_theme';
  readonly currentTheme = signal<AppTheme>('dark');

  constructor() {
    // Strictly enforce Enterprise Dark theme across the application
    if (typeof document !== 'undefined') {
      document.documentElement.setAttribute('data-theme', 'dark');
      try {
        localStorage.setItem(this.THEME_KEY, 'dark');
      } catch {
        // Handle storage quota or private browsing gracefully
      }
    }
  }

  setTheme(_theme: AppTheme = 'dark'): void {
    this.currentTheme.set('dark');
  }
}
