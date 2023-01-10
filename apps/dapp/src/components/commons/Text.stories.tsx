import React from 'react';

import { Text } from './Text';

export default {
  title: 'Components/Commons/Text',
  component: Text,
};

export const Varieties = () => (
  <>
    <Text>Default size responsive text component.</Text>
    <Text small>Small size responsive text component.</Text>
  </>
);
