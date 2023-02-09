import { useState } from 'react';
import { getAccount } from '@wagmi/core';
import styled from 'styled-components';

import { Icon } from './Icon';
import { useApiManager } from '@/hooks/use-api-manager';
import { truncateAddress } from '@/utils/truncate-address';
import { noop } from '@/utils/noop';
import clickableStyles from '@/styles/mixins/clickable-styles';

export const ConnectWalletButton = () => {
  const { connectSigner, disconnectSigner } = useApiManager();
  const { address, isConnected } = getAccount();
  const [mouseOver, setMouseOver] = useState(false);

  const label =
    isConnected && address ? truncateAddress(address) : 'CONNECT WALLET';

  return (
    <>
      <ButtonBox
        onClick={isConnected ? disconnectSigner : noop}
        onMouseEnter={() => setMouseOver(true)}
        onMouseLeave={() => setMouseOver(false)}
      >
        {isConnected ? (
          <span>{mouseOver ? 'DISCONNECT' : label}</span>
        ) : (
          <>
            <Icon
              iconName="metamask"
              size={30}
              onClick={() => connectSigner('metaMask')}
            />
            <Icon
              iconName="wallet-connect"
              size={30}
              onClick={() => connectSigner('walletConnect')}
            />
          </>
        )}
      </ButtonBox>
    </>
  );
};

const ButtonBox = styled.div`
  display: flex;
  align-items: center;
  justify-content: space-between;
  background: transparent;
  color: ${({ theme }) => theme.colors.greyLight};
  font-size: 1rem;
  padding: 0.5rem;
  border-radius: 0.25rem;
  height: fit-content;
  outline: none;
  width: 6rem;

  * {
    ${clickableStyles}
  }
`;
