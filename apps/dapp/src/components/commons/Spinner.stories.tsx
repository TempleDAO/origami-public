import React from 'react';
import styled from 'styled-components';

import { Spinner } from './Spinner';

export default {
  title: 'Components/Commons/Spinner',
  component: Spinner,
};

export const Varieties = () => (
  <ComponentTable>
    <div>default</div>
    <Spinner />
    <div>small</div>
    <Spinner size="small" />
    <div>medium</div>
    <Spinner size="medium" />
    <div>large</div>
    <Spinner size="large" />
  </ComponentTable>
);

const ComponentTable = styled.div`
  padding: 30px;
  display: grid;
  grid-template-columns: 80px 1fr;
  row-gap: 20px;
  align-items: center;
`;
