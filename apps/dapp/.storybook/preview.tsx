import React from 'react';
import { ThemeContext } from 'styled-components';

import { GlobalStyle } from '../src/styles/GlobalStyle';
import { theme } from '../src/styles/theme';

export const parameters = {
  actions: { argTypesRegex: '^on[A-Z].*' },
  controls: {
    matchers: {
      color: /(background|color)$/i,
      date: /Date$/,
    },
  },
};

export const decorators = [
  (Story) => (
    <React.Fragment>
      <ThemeContext.Provider value={theme}>
        <GlobalStyle />
        <Story />
      </ThemeContext.Provider>
    </React.Fragment>
  ),
];
