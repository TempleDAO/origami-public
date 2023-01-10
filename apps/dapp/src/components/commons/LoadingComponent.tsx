import styled, { keyframes } from 'styled-components';

const placeHolderShimmer = keyframes`
    0% { background-position: left bottom; }
    100% { background-position: right bottom; }
`;

export const LoadingComponent = (props: {
  height?: number;
  width?: number;
  className?: string;
}) => (
  <Container $width={props.width} className={props.className}>
    <Bar $height={props.height} />
  </Container>
);

const Container = styled.div<{ $width?: number }>`
  overflow-x: hidden;
  overflow-y: hidden;
  width: ${({ $width }) => ($width ? `${$width}px` : `100%`)};
`;

const Bar = styled.div<{ $height?: number }>`
  animation: ${placeHolderShimmer};
  animation-duration: 2s;
  animation-iteration-count: infinite;
  animation-timing-function: linear;
  background: linear-gradient(
    to right,
    transparent 40%,
    #3a3e44 80%,
    transparent 100%
  );
  background-size: 50% 100%;
  height: ${({ $height }) => ($height ? `${$height}px` : `22rem`)};
  position: relative;
  width: 200%;
  opacity: 0.5;
`;
