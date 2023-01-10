import React from 'react';
import styled from 'styled-components';

import { LoadingComponent } from './LoadingComponent';

export default {
  title: 'Components/Commons/LoadingComponent',
  component: LoadingComponent,
};

export const Varieties = () => {
  return (
    <Container>
      <p>Default</p>
      <LoadingComponent />
      <p>Custom width/height (px)</p>
      <LoadingComponent width={60} height={80} />
      <p>Custom styles with styled-components</p>
      <Styled />
    </Container>
  );
};

const Container = styled.div`
  display: flex;
  flex-direction: column;
  padding: 2rem;
`;

const Styled = styled(LoadingComponent)`
  border-radius: 9999px;
  border: 2px solid red;
`;
