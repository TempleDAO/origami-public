import { DefaultTheme } from 'styled-components';

export const theme: DefaultTheme = {
  colors: {
    bgLight: '#24272C',
    bgMid: '#202020',
    bgDark: '#181818',
    greyLight: '#a3a3a3',
    greyMid: '#646464',
    greyDark: '#3a3e44',
    white: '#ffffff',
    success: '#2DF6A7',
    error: '#FF3459',
    chartLine: '#327A5E',
    gradients: {
      primary: 'linear-gradient(270deg, #29B8ED 0%, #2DF6A7 100%)',
      primaryDark:
        'linear-gradient(0deg, rgba(0, 0, 0, 0.4), rgba(0, 0, 0, 0.4)), linear-gradient(270deg, #29B8ED 0%, #2DF6A7 100%)',
    },
  },
  responsiveBreakpoints: {
    sm: '640px',
    md: '768px',
    lg: '1024px',
    xl: '1280px',
    xxl: '1536px',
  },
};
