import { gmxInvestment, useTestApis } from '@/api/test';
import { Investment } from '@/api/types';
import { useState } from 'react';
import { PageContent } from './index';
import { AsyncWithSigner } from '@/hooks/use-api-manager';

export default {
  title: 'Pages/Manage',
  component: PageContent,
};

export const Default = () => {
  const { papi, sapi, cache } = useTestApis();
  const [selectedInvestment, setSelectedInvestment] =
    useState<Investment | undefined>();
  function requestActionWithSigner(chainId: number, action: AsyncWithSigner) {
    action(papi, sapi);
  }

  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      requestActionWithSigner={requestActionWithSigner}
      cache={cache}
      selectedInvestment={selectedInvestment}
      setSelectedInvestment={setSelectedInvestment}
    />
  );
};

export const Loading = () => {
  const { papi, sapi, cache } = useTestApis(1000000);
  const [selectedInvestment, setSelectedInvestment] =
    useState<Investment | undefined>();
  function requestActionWithSigner(chainId: number, action: AsyncWithSigner) {
    action(papi, sapi);
  }
  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      requestActionWithSigner={requestActionWithSigner}
      cache={cache}
      selectedInvestment={selectedInvestment}
      setSelectedInvestment={setSelectedInvestment}
    />
  );
};

export const SingleHolding = () => {
  const { papi, sapi, cache } = useTestApis();
  const [selectedInvestment, setSelectedInvestment] =
    useState<Investment | undefined>(gmxInvestment);
  function requestActionWithSigner(chainId: number, action: AsyncWithSigner) {
    action(papi, sapi);
  }
  return (
    <PageContent
      papi={papi}
      sapi={sapi}
      requestActionWithSigner={requestActionWithSigner}
      cache={cache}
      selectedInvestment={selectedInvestment}
      setSelectedInvestment={setSelectedInvestment}
    />
  );
};
