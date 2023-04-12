import React from 'react';
import { action } from '@storybook/addon-actions';

import { AsyncButton, Button } from './Button';
import { sleep } from '@/utils/sleep';

export default {
  title: 'Components/Commons/Button',
  component: Button,
};

export const Default = () => (
  <Button onClick={action('pressed')} label="Default" />
);
export const Disabled = () => (
  <Button onClick={action('pressed')} disabled label="Disabled" />
);
export const Spinner = () => (
  <Button onClick={action('pressed')} label="Spinner" showSpinner={true} />
);

export const Secondary = () => (
  <Button secondary onClick={action('pressed')} label="Secondary" />
);

export const WideLabel = () => (
  <Button onClick={action('pressed')} label="With a very wide label" wide />
);

export const Async = () => (
  <AsyncButton
    onClick={async () => {
      await sleep(1000);
      action('pressed');
    }}
    label="Press me"
  />
);
