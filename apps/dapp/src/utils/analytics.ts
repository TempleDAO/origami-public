import { IS_DEVELOPMENT } from '@/config';
import posthog from 'posthog-js';

export class AnalyticsService {
  // eslint-disable-next-line @typescript-eslint/no-empty-function
  private constructor() {}

  public static init(): void {
    console.debug(`AnalyticsService.init: IS_DEVELOPMENT=${IS_DEVELOPMENT}`);
    if (!IS_DEVELOPMENT) {
      // TODO: Move posthog config to env vars
      posthog.init('phc_kXbMwslQybtPZl6w6Q7Cdl7SDqjE4gGxlNJ0HE80ttH', {
        api_host: 'https://app.posthog.com',
      });
    }
  }
}
