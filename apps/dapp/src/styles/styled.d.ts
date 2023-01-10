import 'styled-components';
import { CSSProp } from 'styled-components';

declare module 'styled-components' {
  export interface DefaultTheme {
    colors: {
      bgLight: string;
      bgMid: string;
      bgDark: string;
      greyLight: string;
      greyMid: string;
      greyDark: string;
      white: string;
      success: string;
      error: string;
      chartLine: string;
      gradients: {
        primary: string;
        primaryDark: string;
      };
    };
    responsiveBreakpoints: {
      sm: string;
      md: string;
      lg: string;
      xl: string;
      xxl: string;
    };
  }
}

declare module 'react' {
  interface Attributes {
    css?: CSSProp;
  }
}
