import { gmxInvestment, useTestApis } from '@/api/test';
import { useMemo } from 'react';
import { AssetDetails } from './AssetDetails';

export default {
  title: 'Components/Content/AssetDetails',
  component: AssetDetails,
};

export const Default = () => {
  const { papi, sapi } = useTestApis();
  const investment = useMemo(() => gmxInvestment(), []);

  return <AssetDetails papi={papi} sapi={sapi} investment={investment} />;
};

export const Loading = () => {
  const { papi, sapi } = useTestApis(1000000);
  const investment = useMemo(() => gmxInvestment(), []);

  return <AssetDetails papi={papi} sapi={sapi} investment={investment} />;
};
