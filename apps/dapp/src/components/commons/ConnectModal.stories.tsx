import type { OverlayContentComponent } from './RightPanelOverlay';

import { useState } from 'react';
import { Button } from './Button';
import { RightPanelOverlay } from './RightPanelOverlay';
import { ConnectModalContent } from './ConnectModal';
import { sleep } from '@/utils/sleep';

export default {
  title: 'Components/Commons/ConnectModal',
  component: RightPanelOverlay,
};

export const Default = () => <TestConnectModalOverlay />;

function TestConnectModalOverlay(): JSX.Element {
  const [panelActive, setPanelActive] = useState(false);

  const PanelContent: OverlayContentComponent = ({ startDismiss }) => {
    return (
      <ConnectModalContent
        startDismiss={startDismiss}
        initWallet={async () => {
          await sleep(1000);
        }}
      />
    );
  };

  return (
    <div>
      <h1>Wallet Connection</h1>
      <Button label="Connect" onClick={() => setPanelActive(true)} />
      {panelActive && (
        <RightPanelOverlay
          hidePanel={() => setPanelActive(false)}
          enableContextDismiss={true}
          Content={PanelContent}
        />
      )}
    </div>
  );
}
