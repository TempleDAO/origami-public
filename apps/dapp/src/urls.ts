import { AppRoutes } from './app-routes';

const ORIGAMI_URL = `${window.location.origin}`;
const GMX_URL = 'https://gmx.io';
const DISCLAIMER_URL = `${window.location.origin}${AppRoutes.Disclaimer}`;
const TERMS_OF_SERVICE_URL = `${window.location.origin}${AppRoutes.TermsOfService}`;
const PRIVACY_POLICY_URL = `${window.location.origin}${AppRoutes.PrivacyPolicy}`;
const GEOBLOCK_URL = `${window.location.origin}/api/geoblock`;

export {
  ORIGAMI_URL,
  GMX_URL,
  DISCLAIMER_URL,
  TERMS_OF_SERVICE_URL,
  PRIVACY_POLICY_URL,
  GEOBLOCK_URL,
};
