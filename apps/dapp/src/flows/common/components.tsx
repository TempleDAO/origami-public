import styled from 'styled-components';
import { Icon } from '@/components/commons/Icon';
import { Spinner } from '@/components/commons/Spinner';
import {
  textP1,
  textP2,
  textH3,
  textH1,
  textH2,
} from '@/styles/mixins/text-styles';
import { formatDecimalBigNumber } from '@/utils/formatNumber';

import { LoadingText } from '@/components/commons/LoadingText';
import { Loading } from '@/utils/loading-value';
import { DecimalBigNumber } from '@/utils/decimal-big-number';
import { truncateAddress } from '@/utils/truncate-address';

export function ActionArrow(props: { busytext?: string }) {
  return (
    <FlexRightSpaced>
      <Icon iconName="flow-down" size={40} />
      <FlexDown>
        <ActionLabel active>{props.busytext}</ActionLabel>
      </FlexDown>
      {props.busytext && <Spinner size="small" />}
    </FlexRightSpaced>
  );
}

export function TxPending(props: {
  receivedAmount: DecimalBigNumber;
  receivedAsset: string;
  receivedUsdValue: Loading<string>;
}) {
  return (
    <FlexDown>
      <div>
        <SpanH2>{formatDecimalBigNumber(props.receivedAmount)}</SpanH2>{' '}
        <SpanH3>{props.receivedAsset}</SpanH3>
      </div>
      <DivP1_>
        <LoadingText value={props.receivedUsdValue} /> USD
      </DivP1_>
      <DivP2>(estimated)</DivP2>
    </FlexDown>
  );
}

export function TxSucceeded(props: {
  receivedAmount: DecimalBigNumber;
  receivedAsset: string;
  receivedUsdValue: Loading<string>;
  txHash: string;
  transactionUrl: (s: string) => string;
}) {
  return (
    <FlexDown>
      <DivH3>
        TRANSACTION SUCCESSFUL
        <StyledAnchor
          href={props.transactionUrl(props.txHash)}
          target="_blank"
          rel="noopener noreferrer"
        >
          ({truncateAddress(props.txHash)}
          <Icon iconName="open-in-new" size={20} />)
        </StyledAnchor>
      </DivH3>
      <DivP1_>You received:</DivP1_>
      <div>
        <SpanH2>{formatDecimalBigNumber(props.receivedAmount)}</SpanH2>{' '}
        <SpanH3>{props.receivedAsset}</SpanH3>
      </div>
      <DivP1>
        <LoadingText value={props.receivedUsdValue} /> USD
      </DivP1>
    </FlexDown>
  );
}

export function TxFailed(props: {
  message: string;
  txHash?: string;
  transactionUrl: (s: string) => string;
}) {
  return (
    <FlexDown>
      <DivH3>
        TRANSACTION FAILED
        {props.txHash && (
          <StyledAnchor
            href={props.transactionUrl(props.txHash)}
            target="_blank"
            rel="noopener noreferrer"
          >
            ({truncateAddress(props.txHash)}
            <Icon iconName="open-in-new" size={20} />)
          </StyledAnchor>
        )}
      </DivH3>
      <DivP1_>{props.message}</DivP1_>
    </FlexDown>
  );
}

export const FlexDownSpaced = styled.div`
  width: 100%;
  display: flex;
  flex-direction: column;
  gap: 20px;
`;

export const FlexDown = styled.div`
  display: flex;
  flex-direction: column;
`;

export const FlexRightSpaced = styled.div`
  display: flex;
  flex-direction: row;
  align-items: center;
  justify-content: flex-start;
  gap: 20px;
`;

export const Title = styled.div`
  ${textH1}
  color: ${(props) => props.theme.colors.white};
`;

export const DivP1_ = styled.div`
  ${textP1}
`;

export const DivH3 = styled.div`
  display: flex;
  flex-direction: row;
  align-items: center;
  gap: 10px;
  ${textH3};
`;

export const SpanH2 = styled.span`
  ${textH2}
  color: ${(props) => props.theme.colors.white};
`;

export const SpanH3 = styled.span`
  ${textH3}
  color: ${(props) => props.theme.colors.greyLight};
`;

export const DivP1 = styled.div`
  ${textP1}
  color: ${(props) => props.theme.colors.greyLight};
`;

export const DivP2 = styled.div`
  ${textP2}
`;

export const ActionLabel = styled.div<{ active: boolean }>`
  ${textP1}
  color: ${(props) =>
    props.active ? props.theme.colors.white : props.theme.colors.greyLight};
`;

export const StyledAnchor = styled.a`
  display: flex;
  ${textP2}
  color: ${(props) => props.theme.colors.white};
`;
