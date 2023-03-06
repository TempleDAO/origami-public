import { PageContent } from './index';
import { useTestApis } from '@/api/test';

export default {
  title: 'Pages/LandingPage',
  component: PageContent,
};

export const Default = () => {
  const { cache } = useTestApis();

  return <PageContent cache={cache} />;
};
