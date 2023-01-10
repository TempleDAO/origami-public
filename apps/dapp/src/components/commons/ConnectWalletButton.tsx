import { useState } from 'react';
import styled from 'styled-components';
import { truncateAddress } from '@/utils/truncate-address';
import clickableStyles from '@/styles/mixins/clickable-styles';
import { useApiManager } from '@/hooks/use-api-manager';
import { Button } from './Button';

interface ConnectWalletButtonProps {
  usePrimaryStyling?: boolean;
}

export const ConnectWalletButton: React.FC<ConnectWalletButtonProps> = ({
  usePrimaryStyling,
}) => {
  const apim = useApiManager();
  const address = apim.sapi?.signerAddress;
  const isConnected = address != undefined;
  const [mouseOver, setMouseOver] = useState(false);

  const label = isConnected ? truncateAddress(address) : 'CONNECT WALLET';

  function onClick() {
    console.log('on click', isConnected);
    if (isConnected) {
      apim.disconnectSigner();
    } else {
      apim.connectSigner();
    }
    setMouseOver(false);
  }

  if (usePrimaryStyling)
    return <Button wide onClick={onClick} label="CONNECT WALLET" />;

  return (
    <>
      <ButtonBox
        onClick={onClick}
        onMouseEnter={() => setMouseOver(true)}
        onMouseLeave={() => setMouseOver(false)}
      >
        <span>{isConnected && mouseOver ? 'DISCONNECT' : label}</span>
      </ButtonBox>
    </>
  );
};

const ButtonBox = styled.button`
  display: flex;
  background: transparent;
  color: ${({ theme }) => theme.colors.greyLight};
  font-size: 1rem;
  padding: 0.5rem;
  border: ${({ theme }) => `2px solid ${theme.colors.greyMid}`};
  border-radius: 0.25rem;
  align-items: center;
  justify-content: center;
  height: fit-content;
  cursor: pointer;
  outline: none;
  width: 10rem;

  ${clickableStyles}
`;
