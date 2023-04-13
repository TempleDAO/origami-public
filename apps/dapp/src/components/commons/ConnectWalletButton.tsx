import { useState } from 'react';
import styled from 'styled-components';

import { useApiManager } from '@/hooks/use-api-manager';
import { truncateAddress } from '@/utils/truncate-address';
import clickableStyles from '@/styles/mixins/clickable-styles';
import { Button } from './Button';
import { useConnectModal } from './ConnectModal';

export const ConnectWalletButton = () => {
  const apim = useApiManager();
  const modal = useConnectModal();
  const address = apim.wallet?.address;
  const [mouseOver, setMouseOver] = useState(false);

  async function disconnect() {
    try {
      await apim.walletDisconnect();
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
        <Button onClick={modal.walletInitialize} label="CONNECT" secondary />
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
