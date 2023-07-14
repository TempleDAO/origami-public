import { gmxInvestment, useTestApis } from '@/api/test';
import { useMemo } from 'react';
import { AssetDetails } from './AssetDetails';
import { AsyncWithSigner } from '@/hooks/use-api-manager';

export default {
  title: 'Components/Content/AssetDetails',
  component: AssetDetails,
};

export const Default = () => {
  const { papi, sapi, cache } = useTestApis();
  const investment = useMemo(() => gmxInvestment(), []);
  function requestActionWithSigner(chainId: number, action: AsyncWithSigner) {
    action(papi, sapi);
  }

  return (
    <AssetDetails
      papi={papi}
      sapi={sapi}
      requestActionWithSigner={requestActionWithSigner}
      investment={investment}
      cache={cache}
    />
  );
};

export const Loading = () => {
  const { papi, sapi, cache } = useTestApis(1000000);
  const investment = useMemo(() => gmxInvestment(), []);
  function requestActionWithSigner(chainId: number, action: AsyncWithSigner) {
    action(papi, sapi);
  }

  return (
    <AssetDetails
      papi={papi}
      sapi={sapi}
      requestActionWithSigner={requestActionWithSigner}
      investment={investment}
      cache={cache}
    />
  );
};
