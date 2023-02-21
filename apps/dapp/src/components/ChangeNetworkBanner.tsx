import { Chain } from '@/api/types';
import type { FC, MouseEventHandler } from 'react';

import styled from 'styled-components';

type ChangeNetworkBannerProps = {
  toChain: Chain;
  onClick?: MouseEventHandler;
};

export const ChangeNetworkBanner: FC<ChangeNetworkBannerProps> = ({
  toChain,
  onClick,
}) => {
  const label = `${
    onClick ? 'Click here to' : 'Please'
  } change your network to ${toChain.name}`;
  return <Banner onClick={onClick}>{label}</Banner>;
};

const Banner = styled.div`
  display: flex;
  position: fixed;
  align-items: center;
  justify-content: center;
  box-sizing: border-box;
  padding: 0.5rem 1.5rem;
  width: 100%;
  z-index: 9999;
  background-color: ${({ theme }) => theme.colors.greyMid};
  user-select: none;

  ${({ onClick }) => onClick && `cursor: pointer`}
`;
