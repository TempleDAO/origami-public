import { Tooltip } from '@/components/commons/Tooltip';
import { FC } from 'react';
import type { TippyProps } from '@tippyjs/react';

export const APY_TOOLTIP_CONTENT =
  'APY will experience a ramp up period after each new deposit as rewards catch up to the new TVL';

export const ApyTooltip: FC<TippyProps> = ({ children }) => (
  <Tooltip content={APY_TOOLTIP_CONTENT}>{children}</Tooltip>
);

export type TooltipWrapperFn = (props: {
  key?: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  children?: React.ReactElement<any>;
}) => JSX.Element;

export const ApyTooltipWrapper = (props: {
  key?: number;
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  children?: React.ReactElement<any>;
}) => <ApyTooltip key={props.key}>{props.children}</ApyTooltip>;
