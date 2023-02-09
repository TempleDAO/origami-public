import { polygonMumbai } from '@wagmi/chains';
import { useTestApis } from '@/api/test';
import { PageContent } from './index';

export default {
  title: 'Pages/Invest',
  component: PageContent,
};

const switchNetworkStub = () => Promise.resolve(polygonMumbai);

export const Default = () => {
  const { papi, sapi, cache } = useTestApis();

  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      switchNetwork={switchNetworkStub}
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
      switchNetwork={switchNetworkStub}
      cache={cache}
    />
  );
};
