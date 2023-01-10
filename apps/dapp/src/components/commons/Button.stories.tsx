import React from 'react';
import { action } from '@storybook/addon-actions';

import { Button } from './Button';

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
