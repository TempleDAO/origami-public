import { useTestApis } from '@/api/test';
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
      walletAddress={sapi.signerAddress}
      walletConnect={async () => sapi}
      cache={cache}
    />
  );
};

export const Loading = () => {
  const { papi, sapi, cache } = useTestApis(1000000);

  return (
    <PageContent
      papi={papi}
      walletAddress={sapi.signerAddress}
      walletConnect={async () => sapi}
      cache={cache}
    />
  );
};
