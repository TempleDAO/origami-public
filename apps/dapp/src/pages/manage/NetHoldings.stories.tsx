import { ready } from '@/utils/loading-value';

import React from 'react';
import styled from 'styled-components';
import { NetHoldings } from './NetHoldings';

export default {
  title: 'Components/Content/NetHoldings',
  component: NetHoldings,
};

export const Default = () => (
  <Container>
    <NetHoldings currentNetApr={ready(0.186)} currentNetValue={ready(156000)} />
  </Container>
);

const Container = styled.div`
  display: flex;
  height: 400px;
`;
