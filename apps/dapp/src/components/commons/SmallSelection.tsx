import { FlexDown } from '@/flows/common/components';
import styled, { CSSProperties } from 'styled-components';

/**
 * A simple selection from a small set of values
 *
 * Note that implementation relies on === over T
 */
export interface SmallSelectionProps<T> {
  values: LabelledValue<T>[];
  value: T | undefined;
  onChange: (value: T) => void;
  style?: CSSProperties;
  LabelHeaders?: JSX.Element[]; // array should have the same values prop length
  onCheckedAction?: () => void;
  onUncheckedAction?: () => void;
}

export type LabelledValue<T> = [string, T];

export function SmallSelection<T>(props: SmallSelectionProps<T>) {
  const {
    values: labels,
    value,
    onChange,
    style,
    LabelHeaders,
    onUncheckedAction,
  } = props;
  const labelp = labels.find((v) => v[1] === value);
  const vlabel = labelp && labelp[0];
  const shouldShowHeaders =
    LabelHeaders && LabelHeaders.length === labels.length;

  return (
    <Selection style={style}>
      {labels.map((label, i) => {
        return (
          <FlexDown key={label[0]}>
            {shouldShowHeaders && LabelHeaders[i]}
            {label[0] === vlabel ? (
              <CheckedOption
                key={label[0]}
                id={label[0]}
                onClick={() => {
                  onChange(label[1]);
                  onUncheckedAction && onUncheckedAction();
                }}
              >
                {label[0]}
              </CheckedOption>
            ) : (
              <UncheckedOption
                key={label[0]}
                id={label[0]}
                onClick={() => {
                  onChange(label[1]);
                  onUncheckedAction && onUncheckedAction();
                }}
              >
                {label[0]}
              </UncheckedOption>
            )}
          </FlexDown>
        );
      })}
    </Selection>
  );
}

const Selection = styled.span`
  display: flex;
  flex-direction: row;
  gap: 1rem;
  cursor: pointer;
`;

const CheckedOption = styled.p`
  margin: 0;
  display: inline;
  line-height: 100%;
  background: ${({ theme }) => theme.colors.gradients.primary};
  color: ${({ theme }) => theme.colors.white};
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  border-bottom: 1px solid transparent;
  border-image: ${({ theme }) => theme.colors.gradients.primary};
  border-image-slice: 1;
`;

const UncheckedOption = styled.p`
  margin: 0;
  display: inline;
  line-height: 100%;
  transition: 300ms ease color;
  &:hover {
    color: ${({ theme }) => theme.colors.greyLight};
  }
`;
