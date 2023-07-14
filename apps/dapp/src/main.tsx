import React from 'react';
import ReactDOM from 'react-dom/client';
import { createBrowserRouter, RouterProvider } from 'react-router-dom';
import { Buffer } from 'buffer';
import { ThemeContext } from 'styled-components';

import { GlobalStyle } from './styles/GlobalStyle';
import { theme } from './styles/theme';
import { Page as InvestPage } from './pages/deposit';
import { Page as ManagePage } from './pages/manage';
import { Page as DisclaimerPage } from './pages/disclaimer';
import { Page as LandingPage } from './pages/landing';
import { Page as TermsOfServicePage } from './pages/tos';
import { Page as PrivacyPolicyPage } from './pages/policy';

import './styles/fonts.css';
import { ApiManagerProvider } from './hooks/use-api-manager';
import { getApiConfig } from './config';
import { AppLayout } from './components/Layouts/AppLayout';
import { AppRoutes } from './app-routes';
import { Web3OnboardProvider } from '@web3-onboard/react';
import { WEB3_ONBOARD } from './config/web3onboard';

// polyfill Buffer required for WalletConnect
if (!window.Buffer) {
  window.Buffer = Buffer;
}

const router = createBrowserRouter([
  {
    path: AppRoutes.Index,
    element: <LandingPage />,
  },
  {
    path: AppRoutes.Deposit,
    element: (
      <AppLayout>
        <InvestPage />
      </AppLayout>
    ),
  },
  {
    path: AppRoutes.Manage,
    element: (
      <AppLayout>
        <ManagePage />
      </AppLayout>
    ),
  },
  {
    path: AppRoutes.Disclaimer,
    element: (
      <AppLayout>
        <DisclaimerPage />
      </AppLayout>
    ),
  },
  {
    path: AppRoutes.TermsOfService,
    element: (
      <AppLayout>
        <TermsOfServicePage />
      </AppLayout>
    ),
  },
  {
    path: AppRoutes.PrivacyPolicy,
    element: (
      <AppLayout>
        <PrivacyPolicyPage />
      </AppLayout>
    ),
  },
]);

const API_CONFIG = getApiConfig();

ReactDOM.createRoot(document.getElementById('root') as HTMLElement).render(
  // Put the ApiManagerProvider outside StrictMode, so that the api only gets
  // created once in dev.
  <Web3OnboardProvider web3Onboard={WEB3_ONBOARD}>
    <ApiManagerProvider apiConfig={API_CONFIG}>
      <React.StrictMode>
        <ThemeContext.Provider value={theme}>
          <GlobalStyle />
            <RouterProvider router={router} />
        </ThemeContext.Provider>
      </React.StrictMode>
    </ApiManagerProvider>
  </Web3OnboardProvider>
);
