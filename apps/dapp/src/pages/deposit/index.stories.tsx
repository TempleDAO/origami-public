import { useTestApis } from '@/api/test';
import { PageContent } from './index';

export default {
  title: 'Pages/Deposit',
  component: PageContent,
};

export const Default = () => {
  const { papi, sapi, cache } = useTestApis();

  return (
    <PageContent
      papi={papi}
      walletInitialize={async () => undefined}
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
      walletInitialize={async () => undefined}
      walletConnect={async () => sapi}
      cache={cache}
    />
  );
};
