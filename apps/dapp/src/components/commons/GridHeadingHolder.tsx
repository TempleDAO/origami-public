import breakpoints from '@/styles/responsive-breakpoints';
import styled from 'styled-components';
import { TooltipWrapperFn } from './ApyTooltip';

export interface HeadingProps {
  name: string;
  widthWeight: number;
  tooltipWrapper?: TooltipWrapperFn;
}

export const makeGridHeadings = (headings: HeadingProps[]) => {
  // Create the set of headings, filtering out any undefined (empty columns)
  const rows = headings.map((h, i) => {
    const heading = (
      <Heading key={i + 1} col={i + 1}>
        {h.name}
      </Heading>
    );
    return h.tooltipWrapper
      ? h.tooltipWrapper({ key: i + 1, children: heading })
      : heading;
  });

  const flexWeights = headings.map((h) => `${h.widthWeight}fr`).join(' ');

  return (
    <GridHeadingHolder>
      <HeadingGrid flexWeights={flexWeights}>{rows}</HeadingGrid>
    </GridHeadingHolder>
  );
};

const GridHeadingHolder = styled.div`
  display: grid;
  padding-left: 1rem;
  padding-right: 1rem;
`;

const HeadingGrid = styled.div<{ flexWeights: string }>`
  width: 100%;
  display: none;
  grid-template-columns: ${({ flexWeights }) => flexWeights};
  ${breakpoints.lg(`
    display: grid;
  `)}
`;

const Heading = styled.div<{ col: number }>`
  justify-self: center;
  color: ${({ theme }) => theme.colors.greyLight};
  grid-column: ${({ col }) => col};
  display: none;
  ${breakpoints.lg(`
    display: inline-block;
  `)}
`;
