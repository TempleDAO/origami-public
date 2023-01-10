import React, { useState } from 'react';
import styled from 'styled-components';
import { action } from '@storybook/addon-actions';
import { Checkbox } from './Checkbox';
import { noop } from '@/utils/noop';

export default {
  title: 'Components/Commons/Checkbox',
  component: Checkbox,
  decorators: [],
};

export const Varieties = () => {
  const [isChecked, setChecked] = useState(false);
  return (
    <ComponentTable>
      <div>disabled</div>
      <Checkbox checked={false} disabled={true} onClick={noop} />

      <div>unchecked</div>
      <Checkbox checked={false} disabled={false} onClick={noop} />

      <div>checked</div>
      <Checkbox checked={true} disabled={false} onClick={noop} />

      <div>live</div>
      <Checkbox
        checked={isChecked}
        disabled={false}
        onClick={() => {
          action('toggle');
          setChecked((isChecked) => !isChecked);
        }}
      />
    </ComponentTable>
  );
};

const ComponentTable = styled.div`
  padding: 30px;
  display: grid;
  grid-template-columns: 100px 1fr;
  row-gap: 20px;
  align-items: center;
`;
