import { describe, it, expect } from 'vitest';
import { ErrorBoundary } from './ErrorBoundary';

describe('ErrorBoundary', () => {
  it('updates state when getDerivedStateFromError is called', () => {
    const error = new Error('Test crash');
    const nextState = ErrorBoundary.getDerivedStateFromError(error);
    expect(nextState.hasError).toBe(true);
    expect(nextState.error).toBe(error);
  });

  it('records client error on componentDidCatch without throwing', () => {
    const boundary = new ErrorBoundary({ children: null });
    const error = new Error('Sample client error');
    expect(() => boundary.componentDidCatch(error)).not.toThrow();
  });

  it('renders children when no error has occurred', () => {
    const boundary = new ErrorBoundary({ children: 'Healthy Content' });
    const rendered = boundary.render();
    expect(rendered).toBe('Healthy Content');
  });

  it('renders custom fallback when an error is present and fallback is provided', () => {
    const boundary = new ErrorBoundary({ children: 'Healthy Content', fallback: 'Custom Fallback' });
    boundary.state = { hasError: true, error: new Error('Boom') };
    const rendered = boundary.render();
    expect(rendered).toBe('Custom Fallback');
  });
});
