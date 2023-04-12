import { useState } from 'react';
import { AsyncButton } from './Button';
import { OverlayContentProps, RightPanelOverlay } from './RightPanelOverlay';
import styled from 'styled-components';
import { Icon } from './Icon';
import { SupportedWallet, useApiManager } from '@/hooks/use-api-manager';
import React from 'react';

export interface ConnectModalProps extends OverlayContentProps {
  initWallet(kind: SupportedWallet): Promise<void>;
}

export function ConnectModalContent(props: ConnectModalProps) {
  const [active, setActive] = useState<SupportedWallet | undefined>();

  function onClick(kind: SupportedWallet) {
    if (!active || active === kind) {
      return async () => {
        setActive(kind);
        try {
          await props.initWallet(kind);
        } finally {
          props.startDismiss();
        }
      };
    }
    return undefined;
  }

  return (
    <Content>
      <div>
        <p>Select a wallet:</p>
        <ConnectList>
          <ButtonRow>
            <Icon iconName="metamask" />
            <ConnectButton
              label="Metamask"
              wide
              onClick={onClick('metaMask')}
            />
          </ButtonRow>
          <ButtonRow>
            <Icon iconName="wallet-connect" />
            <ConnectButton
              label="Wallet Connect"
              wide
              onClick={onClick('walletConnect')}
            />
          </ButtonRow>
        </ConnectList>
      </div>
    </Content>
  );
}

interface ConnectModal {
  inProgress: boolean;

  walletInitialize(): Promise<void>;
}

export const ConnectModalContext =
  React.createContext<ConnectModal | undefined>(undefined);

export function ConnectModalProvider(props: { children?: React.ReactNode }) {
  const [inProgress, setInProgress] = useState(false);
  const apim = useApiManager();

  async function walletInitialize() {
    setInProgress(true);
  }

  return (
    <ConnectModalContext.Provider value={{ inProgress, walletInitialize }}>
      {inProgress && (
        <RightPanelOverlay
          hidePanel={() => setInProgress(false)}
          enableContextDismiss={true}
          maxWidthRem={70}
          Content={({ startDismiss }) => (
            <ConnectModalContent
              startDismiss={startDismiss}
              initWallet={apim.walletInitialize}
            />
          )}
        />
      )}
      {props.children}
    </ConnectModalContext.Provider>
  );
}

export function useConnectModal(): ConnectModal {
  const m = React.useContext(ConnectModalContext);
  if (!m) {
    throw new Error('useConnectModal invalid outside an ConnectModalProvider');
  }
  return m;
}

const Content = styled.div`
  display: flex;
  align-items: center;
  justify-content: center;
  width: 100%;
  height: 100%;
`;

const ConnectList = styled.div`
  display: flex;
  flex-direction: column;
  gap: 15px;
  align-items: left;
`;

const ButtonRow = styled.div`
  display: flex;
  flex-direction: row;
  gap: 15px;
  align-items: center;
  width: 250px;
`;

const ConnectButton = styled(AsyncButton)`
  flex-grow: 1;
`;
