import React, { useId } from 'react';
import styled from 'styled-components';

import { Select } from './Select';
import { noop } from '@/utils/noop';

export default {
  title: 'Components/Commons/Select',
  component: Select,
};

const options = [
  { value: 'blue', label: 'Blue' },
  { value: 'red', label: 'Red' },
  { value: 'green', label: 'Green' },
];

export const Varieties = () => {
  const selectId = useId();

  return (
    <Container>
      <div>default</div>
      <Select
        id={selectId}
        instanceId={selectId}
        value={options[0]}
        options={options}
        onChange={noop}
      />
      <div>disabled</div>
      <Select
        id={selectId}
        instanceId={selectId}
        value={options[0]}
        options={options}
        onChange={noop}
        isDisabled={true}
      />
    </Container>
  );
};

const Container = styled.div`
  width: 10rem;
  display: flex;
  flex-direction: column;
`;
