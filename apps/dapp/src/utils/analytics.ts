import { IS_DEVELOPMENT } from '@/config';
import posthog from 'posthog-js';

export class AnalyticsService {
  // eslint-disable-next-line @typescript-eslint/no-empty-function
  private constructor() {}

  public static init(): void {
    console.debug(`AnalyticsService.init: IS_DEVELOPMENT=${IS_DEVELOPMENT}`);

    if (!IS_DEVELOPMENT) {
      const POSTHOG_TOKEN = import.meta.env.VITE_POSTHOG_TOKEN;
      if (!POSTHOG_TOKEN) {
        console.error('Posthog token is not set');
        return;
      }
      posthog.init(POSTHOG_TOKEN, {
        api_host: 'https://app.posthog.com',
      });
    }
  }
}
