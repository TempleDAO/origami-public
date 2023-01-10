import { useTestApis } from '@/api/test';
import { asyncNoop } from '@/utils/noop';
import { PageContent } from './index';

export default {
  title: 'Pages/Invest',
  component: PageContent,
};

export const Default = () => {
  const { papi, sapi } = useTestApis();

  return <PageContent papi={papi} sapi={sapi} connectSigner={asyncNoop} />;
};

export const Loading = () => {
  const { papi, sapi } = useTestApis(1000000);

  return <PageContent papi={papi} sapi={sapi} connectSigner={asyncNoop} />;
};
