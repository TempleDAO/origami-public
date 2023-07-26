import { LandingPageMetrics } from './LandingPageMetrics';
import { useTestApis } from '@/api/test';

export default {
  title: 'Components/Content/LandingPageMetrics',
  component: LandingPageMetrics,
};

export const Default = () => {
  const { cache } = useTestApis();

  return <LandingPageMetrics cache={cache} />;
};
