import React, { createContext, useContext, useState } from 'react';

export type Currency = 'USD';

interface CurrencyContextType {
  currency: Currency;
  setCurrency: (c: Currency) => void;
  formatPrice: (amountInUSD: number) => string;
}

const CurrencyContext = createContext<CurrencyContextType>({
  currency: 'USD',
  setCurrency: () => {},
  formatPrice: (a) => `$${a.toFixed(2)}`,
});

export const CurrencyProvider: React.FC<{ children: React.ReactNode }> = ({ children }) => {
  const [currency] = useState<Currency>('USD');

  const setCurrency = (_c: Currency) => {};

  const formatPrice = (amountInUSD: number): string => {
    return `$${(amountInUSD || 0).toLocaleString('en-US', { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`;
  };

  return (
    <CurrencyContext.Provider value={{ currency, setCurrency, formatPrice }}>
      {children}
    </CurrencyContext.Provider>
  );
};

export const useCurrency = () => useContext(CurrencyContext);
