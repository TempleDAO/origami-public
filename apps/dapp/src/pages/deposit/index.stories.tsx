import { useTestApis } from '@/api/test';
import { PageContent } from './index';
import { AsyncWithSigner } from '@/hooks/use-api-manager';

export default {
  title: 'Pages/Deposit',
  component: PageContent,
};

export const Default = () => {
  const { papi, sapi, cache } = useTestApis();
  function requestActionWithSigner(chainId: number, action: AsyncWithSigner) {
    action(papi, sapi);
  }

  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      cache={cache}
      requestActionWithSigner={requestActionWithSigner}
    />
  );
};

export const Loading = () => {
  const { papi, sapi, cache } = useTestApis(1000000);
  function requestActionWithSigner(chainId: number, action: AsyncWithSigner) {
    action(papi, sapi);
  }
  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      cache={cache}
      requestActionWithSigner={requestActionWithSigner}
    />
  );
};
