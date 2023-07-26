import { useState } from 'react';
import styled from 'styled-components';

import { useApiManager } from '@/hooks/use-api-manager';
import { truncateAddress } from '@/utils/truncate-address';
import clickableStyles from '@/styles/mixins/clickable-styles';
import { Button } from './Button';

export const ConnectWalletButton = () => {
  const { sapi, walletConnect, walletDisconnect } = useApiManager();
  const address = sapi?.signerAddress;
  const [mouseOver, setMouseOver] = useState(false);

  async function disconnect() {
    try {
      await walletDisconnect();
    } finally {
      setMouseOver(false);
    }
  }

  return (
    <>
      {address ? (
        <ButtonBox
          onClick={disconnect}
          onMouseEnter={() => setMouseOver(true)}
          onMouseLeave={() => setMouseOver(false)}
        >
          <span>{mouseOver ? 'DISCONNECT' : truncateAddress(address)}</span>
        </ButtonBox>
      ) : (
        <Button onClick={walletConnect} label="CONNECT" secondary />
      )}
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
