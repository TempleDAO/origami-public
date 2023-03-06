import React from 'react';
import ReactDOM from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { Buffer } from 'buffer';
import { ThemeContext } from 'styled-components';

import { GlobalStyle } from './styles/GlobalStyle';
import { theme } from './styles/theme';
import { Page as InvestPage } from './pages/invest';
import { Page as ManagePage } from './pages/manage';
import { Page as DisclaimerPage } from './pages/disclaimer';
import { Page as LandingPage } from './pages/landing';

import './styles/fonts.css';
import { ApiManagerProvider } from './hooks/use-api-manager';
import { getApiConfig } from './config';
import { AppLayout } from './components/Layouts/AppLayout';

// polyfill Buffer required for WalletConnect
if (!window.Buffer) {
  window.Buffer = Buffer;
}

const router = createBrowserRouter([
  {
    path: '/',
    element: <LandingPage />,
  },
  {
    path: '/invest',
    element: (
      <AppLayout>
        <InvestPage />
      </AppLayout>
    ),
  },
  {
    path: '/manage',
    element: (
      <AppLayout>
        <ManagePage />
      </AppLayout>
    ),
  },
  {
    path: '/disclaimer',
    element: (
      <AppLayout>
        <DisclaimerPage />
      </AppLayout>
    ),
  },
]);

const API_CONFIG = getApiConfig();

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  // Put the ApiManagerProvider outside StrictMode, so that the api only gets
  // created once in dev.
  <ApiManagerProvider apiConfig={API_CONFIG}>
    <React.StrictMode>
      <ThemeContext.Provider value={theme}>
        <GlobalStyle />
        <RouterProvider router={router} />
      </ThemeContext.Provider>
    </React.StrictMode>
  </ApiManagerProvider>
);
