import { useTestApis } from '@/api/test';
import { asyncNoop } from '@/utils/noop';
import { PageContent } from './index';

export default {
  title: 'Pages/Invest',
  component: PageContent,
};

export const Default = () => {
  const { papi, sapi, cache } = useTestApis();

  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      connectSigner={asyncNoop}
      cache={cache}
    />
  );
};

export const Loading = () => {
  const { papi, sapi, cache } = useTestApis(1000000);

  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      connectSigner={asyncNoop}
      cache={cache}
    />
  );
};
