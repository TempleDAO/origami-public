import React from 'react';
import styled from 'styled-components';

import { Icon } from './Icon';

export default {
  title: 'Components/Commons/Icon',
  component: Icon,
};

//TODO: should be read from files under `public/icons`
const iconList = [
  'add',
  'discord',
  'swap',
  'back',
  'disk',
  'info',
  'telegram',
  'calendar',
  'empty-arrow',
  'medium',
  'temple',
  'checkbox',
  'error',
  'metamask',
  'twitter',
  'checkmark',
  'expand-less',
  'plus',
  'verified',
  'close',
  'expand-more',
  'pyramid',
  'wallet-connect',
  'coinbase',
  'fat-arrow-right',
  'settings',
  'wallet',
  'cone',
  'filled-arrow',
  'winner-cup',
  'currency-exchange',
  'forward',
  'subtract',
  'withdraw',
  'deposit',
  'swap-circle',
  'gmx',
  'glp',
];

export const Icons = () => (
  <IconGrid>
    {iconList.map((icon) => (
      <IconContainer key={icon}>
        <Icon iconName={icon} />
        <Label>{icon}</Label>
      </IconContainer>
    ))}
  </IconGrid>
);

const IconGrid = styled.div`
  display: flex;
  flex-wrap: wrap;
  max-width: 50rem;
`;

const IconContainer = styled.div`
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 1rem;
`;

const Label = styled.span`
  margin-top: 0.2rem;
`;
