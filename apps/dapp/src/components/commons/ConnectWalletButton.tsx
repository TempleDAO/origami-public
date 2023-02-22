import { useState } from 'react';
import styled from 'styled-components';

import { Icon } from './Icon';
import { SupportedWallet, useApiManager } from '@/hooks/use-api-manager';
import { truncateAddress } from '@/utils/truncate-address';
import clickableStyles from '@/styles/mixins/clickable-styles';
import { Spinner } from './Spinner';

export const ConnectWalletButton = () => {
  const { walletInitialize, walletDisconnect } = useApiManager();
  const apim = useApiManager();
  const address = apim.wallet?.address;
  const [mouseOver, setMouseOver] = useState(false);
  const [inProgress, setInProgress] = useState(false);

  async function connect(walletKind: SupportedWallet) {
    setInProgress(true);
    try {
      await walletInitialize(walletKind);
    } finally {
      setInProgress(false);
      setMouseOver(false);
    }
  }

  async function disconnect() {
    setInProgress(true);
    try {
      await walletDisconnect();
    } finally {
      setInProgress(false);
      setMouseOver(false);
    }
  }

  if (inProgress) {
    return (
      <ButtonBox>
        <Spinner size="small" />
      </ButtonBox>
    );
  }

  if (address) {
    return (
      <ButtonBox
        onClick={disconnect}
        onMouseEnter={() => setMouseOver(true)}
        onMouseLeave={() => setMouseOver(false)}
      >
        <span>{mouseOver ? 'DISCONNECT' : truncateAddress(address)}</span>
      </ButtonBox>
    );
  }

  return (
    <ButtonBox>
      <Icon iconName="metamask" size={30} onClick={() => connect('metaMask')} />
      <Icon
        iconName="wallet-connect"
        size={30}
        onClick={() => connect('walletConnect')}
      />
    </ButtonBox>
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
