import type { OverlayContentComponent } from './RightPanelOverlay';

import React, { useState } from 'react';
import { Button } from './Button';
import { RightPanelOverlay } from './RightPanelOverlay';

export default {
  title: 'Components/Commons/RightPanelOverlay',
  component: RightPanelOverlay,
};

export const WithContextDismiss = () => (
  <TestRightPanelOverlay enableContextDismiss={true} />
);
export const WithoutContextDismiss = () => (
  <TestRightPanelOverlay enableContextDismiss={false} />
);

function TestRightPanelOverlay(props: {
  enableContextDismiss: boolean;
}): JSX.Element {
  const [panelActive, setPanelActive] = useState(false);

  const PanelContent: OverlayContentComponent = ({ startDismiss }) => {
    return (
      <>
        <p>Something modal goes here</p>
        <Button label="Done" onClick={startDismiss} />
      </>
    );
  };

  return (
    <div>
      <p>Here is the main content</p>
      <p>
        Lorem Ipsum is simply dummy text of the printing and typesetting
        industry. Lorem Ipsum has been the industry standard dummy text ever
        since the 1500s, when an unknown printer took a galley of type and
        scrambled it to make a type specimen book.
      </p>
      <Button label="Show Panel" onClick={() => setPanelActive(true)} />
      {panelActive && (
        <RightPanelOverlay
          hidePanel={() => setPanelActive(false)}
          enableContextDismiss={props.enableContextDismiss}
          Content={PanelContent}
        />
      )}
    </div>
  );
}
