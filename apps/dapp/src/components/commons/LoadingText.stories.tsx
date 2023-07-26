import React from 'react';
import { loading, ready } from '@/utils/loading-value';

import { LoadingText } from './LoadingText';

export default {
  title: 'Components/Commons/LoadingText',
  component: LoadingText,
};

export const Loading = () => <LoadingText value={loading()} />;
export const Ready = () => <LoadingText value={ready('15.22')} />;
export const CustomPlaceholder = () => (
  <LoadingText value={loading()} placeholder="loading..." />
);
